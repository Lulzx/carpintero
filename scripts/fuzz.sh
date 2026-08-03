#!/usr/bin/env bash
# Run random grammars through both engines and report where they disagree.
#
#     scripts/fuzz.sh [batches] [cases-per-batch]
#
# cases.art asks the questions someone thought to ask. This asks the ones
# nobody did: nim/adapter/fuzz.art writes a batch of random grammars with
# the interpreted answer attached, and tests/differential.nim reruns each in
# the compiled core and compares. A disagreement is a real disagreement
# about the language, and the listing beside each batch says which grammar
# caused it.
#
# Batches are separate processes on purpose. A generated grammar that panics
# the interpreted matcher takes its batch down, and nothing catches it: a
# panic unwound through try leaves the values of abandoned frames behind for
# the next statement to misread, so catching would corrupt the batch rather
# than save it. A dead batch is reported and the campaign continues.
set -u

cd "$(dirname "$0")/.."

BATCHES=${1:-10}
PER=${2:-100}
WORK=${TMPDIR:-/tmp}/carpintero-fuzz.$$
mkdir -p "$WORK"

echo "building the differential runner"
nim c -d:release --hints:off -o:"$WORK/diffbin" nim/tests/differential.nim 2>&1 | grep -i 'error' && exit 1

total=0; disagreed=0; died=0; matched=0
for i in $(seq 1 "$BATCHES"); do
    for mode in text block; do
        f="$WORK/$mode-$i.json"
        out=$(arturo nim/adapter/fuzz.art "$f" "$PER" "$mode" 2>&1)
        if ! echo "$out" | grep -q '^wrote'; then
            died=$((died + 1))
            echo "batch $mode-$i died before writing:"
            echo "$out" | tail -5
            continue
        fi
        matched=$((matched + $(echo "$out" | sed 's/.*— \([0-9]*\) matched.*/\1/')))

        d=$("$WORK/diffbin" "$f" 2>&1)
        n=$(echo "$d" | sed -n 's/^differential: \([0-9]*\) cases compared, \([0-9]*\) disagreements/\2/p')
        c=$(echo "$d" | sed -n 's/^differential: \([0-9]*\) cases compared.*/\1/p')
        total=$((total + c))
        disagreed=$((disagreed + n))
        if [ "$n" != "0" ]; then
            echo "== $mode-$i: $n disagreements"
            echo "$d" | grep -A2 DIFFER | sed 's/^/   /'
            echo "$d" | grep '  DIFFER' | awk '{print $2}' | sort -u | while read -r nm; do
                grep "^$nm " "$f.txt" | sed 's/^/   grammar: /' | cut -c1-240
            done
        fi
    done
done

echo
echo "compared $total cases, $matched matched, $disagreed disagreements, $died batches died"
echo "cases and listings are in $WORK"
[ "$disagreed" = "0" ] && [ "$died" = "0" ]
