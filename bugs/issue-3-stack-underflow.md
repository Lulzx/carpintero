# [Draft issue for arturo-lang/arturo]

**Title:** Popping an empty value stack exits 1 with no diagnostic

**Body:**

## Describe the bug

Assignment pops a value off the stack like any other consumer, so a
right-hand side that produces none pops whatever is underneath it:

```arturo
99
y: print "hi"
print ["y is" y]        ; y is 99 — runs to completion, exit 0
```

That part is the stack working as designed. When there is nothing
underneath, the same statement ends the process:

```arturo
print "before"
y: print "hi"
print "never reached"   ; before, hi, then exit 1
```

No error, no traceback, and nothing on stderr (the redirect file is zero
bytes). `stack-underflow-exit.art` runs both halves in one file.

## Expected behavior

An underflow should raise a runtime error naming the statement, the way
other runtime faults do. The exit code alone points at nothing, and the
last line of output is from the statement *before* the one at fault, which
sends you looking in the wrong place.

Binding `null` would also be defensible, though it is the larger change and
a report is not the place to argue it.

## The routes that reach it

These looked like separate bugs, and two of them were reported as separate
bugs before the rule turned up. Each is a value-less right-hand side with an
empty stack under it:

```arturo
G: #[n: 0]
res: do [G\n: 3]                ; a block whose last expression assigns
bad: function [n][ G\n: G\n + n ]
y: bad 1                        ; a function whose body ends in an assignment
r: discard do blk ++ [true]     ; discard produces nothing of its own
```

Each is fine unbound. Neither `do` nor function nesting is required, which
is what made this look depth-dependent for as long as it did: `y: print
"hi"` at top level is the whole bug.

## Environment

- Arturo 0.10.0 "Arizona Bark" (arm64/macos, Homebrew)

## Context

Found while implementing a host-code escape in a pure-Arturo parsing
package, and misdiagnosed three times before the stack explained it: first
as "escape blocks cannot assign", then as a property of `do`, then as a
binding corrupting the enclosing frame.

The workaround follows from the mechanism. Pad the block so it leaves a
value on the stack, and do not bind the result:

```arturo
discard do blk ++ [true]
```

`res: discard do blk ++ [true]` underflows again, since `discard` produces
nothing of its own, so both halves are needed.
