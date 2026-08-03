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
call that encloses it. The argument already supplied in that slot is pushed
down out of reach.

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

Nothing is lost, either. The displaced `42` stays on the stack, `stack`
reports it, and the next call that wants an argument receives it:

```arturo
takesOne: function [v][ print ["received:" v] ]

show "literal " viaLiteral 1 2 42   ; expected: 99
print ["stack:" stack]              ; stack: [42 ...]
takesOne                            ; received: 42
```

So this is the value stack all the way down, and there is nothing here to
fix in the interpreter. What is left is a documentation request: a note
where the stack is described, saying that a leftover inside a function body
is visible to the argument list of the call enclosing it. The stack is
documented and `stack` will show you the evidence, but the reading that gets
you there is not obvious from a call site where both the caller and the
callee look correct in isolation. Naming the interaction, ideally with this
shape as the example, would have turned a long hunt into a lookup.

## Environment

- Arturo 0.10.0 "Arizona Bark" (arm64/macos, Homebrew)

## Context

Found while building a parsing package in pure Arturo, where it showed up as
comparison checks failing on values that printed as equal. `discard` on every
unused result fixes it and reads as intent, which is what the package now
does throughout.
