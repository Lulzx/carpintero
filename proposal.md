# Carpintero: a PARSE-class grammar dialect for Arturo

**Status:** proposal / request for comment
**Form:** pure-Arturo package first, native core proposed only once semantics settle
**Relates to:** the "context-free grammar parser" item in `package-ideas`, and,
less directly, the "completion package" item

## What exists today

`match` and `match?` in `Strings.nim`, both regex. `parse` in `Core.nim`, new
in v0.10.0 (January 2026), which reads a string as an Arturo value: a
deserializer, not a grammar engine. There is no `Parse` among the library
modules, and no grammar package on `pkgr.art`. The lark-style parser entry in
`package-ideas` is still unclaimed.

Because core already owns the word `parse`, this dialect's entry points are
named `scan` and `scan?`. The "On the names" section at the end returns to
this.

For a language descended from the Rebol line, that is a conspicuous gap. PARSE
is the feature that lineage is known for, more than any other dialect, and its
absence is the first thing anyone arriving from Rebol or Red will look for.
When Arturo hit Hacker News in 2020, the creator said a PARSE-like dialect was
already on the to-do list, and that Arturo "has the means to implement it due
to its nature." This proposal is that item, worked out.

## The one-line version

Grammar rules are Arturo blocks. They compose, nest, recurse, and are named like
any other value. They match strings *and* blocks.

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

`scan` returns a dictionary of captures, or `null` on failure. A successful
match that captured nothing returns an empty dictionary. Success and failure
stay distinguishable: `null` means failure and nothing else does, so callers
can test the result directly. `scan?` returns a boolean when you only need the
yes/no.

Three more clauses of the contract, decided here so review has something to
argue with:

- **`scan` matches the whole input.** A rule that matches a prefix and stops
  short is a failure, as in Rebol. Prefix matching is an attribute
  (`scan.prefix`), and in that mode the result includes how far the match
  reached, which is the hook that search-and-extract idioms need.
- **Matching is case-sensitive.** Rebol and Red default to case-insensitive,
  then make bitset matching exact anyway, so one grammar mixes two
  comparison rules. Carpintero picks one rule everywhere. A case-insensitive
  attribute can come later, documented as applying to string literals only.
- **`capture` takes the span the rule consumed.** For string input that is a
  substring, and for block input the matched values. Capturing into the same
  name twice keeps the last match, and accumulating is what `collect`/`keep`
  is for. UPARSE ended up splitting Rebol's `copy` in two because "what input
  did this rule cross" and "what value did it produce" are different
  questions. `capture` answers the first, and a `do` escape can compute the
  second from it.

## Why Arturo is a natural home for this

In Rebol, PARSE's vocabulary collides with the language. `copy`, `set`, `if`,
`not`, `into`, `skip` are all real functions that PARSE reinterprets inside a
rule block, and any word in rule position that happens to be a keyword *is*
the keyword: you cannot name a subrule `to` or `end`. Every Rebol programmer
eventually gets bitten by this, and Red inherited it. Arturo does not escape
the collision either: `to`, `do`, `not`, and `collect` are real Arturo
functions, `any` is a core constant, and this dialect reuses those words with
different meanings inside rules. Same word, different meaning depending on
context. That tension is inherent to dialecting.

What Arturo does offer is a crisp boundary. A rule is a block, and blocks are
not evaluated until something walks them ("a block has no meaning until it is
given one"), so there is never a moment where the evaluator and the dialect
are both live on the same words. Inside `scan` every word answers to the
dialect, and outside it to the language. That boundary is not an exception
carved out of the language. It is the language's stated principle:

> Words and symbols within a block are interpreted — when needed — according to
> the context

A grammar dialect is the hardest exercise of that principle the language could
get. Grafito's graph-command vocabulary shows the idea works for a flat
command language, and the HTML and SQL DSLs on the wishlist would be more of
the same. A grammar dialect shows it survives recursion, backtracking, and a
vocabulary of thirty-odd words, which is the case Rebol used to prove
dialecting was more than a slogan.

One repurposing to name up front: `|` is Arturo's pipe operator. Inside a rule
block it means ordered alternation instead. Since rule blocks are never
evaluated as Arturo code, the two meanings never meet, but a reader who knows
the pipe should be told once, in the docs, that this is deliberate.

## Parsing blocks

Rebol's PARSE works on block input as well as string input. That is the
feature its users cite first, and the reason this proposal is worth more than
a nicer regex. A dialect over block input gets the lexer for free: the input
is already typed values, and the grammar only supplies structure.

Because Arturo code *is* blocks, a rule can match Arturo itself. And because
Arturo already has type literals, the terminal matchers need no new
vocabulary:

```red
funcdef: [
    capture 'name :label
    'function
    capture 'params :block
    capture 'body   :block
]

scan code [any [funcdef | skip]]
```

`:label`, `:word`, `:integer`, `:block`, `:string` are the language's own
type values doing double duty as pattern terminals (`greet:` in a block is a
`:label`, which is why the name terminal above is not `:word`), and
`'function` is a literal matching that exact word. One escape is required for completeness: a `quote` form that
matches the next value literally even when it is a dialect keyword, so a
grammar can match code that itself contains the word `some` or an integer
that would otherwise read as a repeat count. Rebol added `quote` for exactly
this reason, late, after users hit the wall. It should be in from the start.

A dialect that can pattern-match Arturo source is the substrate for the
completion package already on the wishlist, for linting, for refactoring
tools, for documentation extraction, and for anything else that needs to
understand code without running it.

## Vocabulary

Small enough to hold in your head, close enough to Rebol that the knowledge
transfers.

| Group | Words |
| --- | --- |
| Quantify | `some` (1+), `any` (0+), `opt`, `N rule` (exactly N, as in `4 digit`), `between N M` |
| Choose | `\|` for ordered alternation, with blocks for grouping |
| Advance | `to` (up to, exclusive), `thru` (inclusive), `skip`, `end` |
| Look | `ahead` (match without consuming), `not` |
| Capture | `capture 'name rule`, `collect 'name` + `keep` |
| Descend | `into rule` (parse a nested block with its own rules) |
| Escape | `do [...]` (run host code mid-parse), `quote value` (match literally) |
| Match | string/char literals, charsets, `:type` literals, named rules |

Recursion is a rule referring to itself by name, with no special form.

`capture` binds one name to one span. `collect` gathers everything `keep`
kept beneath it:

```red
word: [some charset "a-z"]

scan "one, two, three" [
    collect 'words [some [keep word | skip]]
]
; => [words: ["one" "two" "three"]]
```

Two rules, both learned from Rebol's history:

- **Loops must make progress.** `any` and `some` terminate when an iteration
  matches without consuming input. Red's `while` deliberately lacks this guard
  and its own documentation shows `[while none]` hanging the interpreter.
  Rebol 2's `any []` could lock the session. Ren-C went further and deleted
  the 0+ loop entirely, rebuilding it as `opt some`. Keeping `any` with a
  mandatory progress guard preserves the familiar word without the trap.
- **Alternation binds loosely, blocks group.** `[a b | c]` is `[[a b] | c]`,
  as in Rebol, and the docs say so on the first page.

Charset syntax: inside `charset "..."`, a `-` between two characters denotes
an inclusive range, and a leading, trailing, or escaped `\-` is the literal
dash. `charset "a-z0-9-"` is lowercase letters, digits, and dash. Charsets
are values, so union, intersection, and complement compose them the way
bitsets compose in Rebol, as `csUnion`, `csIntersect`, and
`csComplement`, since core owns the unprefixed words for blocks.

### Arriving from Red

The likeliest early adopters already know PARSE, so the mapping deserves one
table:

| Rebol/Red | Carpintero | Difference |
| --- | --- | --- |
| `parse` | `scan` | core owns `parse` |
| `set x` / `copy x` | `capture 'x` | one form, span-of-input, rolls back |
| `collect` / `keep` | `collect 'x` / `keep` | kept values roll back, named target |
| `and` / `ahead`, `not` | `ahead`, `not` | same |
| `(paren)` | `do [...]` | same re-run caveat, stated up front |
| `into` | `into` | same |
| `quote` | `quote` | same |
| `while` | absent | `any` with a progress guard |
| `insert` / `remove` / `change` | absent | input mutation excluded |
| `pos:` / `:pos` mark and seek | absent | captures and `do` cover the common uses |
| `if (expr)` | absent | `do` plus Phase 2 lookahead covers it |
| datatype terminals (`integer!`) | `:integer` | the language's own type literals |

The absences are deliberate scope, not omissions to be fixed later. The case
for each is elsewhere in this document.

## Backtracking semantics

This is the hardest part of the design to get right, so it is specified here,
and it is the one place this proposal deliberately breaks with the lineage.

**Captures roll back.** If a `capture` succeeds inside an alternative that
later fails, the capture is discarded along with the position. Same for
`collect`/`keep`: kept values belong to the path that kept them.

Rebol and Red made the opposite choice. Red's spec is explicit: "only input
and rule positions are backtracked, other changes remain," so a `set` or
`copy` in a failed alternative leaves the variable holding a value from a
parse path that officially never happened, and `keep`s from dead branches
survive into the collected block. It is the most-cited semantic wart
in PARSE, and every modern engine in this space (LPeg, Janet's `peg`, and
Ren-C's UPARSE redesign of PARSE itself) rolls captures back. UPARSE does it
by routing all accruals through one "pending" list that the failure path
drops. LPeg does it by recording captures as a flat log and truncating the
log to a saved height on backtrack, which costs one integer store. Carpintero
adopts the LPeg model outright: captures are marks in a log during matching,
values materialize only after overall success, rollback is truncation. That
is cheap enough to have in the interpreted version from day one, and it means
the eventual compiled core changes the engine without changing the semantics.
The model has independent validation in the literature: Kuramitsu's AST
machine for Nez treats tree construction as transactions over exactly this
kind of log, aborted on backtrack, and reports it practical at scale.

**Host escapes do not roll back.** `do [...]` runs arbitrary Arturo code, and
its side effects cannot be undone when the matcher backtracks over them. The
contract is explicit: an escape may run on a parse path that is later
abandoned, and may therefore run more than once for a single `scan`. Escapes
should compute, not mutate. Anything that must happen exactly once belongs
after the parse, driven by the captures. Rebol's docs promise only that a
paren "executes if parsing reaches that point," which quietly includes
reaching it twice, and Red at least documents the limited backtracking. Here it
is a rule, stated where the feature is introduced. If a real need for
run-exactly-once escapes emerges, UPARSE points at the sound design: a
deferred escape whose block is queued during matching and evaluated only on
commit. The draft now implements this as `defer`: the block rides in the
capture log, rolls back with a dead branch like a capture does, and runs
exactly once per successful scan, in match order.

## A divergence from the wishlist

The `package-ideas` entry asks for a context-free grammar parser "like lark."
Lark is an Earley/LALR parser: it handles genuinely ambiguous grammars and can
return a parse forest.

This proposes a **PEG**: ordered choice, greedy, first match wins, no
ambiguity by construction. That is what PARSE is, and it is a different thing
from what was asked for.

The case for PEG anyway:

- **It composes as a dialect.** Ordered choice has a local, operational meaning
  you can read off the page. Earley's global disambiguation does not decompose
  into "words interpreted according to context," so a lark-alike would end up
  being a library that takes a grammar *string*, which forfeits the entire
  point of building it in Arturo.
- **It handles the cases people actually have.** Config formats, data formats,
  protocols, source languages. Ambiguity mostly matters for natural language and
  for research on legacy grammars.
- **It is what the lineage expects.** Someone coming from Red is looking for
  PARSE, not for Earley.

And the honest costs, which the documentation should state rather than bury:

- **Ordered choice hides prefixes.** `["a" | "ab"]` never matches `"ab"`,
  because the first alternative wins and the choice is not revisited when the
  caller later fails. The classic companion is that `[any "a" "a"]` can never
  match: repetition is greedy and does not give back. Both have idiomatic
  fixes (order alternatives longest-first, guard with `not`/`ahead`, use
  `to`/`thru`), and both belong in the manual with those fixes attached.
- **Ambiguity is resolved silently.** Where a CFG tool would report an
  ambiguous grammar, a PEG picks the first alternative and moves on. That is
  determinism when you want it and a masked bug when you don't.
- **PEG and CFG are incomparable, not nested.** PEGs match some non-context-free
  languages (aⁿbⁿcⁿ is a textbook example), and whether every context-free
  language is expressible as a PEG is a question that has been open since
  Ford posed it in 2004. "PEG can do everything a CFG can" is not a claim
  this package gets to make.

A real CFG parser remains a legitimate separate package. This proposal does
not satisfy that entry and does not claim to.

## Precedents

This design does not have to be invented from scratch. Four engines have
already run the experiment, and their results are consistent enough to treat
as settled:

- **Janet's `peg` module** is the closest existing analog: grammars are plain
  Janet data structures, compiled to bytecode on first use, and its docs say
  outright that it "borrows syntax and ideas from both LPeg and REBOL/Red
  parse module." It is the proof that PARSE-as-data-structure works in a
  small modern language, in about two thousand lines of C. Its primitive set
  (tagged captures, `to`/`thru`, backmatch, match-time predicates) is the
  debugged union of the two traditions and a useful checklist for what
  Carpintero's later phases might grow.
- **LPeg** contributes the implementation architecture: Ierusalimschy's
  parsing-machine paper defines a small backtracking VM (char, charset,
  choice, commit, call, capture and a handful of optimized forms) plus the
  capture-log model described above. The paper also makes the case *against*
  packrat memoization for pattern-matching workloads, which this proposal
  adopts.
- **NPeg** is LPeg's idea in Nim, Arturo's own implementation language: a
  macro DSL compiled to a parsing VM, with farthest-position error reporting
  built in. When the Phase 3 native core is proposed, NPeg is either the
  design template or, conceivably, the dependency.
- **UPARSE**, Ren-C's ground-up redesign of PARSE by people who spent two
  decades on the original, is the record of which PARSE semantics were
  mistakes: no-rollback captures (fixed via the pending list), the two
  near-identical 0+ loops (deleted), `copy`'s ambiguity between "span of
  input" and "value produced" (split into distinct words). Where Carpintero
  diverges from Rebol, it diverges in the same direction UPARSE did.

## Implementation

**Start in pure Arturo.** A recursive matcher over the rule block, carrying an
input position and a capture log, saving position and log height on
alternation, truncating on failure. Ordinary PEG mechanics, a few hundred
lines. This is deliberately the slow version. UPARSE itself ships as three
thousand lines of interpreted usermode code and is openly "glacially slow,"
because its authors judged that getting the semantics right in a malleable
medium comes first, and the same judgment applies here.

Doing it this way means the design can be evaluated, argued with, and revised
before a single line of Nim is written. It is one file with no core changes
and no dependencies, so trying it is `import` on a clone, and it carries an
`info.art` for `pkgr.art` whenever the semantics are worth publishing. If
they turn out wrong, throwing it away costs a week rather than a subsystem.

This is no longer hypothetical: a draft ships alongside this proposal.
`carpintero.art` (about 1,340 lines) implements the Phase 0 through Phase 2
scope against Arturo 0.10.0, plus the interpreted half of Phase 3
(`cut`, `defer`, opt-in memoization), and `demo.art` passes seventy-one checks
covering the date example above, capture rollback across failed
alternatives, the progress guard on nullable loop bodies, prefix mode,
`to`/`thru`, charset ranges, a mutually recursive JSON validator in nine
rules, block matching (the funcdef example above runs as written against a
block of Arturo code, with `:type` terminals, literal-word matching, and
`quote`), `into` descent into nested blocks (with captures inside the
nested block landing correctly, and rolling back with the path that made
them), charset composition, lookahead, `collect`/`keep` with rollback, the
`do` escape (the demo *demonstrates* the re-run contract: an escape inside
`some` runs once per attempt, including the failed one), and the
farthest-failure error report: the `date` grammar failing on
`"2026-08-0x"` renders the Phase 2 target message shown below verbatim,
with the failing terminal named by its rule (`digit`, not its charset
internals), the enclosing capture as while-matching context, and the
source line with a caret under the column. Failures inside the operand of
`not` are excluded from the expected set, since there a failure is the
grammar succeeding. Direct left recursion
(`expr: [expr "+" digit | digit]`), indirect left recursion through a
nullable prefix, and unbound rule words are all rejected at scan start with
messages naming the cycle or the word. Writing it also surfaced three
interpreter bugs worth filing upstream, which is what dogfooding is for
(minimal repros in `bugs/`): the 0.10.0 lexer does not fully ignore comment
contents (a `\-` inside a comment hangs it), a function call whose result
is discarded can leak that value into the argument stream of an enclosing
call, and binding the result of an expression that produces no value (an
assignment, a `set`, a call to a function whose body ends in one)
corrupts the enclosing frame, usually as a silent exit. The third was
misdiagnosed twice, first as "escape blocks cannot assign", which
accidentally enforced this proposal's own "escapes should compute, not
mutate" rule, then as a property of `do`. The real trigger is the
binding, and the draft sidesteps it by evaluating every escape block
padded with a trailing value (`op ++ [true]`) and discarding the result,
so escapes may in fact assign freely. The unused-result leak is likewise avoided
with the language's own `discard` rather than dummy assignments. Even
the lexer bug has an in-language mitigation, and it is the most
Carpintero-shaped fix imaginable: `read` returns raw source without
lexing anything, so `loadSafe` strips comments at the string level
with a nine-rule Carpintero grammar and only then hands the source to
the lexer, which never sees a comment byte. The file in `bugs/` that
hangs the interpreter runs correctly through it
(`examples/safeload.art`), the dialect fixing the language's own
front end, which is demo 3's thesis stated as a working program.

**Then propose the matcher core in Nim,** once the vocabulary and the
backtracking semantics have stopped moving. The target is an LPeg-style
instruction set with rules compiled once and cached. Core has no bitset
machinery to borrow for this, since `helpers/charsets.nim` is locale
alphabet tables for `alphabet` and `unisort` rather than character classes,
but the piece needed is small and self-contained: Nim's native `set[char]`
is the ASCII half, and the non-ASCII half is the sorted range list the
interpreted version already carries. NPeg demonstrates the whole
architecture in Nim already. Because the interpreted version uses the same
capture-log semantics, the compiled core is an engine swap, not a redesign.
There is even a formal criterion for the compiler's best optimization: the
"linear PEG" subclass identified by Chida and Kuramitsu is exactly the
grammars a compiler can lower to DFA-like code with no backtracking at all,
which generalizes the charset-run and head-fail tricks LPeg applies ad hoc.

That core now exists, in `nim/`: about 1,570 lines of matcher with no
dependencies, plus 290 more for the JSON bridge that a builtin would not
need. It matches text and blocks, and is held to the interpreted semantics
by running the same grammar over the same input in both engines rather than
by sharing code. Over Arturo's own source the two agree on every one of 168
files and find the same 287 definitions, the interpreted matcher taking 15.8
seconds of scanning and the compiled core about 30 milliseconds.

**It has to be a builtin, and that is a measured claim rather than a
preference.** The package changes nothing in Arturo, so the only way to
reach the compiled core from Arturo today is `call.external`, which carries
scalars. `nim/adapter/fast.art` does exactly that, and it is worth having:
about fifty times faster than the interpreted matcher over the corpus, with
no change to Arturo at all. What it cannot do is expose the engine.

| | Corpus time | |
| --- | ---: | --- |
| `scan` | 15.8 s | pure Arturo, the reference |
| `scanFast` | 0.30 s | the shared library, no change to Arturo |
| the core on values it already holds | 0.03 s | what direct access would expose |

Four rounds of optimisation took the serialisation from 15.3 seconds to
0.19, which is enough to answer the obvious objection that the bridge was
simply written badly. It is still 70% of the middle row, and what is left is
not escaping or a wasteful encoding but traversing Arturo's own value tree
from Arturo and building a second copy of it. A further round would likely
shave more; it would not change which row the ceiling sits in.
An extension API that serialises accelerates the reference implementation.
A builtin holding the `Value` block it was handed is the third row. What
that asks for upstream is a `src/library/Parse.nim` and a line in
`src/vm/vm.nim`, plus a way for `do` and `defer` to evaluate back into the
interpreter. Everything else in `nim/` is already written and tested.

**Error reporting is where this can beat Rebol.** Classic PARSE returns true
or false and nothing else, and Red and Ren-C both had to retrofit tracing hooks
to find out where a grammar died. The standard fix, from Ford's thesis
onward, is the farthest-failure heuristic: track the furthest input position
reached across all backtracking, plus the set of terminals that failed there.
That high-water mark is almost always where the real failure is, even though
the matcher has since backtracked far away from it, and maintaining it costs
two fields updated on terminal failure. For string input, report it with line
and column and the expected terminals. Letting a rule carry an optional
description string (Ohm's trick) turns "expected charset 0-9" into "expected
a date." Concretely, the Phase 2 target for the `date` grammar above:

```
scan "2026-08-0x" date
; error: scan failed at line 1, column 10
;        expected: digit  (while matching: day)
;
;            2026-08-0x
;                     ^
```

For block input, report a path of indices into the nested structure
instead. The draft does this by making the failure position itself
path-qualified, the `into` descent indices plus the index, ordered
lexicographically with deeper winning ties, which degenerates to the
plain high-water mark on flat input. A `fail "message"` rule for positions where failure means error
rather than alternative (after a committed keyword, say) is the labeled-
failure refinement from the PEG literature, and slots in as a Phase 2 word.
The same research line has since shown that labels and recovery expressions
can be *inserted automatically* by analyzing the grammar (Medeiros and
Mascarenhas, 2025). Because Carpintero's rules are data, that analysis is an
ordinary Arturo function over blocks, and makes a natural later tool rather
than a core feature.

**Left recursion** must be detected and rejected with a clear message naming
the cycle. Naive PEG loops forever on it. The detection is a known algorithm,
not an invention: compute nullability for every rule by fixpoint, build the
"can invoke at the same position" graph (a rule reaches the rules in its body
that sit behind only nullable prefixes), and reject any cycle. This is Ford's
well-formedness check, it is linear-ish in grammar size, and the same
nullability analysis catches the empty-loop-body hazard for free, so one
pre-pass buys both guarantees. In the pure-Arturo phase there is no compile
step (rules are blocks referring to other rules by name, resolvable only when
`scan` runs), so the check happens once at parse start, when the rule graph
is first reachable, and is cached per rule set. A rule name that is unbound
at parse time is an immediate error naming the word, not a match failure.
The check itself is well-trodden ground: both machine-verified PEG
interpreters in the literature (TRX in Coq, Blaudeau and Shankar's PVS
formalization) implement this same well-formedness condition as their
termination guarantee. One ceiling to respect: beyond well-formedness, most
interesting global properties of a PEG (whether a choice arm is dead, whether
two grammars are equivalent) are undecidable, so any further lint the package
grows must be openly conservative, a warning pass and not a verifier.

*Supporting* left recursion is explicitly out of scope, and not just
for Phase 0. The seed-growing algorithm requires packrat memoization to exist
and produces wrong parses for some grammars that mix left and right recursion
(Tratt's critique). Nearly every practical engine (LPeg, Janet, NPeg, pest,
Ohm) rejects it instead, and the systems that do support it (Python's Pegen,
Autumn, Pika and its successor Squirrel) all pay for it with full memoization
or fixed-point re-parsing. The one real use case, left-associative operator
expressions, is better served by an explicit fold/precedence combinator, which
can arrive in a later phase if grammars demand it.

**No packrat memoization.** For the flat data these grammars mostly chew,
full memoization multiplies memory by the input size and usually slows
matching down. That finding is the founding argument of LPeg's VM, and
CPython's PEG parser settled on memoizing only individually marked rules.
Carpintero routes every rule invocation through one dispatch point keyed by
rule and position, and the draft now carries the opt-in version:
`scan.memo: ['rule ...]` memoizes exactly the named rules for that scan.
The benchmark shows why both halves of that sentence matter: the
deliberately exponential tower grammar drops from about a second and a
half to about five milliseconds when memoized, and ordinary grammars pay
nothing because nothing is memoized unless asked. A memo entry stores the
capture-log slice its rule produced, not just the end position, or memoized
hits would silently drop captures (Kuramitsu documents the fix). The two
honest losses on a hit, documented in the code, are that a `do` escape
inside the rule does not re-run and the farthest-failure report is not
re-recorded. If entries are
keyed so they can be shifted when the input changes, incremental reparsing
falls out almost free, which is how GPeg gets editor-speed reparses from an
LPeg-style machine. The cheaper complement to memoization is a `cut`: a rule
that commits the current choice, discarding backtrack points, which both
bounds pathological backtracking and marks a safe place to flush the capture
log. It has a published formal semantics, and the draft implements it:
`cut` commits the innermost enclosing choice block, so after cut a failure
stops the whole choice instead of trying the next alternative.

**Testing** deserves a plan of its own, because grammars are the worst kind
of code to test by hand: the interesting inputs are the ones nobody thinks
of. Two techniques from the literature apply directly. Differential testing:
run the same grammar through the interpreted matcher and, later, the compiled
core, on generated inputs, and require identical results, with the interpreted
version staying alive permanently as the executable specification. Generation:
deriving test sentences *from* the grammar has to respect PEG semantics,
because naively generating from the CFG reading of a grammar produces strings
the PEG rejects (ordered choice excludes them). Garnock-Jones, Eslamimehr and
Warth show how to generate correctly from PEG derivatives, and a
rules-as-data grammar makes that generator another ordinary function over
blocks.

**Unicode**: match on codepoints, not bytes. Arturo strings are already
character-indexed, not byte-indexed (`size "Hello 世界"` is 8), and the
dialect must agree with the language about what position N means.

## Staging

- **Phase 0**: string matching. Quantifiers with the progress guard, ordered
  choice, captures with rollback, charsets, named and recursive rules, the
  left-recursion/nullability pre-pass. Pure Arturo. Ships alone and is useful
  alone.
- **Phase 1**: block matching, `:type` terminals, `quote`. The reason the
  package exists, and the phase that makes tooling possible.
- **Phase 2**: farthest-failure errors with expected-sets and rule
  descriptions, `fail "message"`, `collect`/`keep`, lookahead, host escape.
- **Phase 3**: the Nim rule compiler, `cut`, opt-in per-rule memoization,
  deferred (commit-time) escapes if demand exists, benchmarks against `match`
  and against hand-written parsers. The interpreted draft carries `cut`,
  `defer`, `scan.memo` and `examples/bench.art`, and `nim/` now carries the
  compiler: an LPeg-style instruction set matching text and blocks, held to
  the interpreted semantics by a differential harness rather than by shared
  code. Over Arturo's own source both engines find the same 287 definitions
  in the same 168 files with no disagreement, the interpreted matcher taking
  15.6 seconds of scanning and the compiled core about 30 milliseconds.
  What remains splits in two. Integration is required and is upstream's:
  `Value` in place of the JSON adapter, escapes calling back into the
  interpreter, and registering the module. Memoization and the charset-run
  opcode are optional and only about speed, and are worth leaving until
  after the value model settles.

## Demos, in order of how convincing they are

All three now exist as runnable scripts in `examples/`, against the draft
implementation.

1. **JSON in eleven lines of rules.** Instantly legible, and everyone
   already knows the grammar, so the reader is comparing presentations rather
   than learning a format.
2. **A format the core currently hand-parses in Nim.** `helpers/` contains
   hand-written `csv.nim`, `toml.nim`, `xml.nim`, `url.nim`, and `markdown.nim`.
   Showing CSV or TOML as a dozen lines of Arturo rules is a demo of
   expressiveness today, and a structural argument only later:
   replacing those parsers depends on the Phase 3 compiled core being fast
   enough, and even then some may stay in Nim. The direction is still worth
   pointing at as Phase 3 work: Nim code becoming Arturo code, a smaller core,
   a language further toward self-hosting.
3. **Arturo parsing Arturo.** Extract every function definition from a source
   file in six lines of rules, then point at the completion package on the
   wishlist and note that this is most of its front end.

## Known problems

- **It will lose to hand-written parsers on speed.** An interpreted matcher
  against tuned Nim is not a fair fight, and the pure-Arturo phase will be far
  worse than that. The pitch is expressiveness, composability, and rules that
  are data, not throughput. Charsets and compiled rules narrow the gap without
  closing it. Any benchmark published should say this first. Worst-case
  behavior should be documented too: PEG without memoization is exponential
  in pathological grammars, effectively linear in real ones, and the manual
  should show what pathological looks like.

  A round of optimization on the draft is worth reporting here, because it
  changes what the compiled core has left to buy. Validating 200 dates went
  from 169 ms to 22 ms, a 1400-character JSON document from 361 ms to 86 ms,
  and `[some digit]` over 32 kB from 2.75 s to 105 ms. Almost none of that
  came from the grammar engine. Two interpreter properties accounted for it:
  indexing an Arturo string by position walks the UTF-8 from the front, so a
  matcher that indexes constantly is quadratic in the length of its input
  unless it converts to a block of characters first. And a scoped Arturo call
  that assigns any local costs roughly twenty times one that assigns none, so
  the cost of the tree walk was mostly the cost of building frames for it,
  recoverable through `function.inline` wherever no two live instances of the
  same function can share a scope. Both are worth knowing independently of
  this package. What they mean for staging is that the remaining gap to
  `match` is about three and a half orders of magnitude rather than four and
  a half, and that it is now genuinely the interpreter, not the design, which
  is the argument for the compiled core, made honestly.
- **PEG is not CFG**, with the specific costs listed above: hidden prefixes,
  greedy repetition, silent disambiguation.
- **The comparison is unforgiving.** Rebol's PARSE has had twenty-five years of
  refinement, and anyone who knows it will measure this against it from the
  first line. That cuts both ways: the refinements are documented, and the
  mistakes are too, which is why this proposal leans on UPARSE's postmortem
  rather than re-deriving it. It is still a good reason to ship a small
  coherent subset that works properly rather than a broad one that mostly
  does.
- **Scope creep is the main risk.** PARSE's full vocabulary is large (Red adds
  input *mutation* mid-parse: `insert`, `remove`, `change`) and every word
  suggests two more. Mutation in particular is excluded on principle, not
  deferred: it is incompatible with capture rollback and it is where PARSE's
  semantics get murkiest. Phase 0 should be ruthless about staying small.

## On the names

**The functions.** `parse` is taken: core binds it in `Core.nim` as the
Arturo-value deserializer, and silently shadowing a core builtin is no way for
a package to introduce itself. `match` is taken by the regex machinery in
`Strings.nim`. That leaves `scan` and `scan?`: unclaimed, short, and a fair
name for a matcher that walks the input once, left to right. If review turns
up a better word, this is the cheapest thing in the proposal to change.

**The package.** Following `aguila` and `peregrino`: **Carpintero**, the
woodpecker. It works through material methodically, a piece at a time, which
is the job. The word also means *carpenter*, which is the other half: taking
structure apart and building structure up. `Urraca` (magpie, for the
collecting) is the alternate.

## References

- Arturo library docs (`parse`, `match`): <https://arturo-lang.io/documentation/library/>
- Arturo creator on PARSE, HN 2020: <https://news.ycombinator.com/item?id=24834636>
- Red PARSE spec (backtracking, `collect`, `while` hazard): <https://github.com/red/docs/blob/master/en/parse.adoc>
- Rebol 3 Parse Project design record: <https://github.com/gchiu/rebol.net/blob/master/docs/Parse_Project.adoc>
- UPARSE source and rationale: <https://github.com/metaeducation/ren-c/blob/master/src/mezz/uparse.r>
- Janet `peg` module: <https://janet-lang.org/docs/peg.html>
- Ierusalimschy, *A Text Pattern-Matching Tool based on Parsing Expression
  Grammars* (the LPeg VM and capture log): <https://www.inf.puc-rio.br/~roberto/docs/peg.pdf>
- NPeg: <https://github.com/zevv/npeg>
- Ford, *Parsing Expression Grammars* (well-formedness, farthest failure):
  <https://bford.info/pub/lang/peg.pdf>
- Maidl et al., *Error Reporting in Parsing Expression Grammars* (labeled
  failures): <https://arxiv.org/abs/1405.6646>
- Tratt, *Direct Left-Recursive Parsing Expression Grammars*:
  <https://tratt.net/laurie/research/pubs/papers/tratt__direct_left_recursive_parsing_expression_grammars.pdf>
- Kuramitsu, *Fast, Flexible, and Declarative Construction of ASTs with PEGs*
  (transactional capture log): <https://arxiv.org/abs/1507.08610>
- Medeiros & Olarte, *A Semantic Framework for PEGs* (formal cut operators):
  <https://arxiv.org/abs/2011.04360>
- Medeiros & Mascarenhas, *Towards Automatic Error Recovery in Parsing
  Expression Grammars*: <https://arxiv.org/abs/2507.03629>
- Blaudeau & Shankar, *A Verified Packrat Parser Interpreter for PEGs*
  (mechanized well-formedness): <https://arxiv.org/abs/2001.04457>
- Loff, Moreira & Reis, *The Computational Power of Parsing Expression
  Grammars* (undecidability limits on grammar analysis):
  <https://arxiv.org/abs/1902.08272>
- Chida & Kuramitsu, *Linear Parsing Expression Grammars* (the DFA-compilable
  subclass): <https://arxiv.org/abs/1707.01814>
- Garnock-Jones, Eslamimehr & Warth, *Recognising and Generating Terms using
  Derivatives of PEGs* (grammar-driven test generation):
  <https://arxiv.org/abs/1801.10490>
- Yedidia & Chong, *Fast Incremental PEG Parsing* (GPeg, relocatable memo
  entries): <https://dl.acm.org/doi/10.1145/3486608.3486900>

---

### Wishlist amendment

For `arturo-lang/package-ideas`, the existing CFG line stays, since this does
not satisfy it:

```markdown
- [ ] A PARSE-style grammar dialect (PEG, ordered choice): rules as composable
      blocks, matching strings *and* blocks, so Arturo can pattern-match its own
      source. Distinct from the lark-style CFG parser above.
```
