# Arturo 0.10.0 interpreter bugs and sharp edges

Found while building the Carpintero grammar-dialect draft (`../carpintero.art`)
on Arturo 0.10.0 "Arizona Bark" (arm64/macos, Homebrew), and while running it
over Arturo's own source tree. Each `.art` file is a minimal self-contained
repro, and each `issue-*.md` is a draft report ready for
`arturo-lang/arturo`. Not filed yet.

Three are bugs. Number 2 turned out to be the value stack behaving as
designed, and its draft is now a documentation question rather than a bug
report. Number 3 turned out to be the same stack from the other side, and
shrank to the one thing about it that is a defect. The first three were
found by writing the dialect, the fourth by *using* it, in the corpus run
described in
[the manual](../MANUAL.md#validation-against-arturos-own-source). All four have
in-language mitigations. Each section names its fix.

## 1. `comment-lexer-hang.art`: `;;` comment contents are scanned by the lexer

A `;` comment is ignored. A `;;` comment is not. A backslash inside one,
followed by anything that is not a letter, hangs the lexer forever (100%
CPU, no output), and an unbalanced `(` or `"` inside one raises a syntax
error. Both are fine with a single semicolon, and neither form contributes
to the program: `to :block` gives the same tokens either way.

What decides the hang is the character after the backslash. Letters are
fine, as are `_` and `/`; `-`, `+`, `.`, `,`, `:`, `=`, `<`, `~`, `?`, `!`,
`|`, `$`, `*`, `)`, a digit, a space and a second backslash all hang. A
backslash with a word character before it is fine (`;; x\-` runs), which is
the shape of ordinary path syntax. What once looked like context-dependence
across adjacent comment lines was this rule and the `;;` distinction.

The string-lexer path hangs too: `to :block` over the same source read raw
never returns either, so this is the lexer and not just the file loader.

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
that slot is pushed down out of reach. That is the value stack doing what it
is documented to do: `7` on its own line, followed by an argless `print`,
prints 7, and the same stack serves both. Nothing leaks anywhere. The
argument was sitting deeper in the stack than the callee's leftover.

`return` is not the trigger either, which is what the first two drafts of
this section claimed. A bare literal in the body behaves identically, as do
an ordinary call and a fallthrough value; `loop` over an empty collection is
the same rule with a `null`.

Nothing is lost either: the displaced argument stays on the stack, `stack`
reports it, and the next call that wants one receives it. What is left is
the documentation request in `issue-2-stack-leftovers.md`, since a call site
where the caller and the callee are each correct in isolation is a poor
place to work this out from first principles.

Run: `arturo stack-leftover-args.art`.

**Mitigation:** route every unused result through the `discard` builtin,
including `discard loop items 'x [...]`. `carpintero.art` does this
throughout, which is the language's own tool for the job rather than a
workaround.

## 3. `stack-underflow-exit.art`: popping an empty value stack exits 1 in silence

Diagnosed three times before it was diagnosed right. First as "`do` of a
block containing an assignment crashes when the executing function is
nested", then as "`do` of a block whose last expression produces no value",
then as "binding a value-less expression corrupts the enclosing frame".
Each was describing a shape rather than the rule, and the rule is section 2
again: **assignment pops a value off the stack like any other consumer.**

A right-hand side that produces none pops whatever is underneath, which is
why `99` on its own line followed by `y: print "hi"` binds 99 and runs to
completion. It is only the empty stack that ends the process, and that is
the part worth reporting: **an underflow exits 1 with no message and
nothing on stderr**, with the last line of output coming from the statement
*before* the one at fault.

Neither `do` nor nesting is required. Two statements are enough:
`y: print "hi"` prints and then ends the run. The `do` forms
(`res: do [G\n: 3]`), the value-less function tail (`y: bad 1`), and
`r: discard ...` are the same statement reached by different routes, which
is the whole of what looked for so long like depth-dependence.

Run: `arturo stack-underflow-exit.art`. Expected five lines. Actual: four,
then silent exit 1. `do-assignment-crash.art` and
`do-assignment-tail-crash.art` are the two shapes it was originally found
in, kept because they are the ones a `do`-using program actually meets.

**Mitigation:** follows from the mechanism. Pad the block so it leaves a
value on the stack, and do not bind the result: `discard do blk ++ [true]`.
Both halves matter, since `res: discard do blk ++ [true]` underflows again,
`discard` producing nothing of its own. `carpintero.art` pads its `do` and
`defer` escape blocks this way, so grammar escapes may assign freely.

## 4. `symbolliteral-equality.art`: a `:symbolliteral` is not equal to itself

`compare s s` returns 1 for one and the same value, while `s < s` and
`s > s` are both `false`, so this is a comparison path with no case for the
type. Equality inherits it: `'+ = '+` is `false`, so is `equal? s s`, and
the type is outside reflexive equality entirely. Every spelling is
affected (`'+ '- '* '^ '~ '=> '-->`), and so is everything built on
equality: `contains?` cannot find one, `unique` will not deduplicate one,
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
