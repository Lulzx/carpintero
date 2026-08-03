## The compiled core as a shared library, callable from Arturo.
##
##     nim c --app:lib -d:release -o:libcarpintero.dylib src/carpintero_ffi.nim
##
## Arturo has no way to add a builtin without changing Arturo, but it can call
## a shared library through `call.external`, so that is the seam. The FFI it
## offers carries at most two scalar arguments and returns one, which means
## the grammar and the input cross as JSON strings in the tagged format
## `adapter/export.art` already writes.
##
## What comes back is **spans**, not values: where each capture started and
## ended, and which `into` descent it was inside. The caller owns the input
## and can slice its own values from those coordinates, so nothing has to be
## reconstructed on the Arturo side. That keeps value identity exact for the
## types this library models opaquely, and it is cheaper than serialising
## matched values back.
##
## One compiled program is cached per distinct grammar string, so scanning a
## corpus with one grammar compiles it once.

import std/[json, tables, strutils]
import carpintero
import carpintero/[load, wire]

var programs = initTable[string, Program]()
var lastError = ""

proc jsonSpan(s: CapSpan): JsonNode =
    result = newJObject()
    var p = newJArray()
    for i in s.path: p.add(newJInt(int(i)))
    result["path"] = p
    result["from"] = newJInt(int(s.start))
    result["to"] = newJInt(int(s.finish))

proc give(s: string): cstring =
    ## The caller reads the string and never frees it, which the FFI has no
    ## way to arrange. One allocation per scan is leaked deliberately; the
    ## alternative is handing back a pointer into a Nim string that the GC
    ## may move or collect while Arturo is still reading it.
    let buf = cast[cstring](alloc0(s.len + 1))
    if s.len > 0:
        copyMem(buf, s.cstring, s.len)
    buf

proc cpScan(grammarJson: cstring, inputJson: cstring): cstring
        {.exportc, dynlib, cdecl.} =
    ## Compile (or reuse) the grammar, scan the input, and report the result
    ## as JSON. On any failure the reply carries `error` and the caller is
    ## expected to fall back to the interpreted matcher.
    try:
        let gkey = $grammarJson
        if gkey notin programs:
            programs[gkey] = compile(loadGrammar(parseJson(gkey)))
        let prog = programs[gkey]

        # ["block",[...]] or ["text","..."], the compact form fast.art emits.
        # This is the whole of the input on every scan, so it is read in one
        # pass rather than through `std/json`: the tree and the walk over it
        # cost more than the match does (43 ms and 14 ms against 32 ms over
        # Arturo's own source). `wire.nim` is held to the JSON reader's
        # answers by `tests/test_wire.nim`.
        let inp = readWire($inputJson)
        var r: ScanResult
        if inp.isText:
            r = scan(prog, inp.text)
        else:
            r = scan(prog, inp.items)

        var reply = newJObject()
        reply["ok"] = newJBool(r.ok)
        reply["reached"] = newJInt(r.reached)

        # an array, not an object: the interpreted matcher's result carries
        # its captures in the order they closed, and a JSON object gives the
        # caller no way to preserve that
        var caps = newJArray()
        if r.ok:
            for name in r.names:
                var entry = newJObject()
                entry["name"] = newJString(name)
                if name in r.collectedSpans:
                    var arr = newJArray()
                    for s in r.collectedSpans[name]: arr.add(jsonSpan(s))
                    entry["items"] = arr
                else:
                    entry["span"] = jsonSpan(r.captureSpans[name])
                caps.add(entry)
        reply["captures"] = caps

        var exp = newJArray()
        for e in r.expected: exp.add(newJString(e))
        reply["expected"] = exp
        var fp = newJArray()
        for i in r.failPath: fp.add(newJInt(int(i)))
        reply["failPath"] = fp
        if r.failMsg.len > 0: reply["failMsg"] = newJString(r.failMsg)

        give($reply)
    except CatchableError as e:
        lastError = e.msg
        give("""{"error":""" & escapeJson(e.msg) & "}")

proc cpLastError(): cstring {.exportc, dynlib, cdecl.} =
    give(lastError)

proc cpReset(): cstring {.exportc, dynlib, cdecl.} =
    ## Drop the compiled-program cache, for a caller that redefines grammars.
    programs.clear()
    give("ok")
