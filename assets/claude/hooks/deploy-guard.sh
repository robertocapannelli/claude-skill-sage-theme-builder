#!/usr/bin/env bash
# .claude/hooks/deploy-guard.sh — PreToolUse hook for Bash.
#
# 1. bin/deploy is the only route to a server: raw ssh/scp/sftp/rsync/lftp are blocked.
# 2. The deploy config never enters the transcript: any command that names the config folder
#    (~/.config/<project-slug>/), the dedicated SSH keys (~/.ssh/<project-slug>_*) or a legacy .env
#    is blocked — cat, grep, source, less, cp, anything.
# 3. A command that names a deploy host (read here from the confs, never printed) is blocked.
#
# Exit 2 = block the command and show stderr to the agent. Over-approximation is intended:
# blocking an innocent command costs one retry; a side door can cost a production database.

input="$(cat)"
if command -v jq >/dev/null 2>&1; then
    cmd="$(printf '%s' "$input" | jq -r '.tool_input.command // ""')"
else
    cmd="$(printf '%s' "$input" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("tool_input",{}).get("command",""))')"
fi
[[ -z "$cmd" ]] && exit 0

project="${CLAUDE_PROJECT_DIR:-$PWD}"
slug="$(sed -n 's/^PROJECT_SLUG="\{0,1\}\([a-z0-9-]*\)"\{0,1\}.*/\1/p' "$project/bin/deploy" 2>/dev/null | head -n1)"
conf_dir="$HOME/.config/${slug:-__none__}"

# 1. The wrapper itself is allowed through (its dangerous commands are gated by `ask` rules and
#    by confirmation flags in the code). Only a bare invocation: no chaining, no redirection.
if [[ "$cmd" =~ ^[[:space:]]*(\./)?bin/deploy([[:space:]][^\;\&\|\<\>\`\$]*)?$ ]]; then
    exit 0
fi

# 2. Raw remote tools.
if [[ "$cmd" =~ (^|[^A-Za-z0-9_-])(ssh|scp|sftp|rsync|lftp|sshpass|ftp|ssh-add|ssh-keygen)($|[^A-Za-z0-9_-]) ]]; then
    echo "Raw remote/key command blocked: use bin/deploy <staging|production> …" >&2
    exit 2
fi

# 3. The config folder and the dedicated keys, in any spelling.
if [[ -n "$slug" ]]; then
    for needle in ".config/$slug" "$conf_dir" ".ssh/${slug}_" "DEPLOY_CONF_DIR"; do
        if [[ "$cmd" == *"$needle"* ]]; then
            echo "The deploy config and keys are never read from the shell: ask the user for what you need (bin/deploy check-env lists missing keys without values)" >&2
            exit 2
        fi
    done
fi

# 4. A legacy .env (bin/deploy migrate-env moves it out of the repository).
stripped="${cmd//.env.example/}"
if [[ "$stripped" =~ (^|[^A-Za-z0-9_.-])\.env($|[^A-Za-z0-9_.-]|\.[a-z]+) ]]; then
    echo "Access to .env is blocked: run bin/deploy migrate-env (it never prints values)" >&2
    exit 2
fi

# 5. Any command naming a deploy host.
if [[ -n "$slug" ]]; then
    for conf in "$conf_dir/staging.conf" "$conf_dir/production.conf"; do
        [[ -f "$conf" ]] || continue
        host="$(sed -n 's/^DEPLOY_HOST=["'\'']\{0,1\}\([^"'\'' #]*\).*/\1/p' "$conf" | head -n1)"
        if [[ -n "$host" && "$cmd" == *"$host"* ]]; then
            echo "Command mentions a deploy host: use bin/deploy" >&2
            exit 2
        fi
    done
fi
exit 0
