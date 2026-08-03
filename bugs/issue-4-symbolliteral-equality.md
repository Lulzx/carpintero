# [Draft issue for arturo-lang/arturo]

**Title:** `:symbolliteral` values are never equal, not even to themselves

**Body:**

## Describe the bug

A value of type `:symbolliteral`, the quoted-operator form (`'+`, `'-`,
`'-->`), compares unequal to itself. Both `=` and `equal?` return `false`
for the very same value, so the type is outside reflexive equality
entirely.

The underlying comparison is what to look at first. `compare` reports
"greater" for a value against itself, while both orderings report false:

```arturo
s: first to :block {'+}

print ["compare s s:" compare s s]   ; 1
print ["s < s:" s < s]               ; false
print ["s > s:" s > s]               ; false
print ["s = s:" s = s]               ; false
```

A `compare` that can only answer 1 is a comparison path with no case for
the type, and it accounts for every symptom below in one line.

Everything downstream of equality inherits it: `contains?` cannot find a
symbolliteral in a block that holds it, `unique` will not deduplicate one,
and any block or dictionary containing one is never equal to a copy of
itself. That last consequence is how this was found: a source-rewriting
tool checked its own output by lexing both forms and comparing the blocks,
and two files out of Arturo's test suite reported a difference that did
not exist.

The neighbouring types behave correctly: `:symbol` (`<=`), `:literal`
(`'foo`) and `:word` (`foo`) are all reflexively equal. Only the
symbolliteral is affected, and every spelling of it is:
`'+ '- '* '^ '~ '=> '-->` all fail.

## To reproduce

```arturo
s: first to :block {'+}

print s = s              ; false, expected true
print equal? s s         ; false, expected true
print contains? @[s] s   ; false, expected true
print unique @[s s]      ; [+ +], expected [+]

a: to :block {byteCode ['+]}
b: to :block {byteCode ['+]}
print a = b              ; false, expected true
```

A self-contained repro, including the control cases for the neighbouring
types, is in `symbolliteral-equality.art`.

## Expected behaviour

`s = s` is `true` for every value of every type. A symbolliteral should
compare by the symbol it names, exactly as `:symbol` and `:literal`
already do.

## Actual behaviour

Every comparison of two symbolliterals returns `false`, including a value
against itself.

## Environment

- Arturo 0.10.0 "Arizona Bark", arm64/macos (Homebrew)

## Notes

`to :string` renders the value correctly, so the value itself is intact
and it is the comparison that is missing, most likely a missing
`SymbolLiteral` branch in the value-equality dispatch, falling through to
a default that reports inequality rather than raising.

The workaround for anyone comparing blocks that might hold one is to
compare `to :string` renderings instead, which is exact for this type but
costs a full serialization of both sides.
