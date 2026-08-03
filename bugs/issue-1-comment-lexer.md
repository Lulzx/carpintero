# [Draft issue for arturo-lang/arturo]

**Title:** A backslash inside a `;;` documentation comment hangs the lexer

**Body:**

## Describe the bug

`;;` is the documentation-comment form: the interpreter reads its contents
and stores them as metadata, which is what `info` prints back. Reading it is
the feature, and the report below is about two ways that reading fails
rather than about the reading itself.

A backslash inside a `;;` comment, followed by anything that is not a
letter, loops forever (100% CPU, no output, must be killed):

```arturo
;; with \- dash
print "should print but never does"
```

An unbalanced delimiter inside one raises a syntax error, which is
awkward for a form whose `description:` field is free text:

```arturo
;; unmatched ( paren
print "ok"                  ; Syntax Error
```

Neither needs a function anywhere near it, and neither happens with a
single `;`, which is ignored outright.

## What decides the hang

The character after the backslash. Letters are fine, so are `_` and `/`:

| after `\` | result |
| --- | --- |
| `a` `z` `A` `_` `/` | runs |
| `-` `+` `.` `,` `:` `=` `<` `~` `?` `!` `\|` `$` `*` `)` `\` space | hangs |
| `1` `9` | hangs |

A backslash with a word character before it is fine (`;; x\-` runs), which
is the shape of ordinary path syntax, so the scanner looks to be reading
`\` as the start of a path component and not terminating when what follows
cannot begin one. Position on the line does not matter: a trailing `;;`
comment after code hangs the same way. Inside a string literal, `";; \- "`
is untouched.

The string-lexer path hangs too, so this is not specific to file loading:
`to :block` over the same source read raw never returns either.

## Reproduce

`comment-lexer-hang.art` is the two-line version above.

## Expected behavior

A scanner that cannot make progress should report an error rather than
loop. Beyond that, a documentation comment is prose, and prose contains
backslashes, apostrophes and unmatched brackets, so the fields would be
better read as text to the end of the line than as source.

## Environment

- Arturo 0.10.0 "Arizona Bark" (arm64/macos, Homebrew)

## Context

Found while developing a pure-Arturo parsing package, where `;;` is the
natural choice for file-header comments and a dash inside one is a natural
thing to write.

There is an in-language workaround, since `read` returns raw source without
lexing: strip comments at the string level, respecting string and char
literals, then lex with `to :block` and evaluate with `do`, so no comment
byte reaches the lexer. The package ships this as `loadSafe`, and
`../examples/safeload.art` runs the hanging repro above through it
successfully. It costs the documentation metadata, which is the right
trade only while the hang exists.
