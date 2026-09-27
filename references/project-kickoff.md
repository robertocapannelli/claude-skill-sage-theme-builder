# Project kickoff: git, environments, deploy, first admin

Run this **before the first line of theme code** on a new project, and as a gap check on an existing
one (skip what already exists, never overwrite it). The order matters: the theme name first, because
the folder, the block namespace and every prefix derive from it; git next, so every later file lands
in a tracked tree; `.env` second, because the deploy scripts read it; the admin user last,
because it needs a working database.

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

- theme folder `wp-content/themes/<slug>/` and `THEME_DIR` / `PROJECT_SLUG` in `.env`;
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
| Is the repository the whole site root or the theme only? | Decides where `.gitignore`, `.env`, `bin/` live (default: site root, see `architecture.md`) |

Then check `git config user.name` / `user.email`; ask only if they are empty for this repository.

```bash
git init -b main
git remote add origin <url>        # or: git remote set-url origin <url> if one exists
git remote -v                      # show it back to the user
```

`.gitignore` at the repository root: **copy `assets/gitignore` verbatim** (merge its lines into an
existing one; never replace the `.env` block with a broader pattern like `.env*`, which would also
ignore `.env.example`).

### `.env` ignored, `.env.example` tracked — always

| File | Git |
|---|---|
| `.env` | **always ignored**, never tracked, never `git add -f` |
| `.env.example` | **always tracked** — it is the only place the project's keys are documented |

Verify right after creating both files, and stop to fix `.gitignore` if any line fails:

```bash
git check-ignore -q .env          && echo "ok: .env ignored"          # must print
git check-ignore -q .env.example  || echo "ok: .env.example tracked"  # must print
git ls-files --error-unmatch .env 2>/dev/null && echo "DANGER: .env is tracked"   # must print nothing
git add .env.example              # staged now; it lands in the first commit the user asks for
```

If `.env` turns out to be tracked (an old repository, a `git add -f`), ignoring it is not enough:
`git rm --cached .env`, tell the user, and treat every secret it contained as exposed if it was ever
pushed — rotate them.

Build output is ignored **on purpose**: it never drifts from the source, and it is why every deploy
builds (`remote-environments.md`).

### The commit rule

**Never `git commit`, `git push`, `git tag` or amend unless the user explicitly asks in the current
request.** Staging, diffing and `git status` are fine. When a unit of work is finished, *propose* a
commit message and stop. "Go ahead" on a previous task is not a standing permission for the next.

The project's `.claude/settings.json` backs this with an `ask` rule (below), so a slip produces a
prompt instead of a commit.

## 2. `.env` — one file, three environments

Two files at the repository root, both **complete from the first minute**:

| File | In git | Content |
|---|---|---|
| `.env.example` | committed | **every** key — project, local, staging **and production** — each with a **fictitious value** and a comment |
| `.env` | gitignored, `chmod 600` | the same keys, real values where known, the fictitious value where not yet known |

**`.env.example` is created by copying `assets/env.example` byte for byte (`cp`), never by retyping
it and never with empty values.** An `.env.example` with bare `KEY=` lines, or missing the production
block, is a defect: whoever starts the project has to reconstruct the keys by hand. If the project
needs an extra key, add it to both files with a fictitious value and a comment.

Fictitious values follow one convention: they contain `example` (RFC 2606 names like
`ssh.example.com`, `/var/www/example-project/…`, `example_user`) or are `CHANGE_ME` for secrets.
`bin/deploy` treats any such value as **not configured** and refuses to deploy with it, so a
placeholder can sit in `.env` safely until the real value arrives. `bin/deploy check-env` lists what is
still missing.

Then build `.env`: ask the user, in one round, for what they already know —

| Key group | Ask |
|---|---|
| `PROJECT_SLUG`, `THEME_DIR` | already known from step 0: the theme slug, `wp-content/themes/<slug>` |
| `LOCAL_*` | local URL, how `wp` is invoked locally (`wp`, `ddev wp`, `docker exec …`), DB name/user/host |
| `STAGING_*`, `PRODUCTION_*` | URL; transport (`ssh` preferred, `sftp` if the host has no shell); host (or `~/.ssh/config` alias), port, user; absolute WordPress root on the server. **Never a password**: access is by the SSH keys already on the computer (`SSH_KEY=default`), or a specific key path if the user names one |

— and write `.env` **once**, as a new file containing **every** key of `.env.example`: the answers
replace the fictitious values, everything unanswered keeps its fictitious value, secrets stay
`CHANGE_ME`. Never drop a key because its value is unknown. Finish with `bin/deploy check-env` and show
the user the list of keys still to fill.

From then on `.env` belongs to the user: the project settings deny reading and editing it and the guard
hook blocks it in the shell, so later changes are made by hand — tell the user which key to change
rather than asking them to paste it.

Deliberately **absent**: remote database credentials. With SSH, remote `wp-cli` reads them from the
remote `wp-config.php`; with SFTP there is no remote `wp-cli` to use them. A secret with no consumer is
pure risk.

After writing: `chmod 600 .env`, and verify `git check-ignore .env` prints `.env` — if it prints
nothing, stop and fix `.gitignore` before anything else.

## 3. Deploy scripts and guard rails — at once, not at the end

Copy `assets/bin/deploy` to `bin/deploy` and `assets/deploy-plugins.txt` to `deploy-plugins.txt` (ask which plugins the site needs; the theme itself needs none) (see `remote-environments.md`) in the kickoff, not when the site is "ready": the
first staging push should be a non-event. Then run `bin/deploy selftest` and `bin/deploy staging
doctor` (the latter only once the user confirms the server exists).

Copy `assets/claude/settings.json` to `.claude/settings.json` (merge if one exists) and
`assets/claude/hooks/deploy-guard.sh` to `.claude/hooks/`. The settings put `git commit/push/tag`
`bin/deploy production` and `bin/deploy staging bootstrap` under `ask`, and deny reading `.env`.

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

- [ ] New theme: name asked and slug confirmed by the user; folder, `style.css` header (with
      `Update URI: false`), block namespace, prefixes, `composer.json`/`package.json` names all use it.
- [ ] `origin` set and shown back to the user; default branch named; no commit made without a request.
- [ ] `.gitignore` copied from `assets/gitignore`; `.env` ignored and untracked, `.env.example` not
      ignored and staged (`git add .env.example`) — the three checks above pass.
- [ ] `.env.example` is a verbatim copy of `assets/env.example`: every key, production included, with
      a fictitious value — no bare `KEY=` line.
- [ ] `.env` has every key of `.env.example` (real values where known, secrets `CHANGE_ME`),
      `chmod 600`, `git check-ignore .env` passes; `bin/deploy check-env` output shown to the user.
- [ ] `bin/deploy` in place; `selftest` passes; `.claude/settings.json` + guard hook installed.
- [ ] New site only: admin user and email asked, never `admin`; password-change reminder given.
- [ ] `it_IT.po` for theme and mu-plugin exist; any extra language asked; `translate:check` wired.
- [ ] Logo in `resources/images/`, login screen branded.
