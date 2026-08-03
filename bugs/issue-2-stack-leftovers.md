# [Draft question for arturo-lang/arturo]

**Title:** Should a leftover value inside a function body be visible to the caller's argument list?

**Body:**

## Question, not a bug report

This started as a bug report about `return`. It is not one, and the first
draft was wrong twice over: `return` has nothing to do with it, and the
mechanism is the value stack working as designed. What is left is a
question about one consequence of that design.

## What happens

A value left unused inside a function body is popped as an argument by the
call that encloses it. The argument already supplied in that slot is
dropped.

```arturo
earlyReturn: function [x][
    if x -> return 7
    8
]
plain: function [][ 9 ]

viaReturn:   function [a b][ earlyReturn true  true ]
viaFallthru: function [a b][ earlyReturn false true ]
viaCall:     function [a b][ plain            true ]
viaLiteral:  function [a b][ 99               true ]

show: function [label got expected][
    print [label "| got:" got "| expected:" expected]
]

show "return  " viaReturn   1 2 42
show "fallthru" viaFallthru 1 2 42
show "call    " viaCall     1 2 42
show "literal " viaLiteral  1 2 42
```

Output:

```
return   | got: true | expected: 7
fallthru | got: true | expected: 8
call     | got: true | expected: 9
literal  | got: true | expected: 99
```

The full repro is `stack-leftover-args.art`.

## Why it is not the bug it looked like

The four lines differ only in how the leftover is produced, and they behave
identically, so an early `return` is not special. A bare literal in the body
does it too. And the stack itself is doing what it is documented to do:

```arturo
7
print       ; prints 7
```

So in `show "..." viaReturn 1 2 42`, the `42` is pushed, then evaluating
`viaReturn 1 2` pushes `7` onto the same stack, and `show` pops the three
nearest values. Nothing escaped from anywhere. The argument was sitting
deeper in the stack than the callee's leftover.

## The part worth asking about

The displaced `42` is not consumed later. A following call that wants an
argument does not receive it, and it is gone by the end of the statement. So
an unrelated edit inside a callee can take the place of an argument the
caller already wrote down, and the real one goes nowhere. The caller reads
correctly, the callee reads correctly, and the wrong value arrives with no
diagnostic.

Two things would help, if the behavior itself is settled:

1. A note in the function or stack documentation, stating that leftovers
   inside a body reach the enclosing call's argument list. The stack is
   documented; this interaction is what took the time to find.
2. Some way to see it. A displaced argument is discarded silently, and a
   warning or a debug-mode trace would have made this a five-minute
   diagnosis.

## Environment

- Arturo 0.10.0 "Arizona Bark" (arm64/macos, Homebrew)

## Context

Found while building a parsing package in pure Arturo, where it showed up as
comparison checks failing on values that printed as equal. `discard` on every
unused result fixes it and reads as intent, which is what the package now
does throughout.
