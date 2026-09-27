# Changelog

Versions follow `metadata.version` in `SKILL.md`. Dates are absolute.

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
