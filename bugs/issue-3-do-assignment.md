# [Draft issue for arturo-lang/arturo]

**Title:** `do` of a block containing an assignment crashes silently when the executing function is nested

**Body:**

## Describe the bug

`do someBlock` works inside a function called from top level, but when the
`do`-executing function is itself called from another function, a block
containing an assignment — plain (`x: 3`) or path (`G\n: 3`) — makes the
interpreter exit 1 silently: no output, no error message.

Blocks containing only expressions or calls to functions of arity ≥ 1 work
at any nesting depth. Calls to zero-arity functions in the same
configuration also crash.

## To reproduce

```arturo
h1: function [b][
    res: do b
    res
]
h0: function [b][
    r: h1 b
    r
]

print h0 [1 + 1]

G: #[n: 0]
print h0 [G\n: 3]
print "never reached"
```

Actual output: `2`, then silent exit 1.
Removing the `h0` wrapper (calling `h1` directly from top level) makes the
same `do` succeed.

## Expected behavior

Prints `2`, then `3`, then `never reached`.

## Root cause hypothesis, and a reliable workaround

The common factor across every crashing shape is not the assignment: it is
that the block's **last expression produces no value** (an assignment, a
`set` call, a call to a function whose own body ends value-less). `do` of
such a block appears to leave the enclosing frame expecting a value that
never arrives; whether that corrupts anything is contextual, which is why
the same shape sometimes works at one nesting depth and dies at another.

Padding the block with a trailing value before evaluation makes every
shape below work, at any depth tested:

```arturo
discard do blk ++ [true]
```

## A second shape of the same crash

The nesting is not required if the assignment hides inside a called
function: `do` of a block that calls a function whose *body ends with an
assignment* crashes even at top level. Making that function return a value
after the assignment fixes it.

```arturo
G: #[n: 0]
bad:  function [x][ G\n: G\n + x ]
good: function [x][ G\n: G\n + x  x ]

r1: do [good 1]
print "good survives"
r2: do [bad 1]
print "never reached"
```

Actual output: `good survives`, then silent exit 1.

## Environment

- Arturo 0.10.0 "Arizona Bark" (arm64/macos, Homebrew)

## Context

Found while implementing a host-code escape in a pure-Arturo parsing
package. Workaround: escape blocks call arity-1+ helper functions instead
of assigning directly.
