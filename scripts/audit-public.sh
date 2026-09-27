#!/usr/bin/env bash
# scripts/audit-public.sh — fail if the skill contains anything that must not be published:
# personal data, client/project names, credentials, real hosts or paths.
#
# Generic patterns live here. Names that must never appear (clients, projects, people, your own
# domains) go in .audit-denylist — one case-insensitive term per line — which is gitignored, so the
# list itself is never published.
#
#   scripts/audit-public.sh            # exits 1 and prints every hit
set -uo pipefail
cd "$(dirname "$0")/.."

files=$(git ls-files --cached --others --exclude-standard | grep -vE '^(scripts/audit-public\.sh|\.gitignore)$')
hits=0
check() {   # check <label> <extended regex> [<allow regex>]
    local out
    out=$(printf '%s\n' "$files" | xargs grep -nIiE -- "$2" 2>/dev/null | { if [[ -n "${3:-}" ]]; then grep -viE -- "$3"; else cat; fi; })
    if [[ -n "$out" ]]; then printf '\n== %s ==\n%s\n' "$1" "$out"; hits=1; fi
}

check "email address" '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}' '@(example\.(com|org)|users\.noreply\.github\.com)|noreply@anthropic\.com'
check "absolute user path" '(/Users/[A-Za-z]|/home/[A-Za-z]{2,}/|C:\\\\Users)' '/home/u/'
check "IPv4 address" '\b([0-9]{1,3}\.){3}[0-9]{1,3}\b' '\b(127\.0\.0\.1|0\.0\.0\.0)\b'
check "private key / token" '(BEGIN [A-Z ]*PRIVATE KEY|ghp_[A-Za-z0-9]{20,}|sk-[A-Za-z0-9]{20,}|AKIA[0-9A-Z]{16}|xox[baprs]-)'
check "Italian VAT / tax id" '\b(IT)?[0-9]{11}\b|\b[A-Z]{6}[0-9]{2}[A-Z][0-9]{2}[A-Z][0-9]{3}[A-Z]\b'
check "phone number" '(\+39|\+1|\+44)[ 0-9]{8,}'
check "password with a value" '(password|passwd|pwd)[[:space:]]*[:=][[:space:]]*["'\'']?[A-Za-z0-9!@#$%^&*]{6,}' 'CHANGE_ME|_PASSWORD=$|--admin_password'

if [[ -f .audit-denylist ]]; then
    while IFS= read -r term || [[ -n "$term" ]]; do
        [[ -z "$term" || "$term" == \#* ]] && continue
        check "denylisted term (.audit-denylist)" "$(printf '%s' "$term" | sed 's/[][\.*^$+?(){}|/]/\\&/g')"
    done < .audit-denylist
else
    printf 'note: no .audit-denylist — client, project and personal names are not being checked\n' >&2
fi

if [[ $hits -eq 0 ]]; then echo "audit: clean"; else echo; echo "audit: FAILED — remove the hits above before publishing" >&2; exit 1; fi
