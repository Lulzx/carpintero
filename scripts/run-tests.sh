#!/usr/bin/env bash
# Every suite, in one command.
#
# The panic cases need one interpreter each: a panic unwound through `try`
# leaves the abandoned frames' values behind for the next statements to
# misread, so a single process cannot check more than one of them.
set -u
cd "$(dirname "$0")/.."

fails=0

echo "== tests.art =="
arturo tests.art || fails=$((fails + 1))

echo
echo "== demo.art =="
if arturo demo.art > /dev/null 2>&1; then
    echo "  demo ran"
else
    echo "  demo FAILED"
    fails=$((fails + 1))
fi

echo
echo "== tests-panics.art =="
cases=$(arturo tests-panics.art 2>&1 | grep '^known cases:' | cut -d: -f2-)
if [ -z "$cases" ]; then
    echo "  could not read the case list"
    exit 1
fi
ok=0
bad=0
for c in $cases; do
    out=$(arturo tests-panics.art "$c" 2>&1)
    if echo "$out" | grep -q "SURVIVED"; then
        echo "  FAIL $c: did not panic"
        bad=$((bad + 1))
    elif echo "$out" | grep -q "carpintero:"; then
        ok=$((ok + 1))
    else
        echo "  FAIL $c: panicked, but not with a carpintero message"
        bad=$((bad + 1))
    fi
done
echo "  panics: $ok passed, $bad failed"
[ "$bad" -eq 0 ] || fails=$((fails + 1))

if command -v nim > /dev/null 2>&1; then
    echo
    echo "== nim/tests/test_vm.nim =="
    (cd nim && nim c --hints:off -r tests/test_vm.nim 2>&1 | tail -3) || fails=$((fails + 1))

    # The differential run is the one that compares the two engines rather
    # than either engine against a written-down expectation. Cases carry the
    # interpreted answer with them, so they are regenerated first.
    echo
    echo "== differential =="
    if arturo nim/adapter/cases.art nim/adapter/cases.json > /dev/null 2>&1; then
        (cd nim && nim c --hints:off -r tests/differential.nim adapter/cases.json 2>&1 | tail -6) \
            || fails=$((fails + 1))
    else
        echo "  could not generate the case corpus"
        fails=$((fails + 1))
    fi
else
    echo
    echo "== nim: skipped, no nim on PATH =="
fi

echo
if [ "$fails" -eq 0 ]; then
    echo "all suites green"
else
    echo "$fails suite(s) failed"
fi
exit "$fails"
