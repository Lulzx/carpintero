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
scanError
; => scan failed at line 1, column 10 — expected: charset 0-9
```

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
| Escape | `do [...]` host code, `quote value` literal match, `fail "msg"` |
| Match | strings, chars, charsets, `:type` values, `'word` literals, named rules |

Semantics worth knowing, all deliberate (the design rationale lives in
[proposal.md](proposal.md)):

- The whole input must match; use `scan.prefix` for prefix matching.
- Captures and keeps **roll back** when an alternative fails — a dead parse
  path leaves nothing behind. This diverges from Rebol/Red on purpose.
- Host escapes do **not** roll back and may run more than once per scan;
  escape blocks should call functions that compute, not assign.
- `some`/`any` stop when an iteration matches without consuming, so
  nullable loop bodies terminate instead of hanging.
- Left recursion — direct, indirect, or through a nullable prefix — is
  rejected at scan start with a message naming the cycle.
- Matching is case-sensitive and works on characters, not bytes.

## Status

Draft implementation of the proposal's Phase 0–2 scope, pure Arturo,
verified against Arturo 0.10.0. `demo.art` is the test suite (47 checks):

```
arturo demo.art
```

`bugs/` contains minimal repros for three Arturo 0.10.0 interpreter bugs
found while building this, with workarounds documented in `carpintero.art`.

## Name

*Carpintero*, the woodpecker: works through material methodically, a piece
at a time. Also *carpenter*: takes structure apart, builds structure up.
