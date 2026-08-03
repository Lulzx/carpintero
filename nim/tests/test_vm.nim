## The compiled core against the semantics the manual states.
##
## Cases are taken from the interpreted suite, so a divergence here is a
## divergence from the specification, not from a hand-written expectation.

import std/[unittest, tables, strutils]
import ../src/carpintero

proc cs(spec: string): Charset =
    ## `charset "0-9a-f"`: a dash between two characters is a range.
    var i = 0
    while i < spec.len:
        if i + 2 < spec.len and spec[i+1] == '-':
            result.addRange(int32(spec[i]), int32(spec[i+2]))
            i += 3
        else:
            result.addChar(int32(spec[i]))
            inc i

let digit = cs("0-9")
let lower = cs("a-z")

proc g(start: Node, rules: openArray[(string, Node)] = []): Grammar =
    result.start = start
    for (n, b) in rules: result.rules[n] = b

suite "terminals":
    test "a literal matches the whole input":
        check scanQ(g(alt(sq(str("hello")))), "hello")
        check not scanQ(g(alt(sq(str("hello")))), "hell")
        check not scanQ(g(alt(sq(str("hello")))), "helloo")

    test "charsets":
        check scanQ(g(alt(sq(cset(digit)))), "7")
        check not scanQ(g(alt(sq(cset(digit)))), "x")

    test "skip and end":
        check scanQ(g(alt(sq(Node(kind: nkSkip), Node(kind: nkEnd)))), "z")

suite "quantifiers":
    let someDigits = g(alt(sq(Node(kind: nkSome, body: cset(digit)))))
    let anyDigits = g(alt(sq(Node(kind: nkAny, body: cset(digit)))))

    test "some needs one":
        check scanQ(someDigits, "1")
        check scanQ(someDigits, "1234567")
        check not scanQ(someDigits, "")

    test "any accepts none":
        check scanQ(anyDigits, "")
        check scanQ(anyDigits, "42")

    test "exactly n":
        let four = g(alt(sq(Node(kind: nkRep, count: 4, repBody: cset(digit)))))
        check scanQ(four, "2026")
        check not scanQ(four, "202")
        check not scanQ(four, "20268")

    test "between bounds":
        let bt = g(alt(sq(Node(kind: nkBetween, lo: 2, hi: 4, btBody: cset(digit)))))
        check not scanQ(bt, "1")
        check scanQ(bt, "12")
        check scanQ(bt, "1234")
        check not scanQ(bt, "12345")

    test "a nullable loop body terminates instead of hanging":
        # `any [opt "a"]`: the body matches without consuming, and the
        # progress guard is what stops this being an infinite loop
        let nullableLoop = g(alt(sq(
            Node(kind: nkAny, body: alt(sq(Node(kind: nkOpt, body: str("a"))))),
            Node(kind: nkEnd))))
        check scanQ(nullableLoop, "")
        check scanQ(nullableLoop, "aaa")

suite "ordered choice":
    test "first match wins, and hides a longer prefix":
        # the documented PEG pitfall: ["a" | "ab"] never matches "ab"
        let hidden = g(alt(sq(str("a")), sq(str("ab"))))
        check scanQ(hidden, "a")
        check not scanQ(hidden, "ab")

    test "longest first fixes it":
        let fixed = g(alt(sq(str("ab")), sq(str("a"))))
        check scanQ(fixed, "a")
        check scanQ(fixed, "ab")

    test "backtracking into a later arm":
        let two = g(alt(sq(str("ab"), str("c")), sq(str("ab"), str("d"))))
        check scanQ(two, "abd")

suite "lookahead":
    test "not":
        let notDigit = g(alt(sq(Node(kind: nkNot, body: cset(digit)),
                               Node(kind: nkSkip))))
        check scanQ(notDigit, "x")
        check not scanQ(notDigit, "5")

    test "ahead does not consume":
        let ahead = g(alt(sq(Node(kind: nkAhead, body: str("ab")), str("abc"))))
        check scanQ(ahead, "abc")

    test "a successful ahead keeps what it captured":
        # Verified against the interpreted matcher, which returns [peek:ab]
        # here. `not` rolls its operand's captures back and `ahead` does not,
        # so the two lookaheads differ; see the README on whether that is
        # meant to be the contract.
        let r = scan(g(alt(sq(
            Node(kind: nkAhead, body: alt(sq(
                Node(kind: nkCap, capName: "peek", capBody: alt(sq(str("ab"))))))),
            str("abc")))), "abc")
        check r.ok
        check r.captures["peek"] == "ab"

    test "not discards what its operand captured":
        let r = scan(g(alt(sq(
            Node(kind: nkNot, body: alt(sq(
                Node(kind: nkCap, capName: "nope", capBody: alt(sq(str("zz"))))))),
            str("abc")))), "abc")
        check r.ok
        check "nope" notin r.captures

suite "to and thru":
    test "to stops before the match":
        let r = scan(g(alt(sq(
            Node(kind: nkCap, capName: "head",
                 capBody: alt(sq(Node(kind: nkTo, body: str(","))))),
            Node(kind: nkSkip),
            Node(kind: nkAny, body: Node(kind: nkSkip))))), "abc,def")
        check r.ok
        check r.captures["head"] == "abc"

    test "thru consumes the match":
        let r = scan(g(alt(sq(
            Node(kind: nkCap, capName: "head",
                 capBody: alt(sq(Node(kind: nkThru, body: str(","))))),
            Node(kind: nkAny, body: Node(kind: nkSkip))))), "abc,def")
        check r.ok
        check r.captures["head"] == "abc,"

suite "captures":
    let date = g(
        alt(sq(
            Node(kind: nkCap, capName: "year",
                 capBody: alt(sq(Node(kind: nkRep, count: 4, repBody: rule("digit"))))),
            str("-"),
            Node(kind: nkCap, capName: "month",
                 capBody: alt(sq(Node(kind: nkRep, count: 2, repBody: rule("digit"))))),
            str("-"),
            Node(kind: nkCap, capName: "day",
                 capBody: alt(sq(Node(kind: nkRep, count: 2, repBody: rule("digit"))))))),
        {"digit": alt(sq(cset(digit)))})

    test "the manual's opening example":
        let r = scan(date, "2026-08-03")
        check r.ok
        check r.captures["year"] == "2026"
        check r.captures["month"] == "08"
        check r.captures["day"] == "03"

    test "a failed scan reports where":
        let r = scan(date, "2026-08-0x")
        check not r.ok
        check r.failPos == 9

    test "captures roll back with a dead alternative":
        # the divergence from Rebol: a capture made in an arm that later
        # fails leaves nothing behind
        let roll = g(alt(
            sq(Node(kind: nkCap, capName: "x", capBody: alt(sq(str("ab")))), str("!")),
            sq(str("abc"))))
        let r = scan(roll, "abc")
        check r.ok
        check "x" notin r.captures

suite "collect and keep":
    test "collect gathers what keep kept":
        let words = g(
            alt(sq(Node(kind: nkCollect, capName: "words", capBody:
                alt(sq(Node(kind: nkAny, body: alt(
                    sq(Node(kind: nkKeep, body: rule("word"))),
                    sq(Node(kind: nkSkip))))))))),
            {"word": alt(sq(Node(kind: nkSome, body: cset(lower))))})
        let r = scan(words, "one, two, three")
        check r.ok
        check r.collected["words"] == @["one", "two", "three"]

suite "cut":
    test "cut commits the choice it is in":
        # after the cut, failing the rest of the arm fails the whole block
        # instead of trying the next alternative
        let withCut = g(alt(
            sq(str("a"), Node(kind: nkCut), str("b")),
            sq(str("a"), str("c"))))
        check scanQ(withCut, "ab")
        check not scanQ(withCut, "ac")

    test "without the cut the second arm is reached":
        let noCut = g(alt(
            sq(str("a"), str("b")),
            sq(str("a"), str("c"))))
        check scanQ(noCut, "ac")

    test "a cut does not leak into a nested block":
        # [a [b | c] d] with a cut before the nested block: the inner choice
        # must still be free to try c
        let nested = g(alt(sq(
            str("a"), Node(kind: nkCut),
            alt(sq(str("b")), sq(str("c"))),
            str("d"))))
        check scanQ(nested, "abd")
        check scanQ(nested, "acd")

suite "left recursion":
    test "direct is rejected with the cycle named":
        let lr = g(alt(sq(rule("x"))), {"x": alt(sq(rule("x"), str("a")))})
        expect CompileError:
            discard compile(lr)

    test "indirect is rejected too":
        let lr = g(alt(sq(rule("x"))),
                   {"x": alt(sq(rule("y"))), "y": alt(sq(rule("x"), str("a")))})
        expect CompileError:
            discard compile(lr)

    test "right recursion is fine":
        let rr = g(alt(sq(rule("x"))),
                   {"x": alt(sq(str("a"), rule("x")), sq(str("a")))})
        check scanQ(rr, "aaaa")

    test "an unbound rule word is an error, not a match failure":
        expect CompileError:
            discard compile(g(alt(sq(rule("nosuch")))))

suite "prefix scanning":
    test "scan.prefix reports how far it reached":
        let r = scan(g(alt(sq(Node(kind: nkSome, body: cset(digit))))),
                     "123abc", prefix = true)
        check r.ok
        check r.reached == 3
