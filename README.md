# Carpintero

*Documentation: <https://lulzx.com/carpintero/>*

A PARSE-class grammar dialect for [Arturo](https://arturo-lang.io): rules are
ordinary Arturo blocks that compose, nest, and recurse, and they match
strings *and* blocks, so Arturo can pattern-match its own source.

```red
digit: charset "0-9"

date: [
    capture 'year  [4 digit]  "-"
    capture 'month [2 digit]  "-"
    capture 'day   [2 digit]
]

scan "2026-08-03" date
; => [year: "2026" month: "08" day: "03"]
```

`scan` returns a dictionary of captures, or `null` on failure. `scan?`
returns a boolean. `scan.prefix` accepts a prefix match and reports how far
it reached. After a failed scan, `scanError` tells you where and why:

```
scan "2026-08-0x" date
print scanError
; scan failed at line 1, column 10 — expected: digit  (while matching: day)
;     2026-08-0x
;              ^
```

A terminal that has a rule name is reported by that name, the innermost
enclosing rule or capture becomes the while-matching context, and the
offending line is shown with a caret under the column. For block input
the report gives an index, or a path of indices into the nested
structure when the failure is inside `into`.

Block input uses the language's own type values as terminals:

```red
funcdef: [
    capture 'name :label
    'function
    capture 'params :block
    capture 'body   :block
]

scan code [any [funcdef | skip]]
```

## Vocabulary

| Group | Words |
| --- | --- |
| Quantify | `some` (1+), `any` (0+), `opt`, `N rule`, `between N M rule` |
| Choose | `\|` ordered alternation, blocks for grouping |
| Advance | `to` (exclusive), `thru` (inclusive), `skip`, `end` |
| Look | `ahead`, `not` |
| Capture | `capture 'name rule`, `collect 'name rule` + `keep rule` |
| Descend | `into rule` (match a nested block in full with its own rules) |
| Escape | `do [...]` host code, `defer [...]` commit-time host code, `quote value` literal match, `fail "msg"` |
| Commit | `cut` (commit the innermost enclosing choice) |
| Match | strings, chars, charsets, `:type` values, `'word` literals, named rules |

Charsets are values and compose: `csUnion`, `csIntersect`,
`csComplement` (the unprefixed words belong to core, for blocks).

Two utilities ride along: `stripComments` removes comments from a
source string with a Carpintero grammar, and `loadSafe` reads a file,
strips it, and returns the lexed block, sidestepping the 0.10.0 lexer
bug where comment contents can hang or corrupt the interpreter
(`examples/safeload.art` runs a file that hangs `arturo` directly).

[TUTORIAL.md](TUTORIAL.md) is the guided path from a first `scan` to
walking a source tree. [MANUAL.md](MANUAL.md) is the full reference:
every word, the error report, memoization, the PEG pitfalls and their
fixes. Semantics worth knowing, all deliberate (the design rationale
lives in [proposal.md](proposal.md)):

- The whole input must match. Use `scan.prefix` for prefix matching.
- Captures and keeps **roll back** when an alternative fails, so a dead
  parse path leaves nothing behind. This diverges from Rebol/Red on purpose.
- Host escapes via `do` do **not** roll back and may run more than once
  per scan, so `do` blocks should compute rather than mutate. That advice
  stands on semantic grounds, not interpreter ones: the matcher
  pads escape blocks with a trailing value before evaluation, so
  assignments and zero-arity calls inside them are safe.
  `defer` is the sound alternative for mutation: its block is queued in the
  capture log and runs only on overall success, exactly once, in match
  order. Dead branches take their defers with them.
- `scan.memo: ['rule ...]` opts named rules into memoization for that
  scan. An entry stores the end position *and* the capture-log slice,
  replayed on a hit, so captures survive. A `do` escape inside a
  memoized rule runs once, not once per attempt.
- `some`/`any` stop when an iteration matches without consuming, so
  nullable loop bodies terminate instead of hanging.
- Left recursion (direct, indirect, or through a nullable prefix) is
  rejected at scan start with a message naming the cycle.
- Matching is case-sensitive and works on characters, not bytes.

## Status

Draft implementation of the proposal's Phase 0–2 scope, pure Arturo,
verified against Arturo 0.10.0. This includes the interpreted half of
Phase 3 (`cut`, `defer`, opt-in memoization, benchmarks), with only
the compiled Nim core left to propose upstream.

`demo.art` is the readable tour (71 checks). `tests.art` is the
regression suite (354 checks, nonzero exit on failure). Grammar errors
have to panic to be tested, and a panic unwound through `try` leaves
the abandoned frames' values behind for the next statements to misread,
so each of those cases runs in its own interpreter through
`tests-panics.art`.

```
arturo demo.art
arturo tests.art
```

[`examples/`](examples/README.md) holds the proposal's three demos, each
runnable on its own: JSON in fifteen rules (`json.art`), RFC 4180 CSV in
a dozen (`csv.art`), and Arturo scanning its own source: one rule
extracting every function definition from `carpintero.art` itself
(`arturo-scan.art`). `arturo-corpus.art` takes that last one all the
way: point it at a checkout of Arturo and it runs both grammars over
every `.art` file in the language's own tree. On 173 files and a
megabyte of source, stripping comments never once changed the program
the lexer builds, and a five-line block grammar found all 287 function
definitions at every nesting depth. [The write-up is in the
manual](MANUAL.md#validation-against-arturos-own-source), including the
fourth interpreter bug it turned up. `bench.art` is the Phase 3
benchmark: it shows scan losing to the native regex engine by the
expected orders of magnitude, memoization collapsing a deliberately
exponential grammar from a sixth of a second to a millisecond and a
half, and a cost per kilobyte that stays flat as the input doubles.

`bugs/` contains minimal repros for four Arturo 0.10.0 interpreter
bugs, three found while building this and one found by running it over
Arturo's own test suite. Workarounds are documented in `carpintero.art`.

## Name

*Carpintero*, the woodpecker: works through material methodically, a piece
at a time. Also *carpenter*: takes structure apart, builds structure up.
