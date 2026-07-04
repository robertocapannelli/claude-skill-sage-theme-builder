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
| Custom REST endpoints / WP-CLI commands | **mu-plugin** | Functionality |
| Third-party API clients, webhooks, cron | **mu-plugin** | Business logic |
| Data a block needs (e.g. "latest products") | **mu-plugin** exposes it; block consumes | Keeps view dumb |

Grey area — **block that needs queried data**: register and render the block in the theme, but put the
query/service in the mu-plugin and call it from the block's `render_callback`/View Composer. The block
stays a thin presentation layer.

## Vite & asset essentials

- Front-end assets: enqueue via Sage's `Vite` facade / `asset()` helper in `setup.php`. Don't hardcode
  `public/build` paths — let the manifest resolve them.
- Block **editor** script: register it depending on the `wp-*` handles WordPress provides, and rely on
  `wordpressPlugin()` to externalize `@wordpress/*` imports to the global `wp` object. The plugin emits
  `editor.deps.json`; the editor enqueue logic reads it to declare script dependencies. Don't bundle
  React/`@wordpress/*` into your block code — that defeats the externalization and bloats the editor.
- `npm run dev` gives HMR (including in the iframed block editor via the injected Vite client); `npm
  run build` produces production assets and regenerates `theme.json`.

## What NOT to touch

- Don't hand-edit `theme.json` design tokens — edit `@theme` in `app.css` and rebuild.
- Don't call `add_theme_support('editor-color-palette' | 'editor-font-sizes' | ...)` — ignored when
  `theme.json` exists; configure via Tailwind instead.
- Don't put `register_post_type`, `register_taxonomy`, or API calls in `setup.php`/`functions.php`.
- Don't ship jQuery or heavy front-end JS to match a design that CSS/Tailwind can handle.