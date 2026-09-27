#!/usr/bin/env bash
# scripts/package.sh — build dist/sage-theme-builder-<version>.zip for upload to claude.ai.
# Contains only what the skill needs at runtime: SKILL.md, references/, assets/.
set -euo pipefail
cd "$(dirname "$0")/.."
scripts/audit-public.sh
version=$(sed -nE 's/^[[:space:]]+version:[[:space:]]*"?([0-9]+\.[0-9]+\.[0-9]+)"?.*/\1/p' SKILL.md | head -1)
[[ -n "$version" ]] || { echo "no metadata.version in SKILL.md" >&2; exit 1; }
missing=$(grep -oE '`(references|assets)/[A-Za-z0-9._/-]+`' SKILL.md references/*.md | cut -d'`' -f2 | sort -u | while read -r f; do [[ -e "$f" ]] || echo "$f"; done)
[[ -z "$missing" ]] || { echo "referenced but missing:"; echo "$missing"; exit 1; } >&2
mkdir -p dist
out="dist/sage-theme-builder-$version.zip"
rm -f "$out"
tmp=$(mktemp -d); mkdir "$tmp/sage-theme-builder"
cp -R SKILL.md references assets "$tmp/sage-theme-builder/"
( cd "$tmp" && zip -rqX "$OLDPWD/$out" sage-theme-builder -x '*.DS_Store' -x '__MACOSX/*' )
rm -rf "$tmp"
echo "packaged $out"
