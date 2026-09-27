#!/usr/bin/env bash
# .claude/hooks/deploy-guard.sh — PreToolUse hook for Bash.
# Makes bin/deploy the only route to remote servers and keeps .env out of the transcript.
# Exit 2 = block the command and show stderr to the agent. Over-approximation is intended:
# blocking an innocent `grep rsync` costs one retry; a side door can cost a production database.

input="$(cat)"
if command -v jq >/dev/null 2>&1; then
    cmd="$(printf '%s' "$input" | jq -r '.tool_input.command // ""')"
else
    cmd="$(printf '%s' "$input" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("tool_input",{}).get("command",""))')"
fi
[[ -z "$cmd" ]] && exit 0

# 1. The wrapper itself is always allowed through (production is gated by an `ask` rule + a flag).
[[ "$cmd" =~ ^[[:space:]]*(\./)?bin/deploy($|[[:space:]]) ]] && exit 0

# 2. Raw remote tools.
if [[ "$cmd" =~ (^|[^A-Za-z0-9_-])(ssh|scp|sftp|rsync|lftp|sshpass|ftp)($|[^A-Za-z0-9_-]) ]]; then
    echo "Raw remote command blocked: use bin/deploy <env> …" >&2
    exit 2
fi

# 3. Anything that touches .env (the Read tool is covered by a deny rule in settings.json).
#    .env.example is fine — strip it before looking, so "git add .env .env.example" is still caught.
stripped="${cmd//.env.example/}"
# Read-only git checks on .env's status are allowed (they never print its content), if not chained.
if [[ "$cmd" =~ ^[[:space:]]*git[[:space:]]+(check-ignore|ls-files)([[:space:]][^\;\&\|\>\<\`\$]*)?$ ]]; then
    stripped=""
fi
if [[ "$stripped" =~ (^|[^A-Za-z0-9_.-])\.env($|[^A-Za-z0-9_.-]|\.[a-z]+) ]]; then
    echo "Access to .env from the shell is blocked (it is never read, tracked or committed): ask the user for the value you need" >&2
    exit 2
fi

# 4. Any command naming a remote host from .env (read here, never printed).
if [[ -f .env ]]; then
    while IFS= read -r host; do
        [[ -n "$host" && "$cmd" == *"$host"* ]] && { echo "Command mentions a deploy host: use bin/deploy" >&2; exit 2; }
    done < <(sed -nE 's/^(STAGING|PRODUCTION)_HOST=["'\'']?([^"'\'' #]+).*/\2/p' .env)
fi
exit 0
