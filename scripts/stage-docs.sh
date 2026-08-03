#!/bin/sh
# Stage the site sources into docs/, so the markdown at the repository root
# stays the single copy — GitHub renders those files directly, and mkdocs
# builds from a tree that mirrors their paths, which keeps every relative
# link between them working in both places.
#
#   ./scripts/stage-docs.sh && mkdocs serve
#
# docs/ is generated and ignored by git.
set -eu

cd "$(dirname "$0")/.."

rm -rf docs
mkdir -p docs/bugs docs/examples docs/nim

cp README.md   docs/index.md
cp TUTORIAL.md docs/TUTORIAL.md
cp MANUAL.md   docs/MANUAL.md
cp proposal.md docs/proposal.md
cp bugs/README.md     docs/bugs/README.md
cp examples/README.md docs/examples/README.md
cp nim/README.md      docs/nim/README.md

echo "staged docs/ from README.md, TUTORIAL.md, MANUAL.md, proposal.md,"
echo "               bugs/README.md, examples/README.md, nim/README.md"
