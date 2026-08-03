# Carpintero manual

The complete reference for the dialect. If you are here to *learn* it,
[TUTORIAL.md](TUTORIAL.md) is the guided path and this is what you reach
for afterwards; the design rationale lives in
[proposal.md](proposal.md). Everything here is exercised by `demo.art`
(71 checks, the readable tour) and `tests.art` (354 checks, the
regression suite) against Arturo 0.10.0.

```red
import ./"carpintero.art"!
```

## The whole dialect on one screen

```red
;; entry points
scan  input rule          ; captures dictionary, or null
scan? input rule          ; boolean
scan.prefix input rule    ; [reached: N captures: [...]]
scan.memo: ['a 'b] i r    ; memoize named rules for this scan
scanError                 ; report for the most recent failed scan

;; quantify            ;; choose            ;; advance
some rule               rule | rule          to rule
any  rule               [ ... ]  (group)     thru rule
opt  rule                                    skip
4    rule              ;; look               end
between 2 5 rule        ahead rule
                        not rule
;; capture            ;; descend           ;; escape
capture 'name rule      into rule            do    [ ... ]
collect 'name rule                           defer [ ... ]
keep rule                                    fail  "message"
                       ;; commit             quote value
                        cut

;; terminals           string  char  charset  :type  'word  quote v
;; charsets            charset "a-z0-9"  csUnion  csIntersect  csComplement
;; utilities           stripComments src     do loadSafe "file.art"
```

Three things that catch everyone once:

- **The whole input must match.** Use `scan.prefix` otherwise.
- **`["a" | "ab"]` never matches `"ab"`.** Ordered choice commits to the
  first arm. Order alternatives longest-first.
- **Rule blocks are never evaluated as code**, so `[some charset "a-z"]`
  cannot work. Build charsets outside the rule and name them.

## Entry points

### `scan input rule`

Matches `input`, a string or a block, against `rule`, a block of
grammar. Returns a **dictionary of captures** on success (empty if the
rule captured nothing) or **`null`** on failure. Nothing else is ever
`null`, so `null?` on the result is the failure test.

The **whole input must match**. A rule that matches a prefix and stops
short is a failure.

Attributes:

- `scan.prefix` accepts a prefix match. The result becomes
  `#[reached: <position> captures: <dictionary>]`, where `reached` is
  how far the match extended. This is the hook for search-and-extract
  idioms.
- `scan.memo: ['ruleA 'ruleB]` memoizes the named rules for this scan.
  See [Memoization](#memoization).

### `scan? input rule`

Boolean form. No attributes.

### `scanError`

A human-readable report for the **most recent failed** scan, built from
the farthest-failure record:

```
scan "2026-08-0x" date
print scanError
; scan failed at line 1, column 10 — expected: digit  (while matching: day)
;     2026-08-0x
;              ^
```

- The failing terminal is reported by its **rule name** when it has one
  (`digit`, not `charset 0-9`).
- The innermost enclosing block rule or capture name becomes the
  *while matching* context.
- For string input the offending line is shown with a caret under the
  column. For block input the report gives an index, or, when the
  failure is inside `into`, a **path of indices** into the nested
  structure (`scan failed at index path 1 1`).
- Failures inside the operand of `not` are excluded: there, failing is
  the grammar succeeding.

## Matching, the ground rules

- Matching is **case-sensitive**, everywhere, for every terminal.
- String positions are **characters, not bytes**. The dialect agrees
  with `size`, `slice`, and the rest of the language about what
  position N means.
- `[a b | c]` parses as `[[a b] | c]`: **alternation binds loosely,
  blocks group.** Write the parentheses you mean.
- Ordered choice is **committed**: once an alternative succeeds, later
  failure of the *surrounding* rule does not revisit it. See
  [PEG pitfalls](#peg-pitfalls-and-their-idiomatic-fixes).

## Terminals

| Terminal | On string input | On block input |
| --- | --- | --- |
| `"abc"` | those characters | one element equal to the string |
| `'a'` (char) | that character | one element equal to the char |
| a charset | one char in the set | one char element in the set |
| `:integer`, `:string`, `:block`, `:label`, ... | (panics) | one element of that type |
| `'word` (literal) | (panics) | that exact word |
| `quote value` | (panics) | the next element equal to `value`, even a dialect keyword |
| `skip` | any one char | any one element |
| `end` | end of input | end of input |

An empty string `""` matches nothing and consumes nothing (string input
only).

`quote` compares with `=`, which is exact for every type except one: on
Arturo 0.10.0 a `:symbolliteral` is not equal to itself, so `[quote '+]`
can never match a `'+`. The `:symbolliteral` type terminal is unaffected
— match the type and inspect the capture. See
[bug 4](bugs/README.md#4-symbolliteral-equalityart-a-symbolliteral-is-not-equal-to-itself).

### Charsets

```red
digit: charset "0-9"
ident: charset "a-z0-9-"      ; trailing dash is a literal dash
odd:   charset "a-c\-x"       ; backslash-dash is a literal dash too
```

Inside `charset "..."`, `-` between two characters is an inclusive
codepoint range. A leading, trailing, or backslash-escaped dash is the
literal character. An inverted range (`"z-a"`) panics.

The `charset` call belongs **outside** the rule, always. Rule blocks are
never evaluated as code, so `[some charset "a-z"]` does not call
anything — the block simply holds the word `charset`, which resolves to
the builtin function, which is not a rule. The grammar pre-pass catches
this and names the word:

```
carpintero: rule word 'charset' resolves to a function, not a rule.
Rule blocks are never evaluated as code, so a call cannot be inlined
into one: build the value outside the rule, bind it to a name, and use
the name in the rule.
```

The same applies to `csUnion` and friends, and to any other call you are
tempted to inline.

Charsets are values and compose (the unprefixed words belong to core,
for blocks):

```red
hexdigit:  csUnion digit charset "a-f"
consonant: csIntersect charset "a-z" csComplement charset "aeiou"
```

`csComplement` inverts over the full codepoint space (0 through
1114111).

## Vocabulary

### Quantifiers

| Form | Meaning |
| --- | --- |
| `some rule` | one or more |
| `any rule` | zero or more |
| `opt rule` | zero or one |
| `4 rule` | exactly N |
| `between 2 5 rule` | N through M, greedy |

All repetition is **greedy and does not give back**: `[any "a" "a"]`
can never match. All loops carry the **progress guard**: an iteration
that matches without consuming input ends the loop, so nullable loop
bodies (`some [opt "a"]`) terminate instead of hanging.

### Sequence, choice, grouping

A block is a sequence. `|` separates ordered alternatives. Inside a
rule block it is dialect vocabulary, not Arturo's pipe operator, and the
two never meet because rule blocks are never evaluated as code.
First match wins. There is no ambiguity and no reconsideration.

### Advancing

| Form | Meaning |
| --- | --- |
| `to rule` | advance to just **before** the next match of `rule` |
| `thru rule` | advance **through** the next match of `rule` |
| `skip` | consume one char / element |
| `end` | succeed only at end of input |

`to` and `thru` fail if `rule` never matches in the rest of the input.

### Lookahead

| Form | Meaning |
| --- | --- |
| `ahead rule` | succeed if `rule` matches here, consuming nothing |
| `not rule` | succeed if `rule` does **not** match here, consuming nothing |

### Captures

```red
capture 'name rule        ; bind name to the span rule consumed
collect 'name rule        ; gather everything keep kept inside rule
keep rule                 ; inside collect: keep the span rule consumed
```

- A capture takes the **span of input the rule consumed**: a substring
  for string input, the matched elements for block input. To compute a
  *value* from it, post-process the captures, or use a `do` escape.
- Capturing into the same name twice keeps the **last** match.
  Accumulation is what `collect`/`keep` is for.
- **Captures roll back.** A capture or keep inside an alternative that
  later fails is discarded with it: a dead parse path leaves nothing
  behind. (This deliberately diverges from Rebol/Red, in the direction
  every modern engine took.)
- `keep` outside any `collect` panics.

### Descending into blocks

```red
pair: [:integer :string]
scan [[1 "a"] [2 "b"]] [some [into pair]]
```

`into rule` (block input only) matches when the current element is a
block and `rule` matches **that block in its entirety**. Captures made
inside land correctly and roll back normally. A rule may descend into
itself: the operand starts at position 0 of a strictly smaller input,
so recursive descent is progress, not left recursion.

#### Walking a whole tree

The idiom for "find every X at any depth" is three alternatives —
match it, descend into it, or step over it — in a rule that names
itself:

```red
defn: [capture 'name :label 'function capture 'params :block]
walk: [any [keep defn | into walk | skip]]

scan src [collect 'found walk]
```

Two things about that shape are load-bearing, and getting either wrong
produces a grammar that works and quietly under-reports:

- The **`collect` wraps the walk from outside** and the recursion lives
  in `walk`. A `collect` that named itself would open a fresh
  collection at every level, and the keeps inside would land in the
  inner one instead of accumulating into the outer.
- **`defn` stops short of the body block.** It consumes up to the
  parameter list and no further, which leaves the body for the next
  step of the walk to descend into — so definitions nested inside
  function bodies are found too. Use `ahead` if you need to *check* for
  something without consuming it. A rule that swallowed the body would
  find only the outermost definition of each nest, which on Arturo's
  own source is [about half of
  them](#validation-against-arturos-own-source).

### Committing

`cut` commits the **innermost enclosing choice block**: after matching
passes `cut`, a failure later in that alternative fails the whole
choice instead of trying the next arm.

```red
scan? "ab" ["a" cut "x" | "ab"]              ; false — second arm never tried
scan? "ab" [["a" cut "x" | "z"] | "ab"]      ; true — cut is local to its block
```

Use it after a committed keyword, where trying other alternatives could
only mask the real error. It also bounds pathological backtracking.

### Host escapes

```red
do [ ... ]        ; run host code now, during matching
defer [ ... ]     ; queue host code; runs only if the whole scan succeeds
fail "message"    ; abort the scan with a panic carrying the position
```

The `do` contract: the block may run on a parse path that is later
abandoned, and therefore **may run more than once** per scan (the demo
proves it: an escape inside `some` runs once per attempt, including the
failing one). `do` blocks should compute, not mutate.

`defer` is the mutation-safe form: its block rides in the capture log,
**rolls back with a dead branch** exactly like a capture, and runs
**exactly once**, in match order, only on overall success,
after matching, during result construction.

Escape blocks may assign, call zero-arity functions, and use `set`
freely. The matcher pads each block with a trailing value before
evaluation, which sidesteps an interpreter bug (see
[bugs/](bugs/README.md)).

## Grammar hygiene, checked for you

Before matching, once per rule set (cached, keyed by the rule and every
resolved rule body, so redefining a rule re-triggers the check):

- **Unbound rule words** are an immediate panic naming the word, not a
  match failure.
- **Left recursion**, whether direct, indirect, or through a nullable
  prefix, is a panic naming the cycle:
  `carpintero: left recursion detected: expr -> expr`.
  Left recursion is rejected, not supported. Write iteration
  (`[digit any ["+" digit]]`) instead of left-recursive rules.

## Memoization

Off by default, because for ordinary grammars it costs more than it
saves. Opt in per rule, per scan:

```red
scan.memo: ['jvalue 'jstring] input grammar
```

A memo entry stores the end position **and the capture-log slice** the
rule produced, replayed on a hit, so captures survive. Failures
memoize too. Two documented losses on a hit: a `do` escape inside the
rule does not re-run, and the farthest-failure record is not
re-recorded.

When to reach for it: grammars where the same rule is re-tried at the
same position across alternatives. The benchmark's deliberately
pathological tower

```red
e1: [e0 "x" | e0 "y"]
e2: [e1 "x" | e1 "y"]
; ... twelve levels
```

costs 2^12 rule invocations bare (about 165 ms interpreted) and drops
to about 1.5 ms with memoization. Real grammars are effectively linear.
This is what pathological looks like, and `examples/bench.art` will
show you both numbers on your machine.

## Performance expectations

An interpreted matcher loses to the native regex engine by roughly
**four orders of magnitude** (`examples/bench.art`: about 22 ms vs
0.004 ms validating 200 dates). What the dialect offers instead is
composability and rules that are data, plus a Phase 3 compiled core
that narrows the gap without closing it. PEG without memoization is
exponential in pathological grammars (see above) and effectively
linear in real ones.

Cost is linear in the length of the input and roughly constant per
character — `examples/bench.art` ends by scanning inputs that double
and printing the cost per kilobyte, which should stay flat. If you are
tuning a grammar, the things that actually move the needle are, in
order: give an alternation its cheapest discriminating terminal first,
so dead arms die on their first character; prefer a charset to an
alternation of literals, since a charset is one table lookup;
and reach for `scan.memo` only for a rule that is genuinely re-tried
at the same position, because the table costs more than it saves
otherwise.

## PEG pitfalls, and their idiomatic fixes

- **Ordered choice hides prefixes.** `["a" | "ab"]` never matches
  `"ab"`: the first arm wins and is not revisited. Fix: order
  alternatives longest-first, or guard with lookahead
  (`["ab" | "a" not "b"]`).
- **Repetition is greedy and does not give back.** `[any "a" "a"]`
  never matches. Fix: make the boundary explicit,
  `[any ["a" ahead "a"] "a"]`, or restructure with `to`/`thru`.
- **Ambiguity is resolved silently.** Where a CFG tool would report an
  ambiguous grammar, ordered choice just picks the first arm. When two
  arms can match the same input, the order *is* the specification.
  Write it deliberately.

## Comment-safe source loading

Two utilities ride along because the 0.10.0 lexer does not fully
ignore comment contents: a `\-` in a comment hangs the file loader, and
other contents corrupt the token stream (see `bugs/`).

```red
stripComments src         ; source string -> source string, comments gone
do loadSafe "file.art"    ; read, strip, lex — the lexer never sees a comment
```

The stripper is itself a nine-rule Carpintero grammar: it respects
double-quoted strings with escapes, nested curly strings, and char
literals, and keeps newlines so line numbers survive. `loadSafe` pads
the lexed block with a trailing `true`, so its `do` result is the
padding, not the file's last value. Evaluate at top level, where
definitions bind globally. `examples/safeload.art` runs the repro file
that hangs `arturo` directly.

## Validation against Arturo's own source

`demo.art` and `tests.art` are grammars written against inputs chosen to
exercise them, which is the weaker half of a testing story. The other
half is `examples/arturo-corpus.art`: the dialect turned loose on a
checkout of Arturo itself — 173 `.art` files, 1,074,474 bytes of source
nobody wrote with this package in mind.

```
git clone --depth 1 https://github.com/arturo-lang/arturo
arturo examples/arturo-corpus.art ./arturo
```

It asks two questions.

### Is `stripComments` safe?

The property that matters for a source rewriter is that rewriting never
changes the program. That is a differential test: lex each file twice,
once raw and once stripped, and compare the blocks. Arturo's own test
suite is a hostile corpus for this by construction — apostrophes inside
comments, commented-out code, nested curly strings, char literals,
deliberate syntax errors.

| Result | Files |
| --- | --- |
| Stripped source lexes to the same block as the raw source | 166 |
| Never lexed in either form | 5 |
| Compared unequal | 2 |

The five that never lexed are four deliberate syntax-error fixtures from
`tests/errors/` and one script that is not valid Arturo standalone. They
fail identically with and without stripping, which is the stripper
behaving correctly rather than failing.

The two that compared unequal are the interesting ones, and the stripper
was not at fault: on 0.10.0 **a `:symbolliteral` is not equal to
itself**, so any file containing a `'+` compares unequal to a
byte-identical copy of itself. That is
[bug 4](bugs/README.md#4-symbolliteral-equalityart-a-symbolliteral-is-not-equal-to-itself),
found by using the dialect rather than by writing it. It reaches one
corner of Carpintero: `[quote '+]` cannot match a `'+` in block input,
because `quote` compares with `=`. Match `:symbolliteral` and inspect
the capture instead.

So: zero cases where stripping a comment changed the program.

### Does a block grammar hold up off its home turf?

The second half of the run is the tree walk from
[above](#walking-a-whole-tree), pointed at every file: find every
function definition, in all the spellings the language allows —
`function`, `method`, and the `$` sigil, block-bodied or `->`-bodied.
`$` lexes as a bare symbol, so `quote $` is what distinguishes a
definition from the arithmetic that lexes identically (`g: + [1 2]`).

It found **287 definitions, 235 block-bodied and 52 after an arrow**.
Cross-checked file by file against an independent regex, the two agree
everywhere except three files — and in all three the grammar is right:
twice because it does not see commented-out definitions (the regex
does), once because the regex miscounted.

The first version of that grammar consumed the body block along with the
head, and found 97. Everything else was nested inside a `describe`
block, another function, or an `if` arm. That is the argument for `into`
in one number.

### What it costs

About two and a half minutes for the megabyte, roughly 8 KB of source
per second, nearly all of it in `stripComments` — which is character-level
matching over the whole input, the worst case for an interpreted matcher.
The block-grammar half runs on already-lexed structure and is
comparatively free. See [Performance expectations](#performance-expectations).

## Differences from Rebol/Red PARSE

| Rebol/Red | Carpintero | Why |
| --- | --- | --- |
| `parse` | `scan` | core owns `parse` |
| case-insensitive default | case-sensitive always | one comparison rule everywhere |
| `set x` / `copy x` | `capture 'x` | one form, span-of-input, and it **rolls back** |
| `collect` / `keep` | `collect 'x` / `keep` | kept values roll back, named target |
| `(paren)` escapes | `do [...]` / `defer [...]` | re-run contract stated, deferred form sound |
| `while` | absent | `any` with a mandatory progress guard |
| `insert` / `remove` / `change` | absent | input mutation is incompatible with rollback |
| `pos:` / `:pos` mark & seek | absent | captures and `do` cover the common uses |
| datatype terminals (`integer!`) | `:integer` | the language's own type literals |
| (none) | `cut`, `scan.memo`, path-qualified block errors | later-generation additions |

The absences are scope decisions, argued in the proposal, not gaps.

## Running the tests

```
arturo demo.art     # the readable tour, 71 checks
arturo tests.art    # the regression suite, 354 checks
arturo tests.art trace
```

`tests.art` exits nonzero if anything fails and prints every failure with
what it got and what it wanted. The `trace` argument prints each section
and each check as it runs, which is how you find a case that *aborts* the
run rather than merely failing it — a distinction that matters here, since
a script that upsets the 0.10.0 interpreter tends to exit silently.

Run it from the repository root: the panic cases shell out.

That last part needs explaining, because it looks like over-engineering
and is not. Grammar errors — an unbound rule word, left recursion, `keep`
outside `collect` — panic by design, and a panic unwound through `try`
leaves the abandoned matcher frames' values on the stack, where the next
statements read them as arguments. The symptom is not a failed assertion;
it is a run that dies several lines later with no message at all. So each
of the eighteen panic cases runs in its own interpreter through
`tests-panics.art`, and counts as passed when that run started and did not
reach the end. You can run one on its own to see the message:

```
arturo tests-panics.art left-direct
```
