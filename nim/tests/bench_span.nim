## What the charset-run lowering is worth.
##
##     cd nim && nim c -d:release --hints:off -r tests/bench_span.nim
##
## A benchmark rather than a test: it asserts nothing, it prints. To see the
## other side of the comparison, delete the `spanBody` branch in
## `emitLoop` and run it again.

import std/[monotimes, times, strutils, tables]
import ../src/carpintero

proc cs(spec: string): Charset =
    var i = 0
    while i < spec.len:
        if i + 2 < spec.len and spec[i+1] == '-':
            result.addRange(int32(spec[i]), int32(spec[i+2]))
            i += 3
        else:
            result.addChar(int32(spec[i]))
            inc i

let digit = cs("0-9")
let letter = cs("a-zA-Z")

proc g(start: Node, rules: openArray[(string, Node)] = []): Grammar =
    result.start = start
    for (n, b) in rules: result.rules[n] = b

proc bench(name: string, gr: Grammar, input: string, reps: int) =
    let prog = compile(gr)
    var ok = true
    let t0 = getMonoTime()
    for _ in 0 ..< reps:
        ok = ok and scan(prog, input).ok
    let ns = (getMonoTime() - t0).inNanoseconds
    echo name, ": ",
         formatFloat(ns.float / reps.float / 1e6, ffDecimal, 2), " ms per scan",
         (if ok: "" else: " (DID NOT MATCH)")

# [some digit] over a megabyte: the whole scan is one run
bench("[some digit] over 1 MB",
      g(alt(sq(Node(kind: nkSome, body: cset(digit))))),
      repeat("0123456789", 100_000), 20)

# [some letter any [" " some letter]] over 700 kB: runs separated by
# something else, which is the shape a real character grammar has
var words = ""
for i in 0 ..< 100_000:
    if i > 0: words.add(' ')
    words.add("abcdef")
bench("[some letter any [\" \" some letter]] over 700 kB",
      g(alt(sq(Node(kind: nkSome, body: cset(letter)),
               Node(kind: nkAny, body: alt(sq(str(" "),
                    Node(kind: nkSome, body: cset(letter)))))))),
      words, 20)
