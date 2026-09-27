# Project kickoff: git, environments, deploy, first admin

Run this **before the first line of theme code** on a new project, and as a gap check on an existing
one (skip what already exists, never overwrite it). The order matters: the theme name first, because
the folder, the block namespace and every prefix derive from it; git next, so every later file lands
in a tracked tree; the deploy config third — outside the repository — because the deploy scripts
read it; the admin user last, because it needs a working database.

Everything here is gathered by **asking the user** — use the question tool when available, plain
questions otherwise. Never invent a remote URL, a host, a username or an email.

## 0. Theme name — the first question on a new theme

On a project that develops a **new theme**, the first thing to ask — before git, before any file — is
the **WordPress theme name**. Never invent it, never keep Sage's default `sage` / "Sage Starter Theme",
never derive it silently from the folder or the domain. (On an existing theme, read it from
`style.css` instead and don't rename anything unless asked — a rename is a migration.)

Ask for the display name, then propose the slug derived from it and have the user confirm it:

| Input | Example | Rule |
|---|---|---|
| Theme name (display) | `Acme Studio` | free text, shown in *Appearance → Themes* |
| Theme slug | `acme-studio` | lowercase `a-z0-9-`, starts with a letter, no `wp`/`wordpress`/`theme` noise; **check it does not exist on wordpress.org** |

The slug is the theme's identity everywhere, so it is fixed now:

- theme folder `wp-content/themes/<slug>/` and `PROJECT_SLUG` at the top of `bin/deploy` (the only
  project fact the deploy script holds; it names `~/.config/<slug>/` and the SSH keys);
- `style.css` header;
- the block namespace and inserter category — `mytheme/…` in every example of these references stands
  for `<slug>/…`;
- the prefix of PHP functions, handles, option and meta keys (`<slug_with_underscores>_…`);
- the mu-plugin's name and text domain.

The **theme's text domain stays `sage`** unless the user asks otherwise: it is Sage's convention, the
translation pipeline and the examples here assume it, and a custom theme is never loaded from
wordpress.org's translation service anyway.

`style.css` — replace Sage's header entirely:

```css
/*
Theme Name:   Acme Studio
Theme URI:    https://www.example.com
Description:  Custom theme for Acme Studio, built on Sage.
Version:      1.0.0
Author:       <ask, or leave the agency name the user gives>
Text Domain:  sage
Requires PHP: 8.2
Update URI:   false
*/
```

`Update URI: false` is not optional: without it, WordPress offers "updates" for any custom theme whose
slug happens to match a theme on wordpress.org — one click and the site is overwritten by a stranger's
theme. Also set `composer.json` `"name"` and `package.json` `"name"` to the slug.

## 1. Git — configured at once, committed only on request

Ask, in one round:

| Question | Why |
|---|---|
| Remote repository URL (GitHub/GitLab/Bitbucket, SSH or HTTPS)? Does it already exist? | `git remote add origin` — never guess the owner or name |
| Default branch name? (default `main`) | `git init -b <branch>` |
| Is the repository the whole site root or the theme only? | Decides where `.gitignore` and `bin/` live (default: site root, see `architecture.md`) |

Then check `git config user.name` / `user.email`; ask only if they are empty for this repository.

```bash
git init -b main
git remote add origin <url>        # or: git remote set-url origin <url> if one exists
git remote -v                      # show it back to the user
```

`.gitignore` at the repository root: **copy `assets/gitignore` verbatim** (merge its lines into an
existing one). It ignores dependencies, build output, uploads, core — and a legacy `.env` as a safety
net. It ignores **no deploy config**, because there is none in the repository to ignore: the config
lives in the user profile (section 2). The templates `bin/deploy.conf.example` and
`bin/deploy.local.conf.example` hold fictitious values and are **always tracked**.

Build output is ignored **on purpose**: it never drifts from the source, and it is why every deploy
builds (`remote-environments.md`).

### The commit rule

**Never `git commit`, `git push`, `git tag` or amend unless the user explicitly asks in the current
request.** Staging, diffing and `git status` are fine. When a unit of work is finished, *propose* a
commit message and stop. "Go ahead" on a previous task is not a standing permission for the next.

The project's `.claude/settings.json` backs this with an `ask` rule (below), so a slip produces a
prompt instead of a commit.

## 2. Deploy config — outside the repository, one file per environment

The repository never contains a secret, a host, a server path or a real URL of a remote environment.
A gitignored file inside the working tree is not enough: one `git add -f`, an rsync of the folder, a
zip of the repo or a tool that indexes the workspace carries it away. So the config lives in the user
profile, and the only thing the repository knows is the project slug:

```
~/.config/<project-slug>/            700 — bin/deploy refuses to run otherwise
├── staging.conf                     600 — template: bin/deploy.conf.example
├── production.conf                  600 — same template
├── local.conf                       600 — template: bin/deploy.local.conf.example (LOCAL_URL, https)
├── backups/  dumps/                 700 — DB dumps hold personal data and password hashes
└── deploy.log
~/.ssh/<project-slug>_<env>_ed25519  dedicated key per environment (bin/deploy key-setup <env>)
```

Steps, in order:

1. Copy `assets/bin/deploy` → `bin/deploy`, `assets/deploy.conf.example` → `bin/deploy.conf.example`,
   `assets/deploy.local.conf.example` → `bin/deploy.local.conf.example` — **verbatim** (`cp`), then set
   `PROJECT_SLUG` at the top of `bin/deploy` to the slug confirmed in step 0 (a `sed` on the one line
   `PROJECT_SLUG="example-project"`; also `THEME_SLUG` if the theme folder differs). Replace
   `example-project` with the slug in `.claude/settings.json` too (section 3).
2. `bin/deploy init` — creates `~/.config/<slug>/` (700), `backups/`, `dumps/`, and copies the templates
   into `staging.conf`, `production.conf`, `local.conf` (600). It never overwrites an existing file.
3. `bin/deploy key-setup staging` and `bin/deploy key-setup production` — one dedicated ed25519 key per
   environment, printed as a **public** key for the user to add on the server (hosting panel → SSH
   keys). Offer `--passphrase` if the user prefers a passphrase kept in the macOS Keychain; that
   variant is interactive, so the user runs it in their own terminal.
4. **The user fills the three confs by hand.** Ask them, in one round, for what they need to know —
   host (or `~/.ssh/config` alias), port, SSH user, absolute WordPress root on the server, public URL
   (https) for each environment; the local URL (https) and how wp-cli runs locally — but **do not
   collect the values in the chat to write them yourself**: tell the user which file and key each
   answer goes to. Claude cannot read or edit those files (section 3), by design.
5. `bin/deploy check-env` — lists keys still holding placeholders and missing keys, **never values**.
   Show its output; repeat until clean. Then `bin/deploy staging doctor` once the server exists.

What the confs deliberately do **not** contain:

- **No password of any kind.** The server is reached with the dedicated SSH key only
  (`IdentitiesOnly=yes`, password and keyboard-interactive auth disabled). The remote database
  credentials are read by wp-cli from the server's `wp-config.php`; the local ones from the local
  `wp-config.php`. There is no `*_DB_PASSWORD` or `*_SFTP_PASSWORD` key, and the packaging check
  refuses a template that adds one.
- **No "use my usual keys".** `DEPLOY_KEY=default` is refused: with the agent's keys ssh tries every
  identity it holds, and a personal key that also opens other clients' servers could be the one that
  authenticates — neither the log nor the hook could tell. A dedicated key is revocable per project
  and environment and can be restricted on the server side.

Placeholder convention, unchanged: a value containing `example` or `CHANGE_ME` counts as not
configured; `bin/deploy` stops and names the key.

### Migrating a project that still has a `.env`

`bin/deploy migrate-env` reads the old repo-root `.env` (parsed, never sourced), writes
`STAGING_*`/`PRODUCTION_*` into `staging.conf`/`production.conf` as `DEPLOY_*`, `LOCAL_URL`/
`LOCAL_WP_CMD` into `local.conf`, drops password keys and `LOCAL_DB_*`, and prints **key names only**.
It refuses to overwrite existing confs and warns if `.env` ever appears in git history (then every
secret it held counts as exposed: rotate it). Then run `key-setup` for each environment (a
`SSH_KEY=default` line is dropped), `check-env`, and — **after the user confirms in the conversation**
— `bin/deploy migrate-env --delete-env`.

## 3. Deploy scripts and guard rails — at once, not at the end

Copy also `assets/deploy-plugins.txt` → `deploy-plugins.txt` (ask which plugins the site needs; the
theme itself needs none), `assets/claude/settings.json` → `.claude/settings.json` (merge if one exists;
replace `example-project` with the slug) and `assets/claude/hooks/deploy-guard.sh` →
`.claude/hooks/`. Do it in the kickoff, not when the site is "ready": the first staging push should be
a non-event. `bin/deploy selftest` must pass.

What the settings and the hook enforce:

| Rule | Where |
|---|---|
| `git commit/push/tag`, `bin/deploy production …`, `staging bootstrap`, `staging restore`, `clone-from-prod`, `migrate-env` always prompt the user | `ask` in `settings.json` (`ask` beats any `allow`) |
| No `Read`/`Edit`/`Write` on `~/.config/<slug>/**`, no `Read` on `~/.ssh/**` or `.env` | `deny` in `settings.json` |
| No raw `ssh`/`scp`/`sftp`/`rsync`/`lftp`/`ssh-keygen`/`ssh-add` | `deny` + hook |
| No shell command that names `~/.config/<slug>`, `~/.ssh/<slug>_*`, a legacy `.env` or a deploy host (`cat`, `grep`, `source`, `cp`… all of them) | hook |

Note the rules in the project's `CLAUDE.md` (`project-memory.md`).

## 4. First WordPress admin — only for sites built from scratch

Applies **only** when WordPress is not installed yet (`wp core is-installed` exits non-zero). On an
existing site — a redesign, a takeover, an imported database — **never create, rename or modify
users** unless the user explicitly asks.

Ask:

1. Which **username** for the administrator? Refuse `admin`, `administrator`, the site name, the
   domain, and the email's local part — all are the first guesses of a brute-force script.
2. Which **email** for that account?

```bash
wp core install \
  --url="<local URL, https>" --title="<site title>" \
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

- [ ] New theme: name asked and slug confirmed by the user; folder, `style.css` header (with
      `Update URI: false`), block namespace, prefixes, `composer.json`/`package.json` names all use it.
- [ ] `origin` set and shown back to the user; default branch named; no commit made without a request.
- [ ] `.gitignore` copied from `assets/gitignore`; the repository holds no host, path, URL of a remote
      environment, key or password — `git grep` for the hosts the user named finds nothing.
- [ ] `bin/deploy` with the real `PROJECT_SLUG`; `bin/deploy.conf.example` and
      `bin/deploy.local.conf.example` copied verbatim and tracked; `selftest` passes.
- [ ] `bin/deploy init` done: `~/.config/<slug>/` 700, three confs 600, filled **by the user**;
      `key-setup` run for both environments and the public keys added on the servers;
      `check-env` clean and shown to the user. No legacy `.env` left (or `migrate-env` run).
- [ ] `.claude/settings.json` (slug substituted) + guard hook installed.
- [ ] New site only: admin user and email asked, never `admin`; password-change reminder given.
- [ ] `it_IT.po` for theme and mu-plugin exist; any extra language asked; `translate:check` wired.
- [ ] Logo in `resources/images/`, login screen branded.
