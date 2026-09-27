---
name: sage-theme-builder
description: >-
  Use when building or changing a WordPress theme on the Sage/Roots stack (Blade, Acorn, Vite,
  Tailwind), even when "Sage" is not named: scaffolding a theme, porting a Figma file or HTML mockup
  to WordPress, design tokens and theme.json, native Gutenberg blocks, block previews that don't
  match the front end, post meta and settings without ACF, schema.org JSON-LD, theme or block tests,
  renaming a block/CPT/option in an existing site, deciding what belongs in the theme versus a
  mu-plugin, starting a new WordPress project (git remote, .env for local/staging/production, first
  admin user), deploying to staging or production, or branding the wp-login screen. Also on Italian
  phrasings ("tema Sage", "nuovo sito WordPress", "fammi un blocco Gutenberg", "l'anteprima
  nell'editor non torna", "rinomina il blocco", "deploy in staging", "metti online"). Runs against a
  real project on disk.
allowed-tools: Read Grep Glob Edit Write Bash(npm *) Bash(yarn *) Bash(node *) Bash(composer *) Bash(wp *) Bash(./bin/*) Bash(docker exec *) Bash(vendor/bin/*) Bash(git status*) Bash(git diff*) Bash(git log*) Bash(git init*) Bash(git remote*) Bash(git check-ignore*)
metadata:
  version: "2.2.1"
---

# Sage Theme Builder

Build fast, SEO-solid, fully editable WordPress themes on **Sage 11** by faithfully translating a
design (Figma or HTML/CSS) into Blade templates, Tailwind v4, and **native** Gutenberg blocks.

## Verified stack (confirm before relying on it)

- **Templating:** Laravel Blade via **Acorn 5**.
- **Build — two bundlers, deliberately:**
  - **Vite** (+ `laravel-vite-plugin`, `@roots/vite-plugin`) for `app.css`/`app.js`/`editor.css`/
    `editor.js` → `public/build/`, plus `wordpressThemeJson()`.
  - **`@wordpress/scripts` (webpack)** for the block editor bundle → `public/blocks/index.js` +
    `index.asset.php`. It emits the exact `wp-*` dependency array, which is what removes the whole
    class of "editor throws `wp is not defined`" problems. One `npm run dev` runs both via
    `concurrently`.
- **CSS:** **Tailwind v4** via `@tailwindcss/vite`, configured CSS-first — `@theme` tokens in
  `resources/css/tokens.css`, imported by `app.css`. Usually no `tailwind.config.js`.
- **theme.json:** the root file is a *source*; the build merges the Tailwind theme into
  `public/build/assets/theme.json`. Never hand-edit design tokens into it, and don't use
  `add_theme_support()` for editor config — it is ignored when a `theme.json` exists.
- Node `^20.19 || >=22.12`.

**Always start by reading `composer.json`, `package.json`, `vite.config.js` and `app/setup.php`** to
confirm versions and structure instead of assuming. `package.json` also tells you immediately whether
the project uses the two-bundler split. If you find `bud.config.js`, you are on Sage 10 — same
architecture, different build commands.

## Operating principles (non-negotiable)

0. **The theme depends ONLY on WordPress + Sage.** No third-party plugin is ever a hard dependency —
   not an SEO plugin, not ACF, nothing. The theme must render correctly and completely with zero
   plugins active. Plugins are *optional enhancers*: detect them at runtime
   (`function_exists`/`defined`), and degrade to **nothing** rather than to half a section. This rule
   outranks every convenience below. See `references/plugin-interop.md`.
1. **Theme = presentation only.** Blade templates and components, block render templates, Tailwind,
   `theme.json` tokens, asset enqueuing. Nothing else.
2. **Business logic & the content model → a mu-plugin.** CPTs, taxonomies, **their meta**, settings
   pages, REST routes, cron, integrations — anything that must survive a theme switch.
   See `references/mu-plugins.md`.
3. **Gutenberg blocks are native and server-rendered.** `block.json` + `render.php`, auto-registered by
   `glob()`; React powers the editor only. See `references/native-blocks.md`.
4. **The content model does not need ACF.** `register_post_meta()` with a REST schema,
   `PluginDocumentSettingPanel` sidebar panels and the Settings API cover typed meta, repeaters and
   options pages natively. See `references/post-meta-and-settings.md`; ACF only where it already
   exists (`references/acf-usage.md`).
5. **Name blocks after structure, not content.** `split-stats`, not `white-label`. A block named after
   the page it first appeared on becomes a database migration the day someone reuses it.
6. **Every block and template ships coherent semantic HTML + a complete schema.org JSON-LD graph.** The
   theme emits its own graph unconditionally (duplication with an SEO plugin accepted by design) and
   does **not** own `<title>`, meta description or canonical. See `references/schema-seo.md`.
7. **Lightweight by construction.** Server-rendered front end, no React shipped to visitors,
   self-hosted fonts, only the CSS/JS actually used. Performance is a design constraint, not a later
   pass.
8. **Everything visible on the front end is editable from the block's controls.** Every text, image,
   link, icon and repeated item a visitor sees maps to an attribute with a control; no visible literal
   in `render.php`. See `references/native-blocks.md` → *Everything visible is editable*.
9. **Git is configured on day one; commits happen only on explicit request.** Remote and branch are
   asked, never guessed. Never `git commit`, `push`, `tag` or amend unless the user asks for it in the
   current request — propose the message and stop. See `references/project-kickoff.md`.
10. **Deploys go through `bin/deploy`, always build first, and production is explicit-only.** Staging
   is the agent's to use; production runs only when the user asks for it in the current message,
   never as a follow-up to a staging deploy. See `references/remote-environments.md`.
11. **Secrets never pass through the conversation.** `.env` holds local/staging/production config,
   is **always gitignored and never tracked**, `chmod 600`; `.env.example` is **always tracked**; secrets are written as `CHANGE_ME` for the user to fill in.
12. **Users are the owner's.** On a site built from scratch, ask which admin username (never `admin`)
   and email to create, and remind the user to change the generated password. On an existing site,
   never create or change users unless asked.
13. **The login screen carries the company logo**, never the WordPress one
   (`references/login-branding.md`).
14. **The codebase is English; the site speaks through translation files.** Code, comments,
   identifiers, commit messages and every source string are English — always, whatever the client's
   language. Every string has its translation: an Italian catalog always exists (theme and mu-plugin),
   other languages are added on request, and no untranslated entry ships. See `references/i18n.md`.

## Workflow

Work through these in order; skip ahead when the request is scoped to one part (e.g. "just make me a
testimonial block" → Phase 1 check, then Phase 5).

**0 — Kickoff** (new project; on an existing one, a gap check after recon — add what is missing,
overwrite nothing). Ask for git remote and branch → `git init` + `origin`; ask for the environment data
→ `.env.example` copied verbatim from `assets/env.example` (every key, production included, fictitious values) + `.env` with the same keys; copy `bin/deploy`, `.claude/settings.json` and the guard hook from this
skill's `assets/`; ask which languages besides Italian → `sage.pot` + `it_IT.po`; ask for the company logo; on a site built from scratch, ask for the admin username
and email, install, remind to change the password. → `project-kickoff.md`

**1 — Recon.** Read `composer.json`, `package.json`, `vite.config.js`, `app/setup.php`,
`resources/css/app.css`: Sage version, bundler split, which optional plugins exist, whether a
mu-plugin and a test suite already exist. With a Figma link, use the Figma MCP
(`get_design_context`, `get_variable_defs`, `get_screenshot`) instead of asking for screenshots you
can fetch yourself.

**2 — Design tokens** into `@theme` in `resources/css/tokens.css`, with `theme(static)` and the
`@source` lines. → `design-to-blade.md`

**3 — Blade components** in `components/` and `partials/`; data from View Composers, never a query in
a view.

**4 — Templates, navigation & login.** Archives and singles as Blade (never blocks), a 404 in the site's
voice, dynamic menus with an admin-only placeholder and an accessible offcanvas, the company logo on
the login screen. → `templates.md`, `navigation.md`, `login-branding.md`

**5 — Native blocks.** One folder per block, `save: () => null`, `<ServerSideRender>` as the canvas
preview, a control for every visible element — walk the front end and name the control for each. →
`native-blocks.md`

**6 — Editor parity.** The canvas shows the front end, not a copy of it. → `block-editor-parity.md`

**7 — Content model.** CPTs, taxonomies and meta in the mu-plugin; sidebar panels and a Settings API
page for editing. → `post-meta-and-settings.md`

**8 — Schema.org & LLM readiness.** Full graph, block-level schema from `render.php`, optional
`llms.txt`. → `schema-seo.md`

**9 — Tests.** Answer *"does this need a test?"* **explicitly** for every new function — the answer may
be no, but it may not be skipped. Yes when it has branches, sanitizes/validates/authorizes, produces
output someone else parses, depends on varying state, or has broken once before. → `testing.md`

**10 — Migrations & hand-off.** A rename — block, CPT, option, meta key — or a change to a block's
attribute defaults is a database migration: idempotent script, `--dry-run`, run once per environment.
Leave the project a `CLAUDE.md` with the commands, constraints and traps. →
`content-migrations.md`, `project-memory.md`

**11 — Build & verify.** `npm run translate`, translate every new entry in every catalog,
`npm run translate:compile` and `translate:check`; then `npm run build`, then `wp acorn optimize`. Editor loads clean, the front end
ships no block React, the JSON-LD validates, the checklist below passes.

**12 — Deploy.** `bin/deploy staging push` (it builds first) and report the staging URL. Production
only when the user asks for it explicitly: `bin/deploy production push --dry-run` to show the diff,
then `--confirm-production=<slug>`. Commit only if asked. → `remote-environments.md`

## Traps that fail silently

Read this table first whenever something "doesn't show up but throws no error".

| Symptom | Cause | Where |
|---|---|---|
| Sidebar meta fields vanish on save, no error | the CPT lacks `custom-fields` in `supports`, so REST has no `meta` property | `post-meta-and-settings.md` |
| A Tailwind class typed by an editor does nothing | Tailwind never scans block attributes — needs `theme(static)`, and `@source` for PHP | `design-to-blade.md` |
| White CTA text invisible in the editor only | an unlayered rule in `editor.css` beats `@layer utilities` | `block-editor-parity.md` |
| Headings/lists unstyled in the canvas, paragraphs fine | prose class applied as `className` instead of a wrapper element | `block-editor-parity.md` |
| English labels on an Italian site | a string added to the code but not translated in `it_IT.po`, or a copy default typed into `block.json` | `i18n.md` |
| Editor translations disappear after a build | `make-json` without `--no-purge`, or per-source catalogs that don't match the single bundle | `i18n.md` |
| A published page's copy changes with no edit | a block saved without attributes inherits changed `block.json` defaults | `content-migrations.md` |
| A migrated block stops parsing | attributes written with `wp_json_encode()` instead of `serialize_block_attributes()` | `content-migrations.md` |
| Fatal `TypeError` on a live page | arithmetic on an editor-supplied attribute in PHP 8 | `native-blocks.md` |
| Layout collapses while images decode | an optimizer runs before core's `wp_filter_content_tags()` at priority 12 | `plugin-interop.md` |
| A plugin's shortcode/tag disappears from the DB after a CLI script | the plugin guards its expansion with `!is_admin()`; WP-CLI is not admin | `plugin-interop.md` |
| Staging shows old CSS/JS, or unstyled pages after a deploy | build output is gitignored and was not rebuilt — deploy by hand instead of `bin/deploy` | `remote-environments.md` |
| An editor can't change a text or image on the page | hard-coded in `render.php`, or an attribute with no control | `native-blocks.md` |
| A composer boolean is always true in `@if` | zero-arg methods arrive as a lazy `InvokableComponentVariable` — invoke it | `architecture.md` |

## Reference map

| Read this | When |
|---|---|
| `references/project-kickoff.md` | New project: git + remote, `.env` for three environments, deploy guard rails, first admin, logo |
| `references/architecture.md` | Project structure, bootstrap, two bundlers, theme↔mu-plugin boundary, composers, escaping |
| `references/design-to-blade.md` | Figma/HTML → tokens → Blade; Tailwind v4 `@theme`, `theme(static)`, `@source`, self-hosted fonts |
| `references/navigation.md` | WP menus, no-menu placeholder, offcanvas, normalized menu reader |
| `references/templates.md` | Blade archives, singles, composed vs prose pages, 404 |
| `references/native-blocks.md` | The block recipe: block.json + render.php, editor bundle, inheritance, naming |
| `references/block-editor-parity.md` | Canvas CSS, `editor.css` as shims, prose wrapper filter, editor data injection |
| `references/post-meta-and-settings.md` | Meta with REST schema, `custom-fields`, repeaters, sidebar panels, Settings API |
| `references/mu-plugins.md` | Scaffolding the mu-plugin: CPTs, taxonomies, REST, key-name discipline |
| `references/schema-seo.md` | JSON-LD patterns, invalid-node rule, semantic/performance/LLM rules, `llms.txt` |
| `references/testing.md` | Three-level suite, the four wiring traps, the block tests you write once |
| `references/content-migrations.md` | Renames and format changes as DB migrations; the script recipe |
| `references/i18n.md` | English-only codebase, mandatory Italian catalog, extra languages, POT/PO/MO/JSON pipeline and its two silent traps |
| `references/plugin-interop.md` | Optional-plugin degradation, `the_content` priorities, WP-CLI resave trap |
| `references/remote-environments.md` | `bin/deploy`: build-then-upload, staging vs production gates, ssh/sftp |
| `references/login-branding.md` | Company logo on `wp-login.php` |
| `references/project-memory.md` | Writing the project's CLAUDE.md as a deliverable |
| `references/acf-usage.md` | Only for projects that already have ACF — including how to get off it |

**Assets to copy, not rewrite:** `assets/gitignore`, `assets/bin/deploy`, `assets/bin/translate-check`, `assets/env.example`,
`assets/claude/settings.json`, `assets/claude/hooks/deploy-guard.sh`.

## Definition of done

- [ ] Git initialised with the user's remote; no commit or push made without an explicit request.
- [ ] `.env.example` has every key (local, staging, production) with fictitious values; `.env`
      (gitignored and untracked, `chmod 600`) has the same keys; `.env.example` is tracked; `bin/deploy check-env` shown to the user;
      `bin/deploy selftest` passes; `.claude/settings.json` + guard hook installed.
- [ ] New site only: admin username/email asked (not `admin`), password-change reminder given.
- [ ] The login screen shows the company logo.
- [ ] Design tokens live only in `@theme`; `theme.json` is generated, not hand-edited; `theme(static)`
      and `@source` are in place.
- [ ] Design reproduced faithfully with semantic Blade; no logic in views.
- [ ] Blocks are native, server-rendered, auto-registered, documented, named after structure.
- [ ] Every visible element of every block has a control; the attribute↔control parity test passes.
- [ ] The editor canvas shows the front-end stylesheet; `editor.css` contains only shims.
- [ ] The content model (CPTs, meta, settings) lives in a mu-plugin, with `custom-fields` where meta is
      edited from the editor.
- [ ] Navigation is dynamic with an admin-only placeholder and an accessible offcanvas.
- [ ] Archives and singles are Blade templates; a 404 exists with sector-appropriate tone.
- [ ] Every page emits a complete, valid schema.org graph; `title`/description/canonical left to WP +
      any SEO plugin.
- [ ] The theme renders fully with **zero plugins active**; optional integrations degrade to nothing.
- [ ] All code, comments and source strings in English; output escaped by context.
- [ ] Every string translated in `it_IT` (and any other requested locale); `translate:check` passes;
      no visible copy in `block.json` defaults.
- [ ] The "does this need a test?" question was answered for every new function, and the answers hold.
- [ ] Every rename or format change shipped with an idempotent migration script, and its per-environment
      status is recorded.
- [ ] `npm run build` + `wp acorn optimize` succeed; editor and front end both clean.
- [ ] Deployed to staging through `bin/deploy`; production untouched unless explicitly requested.
