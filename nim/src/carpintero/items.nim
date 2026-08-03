## Block elements.
##
## Block input is already typed values, so the grammar only has to supply
## structure. The compiled core cannot use Arturo's `Value` without linking
## against the interpreter, so this is the subset of it the matcher actually
## inspects: enough to answer what type an element is, whether two elements
## are equal, and whether one is a block worth descending into.
##
## The adapter that turns a real `Value` into one of these is the only place
## that has to know about Arturo, and it is also the seam the differential
## test runs through.

import std/[strutils, hashes]

type
    ItemKind* = enum
        itNull
        itLogical
        itInteger
        itFloating
        itString
        itChar
        itWord
        itLabel
        itLiteral
        itSymbol
        itSymbolLiteral
        itType
        itBlock
        itDictionary
        itOpaque

    Item* = object
        case kind*: ItemKind
        of itNull: discard
        of itLogical: b*: bool
        of itInteger: i*: int64
        of itFloating: f*: float
        of itChar: c*: int32
        of itString, itWord, itLabel, itLiteral, itSymbol, itSymbolLiteral,
           itType:
            s*: string
        of itBlock: items*: seq[Item]
        of itDictionary: pairs*: seq[(string, Item)]
        of itOpaque:
            ## Every other Arturo type: :inline, :path, :attribute, :color,
            ## :quantity, :regex, :version and the rest. The matcher asks
            ## three questions of a value, and an opaque one answers all
            ## three: what type is it (`tag`), is it a block to descend into
            ## (no), and is it equal to that other value (`tag` and `repr`).
            ## `repr` is empty for the types Arturo cannot render to a
            ## string, which makes two of those compare equal on tag alone.
            ## `quote` is the only word that would notice, and the exporter
            ## refuses to serialise a `quote` of one.
            tag*: string
            repr*: string

const typeNames*: array[ItemKind, string] = [
    ":null", ":logical", ":integer", ":floating", ":string", ":char",
    ":word", ":label", ":literal", ":symbol", ":symbolliteral", ":type",
    ":block", ":dictionary", ""]

proc typeName*(it: Item): string {.inline.} =
    if it.kind == itOpaque: ":" & it.tag
    else: typeNames[it.kind]

proc `==`*(a, b: Item): bool =
    ## Structural equality.
    ##
    ## This is a deliberate divergence from the interpreted matcher, which
    ## inherits Arturo 0.10.0's bug where a `:symbolliteral` is not equal to
    ## itself (`bugs/symbolliteral-equality.art`). `quote '+` therefore cannot
    ## match a `'+` under the interpreter and can here. The differential test
    ## has to know that this one disagreement is the interpreter's, not the
    ## compiler's.
    if a.kind != b.kind: return false
    case a.kind
    of itNull: true
    of itLogical: a.b == b.b
    of itInteger: a.i == b.i
    of itFloating: a.f == b.f
    of itChar: a.c == b.c
    of itString, itWord, itLabel, itLiteral, itSymbol, itSymbolLiteral, itType:
        a.s == b.s
    of itBlock:
        if a.items.len != b.items.len: return false
        for k in 0 ..< a.items.len:
            if a.items[k] != b.items[k]: return false
        true
    of itDictionary:
        if a.pairs.len != b.pairs.len: return false
        for k in 0 ..< a.pairs.len:
            if a.pairs[k][0] != b.pairs[k][0]: return false
            if a.pairs[k][1] != b.pairs[k][1]: return false
        true
    of itOpaque: a.tag == b.tag and a.repr == b.repr

proc `$`*(it: Item): string =
    case it.kind
    of itNull: "null"
    of itLogical: (if it.b: "true" else: "false")
    of itInteger: $it.i
    of itFloating: $it.f
    of itChar: "'" & $chr(it.c and 0xff) & "'"
    of itString: it.s
    of itWord: it.s
    of itLabel: it.s & ":"
    of itLiteral: "'" & it.s
    of itSymbol: it.s
    of itSymbolLiteral: "'" & it.s
    of itType: it.s
    of itBlock:
        var parts: seq[string] = @[]
        for e in it.items: parts.add($e)
        "[" & parts.join(" ") & "]"
    of itDictionary:
        var parts: seq[string] = @[]
        for (k, v) in it.pairs: parts.add(k & ":" & $v)
        "[" & parts.join(" ") & "]"
    of itOpaque:
        if it.repr.len > 0: it.repr else: "<" & it.tag & ">"

# constructors, for tests and for the adapter
proc iNull*(): Item = Item(kind: itNull)
proc iLog*(b: bool): Item = Item(kind: itLogical, b: b)
proc iInt*(i: int64): Item = Item(kind: itInteger, i: i)
proc iFloat*(f: float): Item = Item(kind: itFloating, f: f)
proc iStr*(s: string): Item = Item(kind: itString, s: s)
proc iChar*(c: char): Item = Item(kind: itChar, c: int32(c))
proc iWord*(s: string): Item = Item(kind: itWord, s: s)
proc iLabel*(s: string): Item = Item(kind: itLabel, s: s)
proc iLit*(s: string): Item = Item(kind: itLiteral, s: s)
proc iSym*(s: string): Item = Item(kind: itSymbol, s: s)
proc iSymLit*(s: string): Item = Item(kind: itSymbolLiteral, s: s)
proc iType*(s: string): Item = Item(kind: itType, s: s)
proc iBlock*(items: varargs[Item]): Item = Item(kind: itBlock, items: @items)

proc iOpaque*(tag, repr: string): Item = Item(kind: itOpaque, tag: tag, repr: repr)
