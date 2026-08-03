# Carpintero, compiled core

The Nim matcher from Phase 3 of [the proposal](../proposal.md).
`carpintero.art` stays the specification; this is the engine underneath it.

```
cd nim
nim c --hints:off -r tests/test_vm.nim
```

Nothing here links against Arturo. The VM is built and tested on its own so
that it can be developed without a working Arturo build, and so that the rule
tree it consumes can double as an interchange format: the interpreted side
writes a grammar out, the compiled side reads it, and both run the same
grammar over the same input. That is the differential test the proposal asks
for, and the reason the two halves share no code.

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

## What does not

`defer` blocks reach the capture log and come back in the result as host
block ids in match order, but nothing runs them, since running one means
calling back into Arturo. Memoization is not wired up. Neither is the
`opSpan` charset-run optimisation, which is emitted nowhere yet.

Nothing is wired into Arturo, so the `Item` type stands in for `Value` and
the adapter between them is unwritten.

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
| `instructions.nim` | The opcodes, the program with its literal pools, and a disassembler |
| `grammar.nim` | The rule tree, and nullability by fixpoint |
| `compile.nim` | Tree to program, and Ford's well-formedness check |
| `vm.nim` | The matcher loop, the capture log, and materialising captures |
| `carpintero.nim` | `scan` and `scan?` over the above |

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
