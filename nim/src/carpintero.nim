## Carpintero, compiled core.
##
## `scan` here answers the same question as `scan` in `carpintero.art`: does
## this grammar match the whole of this input, and what did it capture. The
## interpreted version stays the specification; this one is the engine swap
## the proposal asks for, and the two are held together by differential tests
## rather than by shared code.

import std/[tables, unicode]
import carpintero/[charset, grammar, instructions, compile, vm]

export charset, grammar, instructions, compile, vm

type
    ScanResult* = object
        ok*: bool
        captures*: Table[string, string]
        collected*: Table[string, seq[string]]
        reached*: int          ## how far a prefix scan got
        failPos*: int
        expected*: seq[string]
        failMsg*: string

proc scan*(prog: Program, input: string, prefix = false): ScanResult =
    let runes = input.toRunes
    let r = run(prog, runes)
    result.failPos = int(r.failPos)
    result.expected = r.expected
    result.failMsg = r.failMsg
    result.reached = int(r.pos)
    if not r.ok:
        return
    if not prefix and r.pos != int32(runes.len):
        # the whole input must match, so a short match is a failure
        result.ok = false
        if result.failPos < int(r.pos):
            result.failPos = int(r.pos)
            result.expected = @["end of input"]
        return
    result.ok = true
    for c in captures(prog, runes, r):
        if c.name.len > 0:
            result.captures[c.name] = c.value
            if c.collected.len > 0:
                result.collected[c.name] = c.collected

proc scan*(g: Grammar, input: string, prefix = false): ScanResult =
    ## Compile and run. Callers that scan repeatedly should hold the Program
    ## from `compile` instead, which is the whole point of compiling.
    scan(compile(g), input, prefix)

proc scanQ*(g: Grammar, input: string): bool =
    ## `scan?`: the yes or no, with no capture materialisation.
    scan(g, input).ok
