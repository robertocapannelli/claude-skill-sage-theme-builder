# Remote environments: one audited door

Three environments — **local, staging, production** — and exactly **one** route from the working copy
to the two remote ones: `bin/deploy`. Raw `ssh`, `scp`, `rsync`, `lftp` are blocked, so path
validation, confirmations, backups, the build and logging all live in one place.

**The repository holds no config.** Hosts, users, server paths, URLs of the remote environments, keys,
backups, dumps and logs live in the user profile, `~/.config/<project-slug>/` (700, files 600), set up
at kickoff (`project-kickoff.md` → section 2). The only project fact in the repository is
`PROJECT_SLUG`, at the top of `bin/deploy`.

Ready-made files in this skill — **copy them, don't rewrite them from memory**:

| Skill asset | Goes to (project) |
|---|---|
| `assets/bin/deploy` | `bin/deploy` (`chmod +x`; set `PROJECT_SLUG` on its one line) |
| `assets/deploy.conf.example` | `bin/deploy.conf.example` (tracked) → `bin/deploy init` copies it to `~/.config/<slug>/staging.conf` and `production.conf` |
| `assets/deploy.local.conf.example` | `bin/deploy.local.conf.example` (tracked) → `~/.config/<slug>/local.conf` |
| `assets/deploy-plugins.txt` | `deploy-plugins.txt` (tracked: plugins the site needs, one slug per line) |
| `assets/gitignore` | `.gitignore` |
| `assets/claude/settings.json` | `.claude/settings.json` (merge if one exists; replace `example-project` with the slug) |
| `assets/claude/hooks/deploy-guard.sh` | `.claude/hooks/deploy-guard.sh` (`chmod +x`) |

Then `bin/deploy selftest` must print `0 failed`.

**The environment is always the first argument and has no default** — forgetting it is an error, not
a run against the wrong server.

```
bin/deploy selftest                                   # offline: paths, conf isolation, LOCAL_URL, refusals
bin/deploy init                                       # ~/.config/<slug>/ (700) + conf templates (600)
bin/deploy key-setup <env> [--passphrase]             # dedicated SSH key, prints the PUBLIC key
bin/deploy check-env                                  # keys still missing/placeholder — never values
bin/deploy migrate-env [--delete-env]                 # legacy .env → per-env confs
bin/deploy staging doctor                             # read-only checks: key, wp-config, wp-cli, DB
bin/deploy staging push [--dry-run]                   # back up, BUILD, upload theme + mu-plugins
bin/deploy staging bootstrap --plan                   # FIRST deploy: what would be transferred
bin/deploy staging bootstrap --confirm-bootstrap=<slug> [--with-db]   # after the user confirms
bin/deploy production push --confirm-production=<slug>   # explicit request only — see below
bin/deploy clone-from-prod --confirm-clone=<slug>     # staging := copy of production's DB, one way only
bin/deploy <env> wp <args…>                           # remote wp-cli (ssh only)
bin/deploy <env> eval-file <file.php> [args…]         # run a LOCAL wp-cli script (seed, PHP migration) remotely
bin/deploy <env> backup                               # snapshot now (every deploy does it anyway)
bin/deploy <env> backups                              # list the local backups
bin/deploy <env> restore <id|latest> --confirm-restore=<slug> [--files-only|--db-only] [--dry-run]
```

## Config: outside the repository, one file per environment, parsed, isolated

- **Where.** `~/.config/<slug>/staging.conf`, `production.conf` (`DEPLOY_TRANSPORT`, `DEPLOY_HOST`,
  `DEPLOY_PORT`, `DEPLOY_USER`, `DEPLOY_ROOT`, `DEPLOY_URL`, optional `DEPLOY_KEY`) and `local.conf`
  (`LOCAL_URL`, `LOCAL_WP_CMD`, optional `LOCAL_COMPOSER_CMD`, `BACKUP_KEEP`). The `DEPLOY_` prefix is
  deliberate: a bare `USER` or `HOST` would overwrite the shell's own. A gitignored file inside the
  working tree is not a safe place: `git add -f`, an rsync of the folder, a zip of the repo or a tool
  indexing the workspace carries it away. The profile is.
- **Permissions are enforced.** The folder must be 700 and every conf 600, or `bin/deploy` stops.
- **Parsed, never sourced.** `KEY=value` lines are read by a parser that accepts only the keys that
  file may hold; sourcing would execute whatever the file contains. An unexpected key is ignored with a
  warning that names it (never its value).
- **Isolated.** Every load of an environment conf starts by unsetting every deploy variable. A command
  that loads two confs in one process (`clone-from-prod`) otherwise inherits from the first every key
  the second omits — host, root, URL, port — and the checks that follow see wrong values as valid.
  `selftest` proves it offline (`conf_isolation`).
- **Placeholders.** A value containing `example` or `CHANGE_ME` is not configured: the script stops and
  names the key; `check-env` lists them all, never printing a value.
- **`LOCAL_URL` must be https** (`require_local_url`, with its `selftest` cases), checked before any
  export or search-replace: an http URL rewrites every internal link in the wrong scheme, and a
  search-replace for `http://` in a database that says `https://` leaves the local domain behind on
  the server.
- **Claude never reads them.** `deny` on `Read`/`Edit`/`Write` of `~/.config/<slug>/**` and `Read` of
  `~/.ssh/**`; the hook blocks any shell command that names those paths. When a value is needed, ask
  the user — and tell them which file and key to edit, rather than collecting it in the chat.

## Every deploy builds

Build output (`public/build/`, `public/blocks/`, `vendor/`) is gitignored, so the working copy is
never trusted to contain a current build. `push` always, in this order:

1. `npm run build` in the theme (`npm ci` first if `node_modules/` is missing);
2. copies the theme into `.deploy-build/theme/` without `node_modules`, `vendor`, `tests`, `.env*`;
3. `composer install --no-dev --optimize-autoloader` **inside that copy** — the working copy keeps its
   dev dependencies. It runs through `LOCAL_COMPOSER_CMD` (default `composer`): when PHP/Composer
   live only in a container (Devilbox, Docker), set it to e.g.
   `"docker exec -u devilbox -w /shared/httpd/<site>/htdocs devilbox-php-1 composer"` — `-w` must be
   the **repository root as seen inside the container**, because the working dir is passed relative;
   then asserts `vendor/autoload.php`;
4. asserts `public/build/manifest.json` and, when blocks exist, `public/blocks/index.asset.php`;
5. uploads, then `wp acorn optimize` on the server (ssh).

A dry run builds too: the diff it prints is only honest against a fresh build.

## Every deploy starts from a backup — and one command rolls it back

Before **any** change to a server — `push`, `bootstrap`, `eval-file`, on staging and on production —
`bin/deploy` snapshots everything that deploy can overwrite into
`~/.config/<slug>/backups/<env>-<timestamp>/`:

| In the backup | How |
|---|---|
| remote theme folder | exact copy (rsync/lftp) |
| remote `mu-plugins/` | exact copy (includes the host's own mu-plugins) |
| database (ssh) | `wp db export`, gzipped, checked non-empty |
| `manifest` | environment, time, the commit deployed before, what was saved, what did not exist yet |

- **If the backup fails, the deploy does not start.** A deploy without a restore point never happens.
- Over **sftp** the database cannot be exported (no remote wp-cli): the script says so; a `push` does
  not touch the database, but a release that changes data needs a DB backup from the hosting panel
  first — tell the user before deploying.
- `uploads/` is not in the backup: deploys only add media and never delete them on the server.
- Unchanged files are hard-linked to the previous backup, so keeping several costs little disk.
  `BACKUP_KEEP` (default 10) backups are kept per environment; the oldest are pruned.
- Backups contain the database — personal data and password hashes included. They live only in
  `~/.config/<slug>/backups/` (700), outside the repository, never pasted into the conversation.

After every deploy, **tell the user the backup id and the rollback command** the script prints.

### Rolling back

```
bin/deploy staging backups                                   # what is there
bin/deploy staging restore latest --dry-run                  # what would change
bin/deploy staging restore <id> --confirm-restore=<slug>     # files exact + database, then cache flush
```

`restore` puts the saved folders back **exactly** (files added by the bad deploy are removed), imports
the saved database, then runs `cache flush`, `rewrite flush`, `acorn optimize`. `--files-only` /
`--db-only` narrow it. Folders that did not exist before the deploy are left in place (reported).

A restore overwrites the server, so it follows the same rule as a deploy: show the user what will be
restored (`--dry-run`), get an explicit yes, then pass `--confirm-restore=<slug>` — plus
`--confirm-production=<slug>` on production. In an emergency, ask one short question and act on the
answer; don't improvise another route to the server.

## First deploy: `bootstrap`, always confirmed by the user

The first time a site goes to a server — typically staging — `push` is not enough: the server has
WordPress but none of the site. `bootstrap` transfers, in this order:

1. **backup** of everything below that already exists on the server, database included (as for every deploy);
2. **theme + mu-plugins** — through `push`, so the build runs;
3. **plugins the site needs that are missing on the server** — the folders listed in
   `deploy-plugins.txt`, uploaded from `wp-content/plugins/<slug>/` (premium ones included). **A plugin
   already on the server is never overwritten**: plugins are updated from each environment's admin, so
   the local copy is usually older, and pushing it would silently downgrade the live one;
4. **uploads** — `wp-content/uploads/`, added/updated, never deleted on the server;
5. **database** (`--with-db`, ssh only, **staging only** — refused by the code on production) — local
   export (moved at once into `~/.config/<slug>/dumps/`) → remote import, then `search-replace` of
   `LOCAL_URL` → `DEPLOY_URL` in both plain and JSON-escaped form (`https:\/\/…`, the form block
   attributes use), `--skip-columns=guid`; the table prefix must match on both sides;
6. **activation** (ssh) — the theme, the listed plugins, `rewrite flush`, `acorn optimize`; on staging
   `blog_public = 0` (discourage search engines).

Prerequisite: WordPress core is installed on the server with its own `wp-config.php` (hosting
installer or `wp core download` + `wp config create` by the user) — `bin/deploy <env> doctor` must pass.

**The confirmation is mandatory, every time:**

1. Run `bin/deploy <env> bootstrap --plan` (read-only) — with `--with-db` if the database is being
   considered — and show the output to the user: components, local sizes, plugin list, URL rewrite.
2. Ask explicitly (question tool when available): *which components* — plugins yes/no, uploads
   yes/no, **database yes/no** — and *confirm the deploy*. Spell out what the database option means:
   the remote database is **replaced** (backup taken first) and the server's users become the local
   ones.
3. Only after a "yes" in the current conversation, run it with `--confirm-bootstrap=<PROJECT_SLUG>`
   and the chosen flags (`--no-plugins`, `--no-uploads`, `--with-db`). Without the flag the script
   refuses; the project settings also put `bin/deploy <env> bootstrap` under `ask`.

A confirmation covers that one run. Re-running `bootstrap` later — to resync the database, say — is a
new request and needs a new confirmation. After the first deploy, day-to-day updates use `push`.

On production the same command also needs `--confirm-production=<slug>` and is run only on the user's
explicit request; `--with-db` does not exist there.

Over **sftp** there is no remote wp-cli: `--with-db` is refused (import the dump from the hosting
panel) and activation is left to the user in wp-admin — the script says which theme and plugins.

### Staging as a copy of production: `clone-from-prod`

`bin/deploy clone-from-prod --confirm-clone=<slug>` exports production's database into
`~/.config/<slug>/dumps/`, backs up staging, imports, rewrites the production URL to the staging one
(plain and JSON-escaped), sets `blog_public = 0` and flushes caches. **The direction is fixed by the
name and the code**; there is no reverse. It refuses when the two confs have the same `DEPLOY_URL` or
the same host and root — the symptom of a conf copied and not edited. Same confirmation rule as
`bootstrap`: explain that staging's database is replaced, ask, then pass the flag.

### Adding content instead of replacing the database

When the server already has its own database (its users, the hosting's plugins and their settings)
and the user asks to *add what is missing* rather than overwrite it, prefer the project's idempotent
seed over `--with-db`:

1. `bin/deploy <env> backup`;
2. move WordPress's default content to the **trash**, never delete it (`wp post delete <ids>`, no
   `--force`): trashed posts get a `__trashed` slug, so a slug-based seed no longer finds the stock
   `privacy-policy` draft and creates the real page. Ask the user first — it is their server;
3. `bin/deploy <env> eval-file bin/seed.php` — uploads the script's directory (`.php` only, every
   file must start with `defined('ABSPATH') || exit`) to a throwaway folder under `wp-content/`,
   runs it, removes it even on failure. Never `force` on a server where editors may have worked;
4. align the site options the seed does not own (`blogname`, date/time format, timezone) and check
   the **effective** locale with `get_locale()`, not the `WPLANG` option — they can differ locally;
5. verify by diffing the rendered `<body>` of every URL on both sides, normalising host, IDs, nonces,
   and the CDN's email obfuscation; then `blog_public = 0` on staging.

## Staging vs production

| | staging | production |
|---|---|---|
| Who may start it | the agent, whenever a deploy is useful to verify work | **only on the user's explicit request in the current message** |
| Gate in the script | none | `--confirm-production=<PROJECT_SLUG>`; refuses a dirty git tree unless `--allow-dirty` |
| Gate in Claude Code | none | `ask` rule on `bin/deploy production` → always a human prompt |
| Pre-flight | backup (theme, mu-plugins, DB) | same backup; an empty DB dump is fatal |
| Refused by the code | — | overwriting the database (`bootstrap --with-db`); `restore` without `--confirm-production` |

**Production is never a follow-up step.** "Deploy on staging" does not imply production; "looks good
on staging" does not either; nor does a previous production request in the same session. Finish on
staging, report the staging URL, and *ask* whether to go to production. A `--dry-run` against
production is fine to show what would change.

## Two transports

`DEPLOY_TRANSPORT` in each environment's conf:

- **`ssh`** (preferred) — `rsync` over SSH, remote `wp-cli`, DB backup, `acorn optimize` after upload.
- **`sftp`** — for hosting without a shell: `lftp mirror --reverse` over the same SSH connection. No
  remote `wp-cli`: no DB backup, no `acorn optimize` — the script says so, and the user clears caches
  from the hosting panel. Requires `lftp` locally.

## Authentication: one dedicated SSH key per environment, never a password

Both transports authenticate **only with SSH keys**, and only with the project's own:

- `bin/deploy key-setup <env>` creates `~/.ssh/<slug>_<env>_ed25519` and prints the **public** key for
  the user to add on the server (hosting panel → SSH keys, or `~/.ssh/authorized_keys`). `DEPLOY_KEY`
  in the conf can point elsewhere; `default` is refused.
- Every connection runs with `-i <key> -o IdentitiesOnly=yes`, `BatchMode=yes`,
  `PasswordAuthentication=no`, `KbdInteractiveAuthentication=no`: a missing key **fails in seconds**
  instead of hanging on a prompt the agent cannot answer.
- **Why not the agent's keys.** With them ssh offers every identity it holds; a personal key that
  also opens other clients' servers may be the one that gets in, and neither the log nor the hook can
  say which. A dedicated key is revocable per project and environment and can be restricted on the
  server (`from=`, a forced command). The price is one `key-setup` and one paste per environment.
- The key has no passphrase by default, because nothing can type one mid-deploy. `--passphrase` makes
  one (interactive: the user runs it in their own terminal) and the key then goes into the macOS
  Keychain with `ssh-add --apple-use-keychain`.
- `DEPLOY_HOST` may be a `Host` alias from `~/.ssh/config`; the key is still forced by the wrapper.
- `bin/deploy <env> doctor` tests the key first. If it fails, the fix is on the user's side, and the
  agent says so instead of looking for another way in. A host that accepts only passwords is not
  supported: ask the user to enable key access.

The theme directory is mirrored with `--delete` (a release is complete); `mu-plugins/` is **not** —
hosts often drop their own mu-plugins there. Never core, never `uploads/`, never `wp-config.php`.
Plugins never travel with `push`; `bootstrap` uploads only the listed ones that are missing.

## One pure path validator, self-tested

Every remote path goes through `guard_path <root> <path>`: no network, no filesystem; only
`[A-Za-z0-9._/-]`; no `.` or `..` segment; the result must sit under the root, and the root itself
must be absolute and not `/`. Because it is pure, `selftest` runs offline, including the cases that
matter: `wp-content/../../prod`, a sibling that escapes by prefix (`/home/u/staging2-evil` against
`/home/u/staging`), `a$(x)`, `` a`x` ``, a path with a space.

## Make the wrapper the only route

The `PreToolUse` hook (`deploy-guard.sh`) lets `bin/deploy` through and blocks any command that
mentions `ssh|scp|sftp|rsync|lftp|sshpass|ftp|ssh-keygen|ssh-add`, names the config folder
`~/.config/<slug>`, a dedicated key `~/.ssh/<slug>_*` or a legacy `.env` (whatever the verb — `cat`,
`grep`, `source`, `cp`), or names a deploy host read from the confs (never printed). A chained
`bin/deploy …; cat …` is not let through as a `bin/deploy` call. Over-approximating is correct: blocking an innocent `grep rsync` costs one retry, a side door
costs a production database.

Corollary for migration scripts (`content-migrations.md`): give them a `--staging`-style flag that
re-dispatches **through** `bin/deploy <env> wp …`, never a second route of their own. On production
the same rule applies: explicit request only.

## Logs

Every push and remote `wp` call appends `timestamp, env, git sha, user, action` to
`~/.config/<slug>/deploy.log`. Record in the project's `CLAUDE.md` which migrations have run
on which environment (`project-memory.md`).
