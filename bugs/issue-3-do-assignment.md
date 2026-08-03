# [Draft issue for arturo-lang/arturo]

**Title:** Binding the result of an expression that produces no value exits 1 silently

**Body:**

## Describe the bug

An assignment whose right-hand side produces no value corrupts the
enclosing frame, and the interpreter exits 1: no output, no error message,
no traceback. Leaving the same expression unbound is fine.

Two statements are enough, with no block, no `do` and no function in
sight:

```arturo
print "before"
y: print "hi"
print "never reached"
```

Actual output: `before`, `hi`, then silent exit 1.

`print` is standing in for any expression that yields nothing. The same
crash arrives through every other route to a value-less right-hand side.

## The other faces

Each of these is the one rule above, wearing different clothes. Each
exits 1 silently on the last line shown.

A `do` of a block whose last expression is an assignment:

```arturo
G: #[n: 0]
res: do [G\n: 3]           ; crashes
do [G\n: 3]                ; fine, unbound
```

A call to a function whose own body ends in an assignment, so the call
itself produces nothing:

```arturo
G: #[n: 0]
bad: function [n][ G\n: G\n + n ]

bad 1                      ; fine, unbound
y: bad 1                   ; crashes
```

And `discard`, which produces no value of its own:

```arturo
r: discard do blk ++ [true]   ; crashes
discard do blk ++ [true]      ; fine, unbound
```

`bugs/valueless-assignment.art` in the report below is the two-statement
form, with the value-ful control beside it.

## What is *not* the trigger

Worth stating, because this bug wears enough disguises to look like
several, and we chased two of them a long way before finding the rule:

- **`do` is not required.** `y: print "hi"` has no block in it.
- **Function nesting is not required.** All of the above crash at top
  level, in a file with no user-defined function at all.
- **Arity is not the discriminator.** `bad` and a value-returning
  function of the same arity behave differently.
- **It is not contextual.** Every case we found that looked
  depth-dependent or position-dependent turned out to be the presence or
  absence of a binding.

## Expected behavior

Binding a value-less expression should either bind `null` or raise a
catchable error naming the problem. A silent `exit 1` with no diagnostic
is the worst of the three, since nothing in the output points at the
offending line.

## A reliable workaround

Do not bind the result. Where a value is genuinely wanted, pad the
expression so that it produces one. For `do` of an arbitrary block:

```arturo
discard do blk ++ [true]
```

Note that `res: discard do blk ++ [true]` reintroduces the crash, since
`discard` is itself value-less: the padding fixes the block, and dropping
the binding fixes the statement. Both are needed.

## Possibly related

This may share a root with the argument-stream leak reported separately
(a discarded call result landing in an enclosing call's argument slot).
Both are the value stream losing sync around an expression that yields
nothing, in opposite directions: there a value appears where none was
wanted, here none appears where one was.

## Environment

- Arturo 0.10.0 "Arizona Bark" (arm64/macos, Homebrew)

## Context

Found while implementing a host-code escape in a pure-Arturo parsing
package, which now pads every escape block and discards the result
(`discard do op ++ [true]`), so escapes may assign freely.
