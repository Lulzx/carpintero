## The matcher.
##
## One loop over a program, one stack. Backtrack entries and call frames share
## that stack, as they do in LPeg: an entry with `pc == RetFrame` is a return
## address, anything else is a choice point. Failure pops until it finds a
## choice point, which makes failing a loop rather than an unwind.
##
## The capture log is a flat sequence of open and close markers, and rolling
## back is `setLen` to a saved height. A dead parse path costs one integer
## store rather than a copied dictionary.
##
## Two input kinds share the loop. The control flow is identical for both, so
## only the terminals branch: against text a position indexes runes, against a
## block it indexes values. `into` is what makes the block side more than a
## relabelling, since it swaps the sequence being matched partway through and
## has to put it back on every path out, backtracking included.

import std/unicode
import charset, instructions, items

const
    RetFrame = int32(-1)

type
    SourceKind* = enum
        skText
        skBlock

    Source* = object
        case kind*: SourceKind
        of skText: text*: seq[Rune]
        of skBlock: root*: seq[Item]

    LogKind* = enum
        lgOpen, lgClose, lgDefer

    LogEntry* = object
        kind*: LogKind
        cap*: CapKind
        name*: int32
        pos*: int32
        view*: int32          ## which sequence `pos` indexes

    View = object
        items: ptr seq[Item]  ## borrowed from the root, which outlives the run
        outerPos: int32       ## where this block sat in its parent
        prevView: int32       ## registry index to return to

    Frame = object
        pc: int32             ## resume address, or RetFrame for a call frame
        pos: int32            ## saved position; the return address on a call frame
        logTop: int32
        cutLen: int32
        guard: int32          ## index+1 of the cut frame this arm belongs to
        viewTop: int32        ## descent depth, restored on resume
        curView: int32

    CapValue* = object
        text*: string         ## text input
        items*: seq[Item]     ## block input

    CapSpan* = object
        ## Where a capture came from, rather than what it held. The caller
        ## owns the input, so it can slice its own values and keep their
        ## identity instead of taking a reconstruction of them.
        path*: seq[int32]     ## `into` descent indices, outermost first
        start*, finish*: int32

    Capture* = object
        name*: string
        kind*: CapKind        ## a collect reports its list even when empty
        value*: CapValue
        span*: CapSpan
        collected*: seq[CapValue]
        spans*: seq[CapSpan]

    MatchResult* = object
        ok*: bool
        pos*: int32
        caps*: seq[Capture]
        order*: seq[int]      ## cap indices in the order they closed, which
                              ## is the order the interpreted matcher logs
                              ## them and therefore the order its result
                              ## dictionary carries
        defers*: seq[int32]   ## host block ids, in match order, success only
        failPath*: seq[int32] ## descent indices, innermost last
        expected*: seq[string]
        failMsg*: string

# ── failure paths ────────────────────────────────────────────────────────
# For text input the farthest failure is one offset. Under `into` it is a
# path of indices into the nested structure, compared lexicographically with
# the deeper of two equal prefixes winning, which degenerates to the plain
# high-water mark on flat input.

proc farther(a, b: seq[int32]): bool =
    ## Is `a` strictly farther along than `b`?
    var i = 0
    while i < a.len and i < b.len:
        if a[i] > b[i]: return true
        if a[i] < b[i]: return false
        inc i
    a.len > b.len

type
    Matcher = object
        prog: Program
        src: Source
        views: seq[View]      ## active descents; empty at the top level
        viewReg: seq[ptr seq[Item]]
        viewPaths: seq[seq[int32]]   ## the descent path of each registered view
        curView: int32
        stack: seq[Frame]
        log: seq[LogEntry]
        cuts: seq[bool]
        quiet: int            ## >0 inside `not`, where failures are not reported
        failPath: seq[int32]
        expected: seq[string]
        failMsg: string
        haveFail: bool

proc curItems(m: Matcher): ptr seq[Item] {.inline.} =
    m.viewReg[m.curView]

proc inputLen(m: Matcher): int32 {.inline.} =
    case m.src.kind
    of skText: int32(m.src.text.len)
    of skBlock: int32(m.curItems[].len)

proc pathAt(m: Matcher, pos: int32): seq[int32] =
    ## The descent indices plus the position, which is what a failure is
    ## located by once `into` is in play.
    for v in m.views:
        result.add(v.outerPos)
    result.add(pos)

proc note(m: var Matcher, pos: int32, what: string) =
    ## Farthest-failure bookkeeping. The high-water mark across all
    ## backtracking is almost always where the real failure is, even though
    ## the matcher has since backtracked far away from it.
    if m.quiet > 0: return
    let p = m.pathAt(pos)
    if not m.haveFail or farther(p, m.failPath):
        m.failPath = p
        m.expected = @[what]
        m.haveFail = true
    elif p == m.failPath:
        if what notin m.expected:
            m.expected.add(what)

proc describe(p: Program, ins: Instr): string =
    case ins.op
    of opChar: "char " & $Rune(ins.arg)
    of opStr: "literal " & $p.strs[ins.arg]
    of opSet, opSpan: "a character in a set"
    of opAny: "any value"
    of opEndInput: "end of input"
    of opTypeTerm: p.names[ins.arg]
    of opWordTerm: "word " & p.names[ins.arg]
    of opQuote: "quoted " & $p.lits[ins.arg]
    of opInto: "a nested block"
    of opIntoEnd: "end of nested block"
    else: "input"

proc run*(prog: Program, src: Source): MatchResult =
    var m = Matcher(prog: prog, src: src)
    case src.kind
    of skText:
        m.viewReg.add(nil)
    of skBlock:
        m.viewReg.add(addr m.src.root)
    m.viewPaths.add(@[])
    m.curView = 0

    var pc = prog.entry
    var pos = int32(0)
    var failing = false
    let isBlock = src.kind == skBlock

    template fail() =
        failing = true

    template elem(): Item =
        m.curItems[][pos]

    while true:
        if failing:
            failing = false
            var resumed = false
            while m.stack.len > 0:
                let f = m.stack[^1]
                m.stack.setLen(m.stack.len - 1)
                if f.pc == RetFrame:
                    continue
                # an arm of a block that has since been cut takes the block
                # down with it instead of handing on to the next alternative
                if f.guard > 0 and f.guard <= int32(m.cuts.len) and
                   m.cuts[f.guard - 1]:
                    continue
                pos = f.pos
                m.log.setLen(f.logTop)
                m.cuts.setLen(f.cutLen)
                m.views.setLen(f.viewTop)
                m.curView = f.curView
                pc = f.pc
                resumed = true
                break
            if not resumed:
                return MatchResult(ok: false, pos: pos,
                                   failPath: m.failPath, expected: m.expected,
                                   failMsg: m.failMsg)
            continue

        let ins = prog.code[pc]
        let n = m.inputLen

        case ins.op

        of opChar:
            var hit = false
            if pos < n:
                if isBlock:
                    let e = elem()
                    hit = e.kind == itChar and e.c == ins.arg
                else:
                    hit = int32(m.src.text[pos]) == ins.arg
            if hit:
                inc pos
                inc pc
            else:
                m.note(pos, describe(prog, ins)); fail()

        of opSet:
            var hit = false
            if pos < n:
                if isBlock:
                    # a charset against block input only matches a char
                    let e = elem()
                    hit = e.kind == itChar and prog.sets[ins.arg].contains(e.c)
                else:
                    hit = prog.sets[ins.arg].contains(int32(m.src.text[pos]))
            if hit:
                inc pos
                inc pc
            else:
                m.note(pos, describe(prog, ins)); fail()

        of opSpan:
            if isBlock:
                while pos < n and elem().kind == itChar and
                      prog.sets[ins.arg].contains(elem().c):
                    inc pos
            else:
                while pos < n and prog.sets[ins.arg].contains(int32(m.src.text[pos])):
                    inc pos
            # the loop this replaces ended on an iteration whose charset
            # failed right here, and that failure belongs in the expected set
            # at this position as much as any other
            m.note(pos, describe(prog, ins))
            inc pc

        of opStr:
            let lit = prog.strs[ins.arg]
            var hit = false
            var width = int32(1)
            if isBlock:
                # one string *element*, compared whole
                if pos < n:
                    let e = elem()
                    hit = e.kind == itString and e.s == $lit
            else:
                width = int32(lit.len)
                if pos + width <= n:
                    var k = 0
                    while k < lit.len and m.src.text[pos + int32(k)] == lit[k]:
                        inc k
                    hit = k == lit.len
            if hit:
                pos += width
                inc pc
            else:
                m.note(pos, describe(prog, ins)); fail()

        of opAny:
            if pos < n:
                inc pos
                inc pc
            else:
                m.note(pos, "any value"); fail()

        of opEndInput:
            if pos == n: inc pc
            else:
                m.note(pos, "end of input"); fail()

        of opTypeTerm:
            if not isBlock:
                raise newException(ValueError,
                    "carpintero: type terminals need block input")
            if pos < n and elem().typeName == prog.names[ins.arg]:
                inc pos
                inc pc
            else:
                m.note(pos, describe(prog, ins)); fail()

        of opWordTerm:
            if not isBlock:
                raise newException(ValueError,
                    "carpintero: literal word terminals need block input")
            var hit = false
            if pos < n:
                let e = elem()
                # only a `:word`. The interpreted matcher guards this with
                # `word?`, so a label or a literal of the same name does not
                # match, and the compiled core must not be more generous.
                hit = e.kind == itWord and e.s == prog.names[ins.arg]
            if hit:
                inc pos
                inc pc
            else:
                m.note(pos, describe(prog, ins)); fail()

        of opQuote:
            if not isBlock:
                raise newException(ValueError, "carpintero: quote needs block input")
            # Structural equality against the quoted value itself, not
            # against a rendering of it: Arturo prints a :symbolliteral `'+`
            # as `+` and a :literal `'foo` as `foo`, so comparing text would
            # conflate them with the symbol and the word of the same name.
            #
            # Deliberate divergence: the interpreted matcher compares with
            # Arturo's `=`, and on 0.10.0 a :symbolliteral is not equal to
            # itself, so `quote '+` cannot match there and can here.
            var hit = false
            if pos < n:
                hit = elem() == prog.lits[ins.arg]
            if hit:
                inc pos
                inc pc
            else:
                m.note(pos, describe(prog, ins)); fail()

        of opInto:
            if not isBlock:
                raise newException(ValueError, "carpintero: into needs block input")
            var ok = false
            if pos < n and elem().kind == itBlock:
                ok = true
            if not ok:
                m.note(pos, describe(prog, ins)); fail()
            else:
                let nested = addr m.curItems[][pos].items
                m.viewReg.add(nested)
                m.viewPaths.add(m.viewPaths[m.curView] & @[pos])
                m.views.add(View(items: nested, outerPos: pos,
                                 prevView: m.curView))
                m.curView = int32(m.viewReg.len - 1)
                pos = 0
                inc pc

        of opIntoEnd:
            # the operand has to have matched the whole nested block
            if pos != m.inputLen:
                m.note(pos, describe(prog, ins)); fail()
            else:
                let v = m.views[^1]
                m.views.setLen(m.views.len - 1)
                m.curView = v.prevView
                pos = v.outerPos + 1
                inc pc

        of opChoice:
            # aux is 1 when this arm sits directly inside a cut frame, which
            # is the only case where a later `cut` may kill it
            m.stack.add(Frame(pc: pc + ins.arg, pos: pos,
                              logTop: int32(m.log.len),
                              cutLen: int32(m.cuts.len),
                              guard: if ins.aux == 1: int32(m.cuts.len) else: 0,
                              viewTop: int32(m.views.len),
                              curView: m.curView))
            inc pc

        of opCommit:
            m.stack.setLen(m.stack.len - 1)
            pc += ins.arg

        of opPartialCommit:
            # reuse the entry rather than pop and push, so a repetition costs
            # one stack slot instead of one per iteration
            m.stack[^1].pos = pos
            m.stack[^1].logTop = int32(m.log.len)
            m.stack[^1].viewTop = int32(m.views.len)
            m.stack[^1].curView = m.curView
            pc += ins.arg

        of opPartialCommitG:
            # the progress guard, on the iteration that stalls rather than
            # one iteration later: what the stalled pass logged goes with it
            if m.stack[^1].pos == pos:
                m.log.setLen(m.stack[^1].logTop)
                m.stack.setLen(m.stack.len - 1)
                pc += ins.aux
            else:
                m.stack[^1].pos = pos
                m.stack[^1].logTop = int32(m.log.len)
                m.stack[^1].viewTop = int32(m.views.len)
                m.stack[^1].curView = m.curView
                pc += ins.arg

        of opBackCommit:
            # succeed at the saved position: `ahead`, and the probe inside
            # `to`. Rewinding the position rewinds the log with it, so a
            # capture survives only if the match consumed the input it names.
            # LPeg's IBackCommit restores its capture level for the same
            # reason; these are the only two constructs that reach here.
            let f = m.stack[^1]
            m.stack.setLen(m.stack.len - 1)
            pos = f.pos
            m.log.setLen(f.logTop)
            m.views.setLen(f.viewTop)
            m.curView = f.curView
            pc += ins.arg

        of opFailTwice:
            m.stack.setLen(m.stack.len - 1)
            fail()

        of opFail:
            fail()

        of opFailMsg:
            m.failMsg = prog.msgs[ins.arg]
            m.note(pos, prog.msgs[ins.arg])
            fail()

        of opJmp:
            pc += ins.arg

        of opCall:
            m.stack.add(Frame(pc: RetFrame, pos: pc + 1))
            pc = ins.arg

        of opRet:
            # every choice point a rule body opens is committed or unwound
            # before the body ends, so the call frame is on top. If it is not,
            # the compiler emitted something unbalanced, and this is the
            # cheapest place to find out.
            if m.stack.len == 0 or m.stack[^1].pc != RetFrame:
                raise newException(ValueError,
                    "carpintero vm: unbalanced stack at return")
            pc = m.stack[^1].pos
            m.stack.setLen(m.stack.len - 1)

        of opCapOpen:
            m.log.add(LogEntry(kind: lgOpen, cap: CapKind(ins.aux),
                               name: ins.arg, pos: pos, view: m.curView))
            inc pc

        of opCapClose:
            m.log.add(LogEntry(kind: lgClose, cap: CapKind(ins.aux),
                               pos: pos, view: m.curView))
            inc pc

        of opDefer:
            m.log.add(LogEntry(kind: lgDefer, name: ins.arg, pos: pos,
                               view: m.curView))
            inc pc

        of opCutFrame:
            m.cuts.add(false)
            inc pc

        of opCutFrameEnd:
            if m.cuts.len > 0: m.cuts.setLen(m.cuts.len - 1)
            inc pc

        of opCut:
            if m.cuts.len > 0: m.cuts[^1] = true
            inc pc

        of opStrTerm:
            raise newException(ValueError, "carpintero vm: opStrTerm is unused")

        of opMatch:
            result.ok = true
            result.pos = pos
            result.failPath = m.failPath
            result.expected = m.expected
            # captures materialise here, where the borrowed views are still
            # valid and only the log that survived is left
            var stack: seq[(int, LogEntry)] = @[]
            var collecting: seq[int] = @[]
            for e in m.log:
                case e.kind
                of lgOpen:
                    result.caps.add(Capture(name: prog.names[e.name], kind: e.cap))
                    stack.add((result.caps.len - 1, e))
                    if e.cap == ckCollect: collecting.add(result.caps.len - 1)
                of lgClose:
                    if stack.len == 0: continue
                    let (idx, opener) = stack[^1]
                    stack.setLen(stack.len - 1)
                    var v: CapValue
                    case src.kind
                    of skText:
                        v.text = $m.src.text[opener.pos ..< e.pos]
                    of skBlock:
                        let view = m.viewReg[opener.view]
                        if opener.pos < e.pos:
                            v.items = view[][opener.pos ..< e.pos]
                    let sp = CapSpan(path: m.viewPaths[opener.view],
                                     start: opener.pos, finish: e.pos)
                    result.caps[idx].value = v
                    result.caps[idx].span = sp
                    result.order.add(idx)
                    if opener.cap == ckCollect:
                        if collecting.len > 0:
                            collecting.setLen(collecting.len - 1)
                    elif opener.cap == ckKeep:
                        if collecting.len > 0:
                            result.caps[collecting[^1]].collected.add(v)
                            result.caps[collecting[^1]].spans.add(sp)
                of lgDefer:
                    result.defers.add(e.name)
            return result

proc run*(prog: Program, input: string): MatchResult {.inline.} =
    run(prog, Source(kind: skText, text: input.toRunes))

proc run*(prog: Program, input: seq[Item]): MatchResult {.inline.} =
    run(prog, Source(kind: skBlock, root: input))
