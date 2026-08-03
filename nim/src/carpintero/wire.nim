## Reading the FFI's input format in one pass.
##
## `adapter/fast.art` writes the input as tagged two-element arrays, and the
## whole of it crosses on every scan: 138,393 values for Arturo's own source.
## Going through `std/json` means building a `JsonNode` tree and then walking
## it again into `Item`s, which measured 43 ms and 14 ms against 32 ms of
## actual matching. This reads the text straight into `Item`s, and does not
## build the tree at all.
##
## `load.nim` still reads the same shape through `std/json`, and the two are
## held together by `tests/test_wire.nim`, which parses the corpus both ways
## and compares. That is deliberate: the JSON path is the readable statement
## of what the format means, and this one has to agree with it.

import std/strutils
import items

type
    WireError* = object of CatchableError

    WireInput* = object
        ## Either kind of input the matcher takes.
        isText*: bool
        text*: string
        items*: seq[Item]

proc fail(msg: string, at: int) {.noreturn.} =
    raise newException(WireError, msg & " at offset " & $at)

proc expect(s: string, i: var int, c: char) {.inline.} =
    if i >= s.len or s[i] != c:
        fail("expected '" & c & "'", i)
    inc i

proc readString(s: string, i: var int): string =
    ## A JSON string, with the escapes `jsonEscape` on the Arturo side can
    ## produce: the two mandatory ones, the three control characters it names,
    ## and `\uXXXX` for the rest.
    expect(s, i, '"')
    var start = i
    # the common case is a string with nothing to unescape, which can be
    # taken as one slice rather than character by character
    while i < s.len and s[i] != '"' and s[i] != '\\':
        inc i
    if i < s.len and s[i] == '"':
        result = s[start ..< i]
        inc i
        return
    result = s[start ..< i]
    while i < s.len:
        case s[i]
        of '"':
            inc i
            return
        of '\\':
            inc i
            if i >= s.len: fail("string ends inside an escape", i)
            case s[i]
            of '"': result.add('"')
            of '\\': result.add('\\')
            of '/': result.add('/')
            of 'n': result.add('\n')
            of 't': result.add('\t')
            of 'r': result.add('\r')
            of 'b': result.add('\b')
            of 'f': result.add('\f')
            of 'u':
                if i + 4 >= s.len: fail("truncated \\u escape", i)
                let code = parseHexInt(s[i+1 .. i+4])
                result.add(chr(code and 0xff))
                i += 4
            else: fail("unknown escape '\\" & s[i] & "'", i)
            inc i
        else:
            result.add(s[i])
            inc i
    fail("unterminated string", i)

proc readNumber(s: string, i: var int): string {.inline.} =
    let start = i
    while i < s.len and s[i] != ',' and s[i] != ']':
        inc i
    s[start ..< i]

proc readValue(s: string, i: var int): Item

proc readBlockItems(s: string, i: var int): seq[Item] =
    expect(s, i, '[')
    if i < s.len and s[i] == ']':
        inc i
        return
    while true:
        result.add(readValue(s, i))
        if i >= s.len: fail("block ends early", i)
        if s[i] == ',':
            inc i
        elif s[i] == ']':
            inc i
            return
        else:
            fail("expected ',' or ']' in a block", i)

proc readValue(s: string, i: var int): Item =
    expect(s, i, '[')
    expect(s, i, '"')
    if i >= s.len: fail("value ends before its tag", i)
    let tag = s[i]
    inc i
    expect(s, i, '"')
    expect(s, i, ',')
    case tag
    of 'w': result = iWord(readString(s, i))
    of 's': result = iStr(readString(s, i))
    of 'y': result = iSym(readString(s, i))
    of 'l': result = iLabel(readString(s, i))
    of 't': result = iLit(readString(s, i))
    of 'q': result = iSymLit(readString(s, i))
    of 'T': result = iType(readString(s, i))
    of 'n':
        discard readString(s, i)
        result = iNull()
    of 'i':
        let raw = readNumber(s, i)
        # `std/json` keeps an integer too large for `BiggestInt` as a string
        # and reports it as zero, and the corpus has such literals, so this
        # reports zero too rather than failing where the JSON path did not
        var v: int64 = 0
        try: v = int64(parseBiggestInt(raw))
        except ValueError: v = 0
        result = iInt(v)
    of 'f': result = iFloat(parseFloat(readNumber(s, i)))
    of 'c': result = Item(kind: itChar, c: int32(parseInt(readNumber(s, i))))
    of 'g': result = iLog(readNumber(s, i) == "true")
    of 'b': result = Item(kind: itBlock, items: readBlockItems(s, i))
    of 'd':
        var ps: seq[(string, Item)] = @[]
        expect(s, i, '[')
        if i < s.len and s[i] == ']':
            inc i
        else:
            while true:
                expect(s, i, '[')
                let k = readString(s, i)
                expect(s, i, ',')
                ps.add((k, readValue(s, i)))
                expect(s, i, ']')
                if i >= s.len: fail("dictionary ends early", i)
                if s[i] == ',': inc i
                elif s[i] == ']':
                    inc i
                    break
                else: fail("expected ',' or ']' in a dictionary", i)
        result = Item(kind: itDictionary, pairs: ps)
    of 'o':
        let t = readString(s, i)
        expect(s, i, ',')
        result = iOpaque(t, readString(s, i))
    else:
        fail("unknown tag '" & tag & "'", i)
    expect(s, i, ']')

proc readWire*(s: string): WireInput =
    ## `["block",[...]]` or `["text","..."]`, the two shapes `scanFast` sends.
    var i = 0
    expect(s, i, '[')
    let kind = readString(s, i)
    expect(s, i, ',')
    case kind
    of "block":
        result.isText = false
        result.items = readBlockItems(s, i)
    of "text":
        result.isText = true
        result.text = readString(s, i)
    else:
        fail("unknown input kind '" & kind & "'", i)
    expect(s, i, ']')
