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
mkdir -p docs/bugs

cp README.md   docs/index.md
cp MANUAL.md   docs/MANUAL.md
cp proposal.md docs/proposal.md
cp bugs/README.md docs/bugs/README.md

echo "staged docs/ from README.md, MANUAL.md, proposal.md, bugs/README.md"
