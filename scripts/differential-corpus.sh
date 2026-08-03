#!/usr/bin/env bash
# Run both engines over Arturo's own source and require them to agree.
#
#     scripts/differential-corpus.sh ../arturo
#
# The interpreted matcher scans every .art file in the tree and its answers
# are exported with the input. The compiled core reruns each one and checks
# it agrees. Both timings are scan-only: the exporter loads and lexes the
# corpus before the interpreted clock starts, and the compiled clock covers
# compiling the grammar and matching, not reading the case file.
set -u
cd "$(dirname "$0")/.."

root="${1:-../arturo}"
out="${2:-/tmp/carpintero-corpus.json}"

if [ ! -d "$root" ]; then
    echo "no Arturo checkout at $root"
    echo "  git clone --depth 1 https://github.com/arturo-lang/arturo"
    exit 1
fi
if ! command -v nim > /dev/null 2>&1; then
    echo "nim is not on PATH"
    exit 1
fi

echo "== exporting, with the interpreted matcher's answers =="
arturo nim/adapter/corpus.art "$root" "$out" || exit 1

echo
echo "== timing the interpreted matcher =="
arturo nim/adapter/time-corpus.art "$root" | tail -1

echo
echo "== rerunning in the compiled core =="
cd nim || exit 1
nim c -d:release --hints:off -o:/tmp/carpintero-diff tests/differential.nim 2>&1 \
    | grep -vi unusedimport
/tmp/carpintero-diff "$out"
