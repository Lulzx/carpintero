# Carpintero

A PARSE-class grammar dialect for [Arturo](https://arturo-lang.io): rules are
ordinary Arturo blocks that compose, nest, and recurse, and they match
strings *and* blocks — so Arturo can pattern-match its own source.

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
the report gives an index — or, when the failure is inside `into`, a
path of indices into the nested structure.

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

Semantics worth knowing, all deliberate (the design rationale lives in
[proposal.md](proposal.md)):

- The whole input must match; use `scan.prefix` for prefix matching.
- Captures and keeps **roll back** when an alternative fails — a dead parse
  path leaves nothing behind. This diverges from Rebol/Red on purpose.
- Host escapes via `do` do **not** roll back and may run more than once
  per scan; escape blocks should call functions that compute, not
  assign. `defer` is the sound alternative: its block is queued in the
  capture log and runs only on overall success, exactly once, in match
  order — dead branches take their defers with them.
- `scan.memo: ['rule ...]` opts named rules into memoization for that
  scan. An entry stores the end position *and* the capture-log slice,
  replayed on a hit, so captures survive; a `do` escape inside a
  memoized rule runs once, not once per attempt.
- `some`/`any` stop when an iteration matches without consuming, so
  nullable loop bodies terminate instead of hanging.
- Left recursion — direct, indirect, or through a nullable prefix — is
  rejected at scan start with a message naming the cycle.
- Matching is case-sensitive and works on characters, not bytes.

## Status

Draft implementation of the proposal's Phase 0–2 scope, pure Arturo,
verified against Arturo 0.10.0. This includes the interpreted half of
Phase 3 — `cut`, `defer`, opt-in memoization, benchmarks — with only
the compiled Nim core left to propose upstream. `demo.art` is the test
suite (66 checks):

```
arturo demo.art
```

`examples/` holds the proposal's three demos, each runnable on its own:
JSON in fifteen rules (`json.art`), RFC 4180 CSV in a dozen
(`csv.art`), and Arturo scanning its own source — one rule extracting
every function definition from `carpintero.art` itself
(`arturo-scan.art`). `bench.art` is the Phase 3 benchmark: it shows
scan losing to the native regex engine by the expected orders of
magnitude, and memoization collapsing a deliberately exponential
grammar from seconds to milliseconds.

`bugs/` contains minimal repros for three Arturo 0.10.0 interpreter bugs
found while building this, with workarounds documented in `carpintero.art`.

## Name

*Carpintero*, the woodpecker: works through material methodically, a piece
at a time. Also *carpenter*: takes structure apart, builds structure up.
