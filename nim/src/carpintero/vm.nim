## The matcher.
##
## One loop over a program, one stack. Backtrack entries and call frames share
## that stack, as they do in LPeg: an entry with `pc == RetFrame` is a return
## address, anything else is a choice point. Failure pops until it finds a
## choice point, which makes `fail` a single loop rather than an unwind.
##
## The capture log is a flat sequence of open and close markers, and rolling
## back is `setLen` to a saved height. That is the whole of the rollback
## semantics the proposal argues for, and it is why a dead parse path costs
## one integer store rather than a copied dictionary.

import std/[unicode, tables]
import charset, instructions

const
    RetFrame = int32(-1)

type
    LogKind* = enum
        lgOpen, lgClose, lgDefer

    LogEntry* = object
        kind*: LogKind
        cap*: CapKind
        name*: int32
        pos*: int32
        inputId*: int32

    Frame = object
        pc: int32            ## resume address, or RetFrame for a call frame
        pos: int32           ## saved position; the return address on a call frame
        logTop: int32
        cutLen: int32        ## cut-frame stack height, restored on resume
        guard: int32         ## index+1 of the cut frame this arm belongs to,
                             ## or 0 when this choice is not inside one

    MatchResult* = object
        ok*: bool
        pos*: int32          ## how far the match reached
        log*: seq[LogEntry]
        failPos*: int32      ## farthest position any terminal reached
        expected*: seq[string]
        failMsg*: string     ## set when a `fail` rule fired

    Matcher* = object
        prog: Program
        input: seq[Rune]
        stack: seq[Frame]
        log: seq[LogEntry]
        cuts: seq[bool]
        quiet: int           ## >0 inside `not`, where failures are not reported
        failPos: int32
        expected: seq[string]
        failMsg: string

proc note(m: var Matcher, pos: int32, what: string) {.inline.} =
    ## Farthest-failure bookkeeping: the high-water mark across all
    ## backtracking is almost always where the real failure is, even though
    ## the matcher has since backtracked far away from it.
    if m.quiet > 0: return
    if pos > m.failPos:
        m.failPos = pos
        m.expected = @[what]
    elif pos == m.failPos:
        if what notin m.expected:
            m.expected.add(what)

proc describe(p: Program, ins: Instr): string =
    case ins.op
    of opChar: "'" & $Rune(ins.arg) & "'"
    of opStr: "\"" & $p.strs[ins.arg] & "\""
    of opSet, opSpan: "a character in a set"
    of opAny: "any value"
    of opEndInput: "end of input"
    of opTypeTerm, opWordTerm: p.names[ins.arg]
    else: "input"

proc run*(prog: Program, input: seq[Rune]): MatchResult =
    var m = Matcher(prog: prog, input: input, failPos: -1)
    let n = int32(input.len)
    var pc = prog.entry
    var pos = int32(0)
    var failing = false

    template fail() =
        failing = true

    while true:
        if failing:
            # unwind to the nearest choice point, dropping call frames
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
                pc = f.pc
                resumed = true
                break
            if not resumed:
                return MatchResult(ok: false, pos: pos, log: @[],
                                   failPos: m.failPos, expected: m.expected,
                                   failMsg: m.failMsg)
            continue

        let ins = prog.code[pc]
        case ins.op

        of opChar:
            if pos < n and int32(input[pos]) == ins.arg:
                inc pos
                inc pc
            else:
                m.note(pos, describe(prog, ins)); fail()

        of opSet:
            if pos < n and prog.sets[ins.arg].contains(int32(input[pos])):
                inc pos
                inc pc
            else:
                m.note(pos, describe(prog, ins)); fail()

        of opSpan:
            while pos < n and prog.sets[ins.arg].contains(int32(input[pos])):
                inc pos
            inc pc

        of opStr:
            let lit = prog.strs[ins.arg]
            let ln = int32(lit.len)
            if pos + ln <= n:
                var k = 0
                while k < lit.len and input[pos + int32(k)] == lit[k]:
                    inc k
                if k == lit.len:
                    pos += ln
                    inc pc
                else:
                    m.note(pos, describe(prog, ins)); fail()
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

        of opChoice:
            # aux is 1 when this arm sits directly inside a cut frame, which
            # is the only case where a later `cut` may kill it
            m.stack.add(Frame(pc: pc + ins.arg, pos: pos,
                              logTop: int32(m.log.len),
                              cutLen: int32(m.cuts.len),
                              guard: if ins.aux == 1: int32(m.cuts.len) else: 0))
            inc pc

        of opCommit:
            m.stack.setLen(m.stack.len - 1)
            pc += ins.arg

        of opPartialCommit:
            # reuse the entry rather than pop and push, so a repetition costs
            # one stack slot instead of one per iteration
            m.stack[^1].pos = pos
            m.stack[^1].logTop = int32(m.log.len)
            pc += ins.arg

        of opPartialCommitG:
            # the same, with the progress guard: an iteration that matched
            # without consuming ends the loop instead of spinning
            if m.stack[^1].pos == pos:
                m.stack.setLen(m.stack.len - 1)
                pc += ins.aux
            else:
                m.stack[^1].pos = pos
                m.stack[^1].logTop = int32(m.log.len)
                pc += ins.arg

        of opBackCommit:
            # succeed, but at the saved position: `ahead` and the probe inside
            # `to`. The capture log is deliberately *not* restored, matching
            # the interpreted matcher, where a successful lookahead keeps what
            # it captured.
            let f = m.stack[^1]
            m.stack.setLen(m.stack.len - 1)
            pos = f.pos
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
            m.stack.add(Frame(pc: RetFrame, pos: pc + 1, logTop: 0,
                              cutLen: 0, guard: 0))
            pc = ins.arg

        of opRet:
            # every choice point a rule body opens is committed or unwound
            # before the body ends, so the call frame is on top. If it is not,
            # the compiler emitted something unbalanced and the assertion is
            # the cheapest place to find out.
            if m.stack.len == 0 or m.stack[^1].pc != RetFrame:
                raise newException(ValueError,
                    "carpintero vm: unbalanced stack at return")
            pc = m.stack[^1].pos
            m.stack.setLen(m.stack.len - 1)

        of opCapOpen:
            m.log.add(LogEntry(kind: lgOpen, cap: CapKind(ins.aux),
                               name: ins.arg, pos: pos))
            inc pc

        of opCapClose:
            m.log.add(LogEntry(kind: lgClose, cap: CapKind(ins.aux), pos: pos))
            inc pc

        of opDefer:
            m.log.add(LogEntry(kind: lgDefer, name: ins.arg, pos: pos))
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

        of opMatch:
            return MatchResult(ok: true, pos: pos, log: m.log,
                               failPos: m.failPos, expected: m.expected)

        of opTypeTerm, opWordTerm, opStrTerm, opQuote, opInto, opIntoEnd:
            raise newException(ValueError,
                "carpintero vm: " & $ins.op & " needs block input, which this " &
                "build does not carry yet")

proc run*(prog: Program, input: string): MatchResult {.inline.} =
    run(prog, input.toRunes)

# ── materialising captures ───────────────────────────────────────────────
# Only after overall success, and only from the log that survived. The log is
# a flat open/close sequence, so one walk with a stack rebuilds the nesting.

type
    Capture* = object
        name*: string
        value*: string
        collected*: seq[string]

proc captures*(prog: Program, input: seq[Rune], r: MatchResult): seq[Capture] =
    if not r.ok: return @[]
    var stack: seq[(int, LogEntry)] = @[]     # index into result, opener
    var collecting: seq[int] = @[]            # result indices of open collects
    for e in r.log:
        case e.kind
        of lgOpen:
            var c = Capture(name: prog.names[e.name])
            result.add(c)
            stack.add((result.len - 1, e))
            if e.cap == ckCollect: collecting.add(result.len - 1)
        of lgClose:
            if stack.len == 0: continue
            let (idx, opener) = stack[^1]
            stack.setLen(stack.len - 1)
            let text = $input[opener.pos ..< e.pos]
            result[idx].value = text
            if opener.cap == ckCollect:
                if collecting.len > 0: collecting.setLen(collecting.len - 1)
            elif opener.cap == ckKeep:
                if collecting.len > 0:
                    result[collecting[^1]].collected.add(text)
        of lgDefer:
            discard

proc asTable*(caps: seq[Capture]): Table[string, string] =
    ## The shape `scan` returns: one name to one span, last match winning.
    for c in caps:
        if c.name.len > 0: result[c.name] = c.value
