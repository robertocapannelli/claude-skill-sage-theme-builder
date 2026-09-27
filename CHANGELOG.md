# Changelog

Versions follow `metadata.version` in `SKILL.md`. Dates are absolute.

## 2.4.0 — 2026-09-27

- **Theme name asked first** on every new theme (kickoff step 0): display name → slug confirmed by the
  user → folder, `THEME_DIR`/`PROJECT_SLUG`, `style.css` header, block namespace, prefixes,
  `composer.json`/`package.json` names. Existing themes are read, never renamed unless asked.
- `style.css` header template with `Update URI: false`, so a slug that matches a wordpress.org theme can
  never be "updated" over the custom one.
- Text domain stays `sage` by default.

## 2.3.0 — 2026-09-27

- **SSH key authentication only, with the keys already on the computer**: `<ENV>_SSH_KEY=default`
  uses ssh-agent / Keychain, `~/.ssh/config` and `~/.ssh/id_*`; a path pins one key. `<ENV>_HOST` may
  be a `~/.ssh/config` alias.
- Password and keyboard-interactive auth disabled on every connection (ssh, rsync, lftp): a missing
  key fails fast instead of prompting.
- SFTP password support removed: `*_SFTP_PASSWORD` keys dropped from `.env.example`; sftp uses the
  same keys as ssh.
- `bin/deploy <env> doctor` tests key authentication first and says how to fix it.

## 2.2.1 — 2026-09-27

- `.env` always gitignored and never tracked, `.env.example` always tracked: new `assets/gitignore`
  copied verbatim, three verification checks at kickoff, `git add .env.example` staged right away.
- `bin/deploy` refuses to run if `.env` is tracked, warns if `.env.example` is ignored.
- Guard hook: `git add .env .env.example` is now blocked (previously the mention of `.env.example`
  let the whole command through).
- `scripts/package.sh` verifies the gitignore template's semantics in a scratch repository.

## 2.2.0 — 2026-09-27

- **`.env.example` is complete from the start**: `assets/env.example` now has every key — project,
  local, staging and production — each with a fictitious value and a comment; the kickoff copies it
  verbatim instead of writing bare `KEY=` lines (the 2.0 wording asked for "no values", which caused
  it).
- `.env` is written with every key; unknown values keep the fictitious one.
- `bin/deploy` treats values containing `example` or `CHANGE_ME` as unset and stops naming the key;
  new `bin/deploy check-env` lists what is still to fill.
- `scripts/package.sh` fails if a key read by `bin/deploy` is missing from `assets/env.example` or has
  no value.
- One new eval.

## 2.1.0 — 2026-09-27

- **English-only codebase, mandatory translations** (`i18n.md`, principle 14): code, comments and
  every source string in English; Italian catalog created at kickoff for theme and mu-plugin; other
  languages on request; `assets/bin/translate-check` fails on a missing Italian catalog or on
  untranslated/fuzzy entries.
- Block placeholder copy moved from `block.json` defaults (untranslatable) to a default variation
  seeded with `__()` (`native-blocks.md`).
- Kickoff asks for site languages and sets up the catalogs (`project-kickoff.md`).
- One new eval.

## 2.0.1 — 2026-09-27

- Public `README.md` for the GitHub repository (not packaged in the skill zip).

## 2.0.0 — 2026-09-27

- **Kickoff phase** (`references/project-kickoff.md`): git initialised with the user's remote and
  branch, asked via questions; `.env` for local/staging/production with secrets as `CHANGE_ME`;
  deploy scripts and guard rails installed from day one.
- **Commits only on explicit request**; `.claude/settings.json` puts `git commit/push/tag` under `ask`.
- **Deploy rewritten** (`references/remote-environments.md`, `assets/bin/deploy`): config from `.env`,
  every push builds first (npm build + `composer --no-dev` in a release copy), staging vs production
  gates (`--confirm-production=<slug>`, clean tree, pre-flight backup), ssh (rsync) and sftp (lftp)
  transports.
- **Everything visible in a block is editable**: element→control map, no visible literals in
  `render.php`, attribute↔control parity test (`native-blocks.md`, `testing.md`).
- **Login screen branding** with the company logo (`references/login-branding.md`).
- **First admin user**: asked (never `admin`), only on sites built from scratch, with a
  password-change reminder; existing sites' users are never touched unless asked.
- Skill versioning via `metadata.version`; maintainer rules in `CLAUDE.md`; `scripts/audit-public.sh`
  and `scripts/package.sh`.
- Six new evals.

## 1.x

History before versioned releases: see `git log`.
