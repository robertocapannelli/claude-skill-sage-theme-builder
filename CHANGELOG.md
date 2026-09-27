# Changelog

Versions follow `metadata.version` in `SKILL.md`. Dates are absolute.

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
