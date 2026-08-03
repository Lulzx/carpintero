# [Draft issue for arturo-lang/arturo]

**Title:** Lexer does not fully ignore comment contents: `\-` in a comment hangs the parser

**Body:**

## Describe the bug

Comment contents are not fully ignored by the lexer in v0.10.0. The clearest
case: a `\-` sequence inside a line comment makes the parser hang forever
(100% CPU, no output, must be killed).

Related, harder-to-minimize symptoms we hit with other comment contents
(quotes, apostrophes, brackets): phantom `Syntax Error: missing closing
parenthesis` reported at EOF, and silent `exit 1` with no output at all.
These appear to be **contextual**: a comment line that parses fine in
isolation can break a file when adjacent to other lines, which is why only
the hang is minimized below.

## To reproduce

```arturo
;; with \- dash
print "should print but never does"
```

Running `arturo repro.art` hangs.

## Expected behavior

Comments should be byte-transparent to the lexer, and the script should
print and exit.

## Environment

- Arturo 0.10.0 "Arizona Bark" (arm64/macos, Homebrew)

## Context

Found while developing a pure-Arturo parsing package. Practical workaround:
restrict comments to plain words, commas, periods, colons, and single
dashes.

A general in-language workaround also exists, since `read` returns raw
source without lexing: strip comments at the string level (respecting
string and char literals), then lex with `to :block` and evaluate with
`do`, so no comment byte reaches the lexer. The package now ships this
as `loadSafe`. The repro file above, which hangs `arturo` directly, runs
correctly through it.
