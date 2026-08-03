## Character classes.
##
## The interpreted matcher carries a charset as an ASCII lookup array plus a
## sorted list of ranges for everything above it, and settles the common case
## from the array without a call. The same split survives the translation,
## except that Nim gives the ASCII half away for free: `set[char]` is a
## 256-bit bitmap the compiler tests with a single instruction.
##
## Matching is on codepoints, not bytes, because Arturo strings are
## character-indexed and the dialect has to agree with the language about
## what position N means.

type
    Charset* = object
        ascii*: set[char]                 ## codepoints below 128
        ranges*: seq[(int32, int32)]      ## inclusive, sorted, disjoint, >= 128
        negated*: bool                    ## complement applied after the above

proc addRange*(cs: var Charset, lo, hi: int32) =
    ## Add an inclusive codepoint range, splitting it across the two halves.
    ## Ranges are kept sorted and merged so that `contains` can binary-search
    ## and so that union does not grow the list without bound.
    if lo > hi: return
    if lo < 128:
        for c in lo .. min(hi, 127'i32):
            cs.ascii.incl(char(c))
        if hi < 128: return
    let l = max(lo, 128'i32)
    var merged: seq[(int32, int32)] = @[]
    var nlo = l
    var nhi = hi
    for (a, b) in cs.ranges:
        if b + 1 < nlo:
            merged.add((a, b))
        elif nhi + 1 < a:
            merged.add((nlo, nhi))
            nlo = a
            nhi = b
        else:
            nlo = min(nlo, a)
            nhi = max(nhi, b)
    merged.add((nlo, nhi))
    cs.ranges = merged

proc addChar*(cs: var Charset, cp: int32) {.inline.} =
    cs.addRange(cp, cp)

proc contains*(cs: Charset, cp: int32): bool {.inline.} =
    ## The ASCII bitmap settles the overwhelming majority of terminals.
    var hit: bool
    if cp < 128:
        hit = cp >= 0 and char(cp) in cs.ascii
    else:
        hit = false
        var lo = 0
        var hi = cs.ranges.len - 1
        while lo <= hi:
            let mid = (lo + hi) div 2
            let (a, b) = cs.ranges[mid]
            if cp < a: hi = mid - 1
            elif cp > b: lo = mid + 1
            else:
                hit = true
                break
    result = hit xor cs.negated

proc union*(a, b: Charset): Charset =
    ## Union of two sets. A negated operand is expanded through its ranges
    ## rather than kept lazily, since composition happens once per grammar
    ## and matching happens once per character.
    result.ascii = a.ascii + b.ascii
    result.ranges = a.ranges
    for (lo, hi) in b.ranges:
        result.addRange(lo, hi)

proc intersect*(a, b: Charset): Charset =
    result.ascii = a.ascii * b.ascii
    for (lo, hi) in a.ranges:
        for (lo2, hi2) in b.ranges:
            let l = max(lo, lo2)
            let h = min(hi, hi2)
            if l <= h: result.addRange(l, h)

proc complement*(a: Charset): Charset =
    result = a
    result.negated = not a.negated

proc isEmpty*(cs: Charset): bool =
    cs.ascii == {} and cs.ranges.len == 0 and not cs.negated
