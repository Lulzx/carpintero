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

Two utilities ride along. `stripComments` removes comments from a source
string with a Carpintero grammar, and `loadSafe` reads a file, strips it,
and returns the lexed block, sidestepping the 0.10.0 lexer bug where
comment contents can hang or corrupt the interpreter
(`examples/safeload.art` runs a file that hangs `arturo` directly).

## Semantics worth knowing

All deliberate; the rationale is in [proposal.md](proposal.md).

- The whole input must match. Use `scan.prefix` for prefix matching.
- Captures and keeps **roll back** when an alternative fails, so a dead
  parse path leaves nothing behind. This diverges from Rebol/Red on purpose.
- Host escapes via `do` do **not** roll back and may run more than once
  per scan, so `do` blocks should compute rather than mutate. That advice
  stands on semantic grounds, not interpreter ones: the matcher pads escape
  blocks with a trailing value before evaluation, so assignments and
  zero-arity calls inside them are safe. `defer` is the sound alternative
  for mutation: its block is queued in the capture log and runs only on
  overall success, exactly once, in match order. Dead branches take their
  defers with them.
- `scan.memo: ['rule ...]` opts named rules into memoization for that
  scan. An entry stores the end position *and* the capture-log slice,
  replayed on a hit, so captures survive. A `do` escape inside a
  memoized rule runs once, not once per attempt.
- `some`/`any` stop when an iteration matches without consuming, and that
  iteration is not taken: what it captured rolls back with it.
- Left recursion (direct, indirect, or through a nullable prefix) is
  rejected at scan start with a message naming the cycle.
- Matching is case-sensitive and works on characters, not bytes.

## Two implementations

`carpintero.art` is the reference: the whole dialect in pure Arturo,
covering the proposal's Phase 0 to 2 and the interpreted half of Phase 3
(`cut`, `defer`, opt-in memoization, benchmarks). It is the specification,
and where the two disagree it is the one that is right.

[`nim/`](nim/README.md) is the compiled core the proposal asks upstream
for: an LPeg-style instruction set matching text and blocks, built
standalone so it needs no Arturo build to develop. The two share no
matching code, so they are held together by running the same grammar over
the same input and comparing:

```
scripts/differential-corpus.sh ../arturo
```

Over Arturo's own source both engines find the same 287 definitions in the
same 168 files, with the same captures and no disagreement. The interpreted
matcher takes 16.6 seconds of scanning and the compiled core 28
milliseconds.

Reaching that speed from Arturo needs a builtin, which would mean changing
Arturo, so this package does not. Going through the FFI instead costs more
in serialisation than the whole match: 13.8 seconds to build the JSON
against 0.13 seconds to cross the boundary and match. The measurement, and
what it argues, is in [nim/README.md](nim/README.md).

## Running everything

```
scripts/run-tests.sh
```

| Suite | What it covers |
| --- | --- |
| `tests.art` | 359 checks over the interpreted matcher |
| `tests-panics.art` | 18 grammar errors, one interpreter each |
| `nim/tests/test_vm.nim` | 40 checks over the compiled core |
| `nim/tests/differential.nim` | 51 cases run in both engines and compared |
| `demo.art` | 71 checks, written to be read rather than to cover |

The panic cases need one interpreter apiece: a panic unwound through `try`
leaves the abandoned frames' values behind for the next statements to
misread, so a single process cannot check more than one of them.

## Examples

[`examples/`](examples/README.md) holds the proposal's three demos, each
runnable on its own: JSON in fifteen rules (`json.art`), RFC 4180 CSV in a
dozen (`csv.art`), and Arturo scanning its own source, one rule extracting
every function definition from `carpintero.art` itself (`arturo-scan.art`).

`arturo-corpus.art` takes that last one all the way. Point it at a checkout
of Arturo and it runs both grammars over every `.art` file in the language's
own tree. On a megabyte of source, stripping comments never once changed the
program the lexer builds, and a five-line block grammar found all 287
function definitions at every nesting depth. [The write-up is in the
manual](MANUAL.md#validation-against-arturos-own-source), including the
fourth interpreter bug it turned up.

`bench.art` is the Phase 3 benchmark: `scan` losing to the native regex
engine by the expected orders of magnitude, memoization collapsing a
deliberately exponential grammar from a sixth of a second to a millisecond
and a half, and a cost per kilobyte that stays flat as the input doubles.

## Interpreter bugs

[`bugs/`](bugs/README.md) has minimal repros for four Arturo 0.10.0
interpreter bugs: a comment that hangs the lexer, discarded call results
leaking into argument passing, a value-less binding that exits 1 silently,
and a `:symbolliteral` that is not equal to itself. Three were found by
writing the dialect and the fourth by running it over Arturo's own test
suite. Each has an in-language workaround, used in `carpintero.art`.

## Reading

- [TUTORIAL.md](TUTORIAL.md), the guided path from a first `scan` to
  walking a source tree.
- [MANUAL.md](MANUAL.md), the full reference: every word, the error report,
  memoization, the PEG pitfalls and their fixes.
- [proposal.md](proposal.md), the design rationale and the case for
  upstreaming.
- [nim/README.md](nim/README.md), the compiled core and what it measured.

## Name

*Carpintero*, the woodpecker: works through material methodically, a piece
at a time. Also *carpenter*: takes structure apart, builds structure up.
