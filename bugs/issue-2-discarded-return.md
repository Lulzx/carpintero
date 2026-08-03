# [Draft issue for arturo-lang/arturo]

**Title:** Discarded call result leaks into the argument stream of an enclosing call

**Body:**

## Describe the bug

When a function is called inline as an argument to another call, and inside
it a call's result is discarded (most reliably a value produced by an early
`return` in the callee), the discarded value leaks into the enclosing
call's argument stream: the next argument slot receives the leaked value
and the real argument is silently lost.

`loop` over an empty collection in the same position leaks a `null` the
same way, so this looks like one stack-discipline bug with several faces.

## To reproduce

```arturo
earlyReturn: function [x][
    if x -> return 7
    8
]

discards: function [a b][
    earlyReturn true
    true
]

show: function [label got expected][
    print [label "| got:" got "| expected:" expected]
]

show "leak" discards 1 2 42
```

Actual output:

```
leak | got: true | expected: 7
```

`expected` receives the leaked `7`, and the real argument `42` is lost. If the
result of `earlyReturn true` is assigned to a variable instead of
discarded, the output is correct (`expected: 42`).

## Expected behavior

`show` should receive `42` as its third argument regardless of what
`discards` does internally with intermediate values.

## Environment

- Arturo 0.10.0 "Arizona Bark" (arm64/macos, Homebrew)

## Context

Found while developing a pure-Arturo parsing package, where it manifested
as comparison checks failing on values that printed as equal. Workaround:
route every unused call result through the `discard` builtin, including
`discard loop items 'x [...]` for the empty-loop face, which it also
fixes. (Dummy-variable assignment works too, but `discard` is the
intended tool and reads as intent.)
