## The one-pass wire reader against the `std/json` reader.
##
## `wire.nim` exists only to be faster than `load.nim` on the same text, so
## the test that matters is that they produce the same `Item`s. The cases
## below cover every tag; passing a file of wire-format inputs runs the same
## comparison over a real corpus:
##
##     arturo adapter/dump-wire.art ../arturo /tmp/inputs.txt
##     CARPINTERO_WIRE_CORPUS=/tmp/inputs.txt nim c --hints:off -r tests/test_wire.nim
##
## The path arrives in the environment rather than on the command line
## because `unittest` reads the command line itself, as a test-name filter.

import std/[json, os, unittest]
import ../src/carpintero/[items, load, wire]

proc bothWays(s: string): (Item, Item) =
    ## The same text through each reader, as one block item apiece.
    let viaWire = readWire(s)
    let tree = parseJson(s)
    var viaJson: seq[Item] = @[]
    for e in tree[1]: viaJson.add(loadItem(e))
    (Item(kind: itBlock, items: viaWire.items), Item(kind: itBlock, items: viaJson))

proc agree(s: string): bool =
    let (a, b) = bothWays(s)
    a == b

suite "wire":
    test "every tag reads as the JSON path reads it":
        check agree("""["block",[["w","print"],["s","hi"],["y","+"],["l","name"]]]""")
        check agree("""["block",[["t","lit"],["q","'+"],["T",":string"],["n",""]]]""")
        check agree("""["block",[["i",42],["i",-7],["f",1.5],["c",65],["g",true],["g",false]]]""")
        check agree("""["block",[["o","path",""],["o","quantity","1 m"]]]""")

    test "nesting, including empty blocks":
        check agree("""["block",[["b",[]],["b",[["b",[["w","deep"]]]]]]]""")
        check agree("""["block",[["d",[]],["d",[["k",["i",1]],["j",["b",[["w","x"]]]]]]]]""")

    test "escapes":
        check agree("""["block",[["s","a\"b"],["s","a\\b"],["s","a\nb\tc\rd"]]]""")
        check agree("""["block",[["s",""],["s",""]]]""")
        check agree("""["block",[["s","no escapes at all"]]]""")

    test "an integer too large for int64 reads as zero, as it does through JSON":
        check agree("""["block",[["i",1231312371823871236182736128376128376]]]""")

    test "text input":
        let w = readWire("""["text","two words"]""")
        check w.isText
        check w.text == "two words"
        check readWire("""["text","a\nb"]""").text == "a\nb"

    test "malformed input raises rather than misreads":
        expect WireError: discard readWire("""["block",[["w","unclosed"]""")
        expect WireError: discard readWire("""["block",[["z","bad tag"]]]""")
        expect WireError: discard readWire("""["nope",[]]""")

    test "the corpus, when one is given":
        let corpus = getEnv("CARPINTERO_WIRE_CORPUS")
        if corpus.len > 0 and fileExists(corpus):
            var n = 0
            for line in corpus.lines:
                if line.len == 0: continue
                check agree(line)
                inc n
            echo "  compared ", n, " corpus inputs"
        else:
            skip()
