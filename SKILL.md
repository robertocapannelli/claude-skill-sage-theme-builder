---
name: sage-theme-builder
description: >-
  Build production WordPress themes on the Sage 11 (Roots) starter theme, starting from a Figma
  design or HTML/CSS mockups and porting them faithfully to WordPress. Use this whenever the user
  wants to start or scaffold a Sage theme, convert a Figma file or HTML mockup into Blade components
  + Tailwind v4, create native Gutenberg blocks, wire up design tokens / theme.json, add schema.org
  JSON-LD, or decide what belongs in the theme versus a mu-plugin. Trigger on phrases like "tema
  Sage", "porta questo Figma su WordPress", "converti questo HTML in tema", "fammi un blocco
  Gutenberg", "scaffolda un blocco nativo", "tema WordPress performante con Tailwind", or any work
  that implies the Roots stack (Blade, Acorn, Vite) even when "Sage" is not named explicitly.
  Runs in Claude Code against a real Sage 11 project on disk.
---

# Sage Theme Builder

Build fast, SEO-solid, fully editable WordPress themes on **Sage 11** by faithfully translating a
design (Figma or HTML/CSS) into Blade components, Tailwind v4, and **native** Gutenberg blocks.

## Verified stack (Sage 11.x — confirm before relying on it)

- **Templating:** Laravel Blade via **Acorn 5** (Laravel 12 components).
- **Build:** **Vite 6** (NOT Bud — Bud was Sage 10). `@roots/vite-plugin` provides `wordpressPlugin()`
  (externalizes `@wordpress/*` to `wp.*` globals + emits `editor.deps.json`) and `wordpressThemeJson()`.
- **CSS:** **Tailwind v4** via `@tailwindcss/vite`, configured **CSS-first** with `@theme {}` in
  `resources/css/app.css` (there is usually no `tailwind.config.js`).
- **theme.json:** auto-generated on build from the Tailwind theme. Do **not** hand-edit design tokens
  into `theme.json`, and do **not** use `add_theme_support()` for editor config — it is ignored when a
  `theme.json` is present.

**Always start by reading the project's `composer.json`, `package.json`, and `vite.config.js`** to
confirm versions and structure instead of assuming. If you find Bud (`bud.config.js`), you are on
Sage 10 — adapt the build commands accordingly but keep the same architecture.

## Operating principles (non-negotiable)

0. **The theme depends ONLY on WordPress + Sage.** No third-party plugin is ever a hard dependency —
   not Yoast, not ACF, nothing. The theme must render correctly and completely with zero plugins
   active. Plugins are *optional enhancers*: detect them at runtime (`function_exists`/`defined`/
   `is_plugin_active`) and degrade gracefully, never couple to them. Anything substitutable stays
   substitutable. This rule outranks every convenience below.
1. **Theme = presentation only.** Blade templates/components, block rendering markup, Tailwind,
   `theme.json` tokens, asset enqueuing. Nothing else.
2. **Business logic & functionality → custom mu-plugin**, never the theme. CPTs, taxonomies, custom
   REST endpoints, cron, third-party integrations, anything that must survive a theme switch. See
   `references/mu-plugins.md`.
3. **Gutenberg blocks = native WordPress APIs** (`block.json` + `registerBlockType`). No ACF blocks.
   Default to **dynamic blocks rendered server-side in Blade** (React only powers the editor). See
   `references/native-blocks.md`.
4. **ACF Pro is for fields, options pages, and meta — not for building blocks.** Use it only when a
   native solution would be materially more work. See `references/acf-usage.md`.
5. **Every block and template ships coherent semantic HTML + a complete schema.org JSON-LD graph,
   always.** The theme emits its full structured data unconditionally (duplication with an SEO plugin
   is accepted by design). It does **not** own `<title>`, meta description, or canonical — those are
   left to WordPress (`title-tag`) + whatever SEO plugin the site uses, so an external plugin can
   manage them with no conflict and no dependency. See `references/schema-seo.md`.
6. **Lightweight by construction.** Server-rendered front end, no React shipped to visitors, only the
   CSS/JS actually used, lazy assets per block. Performance is a design constraint, not a later pass.

## Workflow

Work through these phases in order. Skip a phase only if the user's request is scoped to one part
(e.g. "just make me a testimonial block" → jump to Phase 4 after a quick Phase 0 check).

### Phase 0 — Recon
- Read `composer.json`, `package.json`, `vite.config.js`, `app/setup.php`, and `resources/css/app.css`.
- Confirm: Sage version, Vite vs Bud, Tailwind present, ACF Pro installed (`wpackagist-plugin/...` or
  active plugin), Yoast present, whether a project mu-plugin already exists.
- Inventory the design input: Figma link, exported images, or HTML/CSS. If a **Figma link** is given,
  use the Figma MCP (`get_design_context`, `get_screenshot`, `get_variable_defs`) — see
  `references/design-to-blade.md`. Don't ask for screenshots you can pull yourself.

### Phase 1 — Design tokens
Extract the design system (colors, typography scale, spacing, radii, breakpoints) and encode it once
in `@theme {}` in `resources/css/app.css`. This single source feeds both Tailwind utilities and the
auto-generated `theme.json`, so the block editor inherits the palette/fonts with zero extra work.
Map Figma variables → `@theme` tokens directly. Details: `references/design-to-blade.md`.

### Phase 2 — Blade component library
Decompose the design into reusable Blade components in `resources/views/components/` (buttons, cards,
sections, nav). Pass data via **View Composers** (`app/View/Composers/`), never query inside views.
Faithful markup = semantic HTML5 landmarks + Tailwind utilities matching the design tokens.

### Phase 3 — Templates & layouts
Build the page templates (`index`, `front-page`, `single`, `page`, `archive`, `404`) and layouts
(`resources/views/layouts/app.blade.php`) by composing the Phase 2 components.

### Phase 4 — Native Gutenberg blocks
For every editable design section, scaffold a native dynamic block: `block.json` (apiVersion 3),
React `edit.js` for back-end editing, `save: () => null`, and a Blade view rendered via
`render_callback`. Document each block (attributes table + README) so editors and future devs
understand it. Full pattern, Vite wiring, and the static-`save()` alternative:
`references/native-blocks.md`.

### Phase 5 — ACF (only where it earns its place)
Use ACF Pro for post/page meta, options pages, and complex repeaters that aren't block content.
Prefer PHP-defined field groups (versionable) or local JSON sync. See `references/acf-usage.md`.

### Phase 6 — mu-plugin for functionality
Anything beyond presentation goes here: register CPTs/taxonomies, REST endpoints, business logic,
integrations. The theme consumes this layer; it never owns it. See `references/mu-plugins.md`.

### Phase 7 — Schema.org & SEO/LLM optimization
The theme always emits its **own complete** JSON-LD graph (Organization, WebSite, BreadcrumbList,
Article, Product/Offer, LocalBusiness, FAQPage as relevant) — unconditionally, duplication accepted.
It defers `<title>`, meta description, canonical, and OG/Twitter to WordPress + any SEO plugin
(`add_theme_support('title-tag')`, no hard emit), so an external plugin can own them without conflict.
Ensure semantic structure, heading hierarchy, and optionally `llms.txt`. A `theme/seo/emit_schema`
filter allows turning schema output off per project. See `references/schema-seo.md`.

### Phase 8 — Build & verify
- Run `npm run build` (or `npm run dev` for HMR). For block editor scripts, confirm `editor.deps.json`
  is generated and the editor isn't throwing missing-`wp.*` errors.
- Run `wp acorn optimize` before considering it production-ready (compiles Blade, caches config).
- Verify: blocks appear and edit correctly, front end renders server-side with no React bundle,
  JSON-LD validates, Lighthouse/PSI is clean. See the checklist below.

## Reference map

| Read this | When |
|---|---|
| `references/architecture.md` | Project structure, theme↔mu-plugin boundary, Vite/asset details, what NOT to touch |
| `references/design-to-blade.md` | Turning Figma/HTML into tokens + Blade components; Tailwind v4 `@theme`; Figma MCP usage |
| `references/native-blocks.md` | Full native dynamic-block recipe, scaffolding, editor controls, docs conventions, build wiring |
| `references/acf-usage.md` | Deciding when ACF Pro is appropriate and how to wire it cleanly |
| `references/mu-plugins.md` | Scaffolding a project mu-plugin for CPTs, taxonomies, REST, logic |
| `references/schema-seo.md` | JSON-LD patterns, Yoast coexistence, semantic/performance/LLM rules |

## Definition of done

- [ ] Design tokens live only in `@theme`; `theme.json` is generated, not hand-edited.
- [ ] Design reproduced faithfully with semantic Blade components; no logic in views.
- [ ] Blocks are native, editable in the back end, documented, and render server-side (no front-end React).
- [ ] No business logic in the theme; functionality lives in a mu-plugin.
- [ ] ACF used only where justified, fields versionable.
- [ ] Theme renders fully with **zero plugins active**; no hard dependency on Yoast, ACF, or anything but WP + Sage.
- [ ] Every page emits a complete, valid schema.org graph (duplication with an SEO plugin accepted); `title`/description/canonical left to WP + optional SEO plugin.
- [ ] `npm run build` + `wp acorn optimize` succeed; editor and front end both clean.