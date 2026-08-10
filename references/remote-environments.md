# Remote environments: one audited door

Local environment setup stays out of scope (see `architecture.md`). What belongs here is the shape of
the **only** route between the working copy and a staging or production server, because that route is
also the one an agent will use.

The goal: a single verb. Everything else — raw `ssh`, `scp`, `rsync` — is blocked, so there is exactly
one place where path validation, allowlists, confirmations, backups and logging live.

```
bin/deploy doctor              # read-only checks: ssh reachable, root exists, wp-cli, DB
bin/deploy selftest            # offline test of the path validator
bin/deploy push [-n] [path]    # rsync an allowlisted subset (-n = dry run)
bin/deploy pull <rel> <dest>
bin/deploy wp <args…>          # remote wp-cli, --path forced
bin/deploy db pull|push|query
```

## Config lives outside the repository

Host, user, key and remote root go in `~/.config/<project>/deploy.conf`, `chmod 600`, with a committed
`.conf.example`. The wrapper refuses to run if the permissions are wrong or a required variable is
missing. Remote database credentials never exist locally — remote `wp-cli` reads them from the remote
`wp-config.php`.

Use a **dedicated SSH key** with `-o IdentitiesOnly=yes -o BatchMode=yes`, not the agent, and append
every invocation to a log file.

## One pure path validator, self-tested

Every remote path passes through a single function with no network or filesystem access:

```bash
# guard_path <root> <path> — pure. Only [A-Za-z0-9._/-]; no "." or ".." segment;
# the result must sit under <root>.
guard_path() {
    case "$path" in *[!A-Za-z0-9._/-]*) return 1 ;; esac
    …
    case "/${abs#/}/" in */../*|*/./*) return 1 ;; esac
    [[ "$abs" == "$root" || "$abs" == "$root/"* ]] || return 1
    printf '%s\n' "$abs"
}
```

The root itself goes through it too (rejecting `/` and relative roots). Because the function is pure,
`selftest` can exercise it **offline** — twenty-odd cases, and the ones that matter are the
non-obvious ones: `wp-content/../../prod`, a sibling directory that escapes by prefix match
(`/home/u/staging2-evil` against root `/home/u/staging`), `a$(x)`, `` a`x` ``, a path with a space.

## Allowlists, not exclusions alone

Push a curated set of destinations rather than the tree:

```bash
dests=(wp-content/themes/<theme> wp-content/mu-plugins wp-content/plugins)
rsync_opts=(-az --itemize-changes $dry
            --exclude wp-config.php --exclude .git --exclude node_modules
            --exclude .env --exclude .DS_Store)
```

Never core, never `uploads/`, never the remote `wp-config.php`.

## Destructive operations: two gates and a backup

A global `--yes` parsed before dispatch, **plus** a per-operation confirmation, **plus** a mandatory
pre-flight backup of the remote database whose emptiness is fatal:

```bash
remote_wp db export - > "$file"
[[ -s "$file" ]] || die "remote backup is empty ($file): stopping"
```

Quote arguments with `printf '%q'` before they cross the SSH boundary, and keep the local and remote
executors symmetric (`remote_wp` vs `local_wp`) so every call site reads the same.

## Make the wrapper the only route

A `PreToolUse` hook in `.claude/settings.json` turns the convention into a constraint:

```bash
# .claude/hooks/deploy-guard.sh
[[ "$cmd" =~ ^(\./)?bin/deploy($|[[:space:]]) ]] && exit 0
if [[ "$cmd" =~ (^|[^A-Za-z0-9_-])(ssh|scp|sftp|rsync|sshpass)($|[^A-Za-z0-9_-]) ]]; then
    echo "Raw remote command blocked: use bin/deploy" >&2
    exit 2
fi
# also block any command mentioning the host, read from the conf and never printed
```

Over-approximating is correct here: blocking an innocent `grep rsync` costs one retry, leaving a side
door costs a production database. Pair it with a `deny` rule on reading the config file so credentials
never enter a transcript.

Corollary for migration scripts (`content-migrations.md`): give them a `--staging`-style flag that
re-dispatches **through** the wrapper, rather than opening a second route of their own.
