# [Draft issue for arturo-lang/arturo]

**Title:** `;;` comment contents are scanned by the lexer, and a backslash inside one hangs it

**Body:**

## Describe the bug

A `;` comment is ignored. A `;;` comment is not: its contents are scanned,
and two things follow from that on 0.10.0.

A backslash inside a `;;` comment, followed by anything that is not a
letter, hangs the lexer forever (100% CPU, no output, must be killed):

```arturo
;; with \- dash
print "should print but never does"
```

An unbalanced delimiter inside a `;;` comment raises a syntax error:

```arturo
;; unmatched ( paren
print "ok"                  ; Syntax Error
```

Both are fine with a single semicolon. Neither comment form contributes to
the program, so nothing is being parsed *into* anything: `to :block` over
either version gives `[print 1]`.

## What decides it

The character after the backslash. Letters are fine, so are `_` and `/`:

| after `\` | result |
| --- | --- |
| `a` `z` `A` `_` `/` | runs |
| `-` `+` `.` `,` `:` `=` `<` `~` `?` `!` `\|` `$` `*` `)` `\` space | hangs |
| `1` `9` | hangs |

A backslash with a word character before it is fine (`;; x\-` runs), which
is the shape of ordinary path syntax. Position on the line does not matter:
a trailing `;;` comment after code hangs the same way. Inside a string
literal, `";; \- "` is untouched.

## Reproduce

`comment-lexer-hang.art` is the two-line version above.

## Expected behavior

Comment contents should not affect lexing. Failing that, a lexer that
cannot make progress should report an error rather than loop.

## Environment

- Arturo 0.10.0 "Arizona Bark" (arm64/macos, Homebrew)

## Context

Found while developing a pure-Arturo parsing package, where `;;` is a
natural choice for file-header comments and a dash inside one is a natural
thing to write.

There is an in-language workaround, since `read` returns raw source without
lexing: strip comments at the string level, respecting string and char
literals, then lex with `to :block` and evaluate with `do`, so no comment
byte reaches the lexer. The package ships this as `loadSafe`, and
`../examples/safeload.art` runs the hanging repro above through it
successfully.

If `;;` is meant to be a documentation form the lexer inspects on purpose,
the hang is still a hang, and the report is then about the loop rather than
about the scanning.
