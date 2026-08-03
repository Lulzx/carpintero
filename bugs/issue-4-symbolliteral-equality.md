# [Draft issue for arturo-lang/arturo]

**Title:** `:symbolliteral` values are never equal, not even to themselves

**Body:**

## Describe the bug

A value of type `:symbolliteral`, the quoted-operator form (`'+`, `'-`,
`'-->`), compares unequal to itself. Both `=` and `equal?` return `false`
for the very same value, so the type is outside reflexive equality
entirely.

The underlying comparison is what to look at first, and two lines show it:

```arturo
print compare '+ '+     ; 1
print '+ = '+           ; false
```

`compare`'s own shipped documentation is "compare given values and return
-1, 0, or 1 based on the result", and its example is `compare 3 3 ; => 0`.
Here it answers 1 for one and the same value.

It also disagrees with the comparison operators, which say nothing at all:

```arturo
print '+ < '+           ; false
print '+ > '+           ; false
```

So the value is neither less than, equal to, nor greater than itself, while
`compare` calls it greater. Two callers giving incompatible answers about
one pair is a comparison path with no case for the type rather than a
decision about symbols, and it accounts for every symptom below.

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
print '+ = '+            ; false, expected true
print equal? '+ '+       ; false, expected true
print contains? @['+] '+ ; false, expected true
print unique @['+ '+]    ; [+ +], expected [+]

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
