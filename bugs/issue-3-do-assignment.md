# [Draft issue for arturo-lang/arturo]

**Title:** `do` of a block whose last expression produces no value corrupts the enclosing frame

**Body:**

## Describe the bug

`do` of a block whose **last expression produces no value** leaves the
enclosing frame expecting one, and the interpreter exits 1 silently: no
output, no error message. A plain assignment (`x: 3`), a path assignment
(`G\n: 3`), a `set` call, and a call to a function whose own body ends
value-less all leave a block value-less.

Whether it crashes is contextual, which is why one shape can look like
several bugs: the first repro below needs the `do`-executing function to
be called from another function, and the second crashes at top level.
Blocks ending in an ordinary expression work at any depth. Arity is not
the discriminator either, since the arity-1 `bad` in the second repro
fails while the arity-1 `good` beside it does not.

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

## A reliable workaround

Padding the block with a trailing value before evaluation makes both
shapes above work, at any depth tested:

```arturo
discard do blk ++ [true]
```

Discard that result rather than binding it. `res: discard do blk ++
[true]` reintroduces the bug, since `discard` produces no value of its
own and so leaves the assignment with the same value-less tail.

## Environment

- Arturo 0.10.0 "Arizona Bark" (arm64/macos, Homebrew)

## Context

Found while implementing a host-code escape in a pure-Arturo parsing
package, which now pads every escape block this way (`discard do op ++
[true]`), so escapes may assign freely.
