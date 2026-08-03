import ../src/carpintero
import std/tables

proc cs(spec: string): Charset =
    var i = 0
    while i < spec.len:
        if i + 2 < spec.len and spec[i+1] == '-':
            result.addRange(int32(spec[i]), int32(spec[i+2]))
            i += 3
        else:
            result.addChar(int32(spec[i]))
            inc i

let lower = cs("a-z")
var g: Grammar
g.start = alt(sq(Node(kind: nkCollect, capName: "words", capBody:
    alt(sq(Node(kind: nkAny, body: alt(
        sq(Node(kind: nkKeep, body: rule("word"))),
        sq(Node(kind: nkSkip)))))))))
g.rules["word"] = alt(sq(Node(kind: nkSome, body: cset(lower))))
echo compile(g)
