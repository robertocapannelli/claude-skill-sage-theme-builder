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
# every key bin/deploy reads must exist in assets/env.example with a non-empty value
keys=$( { grep -oE 'envvar "?[A-Z_]+"?' assets/bin/deploy | grep -oE '[A-Z][A-Z_]+$' | sed 's/^/STAGING_/;p;s/^STAGING_/PRODUCTION_/'
          echo PROJECT_SLUG; echo THEME_DIR; echo MU_PLUGINS_DIR; } | sort -u )
bad=""
for k in $keys; do grep -qE "^$k=[^[:space:]#]" assets/env.example || bad="$bad $k"; done
[[ -z "$bad" ]] || { echo "assets/env.example missing or empty:$bad" >&2; exit 1; }
if grep -qE '^[A-Z_]+=([[:space:]]|#|$)' assets/env.example; then echo "assets/env.example has keys without a value" >&2; exit 1; fi

# assets/gitignore must ignore .env and keep .env.example tracked
g=$(mktemp -d); cp assets/gitignore "$g/.gitignore"; touch "$g/.env" "$g/.env.example" "$g/.env.local"
( cd "$g" && git init -q && git check-ignore -q .env && git check-ignore -q .env.local && ! git check-ignore -q .env.example ) \
    || { echo "assets/gitignore: .env must be ignored and .env.example tracked" >&2; exit 1; }
rm -rf "$g"

mkdir -p dist
out="dist/sage-theme-builder-$version.zip"
rm -f "$out"
tmp=$(mktemp -d); mkdir "$tmp/sage-theme-builder"
cp -R SKILL.md references assets "$tmp/sage-theme-builder/"
( cd "$tmp" && zip -rqX "$OLDPWD/$out" sage-theme-builder -x '*.DS_Store' -x '__MACOSX/*' )
rm -rf "$tmp"
echo "packaged $out"
