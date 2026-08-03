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

Text input, through the whole of the control flow: literals, characters,
charsets, `skip`, `end`, ordered choice, `some`, `any`, `opt`, `N rule`,
`between`, `not`, `ahead`, `to`, `thru`, `capture`, `collect` with `keep`,
`cut`, named and mutually recursive rules, the left-recursion pre-pass, and
farthest-failure reporting with an expected-set.

29 tests in `tests/test_vm.nim`, written from the cases the interpreted suite
covers rather than from the implementation, so a disagreement between them is
a disagreement with the manual.

## What does not

Block input. `into`, `:type` terminals, `'word` terminals and `quote` have
opcodes and compile, but the machine raises on them, because the input is
still a `seq[Rune]` rather than a sequence of values. Block matching is the
phase the proposal calls the reason the package exists, so it is next.

`defer` blocks reach the capture log and are never run, since running one
means calling back into Arturo. Memoization is not wired up. Neither is the
`opSpan` charset-run optimisation, which is emitted nowhere yet.

## Layout

| File | What it holds |
| --- | --- |
| `charset.nim` | ASCII bitmap plus sorted ranges above it, union, intersection, complement |
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

**`into` switches the input mid-match**, which LPeg has no notion of. The
opcodes are defined and the backtrack frame has room for the input stack
depth; the descent itself waits on block input.

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
