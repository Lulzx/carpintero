## Run every exported case through the compiled core and check it agrees
## with what the interpreted matcher decided.
##
##     arturo nim/adapter/cases.art nim/adapter/cases.json
##     cd nim && nim c --hints:off -r tests/differential.nim
##
## The cases carry the interpreted answer with them, so this compares two
## engines rather than comparing one engine against a hand-written
## expectation. A disagreement is a real disagreement about the language.

import std/[os, strutils, tables, strformat]
import ../src/carpintero
import ../src/carpintero/load

proc asItem(c: CapValue, isBlock: bool): Item =
    ## A capture in the shape the exporter writes: block input yields the
    ## matched values, text input the characters joined back into a string.
    if isBlock: Item(kind: itBlock, items: c.items)
    else: iStr(c.text)

type Failure = object
    name: string
    what: string
    wanted: string
    got: string

proc main() =
    let path = if paramCount() >= 1: paramStr(1) else: "adapter/cases.json"
    if not fileExists(path):
        echo "no case file at ", path
        echo "generate it with: arturo nim/adapter/cases.art nim/adapter/cases.json"
        quit(1)

    let cases = loadCases(path)
    var fails: seq[Failure] = @[]
    var compared = 0
    var skipped: seq[string] = @[]

    for c in cases:
        var r: ScanResult
        try:
            let prog = compile(c.grammar)
            r = if c.isBlock: scan(prog, c.items) else: scan(prog, c.text)
        except CompileError as e:
            # the interpreted side panics on a bad grammar, and those cases
            # are covered by tests-panics.art rather than here
            skipped.add(c.name & " (" & e.msg & ")")
            continue
        inc compared

        if r.ok != c.ok:
            fails.add(Failure(name: c.name, what: "match",
                              wanted: $c.ok, got: $r.ok))
            continue
        if not c.ok:
            continue

        # captures, by name, compared structurally rather than by rendering
        for name, wanted in c.captures:
            if name notin r.captures:
                fails.add(Failure(name: c.name, what: "capture " & name,
                                  wanted: $wanted, got: "absent"))
            else:
                let got = asItem(r.captures[name], c.isBlock)
                if got != wanted:
                    fails.add(Failure(name: c.name, what: "capture " & name,
                                      wanted: $wanted, got: $got))
        for name, _ in r.captures:
            if name notin c.captures and name notin c.collected:
                fails.add(Failure(name: c.name, what: "capture " & name,
                                  wanted: "absent",
                                  got: $asItem(r.captures[name], c.isBlock)))

        for name, wanted in c.collected:
            if name notin r.collected:
                fails.add(Failure(name: c.name, what: "collect " & name,
                                  wanted: $wanted.len & " items", got: "absent"))
            else:
                let mine = r.collected[name]
                if mine.len != wanted.len:
                    fails.add(Failure(name: c.name, what: "collect " & name,
                                      wanted: $wanted.len & " items",
                                      got: $mine.len & " items"))
                else:
                    for i in 0 ..< mine.len:
                        let got = asItem(mine[i], c.isBlock)
                        if got != wanted[i]:
                            fails.add(Failure(name: c.name,
                                              what: &"collect {name}[{i}]",
                                              wanted: $wanted[i], got: $got))

    echo &"differential: {compared} cases compared, {fails.len} disagreements"
    if skipped.len > 0:
        echo &"  skipped {skipped.len}:"
        for s in skipped: echo "    ", s
    for f in fails:
        echo &"  DIFFER {f.name} / {f.what}"
        echo &"    interpreted: {f.wanted}"
        echo &"    compiled:    {f.got}"
    if fails.len > 0: quit(1)

main()
