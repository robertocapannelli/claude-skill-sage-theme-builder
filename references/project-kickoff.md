# Project kickoff: git, environments, deploy, first admin

Run this **before the first line of theme code** on a new project, and as a gap check on an existing
one (skip what already exists, never overwrite it). The order matters: git first, so every later file
lands in a tracked tree; `.env` second, because the deploy scripts read it; the admin user last,
because it needs a working database.

Everything here is gathered by **asking the user** — use the question tool when available, plain
questions otherwise. Never invent a remote URL, a host, a username or an email.

## 1. Git — configured at once, committed only on request

Ask, in one round:

| Question | Why |
|---|---|
| Remote repository URL (GitHub/GitLab/Bitbucket, SSH or HTTPS)? Does it already exist? | `git remote add origin` — never guess the owner or name |
| Default branch name? (default `main`) | `git init -b <branch>` |
| Is the repository the whole site root or the theme only? | Decides where `.gitignore`, `.env`, `bin/` live (default: site root, see `architecture.md`) |

Then check `git config user.name` / `user.email`; ask only if they are empty for this repository.

```bash
git init -b main
git remote add origin <url>        # or: git remote set-url origin <url> if one exists
git remote -v                      # show it back to the user
```

`.gitignore` at the repository root — at minimum:

```gitignore
.env
.env.*
!.env.example
node_modules/
vendor/
wp-content/themes/*/public/build/
wp-content/themes/*/public/blocks/
wp-content/uploads/
.deploy-build/
.deploy-logs/
.deploy-backups/
.DS_Store
# WordPress core, if the repo is the site root
/wp-admin/
/wp-includes/
/wp-*.php
/index.php
/license.txt
/readme.html
/xmlrpc.php
wp-config.php
```

Build output is ignored **on purpose**: it never drifts from the source, and it is why every deploy
builds (`remote-environments.md`).

### The commit rule

**Never `git commit`, `git push`, `git tag` or amend unless the user explicitly asks in the current
request.** Staging, diffing and `git status` are fine. When a unit of work is finished, *propose* a
commit message and stop. "Go ahead" on a previous task is not a standing permission for the next.

The project's `.claude/settings.json` backs this with an `ask` rule (below), so a slip produces a
prompt instead of a commit.

## 2. `.env` — one file, three environments

One `.env` at the repository root, **gitignored**, plus a committed `.env.example` with the same keys
and no values. Ask the user for the non-secret values and write them; write every secret as
`CHANGE_ME` and tell the user which lines to fill in by hand. Secrets must never pass through the
conversation.

Start from `assets/env.example` (copy it to `.env.example`, then to `.env`). Ask, in one round:

| Key group | Ask |
|---|---|
| `PROJECT_SLUG`, `THEME_DIR` | short project slug; theme folder name |
| `LOCAL_*` | local URL, how `wp` is invoked locally (`wp`, `ddev wp`, `docker exec …`), DB name/user/host |
| `STAGING_*`, `PRODUCTION_*` | URL; transport (`ssh` preferred, `sftp` if the host has no shell); host, port, user; path to the dedicated SSH key; absolute WordPress root on the server |

Unknown values stay empty; the script refuses to run against an environment until they are filled.

Write `.env` **once**, as a new file, with the answers. From then on it belongs to the user: the
project settings deny reading and editing it and the guard hook blocks it in the shell, so later
changes are made by hand — tell the user which key to change rather than asking them to paste it.

Deliberately **absent**: remote database credentials. With SSH, remote `wp-cli` reads them from the
remote `wp-config.php`; with SFTP there is no remote `wp-cli` to use them. A secret with no consumer is
pure risk.

After writing: `chmod 600 .env`, and verify `git check-ignore .env` prints `.env` — if it prints
nothing, stop and fix `.gitignore` before anything else.

## 3. Deploy scripts and guard rails — at once, not at the end

Copy `assets/bin/deploy` to `bin/deploy` (see `remote-environments.md`) in the kickoff, not when the site is "ready": the
first staging push should be a non-event. Then run `bin/deploy selftest` and `bin/deploy staging
doctor` (the latter only once the user confirms the server exists).

Copy `assets/claude/settings.json` to `.claude/settings.json` (merge if one exists) and
`assets/claude/hooks/deploy-guard.sh` to `.claude/hooks/`. The settings put `git commit/push/tag`
and `bin/deploy production` under `ask`, and deny reading `.env`.

`ask` beats any `allow`, so these always produce a human prompt. The `deny` on `.env` keeps secrets
out of transcripts; the guard hook (`remote-environments.md`) also blocks `cat .env` and friends,
which the `Read` rule does not cover. Note the rule in the project's `CLAUDE.md`.

## 4. First WordPress admin — only for sites built from scratch

Applies **only** when WordPress is not installed yet (`wp core is-installed` exits non-zero). On an
existing site — a redesign, a takeover, an imported database — **never create, rename or modify
users** unless the user explicitly asks.

Ask:

1. Which **username** for the administrator? Refuse `admin`, `administrator`, the site name, the
   domain, and the email's local part — all are the first guesses of a brute-force script.
2. Which **email** for that account?

```bash
$LOCAL_WP_CMD core install \
  --url="$LOCAL_URL" --title="<site title>" \
  --admin_user="<asked>" --admin_email="<asked>" \
  --skip-email
```

Without `--admin_password`, WP-CLI generates a strong one and prints it once. Then **always** tell the
user, in so many words: *"Change this password now: log in and set a new one from Users → Profile, or
run `wp user reset-password <user>`. The generated one has been printed in this session's log."*
Repeat the reminder in the hand-off summary.

Staging and production get their own admin accounts created by the user on the server — the local
password is never reused there.

## 5. Languages

The codebase is English; the site speaks through translation files (`i18n.md`). Ask:

- Site language(s)? **Italian is the default and always gets a catalog.** Any other language adds its
  own catalog from the same POT.

Then: `resources/lang/sage.pot` + `it_IT.po`, the mu-plugin's `<domain>-it_IT.po`, the `translate*`
npm scripts, the `load_textdomain()` hook. On a site built from scratch also set the site language:
`wp language core install it_IT --activate`.

## 6. Company logo

Ask for the company logo (SVG preferred, otherwise a PNG at least 640 px wide) if the design does not
already contain it, save it as `resources/images/logo.svg`, and wire the login screen at once
(`login-branding.md`).

## Checklist

- [ ] `origin` set and shown back to the user; default branch named; no commit made without a request.
- [ ] `.gitignore` covers `.env`, build output, `vendor/`, `node_modules/`, uploads, core.
- [ ] `.env` written (secrets as `CHANGE_ME`), `chmod 600`, `git check-ignore .env` passes;
      `.env.example` committed-ready.
- [ ] `bin/deploy` in place; `selftest` passes; `.claude/settings.json` + guard hook installed.
- [ ] New site only: admin user and email asked, never `admin`; password-change reminder given.
- [ ] `it_IT.po` for theme and mu-plugin exist; any extra language asked; `translate:check` wired.
- [ ] Logo in `resources/images/`, login screen branded.
