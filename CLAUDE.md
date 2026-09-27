# Maintaining this skill

This repository **is** the `sage-theme-builder` skill and it is **public on GitHub**. These rules apply
to every change to the skill itself (they are not loaded when the skill is used on a theme project).

## Every update, in this order

1. **Edit** `SKILL.md`, `references/`, `assets/`, `evals/` as needed.
2. **Bump the version** in `SKILL.md` → `metadata.version` (semver):
   - **major** — a workflow or operating rule changes what the agent does by default;
   - **minor** — new reference, asset, rule or eval that adds ground without changing existing behaviour;
   - **patch** — wording, fixes, clarifications.
   No change ships under an unchanged version.
3. **Add a `CHANGELOG.md` entry** for that version, dated (absolute date), one line per change.
4. **Audit**: `scripts/audit-public.sh` must print `audit: clean`.
5. **Package**: `scripts/package.sh` → `dist/sage-theme-builder-<version>.zip` (also checks that every
   `references/…` and `assets/…` path cited in the docs exists).
6. **Sync local and remote**: commit, tag `v<version>`, push commit and tag to `origin`. A request to
   update the skill includes this step — the skill is never left updated only locally. Then
   re-upload the zip in claude.ai (delete the old skill entry first to avoid a `name` conflict).

## Nothing personal, nothing client-specific — ever

The skill must never contain references to specific projects or clients, personal information, or
sensitive data: names, emails, phone numbers, VAT/tax ids, real domains, hostnames, IPs, server paths,
credentials, screenshots of real sites. Examples use `acme`, `mytheme`, `example.com`, `/home/u/…`.

- `scripts/audit-public.sh` checks the generic patterns; `.audit-denylist` (gitignored, local only)
  holds the specific names to catch — keep it updated when a new client or project starts.
- **If you notice such content — in the working tree or in git history — stop and tell the user
  immediately**, then start the removal: fix the files, and if it was ever pushed, plan a history
  rewrite (`git filter-repo`) + force-push with the user's explicit approval, and rotate any credential
  that was exposed. Removing it in a new commit does not remove it from GitHub.
- Lessons from real projects are generalised before they land here: the trap and the rule, never the
  project it came from.

## Layout

```
SKILL.md            orchestrator, frontmatter carries metadata.version
references/         loaded on demand by the agent
assets/             files the agent copies into projects (bin/deploy, .env.example, .claude/…)
evals/evals.json    behaviour cases (not packaged)
scripts/            maintainer tooling (not packaged)
CHANGELOG.md        one entry per version (not packaged)
README.md           public description for GitHub (not packaged)
```
