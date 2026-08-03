# Examples

Each file runs on its own from the repository root, no arguments unless
noted:

```
arturo examples/json.art
```

| File | What it is | Why read it |
| --- | --- | --- |
| `json.art` | JSON in fifteen rules | The proposal's headline claim, and the shortest complete grammar here. Ends by showing what `scanError` says about `{"a": 01}`. |
| `csv.art` | RFC 4180 CSV in a dozen | Quoting rules, doubled quotes inside quoted fields, and why `to`/`thru` are not always the answer. |
| `arturo-scan.art` | Arturo reading one file of its own source | Every top-level function definition in `carpintero.art`, name and parameter list, extracted without running any of it. |
| `arturo-corpus.art` | Arturo reading *all* of its own source | Takes the path to an Arturo checkout. The differential test that validates `stripComments` against a megabyte of real source, plus a recursive `into` walk that finds every definition at any nesting depth. See below. |
| `safeload.art` | `loadSafe` in anger | Runs `bugs/comment-lexer-hang.art`, a file that hangs `arturo` outright, by stripping its comments with a Carpintero grammar before the lexer sees them. |
| `bench.art` | The Phase 3 numbers | `scan` against the native regex engine, memoization against a deliberately exponential grammar, and cost per kilobyte as the input doubles. |

## Running the corpus example

`arturo-corpus.art` is the only one that needs an argument — a checkout
of Arturo itself:

```
git clone --depth 1 https://github.com/arturo-lang/arturo
arturo examples/arturo-corpus.art ./arturo
```

Budget a couple of minutes. The interpreted matcher moves at roughly
8 KB of source per second and the corpus is about a megabyte, most of
it spent in `stripComments`, which is the part being tested.

The run reports four things: how many files the stripper rewrote without
changing the program the lexer builds, how many never lexed in either
form (Arturo keeps deliberate syntax errors in its test suite, and those
are not stripper failures), how many compared unequal, and how many
function definitions the block grammar found.

The results, and the interpreter bug the "compared unequal" line turned
up, are written up in
[the manual](../MANUAL.md#validation-against-arturos-own-source).
