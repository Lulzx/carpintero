## Carpintero, compiled core.
##
## `scan` here answers the same question as `scan` in `carpintero.art`: does
## this grammar match the whole of this input, and what did it capture. The
## interpreted version stays the specification; this is the engine swap the
## proposal asks for, and the two are held together by differential tests
## rather than by shared code.

import std/[tables, unicode, strutils]
import carpintero/[charset, grammar, instructions, compile, vm, items]

export charset, grammar, instructions, compile, vm, items

type
    ScanResult* = object
        ok*: bool
        captures*: Table[string, CapValue]
        collected*: Table[string, seq[CapValue]]
        reached*: int          ## how far a prefix scan got
        defers*: seq[int32]    ## host block ids to run, in match order
        failPath*: seq[int32]
        expected*: seq[string]
        failMsg*: string

proc scan*(prog: Program, src: Source, prefix = false): ScanResult =
    let total = case src.kind
                of skText: int32(src.text.len)
                of skBlock: int32(src.root.len)
    let r = run(prog, src)
    result.failPath = r.failPath
    result.expected = r.expected
    result.failMsg = r.failMsg
    result.reached = int(r.pos)
    if not r.ok:
        return
    if not prefix and r.pos != total:
        # A prefix that matched and stopped short is a failure, and the report
        # has to say so. Without this the high-water mark still holds whatever
        # speculative terminal died furthest along in an abandoned arm, which
        # for the commonest failure of all is never the reason.
        result.ok = false
        let here = @[r.pos]
        if result.failPath.len == 0 or result.failPath == here:
            result.failPath = here
            if "end of input" notin result.expected:
                result.expected.add("end of input")
        elif result.failPath.len == 1 and result.failPath[0] < r.pos:
            result.failPath = here
            result.expected = @["end of input"]
        return
    result.ok = true
    result.defers = r.defers
    for c in r.caps:
        if c.name.len > 0:
            result.captures[c.name] = c.value
            if c.collected.len > 0:
                result.collected[c.name] = c.collected

proc scan*(prog: Program, input: string, prefix = false): ScanResult {.inline.} =
    scan(prog, Source(kind: skText, text: input.toRunes), prefix)

proc scan*(prog: Program, input: seq[Item], prefix = false): ScanResult {.inline.} =
    scan(prog, Source(kind: skBlock, root: input), prefix)

proc scan*(g: Grammar, input: string, prefix = false): ScanResult =
    ## Compile and run. Callers that scan repeatedly should hold the Program
    ## from `compile` instead, which is the whole point of compiling.
    scan(compile(g), input, prefix)

proc scan*(g: Grammar, input: seq[Item], prefix = false): ScanResult =
    scan(compile(g), input, prefix)

proc scanQ*(g: Grammar, input: string): bool =
    ## `scan?`: the yes or no.
    scan(g, input).ok

proc scanQ*(g: Grammar, input: seq[Item]): bool =
    scan(g, input).ok

proc text*(c: CapValue): string {.inline.} = c.text

# A text capture reads as the string it spans, so that callers and tests can
# compare against one without unwrapping.
proc `==`*(c: CapValue, s: string): bool {.inline.} = c.text == s
proc `==`*(s: string, c: CapValue): bool {.inline.} = c.text == s

proc `==`*(a: seq[CapValue], b: seq[string]): bool =
    if a.len != b.len: return false
    for i in 0 ..< a.len:
        if a[i].text != b[i]: return false
    true

proc `==`*(c: CapValue, its: seq[Item]): bool {.inline.} = c.items == its

proc `$`*(c: CapValue): string =
    if c.items.len > 0:
        var parts: seq[string] = @[]
        for e in c.items: parts.add($e)
        "[" & parts.join(" ") & "]"
    else:
        c.text

proc scanError*(prog: Program, r: ScanResult): string =
    ## The report, in the shape the manual specifies for block input: an index,
    ## or a path of indices when the failure is inside `into`.
    let exp = if r.expected.len == 0: "end of input" else: r.expected.join(", ")
    if r.failPath.len > 1:
        var parts: seq[string] = @[]
        for i in r.failPath: parts.add($i)
        "scan failed at index path " & parts.join(" ") & ", expected: " & exp
    else:
        let at = if r.failPath.len == 1: r.failPath[0] else: 0'i32
        "scan failed at index " & $at & ", expected: " & exp
