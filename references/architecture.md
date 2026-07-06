# Architecture & boundaries

## Sage 11 file structure

```
themes/<theme>/
├── app/
│   ├── Providers/                 # Service providers (ThemeServiceProvider, etc.)
│   ├── View/Composers/            # Controllers for Blade views — data prep lives here
│   ├── Blocks/                    # (optional) PHP for native block registration/render callbacks
│   ├── filters.php                # WP filter hooks (presentation-level only)
│   └── setup.php                  # Theme supports, menus, sidebars, asset + editor enqueues
├── resources/
│   ├── css/
│   │   ├── app.css                # Tailwind entry + @theme tokens (front end)
│   │   └── editor.css             # Editor-only styles
│   ├── js/
│   │   ├── app.js                 # Front-end JS (keep minimal)
│   │   └── editor.js              # Block editor JS entry (imports block edit components)
│   └── views/
│       ├── layouts/               # app.blade.php base layout
│       ├── sections/              # header/footer
│       ├── partials/              # smaller reused fragments
│       ├── components/            # Blade components (<x-...>)
│       └── blocks/                # Blade views rendered by native block render_callback
├── public/build/                  # Compiled assets (Vite output) + generated theme.json
├── theme.json                     # GENERATED on build — do not hand-edit tokens
├── vite.config.js
├── composer.json
└── package.json
```

If you see `bud.config.js` and `resources/scripts` / `resources/styles` instead of `resources/js` /
`resources/css`, you are on **Sage 10**. Same architecture; build command differs (`yarn build` via
Bud, asset helper is `bundle()`/`asset()`), and block editor wiring uses Bud entries.

## The theme ↔ mu-plugin boundary

Decide with one question: **"Would this still need to exist if the client switched themes?"**

| Concern | Lives in | Why |
|---|---|---|
| Blade templates, components, layouts | Theme | Pure presentation |
| Tailwind, `@theme` tokens, `theme.json` | Theme | Visual design system |
| Block **registration + edit.js + Blade render** | Theme | Design-coupled presentation of THIS site |
| Asset enqueuing | Theme | Presentation |
| Custom Post Types, taxonomies | **mu-plugin** | Content model must outlive the theme |
| **Durable content** (options, ACF fields, CPT entries) | **mu-plugin** | Data must not orphan on a theme switch |
| Custom REST endpoints / WP-CLI commands | **mu-plugin** | Functionality |
| Third-party API clients, webhooks, cron | **mu-plugin** | Business logic |
| Data a block displays (e.g. "latest products") | **mu-plugin** owns the data; block is a view | Keeps the block a dumb window onto durable data |

**The durable-content rule (decides where a block's content lives).** A dynamic block stores its typed
content in attributes inside `post_content`. That content is therefore coupled to the block's
registration — deregister the block (theme switch) and it orphans. So:

- **Display blocks** (a carousel of latest news, a product grid): the real data lives in a CPT, already
  theme-independent. The block only *queries and renders* it — content is edited in the CPT, never in
  the block. Registering these in the theme is fine; switching themes loses the view, not the data.
- **Container blocks** (hero heading, CTA copy): the attributes *are* the data. If that content must
  survive a theme switch, it doesn't belong in the block — put it in ACF/options/a CPT (mu-plugin) and
  let the block display it. If it's presentational copy you'd redo in a redesign anyway, accept the
  theme coupling.

Rule of thumb: **durable content lives in the mu-plugin layer; blocks are windows onto it.** Don't try
to "make blocks independent" by moving their registration to the mu-plugin while rendering through
`\Roots\view()` — Blade rendering still dies on a non-Sage theme, so the independence is illusory. (A
genuinely standalone-durable block needs mu-plugin registration *and* autonomous PHP rendering; that
heavy pattern is documented in `native-blocks.md` as an exception, not the default.)

## Vite & asset essentials

- Front-end assets: enqueue via Sage's `Vite` facade / `asset()` helper in `setup.php`. Don't hardcode
  `public/build` paths — let the manifest resolve them.
- Block **editor** script: register it depending on the `wp-*` handles WordPress provides, and rely on
  `wordpressPlugin()` to externalize `@wordpress/*` imports to the global `wp` object. The plugin emits
  `editor.deps.json`; the editor enqueue logic reads it to declare script dependencies. Don't bundle
  React/`@wordpress/*` into your block code — that defeats the externalization and bloats the editor.
- `npm run dev` gives HMR (including in the iframed block editor via the injected Vite client); `npm
  run build` produces production assets and regenerates `theme.json`.

## Conventions

- **All code, comments, identifiers, and commit messages in English.** UI-facing strings are
  translatable (`__()`, `_e()`); everything in the codebase is English regardless of the client's language.
- **Output escaping is context-driven — there is no one-size function.** Escape at the point of output:
  - Plain text → `esc_html()` (Blade `{{ }}` already does this).
  - HTML attributes → `esc_attr()`.
  - URLs → `esc_url()`.
  - Content where limited HTML is intentional (RichText block fields: bold, links, lists) →
    `wp_kses_post()`, used with Blade raw echo: `{!! wp_kses_post($value) !!}`.

  `wp_kses_post()` is the right tool *only* for the last case, and it's the most expensive — using it on
  URLs or plain text is both wasteful and less safe (wrong escaping for the context). Match the function
  to the sink.

## Environment is out of scope

This skill assumes a working WordPress install with the `wp` CLI available. It does **not** manage the
local dev environment — starting Devilbox/DDEV/Local/Valet, containers, or hosts. That's infrastructure,
deliberately kept out so the skill stays tech-stack-agnostic. If environment bootstrapping is needed,
it belongs in a separate, dedicated skill, not here.



- Don't hand-edit `theme.json` design tokens — edit `@theme` in `app.css` and rebuild.
- Don't call `add_theme_support('editor-color-palette' | 'editor-font-sizes' | ...)` — ignored when
  `theme.json` exists; configure via Tailwind instead.
- Don't put `register_post_type`, `register_taxonomy`, or API calls in `setup.php`/`functions.php`.
- Don't ship jQuery or heavy front-end JS to match a design that CSS/Tailwind can handle.
