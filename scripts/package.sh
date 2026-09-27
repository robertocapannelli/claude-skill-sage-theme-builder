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
# every key bin/deploy accepts must be documented in its template with a fictitious value
# (DEPLOY_KEY and LOCAL_COMPOSER_CMD are optional and may appear commented out)
check_template() {   # check_template <template> <space-separated keys>
    local t="$1" k bad=""
    for k in $2; do
        grep -qE "^#? ?$k=[^[:space:]#]" "$t" || bad="$bad $k"
    done
    [[ -z "$bad" ]] || { echo "$t missing or empty:$bad" >&2; exit 1; }
    if grep -qE '^[A-Z_]+=([[:space:]]|#|$)' "$t"; then echo "$t has keys without a value" >&2; exit 1; fi
    if grep -qiE '^[A-Z_]*(PASSWORD|PASS|SECRET|TOKEN)[A-Z_]*=' "$t"; then echo "$t must not contain password/secret keys" >&2; exit 1; fi
}
env_keys=$(sed -n 's/^ENV_KEYS="\(.*\)"/\1/p' assets/bin/deploy)
local_keys=$(sed -n 's/^LOCAL_KEYS="\(.*\)"/\1/p' assets/bin/deploy)
[[ -n "$env_keys" && -n "$local_keys" ]] || { echo "ENV_KEYS/LOCAL_KEYS not found in assets/bin/deploy" >&2; exit 1; }
check_template assets/deploy.conf.example "$env_keys"
check_template assets/deploy.local.conf.example "$local_keys"
grep -q '^PROJECT_SLUG="example-project"' assets/bin/deploy || { echo "assets/bin/deploy must ship with PROJECT_SLUG=\"example-project\"" >&2; exit 1; }
[[ ! -e assets/env.example ]] || { echo "assets/env.example is obsolete: config lives in ~/.config/<slug>/" >&2; exit 1; }
( cd assets && bash bin/deploy selftest >/dev/null ) || { echo "assets/bin/deploy selftest failed" >&2; exit 1; }

# assets/gitignore must ignore a legacy .env and keep the conf templates tracked
g=$(mktemp -d); cp assets/gitignore "$g/.gitignore"; mkdir -p "$g/bin"
touch "$g/.env" "$g/.env.local" "$g/bin/deploy.conf.example" "$g/bin/deploy.local.conf.example"
( cd "$g" && git init -q && git check-ignore -q .env && git check-ignore -q .env.local \
    && ! git check-ignore -q bin/deploy.conf.example && ! git check-ignore -q bin/deploy.local.conf.example ) \
    || { echo "assets/gitignore: .env must be ignored and the conf templates tracked" >&2; exit 1; }
rm -rf "$g"

mkdir -p dist
out="dist/sage-theme-builder-$version.zip"
rm -f "$out"
tmp=$(mktemp -d); mkdir "$tmp/sage-theme-builder"
cp -R SKILL.md references assets "$tmp/sage-theme-builder/"
( cd "$tmp" && zip -rqX "$OLDPWD/$out" sage-theme-builder -x '*.DS_Store' -x '__MACOSX/*' )
rm -rf "$tmp"
echo "packaged $out"
