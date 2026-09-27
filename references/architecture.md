# Architecture & boundaries

## Sage 11 file structure (as built)

```
themes/<theme>/
├── app/
│   ├── Providers/                 # ThemeServiceProvider (extends Acorn's SageServiceProvider)
│   ├── View/Composers/            # data prep for views — App, Post, Comments
│   ├── Support/                   # plain classes the composers and templates lean on
│   ├── setup.php                  # theme supports, menus, editor styles, theme.json wiring
│   ├── filters.php                # presentation-level WP filters
│   ├── blocks.php                 # block registration + editor script + editor data
│   └── schema.php                 # JSON-LD graph
├── resources/
│   ├── blocks/<name>/             # block.json + render.php  ← the blocks themselves
│   ├── blocks/_helpers.php        # shared render helpers
│   ├── css/
│   │   ├── app.css                # Tailwind entry + @font-face + layers (front end)
│   │   ├── tokens.css             # @theme tokens, imported by app.css
│   │   ├── editor.css             # canvas shims ONLY (see block-editor-parity.md)
│   │   └── editor-sidebar.css     # wp-admin UI, imported from editor.js
│   ├── js/
│   │   ├── app.js                 # front-end JS (keep minimal)
│   │   ├── editor.js              # admin-side editor UI (sidebar panels) — Vite, no JSX
│   │   └── blocks/                # editor UI for the blocks — wp-scripts, JSX
│   │       ├── index.js           # bundle entry: imports every block (the one manual list)
│   │       └── <name>/index.js
│   ├── fonts/  images/  lang/
│   └── views/                     # layouts, sections, partials, components, forms
├── public/build/                  # Vite output + generated theme.json
├── public/blocks/                 # wp-scripts output: index.js + index.asset.php
├── theme.json                     # SOURCE for the generated one — no design tokens here
├── vite.config.js  jest.config.cjs  composer.json  package.json
```

Root of the repository (outside the theme): `tests/`, `bin/`, `wp-content/mu-plugins/`.

If you find `bud.config.js` and `resources/scripts` / `resources/styles`, you are on **Sage 10**: same
architecture, different build (Bud, `bundle()`/`asset()` helpers).

## Bootstrap

```php
// functions.php
if (! file_exists($composer = __DIR__.'/vendor/autoload.php')) {
    wp_die(__('Error locating autoloader. Please run <code>composer install</code>.', 'sage'));
}
require $composer;

Application::configure()->withProviders([ThemeServiceProvider::class])->boot();

collect(['setup', 'filters', 'blocks', 'schema'])->each(function ($file) {
    if (! locate_template($file = "app/{$file}.php", true, true)) {
        wp_die(sprintf(__('Error locating <code>%s</code> for inclusion.', 'sage'), $file));
    }
});
```

Sage ships `['setup', 'filters']`. **Add one file per concern** rather than growing `setup.php` — the
manifest is the map of what the theme does.

**Every PHP file opens with `defined('ABSPATH') || exit;`**, and in namespaced files it goes *after*
the `namespace` declaration and the `use` block — before them it is a fatal.

## Two bundlers, on purpose

| | Vite | wp-scripts (webpack) |
|---|---|---|
| Builds | `app.css`, `app.js`, `editor.css`, `editor.js` | `resources/js/blocks/**` |
| Output | `public/build/` (+ generated `theme.json`) | `public/blocks/index.js` + `index.asset.php` |
| JSX | no — use `createElement` | yes |

```json
"dev":   "concurrently \"vite\" \"wp-scripts start --webpack-src-dir=resources/js/blocks --output-path=public/blocks\"",
"build": "vite build && npm run build:blocks"
```

Why both: wp-scripts emits `index.asset.php` with the exact `wp-*` dependency array and a content hash,
which is what `wp_register_script()` wants and what removes the whole class of "editor throws
`wp is not defined`" problems. Vite gives HMR, the manifest and `wordpressThemeJson()`. Trying to make
one tool do both costs more than running two.

## Assets

- **Front end**: no `wp_enqueue_scripts` hook at all — the layout Blade calls
  `@vite(['resources/css/app.css', 'resources/js/app.js'])`.
- **Editor canvas**: the built stylesheet is injected through `block_editor_settings_all` — see
  `block-editor-parity.md`.
- **Editor JS (admin side)**: printed in `admin_head` behind `get_current_screen()?->is_block_editor()`,
  enqueueing the handles listed in `editor.deps.json` when not running hot.
- **Blocks editor JS**: one registered handle built from `index.asset.php` (`native-blocks.md`).
- **theme.json**: the root file is the *source*; the build merges the Tailwind theme into
  `public/build/assets/theme.json`. Point WordPress at the built one:

```php
add_filter('theme_file_path', function ($path, $file) {
    return $file === 'theme.json' ? public_path('build/assets/theme.json') : $path;
}, 10, 2);
```

Setup toggles worth copying: `should_load_separate_core_block_assets` → `__return_false`,
`remove_theme_support('block-templates')` and `remove_theme_support('core-block-patterns')` when the
site is not FSE, and an explicit `load_textdomain()` (Sage does not load translations by itself).

## The theme ↔ mu-plugin boundary

Decide with one question: **"Would this still need to exist if the client switched themes?"**

| Concern | Lives in | Why |
|---|---|---|
| Blade templates, components, layouts | Theme | Pure presentation |
| Tailwind, `@theme` tokens, `theme.json` | Theme | Visual design system |
| Block registration + editor UI + render template | Theme | Design-coupled presentation of THIS site |
| Asset enqueuing | Theme | Presentation |
| Custom post types, taxonomies, **their meta** | **mu-plugin** | Content model must outlive the theme |
| Settings page / options | **mu-plugin** | Data must not orphan on a theme switch |
| REST routes, WP-CLI commands, cron | **mu-plugin** | Functionality |
| Third-party API clients, webhooks | **mu-plugin** | Business logic |
| Data a block displays | **mu-plugin** owns the data; block is a view | Keeps the block a window onto durable data |

**The durable-content rule.** A dynamic block stores its content in attributes inside `post_content`,
coupled to the block's registration — deregister the block and it orphans. So:

- **Display blocks** (a grid of latest projects) query a CPT that is already theme-independent. The
  block renders; the content is edited in the post type. Switching themes loses the view, not the data.
- **Container blocks** (hero heading, CTA copy) — the attributes *are* the data. If that copy must
  survive a theme switch, it belongs in a CPT or in settings and the block should display it. If it is
  presentational copy you would rewrite in a redesign anyway, accept the coupling.

Do not try to "make blocks independent" by registering them from the mu-plugin while rendering through
`\Roots\view()` — Blade still dies on a non-Sage theme, so the independence is illusory. A PHP
`render.php` is closer to independent, but the markup is still the theme's job.

## View Composers

```php
namespace App\View\Composers;

use Roots\Acorn\View\Composer;

class App extends Composer
{
    protected static $views = ['*'];                  // or ['partials.content-*'] etc.

    public function siteName(): string { return get_bloginfo('name', 'display'); }
    public function navPrimary(): array { return NavMenu::items('primary_navigation'); }
    public function headerBoxed(): bool { return get_option('options_header_boxed') === '1'; }
}
```

Every public zero-argument method becomes a variable named after it (`navPrimary()` → `$navPrimary`).
Views never query; composers prepare.

⚠️ **Zero-argument methods reach the view as an `InvokableComponentVariable` — a lazy proxy, not a
value.** In an `@if` or a ternary that object is **always truthy**, even when the method returns
`false`, `''` or `[]`. Blade also cannot subscript it.

- Booleans and conditionals: **invoke it** — `@if ($headerBoxed())`.
- `{{ }}` and `@foreach` resolve it by themselves.
- Need `$navServices[0]['url']`? Expose a scalar accessor method instead, and say why in a comment —
  this looks like an over-complication until someone reproduces the bug.

Related habit: URL resolvers should return `'#'` rather than `null` or `''` when the target content
does not exist yet, so chrome never renders a broken link on a fresh install.

## Conventions

- **All code, comments, identifiers, commit messages and source strings in English**, regardless of
  the client's language — mandatory. Every UI string goes through a translation function and has its
  translation in the project's catalogs: Italian always, other languages on request (`i18n.md`).
- **Escaping is context-driven — there is no one-size function.** Escape at the point of output:
  plain text → `esc_html()` (Blade `{{ }}` already does it); attributes → `esc_attr()`; URLs →
  `esc_url()`; content where limited HTML is intentional (a RichText field: bold, links, lists) →
  `wp_kses_post()` with a raw echo. `wp_kses_post()` is the right tool *only* for that last case, and
  it is the most expensive — using it on a URL is both wasteful and less safe, because it is the wrong
  escaping for the sink.
- **Do not run a Laravel-preset formatter on block render templates or on mu-plugins.** It rewrites
  alternative syntax into braces and reformats concatenation, burying real changes in noise. Run it on
  `app/` and ordinary PHP.
- Don't hand-edit `theme.json` design tokens — edit `@theme` and rebuild.
- Don't call `add_theme_support('editor-color-palette' | 'editor-font-sizes' | …)` — ignored when a
  `theme.json` exists.
- Don't put `register_post_type`, `register_taxonomy` or API calls in `setup.php`/`functions.php`.
- Don't ship jQuery or heavy front-end JS for something CSS can do.

## Environments: tooling out of scope, description in scope

This skill does not choose or install the local dev tooling — Devilbox/DDEV/Local/Valet, containers,
hosts. That stays stack-agnostic. What it does own, from the kickoff, is the **description** of all
three environments: one `.env` with local, staging and production data (how `wp` is invoked locally,
URLs, hosts, roots), and `bin/deploy` as the one door to the remote ones. See `project-kickoff.md`
and `remote-environments.md`.
