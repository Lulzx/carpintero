## Rule tree to program.
##
## The lowerings are LPeg's, with three departures the dialect forces.
##
## `cut` needs a frame. The interpreted matcher keeps a stack of one flag per
## rule *block*, sets the innermost on `cut`, and makes a failing alternative
## kill the whole block when the flag is set. A choice frame in the VM is per
## alternative, not per block, so blocks that contain a cut get an explicit
## frame around them. Blocks that do not, which is nearly all of them, get
## nothing: the analysis runs at compile time and costs the runtime nothing.
##
## Loops need the progress guard. LPeg rejects a nullable loop body at compile
## time; this dialect instead terminates the loop when an iteration matches
## without consuming, which is a runtime test. Compiling nullability lets the
## guard appear only on the loops that can need it.
##
## `into` switches the input mid-match, which LPeg has no equivalent for.

import std/[tables, strutils]
import grammar, instructions

type
    CompileError* = object of CatchableError

    Ctx = object
        p: Program
        nmap: Table[string, bool]
        addrs: Table[string, int32]      ## rule name to entry address
        emitted: seq[string]             ## rules already emitted, in order
        pending: seq[(int32, string)]    ## opCall sites awaiting an address

proc containsCutIn(n: Node): bool =
    ## Walk one block's contents looking for a `cut` that belongs to it. The
    ## search stops at a nested block and at a rule name, since each of those
    ## carries its own frame and a cut inside one commits that one.
    if n == nil: return false
    case n.kind
    of nkCut: true
    of nkAlt, nkRule: false
    of nkSeq:
        for it in n.items:
            if containsCutIn(it): return true
        false
    else: containsCutIn(n.child)

proc containsCut(n: Node): bool =
    ## `n` is the block itself, so its own arms are in scope even though a
    ## *nested* block's would not be.
    for arm in n.items:
        if containsCutIn(arm): return true
    false

proc emit(c: var Ctx, n: Node)

proc emitSeq(c: var Ctx, items: seq[Node]) =
    for it in items:
        c.emit(it)

proc emitAlt(c: var Ctx, n: Node, guarded: bool) =
    ## Ordered choice:
    ##     Choice L_next ; <arm> ; Commit L_done ; L_next: ... ; L_done:
    ## The last arm needs no choice point of its own: if it fails, the whole
    ## alternation fails, which is what the enclosing frame already does.
    ##
    ## `guarded` marks the choice points as belonging to a cut frame, so that
    ## a `cut` reached inside an arm can kill the rest of the block. Only arms
    ## directly inside the framed block are marked, which is what keeps a cut
    ## from leaking into a nested block's choices.
    let mark = if guarded: 1'i32 else: 0'i32
    var commits: seq[int32] = @[]
    for i, arm in n.items:
        if i == n.items.high:
            c.emit(arm)
        else:
            let ch = c.p.add(opChoice, 0, mark)
            c.emit(arm)
            commits.add(c.p.add(opCommit))
            c.p.patch(ch, c.p.here - ch)
    let done = c.p.here
    for at in commits:
        c.p.patch(at, done - at)

proc emitLoop(c: var Ctx, body: Node, atLeastOne: bool) =
    ## `any body` is
    ##     L: Choice L_exit ; <body> ; PartialCommit L ; L_exit:
    ## `some body` is the same with one unguarded copy of the body in front.
    ##
    ## PartialCommit reuses the choice entry instead of popping and pushing,
    ## which is what makes a repetition cost one stack slot rather than one
    ## per iteration. When the body is nullable the guarded form compares the
    ## position against the entry's before reusing it, and leaves the loop if
    ## the iteration consumed nothing.
    if atLeastOne:
        c.emit(body)
    let nullableBody = isNullable(body, c.nmap)
    let ch = c.p.add(opChoice)
    # the loop goes back to the body, never to the Choice: PartialCommit
    # reuses the entry that is already there, and re-executing the Choice
    # would push a second one on every iteration
    let bodyStart = c.p.here
    c.emit(body)
    if nullableBody:
        let pc = c.p.add(opPartialCommitG)
        c.p.patch(pc, bodyStart - pc)
        c.p.patchAux(pc, c.p.here - pc)
    else:
        let pc = c.p.add(opPartialCommit)
        c.p.patch(pc, bodyStart - pc)
    c.p.patch(ch, c.p.here - ch)

proc emitBetween(c: var Ctx, n: Node) =
    ## Bounded repetition unrolls, as it does in LPeg for `p^n`. The bounds in
    ## a grammar are small by nature (`4 digit`, `between 1 3 x`), and the
    ## alternative is a counter register that every other opcode would have to
    ## save and restore across backtracking.
    if n.hi < n.lo or n.lo < 0:
        raise newException(CompileError,
            "between expects 0 <= lo <= hi, got " & $n.lo & " " & $n.hi)
    if n.hi > 1000:
        raise newException(CompileError,
            "between bound " & $n.hi & " is too large to unroll")
    for _ in 0 ..< n.lo:
        c.emit(n.btBody)
    # the optional tail is just that many independent `opt`s: a body that
    # fails at some position fails identically at the next copy, so stopping
    # on first failure and running the rest to no effect agree
    for _ in n.lo ..< n.hi:
        let ch = c.p.add(opChoice)
        c.emit(n.btBody)
        let cm = c.p.add(opCommit)
        c.p.patch(ch, c.p.here - ch)
        c.p.patch(cm, c.p.here - cm)

proc emit(c: var Ctx, n: Node) =
    if n == nil: return
    case n.kind

    of nkSeq:
        emitSeq(c, n.items)

    of nkAlt:
        # a block that contains a cut gets a frame so that `cut` has something
        # to commit; every other block is a bare ordered choice
        if containsCut(n):
            let f = c.p.add(opCutFrame)
            emitAlt(c, n, guarded = true)
            discard c.p.add(opCutFrameEnd)
            c.p.patch(f, c.p.here - f)
        else:
            emitAlt(c, n, guarded = false)

    of nkStr:
        if n.text.len == 0: return          # matches without consuming
        if n.text.len == 1:
            discard c.p.add(opChar, int32(n.text[0]))
        else:
            discard c.p.add(opStr, c.p.poolStr(n.text))

    of nkChar:
        discard c.p.add(opChar, n.cp)

    of nkSet:
        discard c.p.add(opSet, c.p.poolSet(n.cs))

    of nkSkip:
        discard c.p.add(opAny)

    of nkEnd:
        discard c.p.add(opEndInput)

    of nkRule:
        if n.name notin c.nmap:
            raise newException(CompileError, "unbound rule word '" & n.name & "'")
        let site = c.p.add(opCall)
        c.pending.add((site, n.name))

    of nkSome:
        emitLoop(c, n.body, atLeastOne = true)

    of nkAny:
        emitLoop(c, n.body, atLeastOne = false)

    of nkOpt:
        ##     Choice L ; <body> ; Commit L ; L:
        let ch = c.p.add(opChoice)
        c.emit(n.body)
        let cm = c.p.add(opCommit)
        c.p.patch(ch, c.p.here - ch)
        c.p.patch(cm, c.p.here - cm)

    of nkRep:
        if n.count < 0:
            raise newException(CompileError, "a repeat count cannot be negative")
        if n.count > 1000:
            raise newException(CompileError,
                "repeat count " & $n.count & " is too large to unroll")
        for _ in 0 ..< n.count:
            c.emit(n.repBody)

    of nkBetween:
        emitBetween(c, n)

    of nkNot:
        ##     Choice L ; <body> ; FailTwice ; L:
        ## The capture log rolls back with the choice entry either way, which
        ## is what the interpreted version does explicitly around `not`.
        let ch = c.p.add(opChoice)
        c.emit(n.body)
        discard c.p.add(opFailTwice)
        c.p.patch(ch, c.p.here - ch)

    of nkAhead:
        ##     Choice L_fail ; <body> ; BackCommit L_ok ; L_fail: Fail ; L_ok:
        let ch = c.p.add(opChoice)
        c.emit(n.body)
        let bc = c.p.add(opBackCommit)
        c.p.patch(ch, c.p.here - ch)
        discard c.p.add(opFail)
        c.p.patch(bc, c.p.here - bc)

    of nkTo, nkThru:
        ## Advance one item at a time, probing the body at each position.
        ##     L_try: Choice L_step ; <body> ; Commit L_done
        ##     L_step: Any ; Jmp L_try
        ##     L_done:
        ## `to` reports the position where the body started, so it saves and
        ## restores around the successful probe; `thru` keeps the end.
        let tryAt = c.p.here
        let ch = c.p.add(opChoice)
        if n.kind == nkTo:
            # probe without consuming: BackCommit restores the saved position
            c.emit(n.body)
            let bc = c.p.add(opBackCommit)
            c.p.patch(ch, c.p.here - ch)
            discard c.p.add(opAny)
            let jm = c.p.add(opJmp)
            c.p.patch(jm, tryAt - jm)
            c.p.patch(bc, c.p.here - bc)
        else:
            c.emit(n.body)
            let cm = c.p.add(opCommit)
            c.p.patch(ch, c.p.here - ch)
            discard c.p.add(opAny)
            let jm = c.p.add(opJmp)
            c.p.patch(jm, tryAt - jm)
            c.p.patch(cm, c.p.here - cm)

    of nkCap:
        discard c.p.add(opCapOpen, c.p.poolName(n.capName), int32(ckCap))
        c.emit(n.capBody)
        discard c.p.add(opCapClose, 0, int32(ckCap))

    of nkCollect:
        discard c.p.add(opCapOpen, c.p.poolName(n.capName), int32(ckCollect))
        c.emit(n.capBody)
        discard c.p.add(opCapClose, 0, int32(ckCollect))

    of nkKeep:
        discard c.p.add(opCapOpen, c.p.poolName(""), int32(ckKeep))
        c.emit(n.body)
        discard c.p.add(opCapClose, 0, int32(ckKeep))

    of nkInto:
        let it = c.p.add(opInto)
        c.emit(n.body)
        discard c.p.add(opIntoEnd)
        c.p.patch(it, c.p.here - it)

    of nkCut:
        discard c.p.add(opCut)

    of nkFail:
        discard c.p.add(opFailMsg, c.p.poolMsg(n.msg))

    of nkDefer:
        discard c.p.add(opDefer, int32(n.blockId))

    of nkTypeTerm:
        discard c.p.add(opTypeTerm, c.p.poolName(n.name))

    of nkWordTerm:
        discard c.p.add(opWordTerm, c.p.poolName(n.name))

    of nkQuote:
        discard c.p.add(opQuote, c.p.poolName(n.literal))

# ── left recursion ───────────────────────────────────────────────────────
# Ford's well-formedness check, the same one the interpreted pre-pass runs:
# a rule reaches the rules that sit behind only nullable prefixes, and any
# cycle in that graph is left recursion. Rejected with the cycle named,
# because a naive PEG loops forever on it instead.

proc headsOf(n: Node, nmap: Table[string, bool], acc: var seq[string]) =
    if n == nil: return
    case n.kind
    of nkRule:
        acc.add(n.name)
    of nkSeq:
        for it in n.items:
            headsOf(it, nmap, acc)
            if not isNullable(it, nmap): break
    of nkAlt:
        for it in n.items: headsOf(it, nmap, acc)
    of nkNot, nkAhead, nkTo, nkThru:
        headsOf(n.child, nmap, acc)
    of nkSome, nkAny, nkOpt, nkKeep, nkInto:
        headsOf(n.child, nmap, acc)
    of nkRep:
        if n.count > 0: headsOf(n.repBody, nmap, acc)
    of nkBetween:
        headsOf(n.btBody, nmap, acc)
    of nkCap, nkCollect:
        headsOf(n.capBody, nmap, acc)
    else: discard

proc checkLeftRecursion*(g: Grammar, nmap: Table[string, bool]) =
    var state = initTable[string, int]()      # 0 unvisited, 1 on stack, 2 done
    for name in g.rules.keys: state[name] = 0
    var path: seq[string] = @[]

    proc dfs(name: string) =
        if state.getOrDefault(name, 2) == 2: return
        if state[name] == 1:
            let at = path.find(name)
            let cycle = if at >= 0: path[at .. ^1] else: path
            raise newException(CompileError,
                "left recursion: " & cycle.join(" -> ") & " -> " & name)
        state[name] = 1
        path.add(name)
        var heads: seq[string] = @[]
        headsOf(g.rules[name], nmap, heads)
        for h in heads:
            if h in g.rules: dfs(h)
        discard path.pop()
        state[name] = 2

    for name in g.rules.keys:
        dfs(name)
    var heads: seq[string] = @[]
    headsOf(g.start, nmap, heads)
    for h in heads:
        if h in g.rules: dfs(h)

# ── entry point ──────────────────────────────────────────────────────────

proc compile*(g: Grammar): Program =
    ## Compile a grammar to a program. Rules are emitted once each, after the
    ## start expression, and call sites are patched when every address is
    ## known, so mutual recursion needs no forward declaration.
    var c = Ctx(nmap: computeNullable(g))
    for name in g.rules.keys:
        if name notin c.nmap: c.nmap[name] = false
    checkLeftRecursion(g, c.nmap)

    c.p.entry = 0
    c.emit(g.start)
    discard c.p.add(opMatch)

    # rules, each ending in Ret; emitting into a work list rather than
    # recursing keeps a deep grammar off the Nim stack
    var queue: seq[string] = @[]
    for (_, name) in c.pending:
        if name notin queue: queue.add(name)
    var i = 0
    while i < queue.len:
        let name = queue[i]
        inc i
        if name in c.addrs: continue
        c.addrs[name] = c.p.here
        let before = c.pending.len
        c.emit(g.rules[name])
        discard c.p.add(opRet)
        for j in before ..< c.pending.len:
            let dep = c.pending[j][1]
            if dep notin c.addrs and dep notin queue: queue.add(dep)

    for (site, name) in c.pending:
        if name notin c.addrs:
            raise newException(CompileError, "unbound rule word '" & name & "'")
        c.p.patch(site, c.addrs[name])

    result = c.p
