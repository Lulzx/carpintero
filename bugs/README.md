# Arturo 0.10.0 interpreter bugs

Found while building the Carpintero grammar-dialect draft (`../carpintero.art`)
on Arturo 0.10.0 "Arizona Bark" (arm64/macos, Homebrew). Each file is a
minimal self-contained repro, ready to attach to an issue on
`arturo-lang/arturo`. Not filed yet.

## 1. `comment-lexer-hang.art` — lexer does not fully ignore comment contents

A `\-` sequence inside a line comment hangs the parser forever (100% CPU,
no output). Other comment contents produce phantom syntax errors at EOF
("missing closing parenthesis") or silent `exit 0` with no output, and some
failures depend on the *combination* of adjacent comment lines, so the same
comment can be fine in one file and fatal in another.

Run: `arturo comment-lexer-hang.art` → hangs (kill it manually).
Expected: prints `should print but never does`.

## 2. `discarded-return-leak.art` — discarded call results corrupt argument passing

When a function is called as an argument to another call, and *inside* it a
call's result is discarded (most reliably a value produced by an early
`return` in the callee, or `loop` over an empty collection), the discarded
value leaks into the enclosing call's argument stream: the next argument
slot receives the leaked value and the real argument is lost.

Run: `arturo discarded-return-leak.art`.
Expected: `expected: 42`, actual: `expected: 7`.

Workaround used in carpintero.art: assign every unused call result to a
dummy variable, and guard every `loop` that might iterate an empty
collection.

## 3. `do-assignment-crash.art` — `do` of a block containing an assignment crashes when nested

`do someBlock` works inside a function called from top level, but when the
`do`-executing function is itself called from another function, a block
containing a plain assignment (`x: 3`) or a path assignment (`G\n: 3`)
crashes the interpreter silently (exit 1, no output, no error). Blocks
containing only expressions or calls to arity-1+ functions work at any
depth. Calls to zero-arity functions also crash in the same configuration.

Run: `arturo do-assignment-crash.art`.
Expected: prints `2`, then `3`, then `never reached`; actual: prints `2`
then exits 1 silently.

