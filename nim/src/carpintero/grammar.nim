## The rule tree the compiler consumes.
##
## In the interpreted matcher a rule *is* an Arturo block, walked directly.
## The compiled core cannot walk Arturo blocks without linking against the
## interpreter, so the tree is restated here as a plain Nim type, and the
## adapter that turns a `Value` into one of these is the only part that has
## to know about Arturo at all.
##
## Keeping that boundary means the VM can be built and tested on its own, and
## it gives the differential test a serialisable interchange format: the
## interpreted side writes the tree as JSON, the compiled side reads it, and
## both run the same grammar.

import std/[tables, unicode]
import charset

type
    NodeKind* = enum
        nkSeq           ## a sequence of elements
        nkAlt           ## ordered alternation, the arms of a block
        nkStr           ## a text literal
        nkChar
        nkSet
        nkSkip          ## `skip`
        nkEnd           ## `end`
        nkRule          ## a named rule, by name
        nkSome          ## 1 or more
        nkAny           ## 0 or more
        nkOpt
        nkRep           ## exactly n
        nkBetween       ## lo to hi
        nkNot
        nkAhead
        nkTo            ## advance until the body matches, exclusive
        nkThru          ## as above, inclusive
        nkCap
        nkCollect
        nkKeep
        nkInto
        nkCut
        nkFail
        nkDefer
        nkTypeTerm      ## `:integer` and friends, block input only
        nkWordTerm      ## `'function`, block input only
        nkQuote         ## `quote v`, block input only

    Node* = ref object
        case kind*: NodeKind
        of nkSeq, nkAlt:
            items*: seq[Node]
        of nkStr:
            text*: seq[Rune]
        of nkChar:
            cp*: int32
        of nkSet:
            cs*: Charset
        of nkRule, nkTypeTerm, nkWordTerm:
            name*: string
        of nkSome, nkAny, nkOpt, nkNot, nkAhead, nkTo, nkThru, nkInto, nkKeep:
            body*: Node
        of nkRep:
            count*: int
            repBody*: Node
        of nkBetween:
            lo*, hi*: int
            btBody*: Node
        of nkCap, nkCollect:
            capName*: string
            capBody*: Node
        of nkFail:
            msg*: string
        of nkDefer:
            blockId*: int
        of nkQuote:
            literal*: string
        of nkSkip, nkEnd, nkCut:
            discard

    Grammar* = object
        rules*: Table[string, Node]
        start*: Node

# Invariant the compiler relies on: **every Arturo rule block is an `nkAlt`**,
# including a block with no `|` in it, which is a single-armed one. `nkSeq` is
# only ever the contents of one arm. `cut` commits the innermost enclosing
# block, so the compiler needs block boundaries to survive into the tree, and
# this is where they live.

proc child*(n: Node): Node =
    ## The single operand of a one-operand node, whatever it is called.
    case n.kind
    of nkSome, nkAny, nkOpt, nkNot, nkAhead, nkTo, nkThru, nkInto, nkKeep:
        n.body
    of nkRep: n.repBody
    of nkBetween: n.btBody
    of nkCap, nkCollect: n.capBody
    else: nil

proc sq*(items: varargs[Node]): Node = Node(kind: nkSeq, items: @items)
proc alt*(items: varargs[Node]): Node = Node(kind: nkAlt, items: @items)
proc str*(s: string): Node = Node(kind: nkStr, text: s.toRunes)
proc cset*(cs: Charset): Node = Node(kind: nkSet, cs: cs)
proc rule*(name: string): Node = Node(kind: nkRule, name: name)

# ── nullability ──────────────────────────────────────────────────────────
# The same fixpoint the interpreted pre-pass computes, for the same two
# reasons: a left-recursive grammar has to be rejected before matching, and a
# loop whose body can match empty needs the guarded loop form. Knowing which
# loops those are at compile time is what keeps the guard off the hot path
# for every loop that cannot need it.

proc nullableNode(n: Node, nmap: Table[string, bool]): bool =
    ## Cycles through rule names terminate because a name is answered from
    ## `nmap` rather than followed, and the caller iterates to a fixpoint.
    if n == nil: return true
    case n.kind
    of nkSeq:
        for it in n.items:
            if not nullableNode(it, nmap): return false
        true
    of nkAlt:
        for it in n.items:
            if nullableNode(it, nmap): return true
        false
    of nkStr: n.text.len == 0
    of nkChar, nkSet, nkSkip, nkTypeTerm, nkWordTerm, nkQuote, nkInto: false
    of nkEnd, nkCut, nkFail, nkDefer, nkNot, nkAhead: true
    of nkAny, nkOpt, nkTo, nkThru: true
    of nkSome, nkKeep: nullableNode(n.body, nmap)
    of nkRep: n.count == 0 or nullableNode(n.repBody, nmap)
    of nkBetween: n.lo == 0 or nullableNode(n.btBody, nmap)
    of nkCap, nkCollect: nullableNode(n.capBody, nmap)
    of nkRule: nmap.getOrDefault(n.name, false)

proc computeNullable*(g: Grammar): Table[string, bool] =
    ## Fixpoint over the rule table. Starts every rule at "not nullable" and
    ## raises to nullable until nothing changes, which terminates because the
    ## map only ever grows.
    for name in g.rules.keys:
        result[name] = false
    var changed = true
    while changed:
        changed = false
        for name, body in g.rules:
            if result[name]: continue
            if nullableNode(body, result):
                result[name] = true
                changed = true

proc isNullable*(n: Node, nmap: Table[string, bool]): bool =
    nullableNode(n, nmap)
