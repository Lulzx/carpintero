# Arturo 0.10.0 interpreter bugs and sharp edges

Found while building the Carpintero grammar-dialect draft (`../carpintero.art`)
on Arturo 0.10.0 "Arizona Bark" (arm64/macos, Homebrew), and while running it
over Arturo's own source tree. Each `.art` file is a minimal self-contained
repro, and each `issue-*.md` is a draft report ready for
`arturo-lang/arturo`. Not filed yet.

Three are bugs. Number 2 turned out to be the value stack behaving as
designed, and its draft is now a documentation question rather than a bug
report. The first three were found by writing the dialect, the fourth by
*using* it, in the corpus run described in
[the manual](../MANUAL.md#validation-against-arturos-own-source). All four have
in-language mitigations. Each section names its fix.

## 1. `comment-lexer-hang.art`: lexer does not fully ignore comment contents

A `\-` sequence inside a line comment hangs the file loader forever (100%
CPU, no output). Other comment contents produce phantom syntax errors at
EOF ("missing closing parenthesis") or silent exits, and some failures
depend on the *combination* of adjacent comment lines, so the same comment
can be fine in one file and fatal in another. The string-lexer path hangs
too: `to :block` over the same source read raw never returns either, so
this is the lexer mishandling comment bytes and not just the file loader.

Run: `arturo comment-lexer-hang.art` and it hangs (kill it manually).
Expected: prints `should print but never does`.

**Mitigation:** `read` returns raw source without lexing, so strip
comments at the string level before the lexer sees them. The package
provides this as `stripComments`/`loadSafe` (the stripper is itself a
Carpintero grammar), and `../examples/safeload.art` runs this very repro file
through it, successfully.

## 2. `stack-leftover-args.art`: a leftover inside a callee displaces the caller's argument

**Not a bug.** A value left unused inside a function body is popped as an
argument by the call that encloses it, and the argument already written in
that slot is dropped. That is the value stack doing what it is documented to
do: `7` on its own line, followed by an argless `print`, prints 7, and the
same stack serves both. Nothing leaks anywhere. The argument was sitting
deeper in the stack than the callee's leftover.

`return` is not the trigger either, which is what the first two drafts of
this section claimed. A bare literal in the body behaves identically, as do
an ordinary call and a fallthrough value; `loop` over an empty collection is
the same rule with a `null`.

What is left is the question in `issue-2-stack-leftovers.md`: the displaced
argument is not consumed later, it is discarded silently at the end of the
statement, so an edit inside a callee can substitute a value into a caller's
argument list with no diagnostic.

Run: `arturo stack-leftover-args.art`.

**Mitigation:** route every unused result through the `discard` builtin,
including `discard loop items 'x [...]`. `carpintero.art` does this
throughout, which is the language's own tool for the job rather than a
workaround.

## 3. `valueless-assignment.art`: binding a value-less expression corrupts the frame

Diagnosed twice before it was diagnosed right. First as "`do` of a block
containing an assignment crashes when the executing function is nested",
then as "`do` of a block whose last expression produces no value". Both
were describing the shape that turned up first rather than the rule, which
is: **an assignment whose right-hand side produces no value exits 1
silently**. Leaving the same expression unbound is fine.

Neither `do` nor nesting is required. Two statements are enough:
`y: print "hi"` prints and then kills the interpreter. The `do` forms
(`res: do [G\n: 3]`), the value-less function tail (`y: bad 1`), and
`r: discard ...` are all the same rule reached by different routes, which
is the whole of what looked for so long like depth-dependence.

Run: `arturo valueless-assignment.art`. Expected four lines. Actual:
three, then silent exit 1. `do-assignment-crash.art` and
`do-assignment-tail-crash.art` are the two shapes it was originally found
in, kept because they are the ones a `do`-using program actually meets.

**Mitigation:** do not bind the result, and where a block must produce
one, pad it: `discard do blk ++ [true]`. Both halves matter, since
`res: discard do blk ++ [true]` crashes again: `discard` is value-less
itself. `carpintero.art` pads its `do` and `defer` escape blocks this way
and discards the result, so grammar escapes may assign freely.

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
