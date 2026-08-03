# Carpintero, compiled core

The Nim matcher from Phase 3 of [the proposal](../proposal.md).
`carpintero.art` stays the specification; this is the engine underneath it.

```
cd nim
nim c --hints:off -r tests/test_vm.nim
```

Nothing here links against Arturo. The VM is built and tested on its own so
that it can be developed without a working Arturo build, and so that the rule
tree it consumes can double as an interchange format.

That interchange is now built, and it is what makes the two halves worth
having separately:

```
arturo nim/adapter/cases.art nim/adapter/cases.json
cd nim && nim c --hints:off -r tests/differential.nim adapter/cases.json
```

`adapter/export.art` writes a grammar, an input, and what the interpreted
matcher made of them. `src/carpintero/load.nim` reads all three back, and
`tests/differential.nim` reruns the grammar here and checks the two engines
agree. 51 cases, no disagreements. Because each case carries the interpreted
answer with it, this compares two engines rather than comparing one engine
against something hand-written, so a disagreement is a real disagreement
about the language.

The format is tagged rather than inferred. Two Arturo values can print
identically and match differently: `'+` prints as `+` and so does the symbol
`+`, and `quote` has to tell them apart, so every value carries its kind and
nothing is reconstructed from a rendering.

## Both engines over Arturo's own source

```
scripts/differential-corpus.sh ../arturo
```

The corpus grammar from `examples/arturo-corpus.art` runs over every `.art`
file in an Arturo checkout, once in each engine:

```
exported 168 cases from 168 files (5 would not lex)
interpreted matcher: 15616 ms scanning, 287 definitions
differential: 168 cases compared, 0 disagreements
  collected: 287 interpreted, 287 compiled
  compiled engine: 0 ms compiling, 31 ms scanning
```

The same five-line block grammar finds the same 287 definitions at every
nesting depth in both, with the same 114 captures, and no case disagrees.
That is the claim the package was built to make, now made twice by
implementations that share no matching code.

Both timings are scanning alone. The exporter loads and lexes the corpus
before the interpreted clock starts, and the compiled clock covers compiling
each grammar and matching, not reading the case file. The five files that
will not lex are fixtures in Arturo's test suite that are invalid on purpose.

## What runs

Both input kinds, through the whole of the control flow: literals,
characters, charsets, `skip`, `end`, ordered choice, `some`, `any`, `opt`,
`N rule`, `between`, `not`, `ahead`, `to`, `thru`, `capture`, `collect` with
`keep`, `cut`, named and mutually recursive rules, the left-recursion
pre-pass, and farthest-failure reporting with an expected-set.

Block input adds `:type` and `'word` terminals, `quote`, and `into`, which
swaps the sequence being matched partway through and puts it back on every
path out, backtracking included. A capture taken inside a descent spans the
nested block rather than the outer one, and a failure inside one is located
by a path of indices instead of a single offset.

The shape that matters is the recursive tree walk, since it is what makes a
grammar useful against source:

```
walk: [any [keep defn | into walk | skip]]
```

Both engines find the same two definitions in
`[outer: function [] [inner: function [] []]]`, at different depths.

40 tests in `tests/test_vm.nim`, written from the cases the interpreted suite
covers rather than from the implementation, so a disagreement between them is
a disagreement with the manual.

## Calling it from Arturo

Arturo cannot gain a builtin without changing Arturo, and this package
changes nothing in the interpreter. What it can do is call a shared library,
so that is the seam:

```
cd nim
nim c --app:lib -d:release -o:libcarpintero.dylib src/carpintero_ffi.nim
arturo nim/adapter/try-fast.art ../arturo
```

`adapter/fast.art` defines `scanFast`, which takes the arguments `scan`
takes and returns the shape `scan` returns, with the matching done in the
compiled core. It agrees with `scan` on the small cases and on all 168
corpus files, capture order included.

Because `call.external` carries scalars and nothing else, the grammar and
the input cross as JSON. What comes back is spans rather than values: where
each capture started and ended, and which `into` descent it was inside.
Arturo then slices its own input from those coordinates, so a captured value
keeps its identity instead of being rebuilt, and the kinds this library
models opaquely survive untouched.

### What that costs, and what it argues

Over the corpus `scanFast` takes 0.25 seconds against `scan`'s 15.8, about
sixty times. Each is timed in its own process, which matters: measured in
one process that runs both, `scan` reports 22.5 seconds rather than 15.8
while `scanFast` reports the same 0.25, so the same-process ratio flatters
the bridge by about 40%. The isolated pair is the honest one.
`adapter/breakdown.art` says where the 0.25 goes:

| Stage | Time |
| --- | --- |
| `emitItem`, Arturo values straight to text | 0.19 s |
| the call itself, reading the input and matching included | 0.045 s |

The first version took 15.3 seconds to serialise and 0.13 to call, and five
changes account for the difference.

Escaping ran as an interpreted loop over characters, at about 2.5
microseconds each. `replace` scans in native code and is flat in the length
of the string: at 1600 characters the loop takes 1011 milliseconds per 200
calls and the replaces take 1.7.

The input went through the tagged dictionaries `itemTree` builds, only to be
walked a second time to make text. It goes straight to text now, in a
two-element array rather than an object, with the type compared as a type
instead of stringified per element.

Most values need no escaping at all, so the escaper starts with one native
test and returns the string untouched when it passes. Words, labels, symbols
and literals come from the lexer and in practice never carry a quote or a
backslash, which over Arturo's own source is 80,403 of them and none needing
an escape, so those are guarded by two `contains?` rather than the regex the
general path uses. That guard costs about 8% and is what keeps the fast path
from being an assumption.

The fourth round is about frames rather than text, and it is most of the
way from 1.5 seconds to 0.19. A function whose body assigns anything costs
about 7.3 microseconds a call in Arturo 0.10.0, against 0.3 for one that
assigns nothing, and it costs that whether or not the assignment runs: an
assignment sitting behind an early return is paid for on every call that
returns early. `emitItem` held the value's type in a local and had the
dictionary and opaque cases inline, so all three of those assignments were
charged to all 138,393 values in the corpus. It now assigns nothing: the
type is re-read for each test, at 0.085 microseconds a test against 7.3 for
the local that would have saved fourteen of them, and the two branches that
need locals are separate functions that pay a scope only when reached. A
sixth of the corpus is kinds the matcher models opaquely, and those went
through a `try` for a rendering, so the four kinds Arturo will not render as
a string are named instead. If a kind not on that list ever refuses,
`emitInput` catches it and re-emits the whole input through the guarded
form, so the list being incomplete costs a re-emission rather than a failed
scan.

The same round added a cache per identifier kind. An identifier's text is
the whole of what it emits, and Arturo's own source holds 45,487 words with
911 distinct spellings and 28,758 symbols with 91, so each spelling is
emitted once and looked up afterwards. That is worth about 17%. The emitter
was checked by hashing everything it produces over the whole corpus before
and after: the output is byte for byte what it was.

The fifth round is the other end of the wire. The library read its input
with `std/json`, which builds a `JsonNode` tree and then walks it a second
time into `Item`s: 43 milliseconds of parsing and 14 of walking, against 32
of matching. `src/carpintero/wire.nim` reads the same text straight into
`Item`s in one pass, and over the corpus that is 48.5 milliseconds against
6.7, so the call went from 80 milliseconds to 45. `load.nim` still reads the
format through `std/json`, and `tests/test_wire.nim` parses both ways and
compares the results, over written cases and over a corpus dumped by
`adapter/dump-wire.art`. The JSON reader is the readable statement of what
the format means; the fast one has to agree with it.

The call is now within about 13 milliseconds of the match it performs, and
the compiled core scans the same corpus in about 30 when handed values it
already holds. What is left of the bridge is 78% serialisation, and it is no
longer escaping, a redundant encoding, scopes for locals nobody needed, or a
tree built to be thrown away, which is what the five rounds removed. It is
traversing Arturo's existing value tree from Arturo and building a second
representation of it, which on this corpus and this emitter works out at
roughly 1.4 microseconds a value. That is a change of kind rather than a
floor: what remains belongs to walking and rebuilding the values, not to how
they are written down or read back.

That is the argument for a builtin rather than a bridge, and it is the one
thing an FFI experiment can establish that a benchmark cannot. Three modes,
same grammar, same corpus, same 287 definitions:

| | Corpus time | |
| --- | ---: | --- |
| `scan` | 15.8 s | pure Arturo, the reference |
| `scanFast` | 0.25 s | the shared library, no change to Arturo |
| the core on values it already holds | 0.03 s | what direct access would expose |

A builtin would take the `Value` block it was handed and match on it in
place, with no serialisation at either end, which is the third row. Adding
one means a `src/library/Parse.nim` and a line in `src/vm/vm.nim`, which is
a change to Arturo and therefore upstream's call to make.

## What does not

Two separate lists, because they are different kinds of work. The first
decides whether this can be a builtin at all. The second only decides how
fast it is once it is one.

**Required before it could be integrated:**

- A `Value` adapter. `Item` stands in for Arturo's `Value` today, and
  everything crossing between them goes through JSON, which the measurement
  above shows is the entire cost of the current bridge. A builtin would
  match the block it was handed in place.
- Host escapes calling back into the interpreter. `do` compiles to nothing
  and `defer` blocks reach the capture log and come back as ids in match
  order, but neither runs, since running one means evaluating Arturo from
  inside the matcher.
- Registration: a `src/library/Parse.nim` and a line in `src/vm/vm.nim`.
  That is a change to Arturo, so it is upstream's to make, and this package
  does not make it.

**Optional, and only about speed:**

- Memoization. The interpreted matcher has `scan.memo`; the compiled core
  does not.
- `opSpan`, a greedy charset run. The opcode exists and the compiler emits
  it nowhere. It is the obvious win for character-level grammars like
  `stripComments`.

Neither of the optional two is worth doing before the required three, since
both would have to be re-tested against a different value model afterwards.

The corpus run compares matching, not diagnostics: the exported answer
carries success, captures and collections, but not the farthest-failure path
or the expected set, so the two engines are only known to agree about what
matched.

Values Arturo has and `Item` does not (`:inline`, `:path`, `:attribute`,
`:color`, `:quantity`, `:regex`, `:version` and the rest, 23 kinds in the
corpus against 14 modelled) cross as opaque leaves carrying a type tag and a
rendering. That is enough for the three questions the matcher asks of a
value, and it holds parity because only `:block` is a block to descend into,
so a leaf here is a leaf there. It would not hold for a grammar that
`quote`d one, and the exporter has no way to warn about that yet.

## Deliberate divergences

Two places where the compiled core does not reproduce the interpreted one,
both recorded in tests so they cannot drift by accident.

`quote` compares structurally. The interpreted matcher compares with Arturo's
`=`, and on 0.10.0 a `:symbolliteral` is not equal to itself
(`../bugs/symbolliteral-equality.art`), so `quote '+` cannot match a `'+`
there and can here. That is the interpreter's bug rather than a semantic
choice, so the compiled core is not copying it.

A prefix that matched and stopped short reports `end of input` at the
position it reached. The interpreted matcher gained the same behaviour once
the compiled version made the gap obvious.

## Layout

| File | What it holds |
| --- | --- |
| `charset.nim` | ASCII bitmap plus sorted ranges above it, union, intersection, complement |
| `items.nim` | Block elements: the subset of Arturo's `Value` the matcher inspects |
| `load.nim` | Reading the interchange format back: values, grammars, whole cases |
| `instructions.nim` | The opcodes, the program with its literal pools, and a disassembler |
| `grammar.nim` | The rule tree, and nullability by fixpoint |
| `compile.nim` | Tree to program, and Ford's well-formedness check |
| `vm.nim` | The matcher loop, the capture log, and materialising captures |
| `wire.nim` | The FFI input format, read in one pass into `Item`s |
| `carpintero.nim` | `scan` and `scan?` over the above |
| `carpintero_ffi.nim` | The shared-library entry points Arturo calls |

`tests/dis.nim` prints the program for one grammar. The compiler is the part
most likely to be wrong, and a listing is the cheapest way to see what it
emitted.

## Departures from LPeg

The lowerings are LPeg's. Three things in the dialect have no LPeg
equivalent, and each costs something.

**`cut` needs a frame.** The interpreted matcher keeps one flag per rule
*block* and makes a failing alternative kill the whole block when the flag is
set. A choice point in the VM is per alternative, not per block, so a block
containing a cut gets an explicit frame around it and its arms are marked as
belonging to that frame. Marking is what keeps a cut from reaching into a
nested block's choices. Blocks with no cut in them, which is nearly all
blocks, get no frame and no mark, because the analysis runs at compile time.

**Loops need a runtime progress guard.** LPeg rejects a nullable loop body at
compile time. This dialect instead ends the loop when an iteration matches
without consuming, which has to be a runtime comparison. Compiling
nullability first means the guarded form of `PartialCommit` is emitted only
for the loops that can need it, and every other loop keeps the plain one.

**`into` switches the input mid-match**, which LPeg has no notion of. A
backtrack frame therefore saves the descent depth and the active sequence
alongside the position, and every path out of a descent restores them,
including the failing ones.

It also has to stay out of the left-recursion check. `into` starts its
operand at position 0 of a strictly smaller input, so descent is progress and
cannot left-recurse; following it during head analysis rejects every
recursive tree walk, which is the most useful shape block input has. The
interpreted pre-pass excludes it for the same reason, and the compiled one
did not until a walk that works there was rejected here.

## A question the translation raised

A successful `ahead` keeps what it captured. `not` discards what its operand
captured. Both were checked against the interpreted matcher:

```arturo
scan "abc" [ahead [capture 'peek "ab"] "abc"]   ; => [peek:ab]
scan "abc" [not [capture 'nope "zz"] "abc"]     ; => []
```

The compiled core reproduces both, and `tests/test_vm.nim` pins them. The
asymmetry is defensible, since the manual rolls captures back when an
alternative *fails* and a successful lookahead has not failed, but it does
mean `ahead` can leave a capture describing input the match never consumed.
Worth settling before the semantics are called stable, which is the argument
for settling them upstream rather than here.
