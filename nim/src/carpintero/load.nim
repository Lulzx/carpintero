## Reading what `adapter/export.art` wrote.
##
## The interchange format is tagged rather than inferred: two Arturo values
## can print identically and match differently, so every value carries its
## kind and nothing is reconstructed from a rendering. `'+` prints as `+` and
## so does the symbol `+`, and `quote` has to tell them apart.

import std/[json, tables, unicode, strutils]
import charset, grammar, items

type
    LoadError* = object of CatchableError

proc want(n: JsonNode, field: string): JsonNode =
    if n.kind != JObject or field notin n:
        raise newException(LoadError, "missing field '" & field & "' in " & $n)
    n[field]

const compactKinds = {
    "b": itBlock, "s": itString, "w": itWord, "l": itLabel, "t": itLiteral,
    "y": itSymbol, "q": itSymbolLiteral, "T": itType, "i": itInteger,
    "f": itFloating, "g": itLogical, "c": itChar, "n": itNull,
    "d": itDictionary, "o": itOpaque}.toTable

proc loadCompact(n: JsonNode): Item =
    ## The form the FFI path sends: a two-element array, tag first. Building
    ## it costs the Arturo side about five times less than the object form,
    ## and the input is the bulk of what crosses.
    if n.kind != JArray or n.len < 1:
        raise newException(LoadError, "malformed compact value: " & $n)
    let tag = n[0].getStr
    if tag notin compactKinds:
        raise newException(LoadError, "unknown compact tag '" & tag & "'")
    case compactKinds[tag]
    of itBlock:
        var its: seq[Item] = @[]
        for e in n[1]: its.add(loadCompact(e))
        Item(kind: itBlock, items: its)
    of itDictionary:
        var ps: seq[(string, Item)] = @[]
        for pair in n[1]: ps.add((pair[0].getStr, loadCompact(pair[1])))
        Item(kind: itDictionary, pairs: ps)
    of itString: iStr(n[1].getStr)
    of itWord: iWord(n[1].getStr)
    of itLabel: iLabel(n[1].getStr)
    of itLiteral: iLit(n[1].getStr)
    of itSymbol: iSym(n[1].getStr)
    of itSymbolLiteral: iSymLit(n[1].getStr)
    of itType: iType(n[1].getStr)
    of itInteger: iInt(n[1].getBiggestInt)
    of itFloating: iFloat(n[1].getFloat)
    of itLogical: iLog(n[1].getBool)
    of itChar: Item(kind: itChar, c: int32(n[1].getInt))
    of itNull: iNull()
    of itOpaque: iOpaque(n[1].getStr, (if n.len > 2: n[2].getStr else: ""))

proc loadItem*(n: JsonNode): Item =
    ## Both shapes: the object form the differential corpus is written in,
    ## and the compact array form the FFI path sends.
    if n.kind == JArray: return loadCompact(n)
    let k = want(n, "k").getStr
    case k
    of "block":
        var its: seq[Item] = @[]
        for e in want(n, "v"): its.add(loadItem(e))
        Item(kind: itBlock, items: its)
    of "dictionary":
        var ps: seq[(string, Item)] = @[]
        for pair in want(n, "v"):
            ps.add((pair[0].getStr, loadItem(pair[1])))
        Item(kind: itDictionary, pairs: ps)
    of "integer": iInt(want(n, "v").getBiggestInt)
    of "floating": iFloat(want(n, "v").getFloat)
    of "logical": iLog(want(n, "v").getBool)
    of "null": iNull()
    of "string": iStr(want(n, "v").getStr)
    of "char": Item(kind: itChar, c: int32(want(n, "v").getInt))
    of "type": iType(want(n, "v").getStr)
    of "word": iWord(want(n, "v").getStr)
    of "label": iLabel(want(n, "v").getStr)
    of "literal": iLit(want(n, "v").getStr)
    of "symbol": iSym(want(n, "v").getStr)
    of "symbolliteral": iSymLit(want(n, "v").getStr)
    of "opaque": iOpaque(want(n, "t").getStr, want(n, "v").getStr)
    else:
        raise newException(LoadError, "unknown value kind '" & k & "'")

proc loadCharset(n: JsonNode): Charset =
    for r in want(n, "ranges"):
        result.addRange(int32(r[0].getInt), int32(r[1].getInt))

proc loadNode*(n: JsonNode): Node =
    let k = want(n, "k").getStr
    case k
    of "alt":
        var arms: seq[Node] = @[]
        for a in want(n, "arms"): arms.add(loadNode(a))
        Node(kind: nkAlt, items: arms)
    of "seq":
        var its: seq[Node] = @[]
        for e in want(n, "items"): its.add(loadNode(e))
        Node(kind: nkSeq, items: its)
    of "str": Node(kind: nkStr, text: want(n, "v").getStr.toRunes)
    of "char": Node(kind: nkChar, cp: int32(want(n, "v").getInt))
    of "set": Node(kind: nkSet, cs: loadCharset(n))
    of "rule": Node(kind: nkRule, name: want(n, "name").getStr)
    of "skip": Node(kind: nkSkip)
    of "end": Node(kind: nkEnd)
    of "cut": Node(kind: nkCut)
    of "some": Node(kind: nkSome, body: loadNode(want(n, "body")))
    of "any": Node(kind: nkAny, body: loadNode(want(n, "body")))
    of "opt": Node(kind: nkOpt, body: loadNode(want(n, "body")))
    of "not": Node(kind: nkNot, body: loadNode(want(n, "body")))
    of "ahead": Node(kind: nkAhead, body: loadNode(want(n, "body")))
    of "to": Node(kind: nkTo, body: loadNode(want(n, "body")))
    of "thru": Node(kind: nkThru, body: loadNode(want(n, "body")))
    of "into": Node(kind: nkInto, body: loadNode(want(n, "body")))
    of "keep": Node(kind: nkKeep, body: loadNode(want(n, "body")))
    of "rep":
        Node(kind: nkRep, count: want(n, "count").getInt,
             repBody: loadNode(want(n, "body")))
    of "between":
        Node(kind: nkBetween, lo: want(n, "lo").getInt,
             hi: want(n, "hi").getInt, btBody: loadNode(want(n, "body")))
    of "capture":
        Node(kind: nkCap, capName: want(n, "name").getStr,
             capBody: loadNode(want(n, "body")))
    of "collect":
        Node(kind: nkCollect, capName: want(n, "name").getStr,
             capBody: loadNode(want(n, "body")))
    of "type": Node(kind: nkTypeTerm, name: want(n, "name").getStr)
    of "word": Node(kind: nkWordTerm, name: want(n, "name").getStr)
    of "quote": Node(kind: nkQuote, literal: loadItem(want(n, "v")))
    of "fail": Node(kind: nkFail, msg: want(n, "msg").getStr)
    of "defer": Node(kind: nkDefer, blockId: want(n, "id").getInt)
    of "do":
        # host code, which the compiled core cannot run. It matches without
        # consuming, so an empty sequence stands in for it and the runner
        # knows not to compare escape effects.
        Node(kind: nkSeq, items: @[])
    else:
        raise newException(LoadError, "unknown grammar node '" & k & "'")

proc loadGrammar*(n: JsonNode): Grammar =
    result.start = loadNode(want(n, "start"))
    for name, body in want(n, "rules").pairs:
        result.rules[name] = loadNode(body)

type
    Case* = object
        name*: string
        grammar*: Grammar
        isBlock*: bool
        text*: string
        items*: seq[Item]
        ok*: bool                              ## what the interpreter decided
        captures*: Table[string, Item]
        collected*: Table[string, seq[Item]]

proc loadCase*(n: JsonNode): Case =
    result.name = want(n, "name").getStr
    result.grammar = loadGrammar(want(n, "grammar"))
    let inp = want(n, "input")
    if want(inp, "kind").getStr == "block":
        result.isBlock = true
        for e in want(inp, "v"): result.items.add(loadItem(e))
    else:
        result.text = want(inp, "v").getStr
    result.ok = want(n, "ok").getBool
    for name, v in want(n, "captures").pairs:
        result.captures[name] = loadItem(v)
    for name, v in want(n, "collected").pairs:
        var its: seq[Item] = @[]
        for e in v: its.add(loadItem(e))
        result.collected[name] = its

proc loadCases*(path: string): seq[Case] =
    let doc = parseJson(readFile(path))
    for c in doc:
        result.add(loadCase(c))
