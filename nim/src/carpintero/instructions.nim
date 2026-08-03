## The instruction set.
##
## An LPeg-style machine: matching is a program over a backtrack stack rather
## than a walk over the rule tree. The opcodes are LPeg's, plus the ones this
## dialect needs that LPeg has no equivalent for (`cut`, `defer`, `into`, the
## progress guard, and the block-input terminals).
##
## Instructions are a flat record with two integer operands rather than an
## object variant. Everything an opcode needs that is not an integer lives in
## a pool on the program, indexed by `arg`, which keeps the instruction small
## enough that the hot loop stays in cache.

import std/unicode
import charset, items

type
    OpKind* = enum
        # Terminals, text input
        opAny           ## consume one item, fail at end of input      (`skip`)
        opChar          ## arg: codepoint
        opSet           ## arg: charset pool index
        opStr           ## arg: string pool index
        opSpan          ## arg: charset pool index; consume greedily, never fails
        opEndInput      ## succeed only at end of input                (`end`)

        # Terminals, block input
        opTypeTerm      ## arg: type-name pool index                   (`:integer`)
        opWordTerm      ## arg: name pool index                        (`'function`)
        opStrTerm       ## arg: string pool index; a string *element*
        opQuote         ## arg: literal pool index                     (`quote v`)

        # Control
        opChoice        ## arg: offset to the alternative
        opCommit        ## arg: offset; pop one backtrack entry and jump
        opPartialCommit ## arg: offset; reuse top entry, jump (loop, non-nullable body)
        opPartialCommitG## arg: body offset, aux: exit offset; as above with the
                        ## progress guard, for a loop whose body can match empty
        opBackCommit    ## arg: offset; pop, restore that entry's position, jump
        opFailTwice     ## pop one entry, then fail                    (`not`)
        opFail          ## force failure
        opJmp           ## arg: offset
        opCall          ## arg: absolute address of a rule
        opRet
        opMatch         ## accept

        # Captures
        opCapOpen       ## arg: name pool index, aux: CapKind
        opCapClose      ## aux: CapKind
        opDefer         ## arg: host block id, queued for commit time

        # Dialect extras
        opCut           ## commit the innermost enclosing choice frame
        opCutFrame      ## arg: offset past the frame; push a cut frame
        opCutFrameEnd   ## pop a cut frame
        opFailMsg       ## arg: string pool index                      (`fail "..."`)
        opInto          ## arg: offset past the body; descend into a nested block
        opIntoEnd       ## ascend, requiring the body to have consumed all of it

    CapKind* = enum
        ckCap           ## `capture 'name rule`
        ckKeep          ## `keep rule`
        ckCollect       ## `collect 'name rule`

    Instr* = object
        op*: OpKind
        arg*: int32
        aux*: int32

    Program* = object
        code*: seq[Instr]
        sets*: seq[Charset]
        strs*: seq[seq[Rune]]     ## text literals, as codepoints
        names*: seq[string]       ## capture and rule names, type and word terminals
        msgs*: seq[string]        ## `fail` messages
        lits*: seq[Item]          ## values matched literally by `quote`
        entry*: int32             ## address of the start rule

proc instr*(op: OpKind, arg: int32 = 0, aux: int32 = 0): Instr {.inline.} =
    Instr(op: op, arg: arg, aux: aux)

proc add*(p: var Program, op: OpKind, arg: int32 = 0, aux: int32 = 0): int32 {.discardable.} =
    ## Append an instruction and return its address, so a later patch can find it.
    result = int32(p.code.len)
    p.code.add(instr(op, arg, aux))

proc patch*(p: var Program, at: int32, arg: int32) {.inline.} =
    p.code[at].arg = arg

proc patchAux*(p: var Program, at: int32, aux: int32) {.inline.} =
    p.code[at].aux = aux

proc here*(p: Program): int32 {.inline.} =
    int32(p.code.len)

proc poolSet*(p: var Program, cs: Charset): int32 =
    for i, existing in p.sets:
        if existing == cs: return int32(i)
    result = int32(p.sets.len)
    p.sets.add(cs)

proc poolStr*(p: var Program, s: seq[Rune]): int32 =
    for i, existing in p.strs:
        if existing == s: return int32(i)
    result = int32(p.strs.len)
    p.strs.add(s)

proc poolName*(p: var Program, s: string): int32 =
    for i, existing in p.names:
        if existing == s: return int32(i)
    result = int32(p.names.len)
    p.names.add(s)

proc poolLit*(p: var Program, it: Item): int32 =
    for i, existing in p.lits:
        if existing == it: return int32(i)
    result = int32(p.lits.len)
    p.lits.add(it)

proc poolMsg*(p: var Program, s: string): int32 =
    result = int32(p.msgs.len)
    p.msgs.add(s)

proc `$`*(p: Program): string =
    ## Disassembly. The compiler is the part most likely to be wrong, and a
    ## listing is the cheapest way to see what it emitted.
    for i, ins in p.code:
        result.add($i & "\t" & ($ins.op)[2 .. ^1])
        case ins.op
        of opChoice, opCommit, opPartialCommit, opBackCommit, opJmp,
           opCutFrame, opInto:
            result.add(" -> " & $(int32(i) + ins.arg))
        of opPartialCommitG:
            result.add(" body -> " & $(int32(i) + ins.arg) &
                       ", exit -> " & $(int32(i) + ins.aux))
        of opCall:
            result.add(" @" & $ins.arg)
        of opChar:
            result.add(" '" & $Rune(ins.arg) & "'")
        of opSet, opSpan:
            result.add(" set#" & $ins.arg)
        of opStr, opStrTerm:
            result.add(" \"" & $p.strs[ins.arg] & "\"")
        of opCapOpen:
            result.add(" " & p.names[ins.arg] & " (" & $CapKind(ins.aux) & ")")
        of opCapClose:
            result.add(" (" & $CapKind(ins.aux) & ")")
        of opTypeTerm, opWordTerm:
            result.add(" " & p.names[ins.arg])
        of opQuote:
            result.add(" " & $p.lits[ins.arg])
        of opFailMsg:
            result.add(" \"" & p.msgs[ins.arg] & "\"")
        of opDefer:
            result.add(" #" & $ins.arg)
        else: discard
        result.add("\n")
