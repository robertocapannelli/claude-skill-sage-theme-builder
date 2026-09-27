# sage-theme-builder

An [Agent Skill](https://docs.claude.com/en/docs/agents-and-tools/agent-skills/overview) that teaches
Claude to build and maintain **WordPress themes on the Roots Sage 11 stack** — from an empty folder to
a deployed site — following a field-tested set of conventions instead of improvising them each time.

It turns a design (Figma file or HTML/CSS mockup) into Blade templates, Tailwind v4 tokens and
**native, server-rendered Gutenberg blocks**, and wraps the work in the parts that usually go wrong
silently: editor/front-end parity, content migrations, i18n, schema.org, tests, and deploys.

> Built for [Claude Code](https://docs.claude.com/en/docs/claude-code/overview), where the skill has
> filesystem and shell access. On claude.ai it still works for reasoning and code snippets, without
> touching a project on disk.

## What it does

- **Project kickoff** — asks for the git remote and branch, sets up a gitignored `.env` describing
  local, staging and production, installs the deploy script and guard rails, brands the login screen,
  and (only on sites built from scratch) creates the first admin with a username and email you choose.
- **Design → theme** — design tokens in Tailwind v4 `@theme`, generated `theme.json`, semantic Blade
  components, archives and singles as templates, accessible navigation.
- **Native Gutenberg blocks** — `block.json` + `render.php`, React only in the editor, auto-registered.
  Every text, image, link and repeated item visible on the front end is editable from the block's
  controls, with a test that keeps it that way.
- **Editor parity** — the canvas renders the real front-end stylesheet, not a lookalike.
- **Content model without ACF** — CPTs, taxonomies, typed post meta and settings pages in a mu-plugin,
  edited through native sidebar panels. ACF is supported only where it already exists.
- **SEO & LLM readiness** — a complete schema.org JSON-LD graph per page, optional `llms.txt`.
- **Tests** — PHPUnit + Jest suite shape, and the four wiring traps that make it lie.
- **Migrations** — renames of blocks, CPTs, options and meta treated as idempotent DB migrations.
- **Deploys** — one audited door, `bin/deploy`: every push builds first; staging is routine,
  production runs only on explicit request, after a backup, over SSH (rsync) or SFTP (lftp).

## Principles it enforces

1. The theme depends only on WordPress + Sage; plugins are optional enhancers that degrade to nothing.
2. Theme = presentation. Business logic and the content model live in a mu-plugin.
3. Blocks are named after their structure (`split-stats`), never after the content they first showed.
4. No git commit, push or tag without an explicit request.
5. No production deploy without an explicit request.
6. Secrets never pass through the conversation: they are written as `CHANGE_ME` and filled in by hand.

## Stack

Sage 11 · Acorn 5 (Laravel Blade) · Vite + `@wordpress/scripts` · Tailwind CSS v4 · WordPress block
editor (apiVersion 3) · WP-CLI · PHPUnit / Jest. Node `^20.19 || >=22.12`. Sage 10 (Bud) projects are
recognised and handled with the same architecture.

## Install

**Claude Code** — clone this repository into your skills folder (or symlink it there), using the URL
from the green *Code* button above:

```bash
git clone <repository-url> ~/.claude/skills/sage-theme-builder
```

**claude.ai** — build the zip and upload it under *Settings → Capabilities → Skills*:

```bash
scripts/package.sh        # → dist/sage-theme-builder-<version>.zip
```

When updating, remove the previous version of the skill first to avoid a name conflict.

## Usage

The skill activates on its own when a request matches — no command needed. For example:

- "Start a new WordPress site with Sage for a furniture company."
- "Turn this section into a Gutenberg block editable from the back end." + HTML
- "The block preview in the editor doesn't match the front end."
- "Rename the `white-label` block to `split-stats` on every environment."
- "Deploy to staging." / "Staging looks good, deploy to production."

Italian phrasings work too ("fammi un blocco Gutenberg", "deploy in staging").

## Repository layout

```
SKILL.md            entry point: operating rules, workflow, traps, reference map
references/         topic guides Claude loads on demand
assets/             files copied into projects: bin/deploy, .env.example, .claude/ settings + hook
evals/evals.json    behaviour test cases for the skill
scripts/            maintainer tooling: public-content audit, packaging
CHANGELOG.md        release notes
CLAUDE.md           rules for maintaining this repository
```

## Versioning

The version lives in `SKILL.md` under `metadata.version` (semver) and each release is tagged
`v<version>`. See [CHANGELOG.md](CHANGELOG.md).

## Contributing

Issues and pull requests are welcome. Keep examples generic (`acme`, `mytheme`, `example.com`): no
client names, real domains, hosts or credentials — `scripts/audit-public.sh` must pass. Maintainer
rules are in [CLAUDE.md](CLAUDE.md).
