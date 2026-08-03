# Arturo 0.10.0 interpreter bugs

Found while building the Carpintero grammar-dialect draft (`../carpintero.art`)
on Arturo 0.10.0 "Arizona Bark" (arm64/macos, Homebrew), and while running it
over Arturo's own source tree. Each `.art` file is a minimal self-contained
repro, and each `issue-*.md` is a draft report ready for
`arturo-lang/arturo`. Not filed yet.

The first three were found by writing the dialect. The fourth was found by
*using* it, in the corpus run described in
[the manual](../MANUAL.md#validation-against-arturos-own-source). All four have
in-language mitigations. Each section names its fix.

## 1. `comment-lexer-hang.art`: lexer does not fully ignore comment contents

A `\-` sequence inside a line comment hangs the file loader forever (100%
CPU, no output). Other comment contents produce phantom syntax errors at
EOF ("missing closing parenthesis") or silent exits, and some failures
depend on the *combination* of adjacent comment lines, so the same comment
can be fine in one file and fatal in another. The string-lexer path
(`to :block` on the same source) does not hang, but silently corrupts the
token stream instead. Both paths mishandle comment bytes.

Run: `arturo comment-lexer-hang.art` and it hangs (kill it manually).
Expected: prints `should print but never does`.

**Mitigation:** `read` returns raw source without lexing, so strip
comments at the string level before the lexer sees them. The package
provides this as `stripComments`/`loadSafe` (the stripper is itself a
Carpintero grammar), and `../examples/safeload.art` runs this very repro file
through it, successfully.

## 2. `discarded-return-leak.art`: discarded call results corrupt argument passing

When a function is called as an argument to another call, and *inside* it a
call's result is discarded (most reliably a value produced by an early
`return` in the callee, or `loop` over an empty collection), the discarded
value leaks into the enclosing call's argument stream: the next argument
slot receives the leaked value and the real argument is lost.

Run: `arturo discarded-return-leak.art`.
Expected: `expected: 42`, actual: `expected: 7`.

**Mitigation:** route every unused result through the `discard` builtin,
including `discard loop items 'x [...]` for the empty-loop face, which it
also fixes. `carpintero.art` does this throughout.

## 3. `do-assignment-crash.art`, `do-assignment-tail-crash.art`: `do` of a value-less-tail block corrupts the frame

Originally diagnosed as "`do` of a block containing an assignment crashes
when the executing function is nested." The second repro narrows the root
cause: the trigger is a block whose **last expression produces no value**,
that is a plain or path assignment, a `set` call, or a call to a function
whose own body ends value-less. `do` of such a block leaves the enclosing
frame expecting a value that never arrives. Whether that crashes is
contextual (the same shape can work at one nesting depth and silently
exit 1 at another), which makes one bug look like several.

Run: `arturo do-assignment-crash.art`. Expected `2`, `3`,
`never reached`. Actual: `2`, then silent exit 1.
Run: `arturo do-assignment-tail-crash.art`. Expected two lines. Actual:
one line, then silent exit 1, with no nesting involved at all.

**Mitigation:** pad the block with a trailing value before evaluating:
`discard do blk ++ [true]`. With the padding, every shape above works at
any depth tested. `carpintero.art` pads its `do` and `defer` escape blocks
this way, so grammar escapes may assign freely.

## 4. `symbolliteral-equality.art`: a `:symbolliteral` is not equal to itself

`'+ = '+` is `false`. So is `equal? s s` for one and the same value: the
type is outside reflexive equality entirely, and every spelling is
affected (`'+ '- '* '^ '~ '=> '-->`). Everything built on equality goes
with it: `contains?` cannot find one, `unique` will not deduplicate one,
and a block holding one is never equal to a byte-identical copy of itself.
The neighbouring types are all fine: `:symbol` (`<=`), `:literal` (`'foo`)
and `:word` are reflexively equal, which is what makes this a bug rather
than a decision about symbols.

This one was found by *using* the dialect rather than writing it. The
corpus run (`../examples/arturo-corpus.art`) checks `stripComments` by
lexing each file twice, raw and stripped, and comparing the blocks, and
two files in Arturo's own test suite came back unequal with every
element rendering identically. The stripper was correct: the bug was in
equality.

Run: `arturo symbolliteral-equality.art`.
Expected: every check prints `true`. Actual: the first five print `false`.

**Mitigation:** compare `to :string` renderings, which is exact for this
type at the cost of serializing both sides.

It reaches one corner of the dialect. `quote` matches by `=`, so
`[quote '+]` cannot match a `'+` in block input: it is asking the
interpreter a question that has no true answer on 0.10.0. The `:symbolliteral`
type terminal is unaffected and matches normally, and every other terminal
form is comparing types the interpreter compares correctly. Match the type
and inspect the capture if you need a specific symbolliteral.
