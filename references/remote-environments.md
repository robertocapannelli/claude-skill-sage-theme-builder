# Remote environments: one audited door

Three environments — **local, staging, production** — configured in one `.env` at kickoff
(`project-kickoff.md`), and exactly **one** route from the working copy to the two remote ones:
`bin/deploy`. Raw `ssh`, `scp`, `rsync`, `lftp` are blocked, so path validation, confirmations,
backups, the build and logging all live in one place.

Ready-made files in this skill — **copy them, don't rewrite them from memory**:

| Skill asset | Goes to (project) |
|---|---|
| `assets/bin/deploy` | `bin/deploy` (`chmod +x`) |
| `assets/gitignore` | `.gitignore` (`.env` always ignored, `.env.example` always tracked) |
| `assets/env.example` | `.env.example` (committed, verbatim copy: every key with a fictitious value) → `.env` (gitignored, `chmod 600`, same keys) |
| `assets/claude/settings.json` | `.claude/settings.json` (merge if one exists) |
| `assets/claude/hooks/deploy-guard.sh` | `.claude/hooks/deploy-guard.sh` (`chmod +x`) |

Then `bin/deploy selftest` must print *all cases pass*.

```
bin/deploy selftest                                   # offline test of the path validator
bin/deploy check-env                                  # which .env keys still hold placeholder values
bin/deploy staging doctor                             # read-only checks: wp-config, wp-cli, DB
bin/deploy staging push [--dry-run]                   # BUILD, then upload theme + mu-plugins
bin/deploy production push --confirm-production=<slug>   # explicit request only — see below
bin/deploy <env> wp <args…>                           # remote wp-cli (ssh only)
bin/deploy <env> db-backup                            # remote DB dump → .deploy-backups/ (ssh only)
```

## Every deploy builds

Build output (`public/build/`, `public/blocks/`, `vendor/`) is gitignored, so the working copy is
never trusted to contain a current build. `push` always, in this order:

1. `npm run build` in the theme (`npm ci` first if `node_modules/` is missing);
2. copies the theme into `.deploy-build/theme/` without `node_modules`, `vendor`, `tests`, `.env*`;
3. `composer install --no-dev --optimize-autoloader` **inside that copy** — the working copy keeps its
   dev dependencies;
4. asserts `public/build/manifest.json` and, when blocks exist, `public/blocks/index.asset.php`;
5. uploads, then `wp acorn optimize` on the server (ssh).

A dry run builds too: the diff it prints is only honest against a fresh build.

## Staging vs production

| | staging | production |
|---|---|---|
| Who may start it | the agent, whenever a deploy is useful to verify work | **only on the user's explicit request in the current message** |
| Gate in the script | none | `--confirm-production=<PROJECT_SLUG>`; refuses a dirty git tree unless `--allow-dirty` |
| Gate in Claude Code | none | `ask` rule on `bin/deploy production` → always a human prompt |
| Pre-flight | — | backup of the remote theme + (ssh) the remote DB into `.deploy-backups/`; an empty DB dump is fatal |

**Production is never a follow-up step.** "Deploy on staging" does not imply production; "looks good
on staging" does not either; nor does a previous production request in the same session. Finish on
staging, report the staging URL, and *ask* whether to go to production. A `--dry-run` against
production is fine to show what would change.

## Two transports

`<ENV>_TRANSPORT` in `.env`:

- **`ssh`** (preferred) — `rsync` over SSH, remote `wp-cli`, DB backup, `acorn optimize` after upload.
- **`sftp`** — for hosting without a shell: `lftp mirror --reverse` over the same SSH connection. No
  remote `wp-cli`: no DB backup, no `acorn optimize` — the script says so, and the user clears caches
  from the hosting panel. Requires `lftp` locally.

## Authentication: SSH keys on this computer, never a password

Both transports authenticate **only with SSH keys**. There is no remote password anywhere — not in
`.env`, not in a prompt, not in the conversation.

- `<ENV>_SSH_KEY=default` (the default) uses what the computer already has: the keys loaded in
  `ssh-agent` (on macOS, the Keychain via `ssh-add --apple-use-keychain`), `~/.ssh/config`, and the
  standard `~/.ssh/id_*`. `<ENV>_HOST` may be a `Host` alias from `~/.ssh/config`, so port, user and
  key can live there.
- A path in `<ENV>_SSH_KEY` pins one specific key (`-i … -o IdentitiesOnly=yes`), useful when the agent
  holds many keys and the server drops the connection after too many attempts.
- Every connection runs with `BatchMode=yes`, `PasswordAuthentication=no`,
  `KbdInteractiveAuthentication=no`, `PreferredAuthentications=publickey`: a missing key **fails in
  seconds** instead of hanging on a prompt the agent cannot answer.
- `bin/deploy <env> doctor` tests the key first. If it fails, the fix is on the user's side, and the
  agent says so instead of looking for another way in: load the key (`ssh-add`), or install the public
  key on the server (`ssh-copy-id -i ~/.ssh/<key>.pub user@host`, or the hosting panel's SSH-keys
  page). A host that accepts only passwords is not supported: ask the user to enable key access.

The theme directory is mirrored with `--delete` (a release is complete); `mu-plugins/` is **not** —
hosts often drop their own mu-plugins there. Never core, never `uploads/`, never `wp-config.php`.
Plugins are not deployed by default; add them to the script only if the project manages them in git.

## Config: `.env`, parsed, never sourced

Values containing `example` or `CHANGE_ME` are placeholders from `.env.example`: the script treats
them as unset and stops with the key's name. The script parses `KEY=value` lines instead of
`source`-ing the file (which would execute it), refuses
to run unless `.env` is `chmod 600`, gitignored **and not tracked**, and needs no remote DB credentials — remote
`wp-cli` reads them from the remote `wp-config.php`. The `deny` rules and the guard hook keep `.env`
out of every transcript; when an agent needs a value, it asks the user.

## One pure path validator, self-tested

Every remote path goes through `guard_path <root> <path>`: no network, no filesystem; only
`[A-Za-z0-9._/-]`; no `.` or `..` segment; the result must sit under the root, and the root itself
must be absolute and not `/`. Because it is pure, `selftest` runs offline, including the cases that
matter: `wp-content/../../prod`, a sibling that escapes by prefix (`/home/u/staging2-evil` against
`/home/u/staging`), `a$(x)`, `` a`x` ``, a path with a space.

## Make the wrapper the only route

The `PreToolUse` hook (`deploy-guard.sh`) lets `bin/deploy` through and blocks any command that
mentions `ssh|scp|sftp|rsync|lftp|sshpass|ftp`, prints `.env`, or names a deploy host read from
`.env`. Over-approximating is correct: blocking an innocent `grep rsync` costs one retry, a side door
costs a production database.

Corollary for migration scripts (`content-migrations.md`): give them a `--staging`-style flag that
re-dispatches **through** `bin/deploy <env> wp …`, never a second route of their own. On production
the same rule applies: explicit request only.

## Logs

Every push and remote `wp` call appends `timestamp, env, git sha, user, action` to
`.deploy-logs/deploy.log` (gitignored). Record in the project's `CLAUDE.md` which migrations have run
on which environment (`project-memory.md`).
