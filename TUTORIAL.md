# Getting started with Carpintero

This is the guided path: one grammar at a time, each building on the
last, ending with Arturo reading its own source. It assumes you know
Arturo and nothing about PARSE. [MANUAL.md](MANUAL.md) is the reference
to reach for once the shape is familiar. [proposal.md](proposal.md)
argues why the dialect looks like this.

Every snippet below runs as written. Start a file with the import and
paste as you go:

```red
import ./"carpintero.art"!
```

## 1. A grammar is a block

There is no parser generator, no compile step, no separate syntax. A
grammar is an Arturo block, and `scan` matches input against it.

```red
scan? "2026-08-03" ["2026-08-03"]     ; true
```

That block is a **sequence**: match a string literal, then stop. `scan?`
answers yes or no. Its sibling `scan` returns a dictionary of whatever
the grammar captured (an empty one here, because nothing was captured
yet), or `null` if the match failed.

One rule to internalise now, because it explains most early surprises:
**the whole input must match.** A grammar that matches a prefix and
stops has failed.

```red
scan? "2026-08-03" ["2026"]           ; false, four characters left over
scan.prefix "2026-08-03" ["2026"]     ; [reached:4 captures:[]]
```

`scan.prefix` is the escape hatch when a prefix is genuinely what you
want. `reached` tells you how far it got.

## 2. Character sets and repetition

A charset is a value you build once, outside the grammar, and name:

```red
digit: charset "0-9"

scan? "7"     [digit]           ; true
scan? "2026"  [4 digit]         ; true, exactly four
scan? "2026"  [some digit]      ; true, one or more
scan? ""      [any digit]       ; true, zero or more
scan? "12-99" [some digit "-" some digit]
```

!!! warning "Charsets are built outside the rule, always"
    Rule blocks are **never evaluated as code**. Writing
    `[some charset "a-z"]` does not call `charset`. The block just
    holds the bare word `charset`, which resolves to the builtin
    function, which is not a grammar rule. Carpintero catches this
    before matching starts and tells you so by name, but the fix is
    always the same: bind the charset to a name first, use the name in
    the rule.

The quantifiers are `some` (1+), `any` (0+), `opt` (0 or 1), a bare
integer for exactly N, and `between N M`. All of them are **greedy and
never give back**. §7 covers what that costs.

## 3. Captures

`capture 'name rule` binds a name to the span of input that `rule`
consumed.

```red
digit: charset "0-9"

date: [
    capture 'y [4 digit] "-"
    capture 'm [2 digit] "-"
    capture 'd [2 digit]
]

r: scan "2026-08-03" date
; r  => [y:2026 m:08 d:03]
; r\y => "2026"
```

A capture is always the *input it consumed*, never a computed value. If
you want an integer, convert it afterwards. The grammar's job is to
find the span, not to interpret it.

To gather a repeating thing, pair `collect` with `keep`:

```red
alpha: charset "a-z"
word:  [some alpha]

scan "a,bb,ccc" [collect 'fields [keep word any ["," keep word]]]
; => [fields:[a bb ccc]]
```

The property that separates this from Rebol and Red: **captures roll
back**. A capture made inside an alternative that later fails is
discarded along with it. A dead parse path leaves nothing behind.

## 4. Ordered choice, and the trap in it

`|` separates alternatives, and blocks group. First match wins, and the
winner is never reconsidered:

```red
scan? "ab" ["a"  | "ab"]      ; false  ← the trap
scan? "ab" ["ab" | "a"]       ; true
```

The first line reads like it should work. It does not: `"a"` matches,
the choice commits, and then the leftover `b` fails the whole scan,
without ever going back to try `"ab"`. This is ordered choice, and it is
the deal PEG makes. In exchange you get no ambiguity and no surprise
exponential blowup from a grammar that quietly matched two ways.

The rule of thumb: **order alternatives longest-first**, or make the
boundary explicit with lookahead (`["ab" | "a" not "b"]`).

Note also that `|` binds loosely: `[a b | c]` is `[[a b] | c]`. Write
the grouping brackets you mean.

## 5. Rules that name each other, and recurse

A rule is a word bound to a block, and rules refer to each other freely,
including to themselves:

```red
nested: ["(" any [nested | not ")" skip] ")"]

scan? "(a(b)c)" nested        ; true
scan? "(a(b)c"  nested        ; false
```

That is the whole of balanced-parenthesis matching, and it is why this
is not a regex library. Recursion through the *middle* or *end* of a
rule is fine. Recursion at the **start** is not, and Carpintero rejects
it before matching rather than hanging:

```red
expr: [expr "+" digit | digit]
; carpintero: left recursion detected: expr -> expr
```

Write the iteration instead, `[digit any ["+" digit]]`, which is what
you meant anyway.

## 6. When it fails, ask why

`scan` returning `null` tells you nothing useful on its own. `scanError`
reports the **farthest** point the matcher reached, which is almost
always where the real problem is:

```red
scan "2026-08-0x" date
print scanError
; scan failed at line 1, column 10 — expected: digit  (while matching: d)
;     2026-08-0x
;              ^
```

`expected:` names the terminal by its **rule name** when it has one,
which is a second reason to name your charsets. `while matching:` is
the innermost enclosing rule or capture, here the capture `'d`.

## 7. Greedy means greedy

```red
scan? "aa" [any "a" "a"]                ; false
scan? "aa" [any ["a" ahead "a"] "a"]    ; true
```

`any "a"` eats both characters and will not give one back for the `"a"`
that follows, so the first line never matches, for *any* input.
`ahead` fixes it by making the loop check that another `"a"` follows
before consuming the current one, and it matches without consuming. Its
partner `not` succeeds when its operand does *not* match.

If a grammar of yours fails on input you are certain is correct, a
greedy loop that swallowed the thing after it is the first suspect.

## 8. Blocks as input

Everything so far worked on strings. The same grammars work on
**blocks**, and since `to :block` turns Arturo source into a block, a
grammar can match Arturo code itself.

On block input the terminals become the language's own type literals,
and `'word` matches an exact word:

```red
src: to :block {add: function [a b][a+b]}

scan src [capture 'name :label 'function capture 'p :block capture 'body :block]
; => [name:[add] p:[[a b]] body:[[a + b]]]
```

`:label` is `add:`, `'function` is the literal word, and each `:block`
is one block element. Note the captures are blocks now: a capture is
the span of input consumed, and on block input a span is a block of
elements.

## 9. Descending, and walking a whole tree

`into rule` matches when the current element is a block *and* `rule`
matches that block in its entirety. Combined with a rule that names
itself, it walks a nested structure to any depth:

```red
defn: [capture 'name :label 'function capture 'params :block]
walk: [any [keep defn | into walk | skip]]

b: to :block {outer: function [][ inner: function [][1] ]}
scan b [collect 'found walk]
; found: [[outer function []] [inner function []]]
```

Read `walk` as the three things that can happen at each element: it
starts a definition, or it is a block worth descending into, or it is
none of our business and we step over it. That is the whole idiom, and
it is most of what you need for source analysis.

Two things worth noticing:

- `defn` deliberately stops at the parameter block without consuming the
  body. That is what leaves the body for the *next* step of the walk to
  descend into, so definitions nested inside function bodies are found
  too. A rule that swallowed the body would silently miss them.
- The `collect` wraps the walk from **outside**, and the recursion is in
  `walk`. A `collect` that named itself would open a fresh collection at
  every level and the inner keeps would never reach the outer one.

## 10. The real thing

`examples/arturo-corpus.art` is §9 pointed at Arturo's own source tree:
every `.art` file in a checkout, comments stripped by a second Carpintero
grammar first. Read it, then run it:

```
git clone --depth 1 https://github.com/arturo-lang/arturo
arturo examples/arturo-corpus.art ./arturo
```

What it found is written up in
[the manual](MANUAL.md#validation-against-arturos-own-source), including
the interpreter bug it turned up.

## Where to go next

- [MANUAL.md](MANUAL.md), the complete reference: every word, the error
  report, memoization, `cut`, `defer`, the PEG pitfalls in full.
- `demo.art`, the same ground as this tutorial in executable form, 71
  checks, printing as it goes.
- `examples/`: [JSON in fifteen rules, RFC 4180 CSV in a dozen, the
  self-scan, and the benchmarks](examples/README.md).
