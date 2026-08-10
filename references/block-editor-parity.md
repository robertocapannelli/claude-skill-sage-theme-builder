# Editor canvas parity

The block editor canvas must show **the front end**, not a lookalike of it. Every hour spent making a
second stylesheet "match" is an hour spent building a divergence that will eventually ship.

Three CSS surfaces, deliberately distinct — confusing them is the root of most editor styling bugs:

| Surface | How it is loaded | What belongs there |
|---|---|---|
| **Canvas iframe** (the page being edited) | `block_editor_settings_all` | the real front-end stylesheet, verbatim, plus markup shims |
| **Admin document** (sidebar, panels, inspector) | imported from the Vite `editor.js` entry | admin UI CSS, native WP admin palette only |
| **Front end** | `@vite([...])` in the layout Blade | everything |

## 1. Give the canvas the real stylesheet

```php
// app/setup.php
add_filter('block_editor_settings_all', function (array $settings) {
    foreach (['resources/css/app.css', 'resources/css/editor.css'] as $entry) {
        $settings['styles'][] = ['css' => "@import url('".Vite::asset($entry)."')"];
    }

    return $settings;
});
```

**Why `@import url()` and not `wp_enqueue_style()` or inlined CSS:** WordPress runs everything in
`$settings['styles']` through `transform_styles()`, which rewrites selectors to scope them under
`.editor-styles-wrapper`. An `@import` is not something it can prefix, so the file reaches the iframe
**byte for byte** — same `@font-face`, same `@layer` order, same utilities as the published page. Pass
the built, hashed URL from the manifest (`Vite::asset()`), never a `resources/` path.

Order matters: the front-end sheet first, the shims second, so the shims win.

With `apiVersion: 3` blocks the canvas is a real iframe, which is what makes this work cleanly — the
imported sheet cannot leak into wp-admin's own chrome.

## 2. `editor.css` is shims, never a copy

```css
/* resources/css/editor.css — shims only.
   app.css is imported into the iframe immediately before this file, so everything the front end
   says in CSS already applies here. Do NOT copy front-end rules into this file. */

/* The canvas plays both <html> and <body>: the front end puts the background on <html> and the
   text colour / font / smoothing on the <body> element written by the layout Blade. */
.editor-styles-wrapper {
  background: var(--color-base);
  color: var(--color-fg);
  font-family: var(--font-sans);
  -webkit-font-smoothing: antialiased;
}

/* Theme sections are full-bleed on the front end and cap themselves from the inside, so the canvas
   must not apply layout.contentSize to them. Core blocks keep the content column. */
.editor-styles-wrapper .is-root-container > [data-type^="mytheme/"] {
  max-width: none;
}
```

That is the whole file, and it should stay roughly that size. **What belongs here is only what the
front end expresses in *markup* rather than CSS** — the classes the layout puts on `<body>`, and the
width behaviour that follows from where your sections sit in the document.

**Why the rule is absolute.** When this file was a hand-maintained copy of the front-end sheet, the
copy drifted: the canvas lost the `@font-face` declarations (wrong font), lost `@layer utilities`
(custom utilities silently missing), and — the expensive one — it carried an **unlayered**
`.editor-styles-wrapper a { color: #fff }` that beat `.text-black` sitting in `@layer utilities`,
making the label of every white CTA invisible in the editor. Unlayered CSS beats layered CSS
regardless of specificity; that is the cascade-layers spec, not a bug you can out-specify. If you ever
genuinely need an editor-only reset, put it **inside a layer that precedes `utilities`**:

```css
@layer base {
  .editor-styles-wrapper a { color: inherit; }
}
```

Never `!important` — that just relocates the next invisible-text bug.

## 3. Prose scoping in the canvas is JavaScript, not CSS

Themes usually scope their ~100 lines of prose typography (`.entry-content h2`, `.entry-content ul`,
…) to a wrapper the front end adds only for editorial pages:

```blade
{{-- resources/views/page.blade.php --}}
@php($isComposed = collect(parse_blocks(get_the_content()))
        ->contains(fn ($b) => str_starts_with((string) ($b['blockName'] ?? ''), 'mytheme/')))

@if ($isComposed)
    @php(the_content())                {{-- sections manage their own full-bleed width --}}
@else
    <article class="mx-auto max-w-3xl">
        <div class="entry-content">@php(the_content())</div>
    </article>
@endif
```

In the canvas that separation does not exist — every block is a sibling under the root container. So
reconstruct the wrapper in JS, around foreign blocks only:

```js
// resources/js/blocks/prose-class.js — its own module so it is unit-testable
export const PROSE_CLASS = 'entry-content';
const OWN_PREFIX = 'mytheme/';

export function isProseBlock(blockName) {
    return typeof blockName === 'string' && ! blockName.startsWith(OWN_PREFIX);
}
```

```js
// resources/js/blocks/index.js
import { addFilter } from '@wordpress/hooks';
import { createElement } from '@wordpress/element';
import { isProseBlock, PROSE_CLASS } from './prose-class.js';

addFilter('editor.BlockListBlock', 'mytheme/prose-scope', (BlockListBlock) =>
    function ProseScope(props) {
        const block = createElement(BlockListBlock, props);

        return isProseBlock(props.name)
            ? createElement('div', { className: PROSE_CLASS }, block)
            : block;
    }
);
```

⚠️ **It must be a wrapper element, not a `className` on the block.** In the canvas a block *is* its
element — the heading block renders the `<h2>` itself — so passing `className` produces
`h2.entry-content`, and every `.entry-content h2` rule stops matching. Headings, lists and quotes come
out naked while paragraphs still look right (they only need `font-size`/`line-height`/`color` inherited
from the root rule), which is precisely why the mistake goes unnoticed.

Removing the filter breaks nothing on the front end. It restores the editor bug.

## 4. Feed the editor data REST cannot give it

```php
add_action('enqueue_block_editor_assets', function () {
    if (! wp_script_is('mytheme/blocks-editor', 'registered')) {
        return;
    }

    wp_add_inline_script(
        'mytheme/blocks-editor',
        'window.myThemeForms = '.wp_json_encode(
            function_exists('mytheme_forms') ? mytheme_forms() : []   // empty when the plugin is absent
        ).';',
        'before'
    );
});
```

Two cases where this is the right tool:

- **A post type registered by a plugin without `show_in_rest`** is invisible to
  `useSelect(coreStore).getEntityRecords()`. Inject the list instead of adding a REST route you would
  then have to secure.
- **A registry that lives in PHP** (an icon table, a size map) and should stay a one-file change.
  Ship it already shaped for the control that consumes it (`[{value, label}]`) so no block keeps its
  own copy, and sort it for the reader — a registry is grouped the way you *add* to it, a dropdown is
  scanned the way you *search* it.

Hook it to `enqueue_block_editor_assets`, not `init`, so the lookups never run on front-end requests.
Read it defensively in JS: `const ICONS = [...(window.myThemeIcons ?? [])]`.

## 5. Build-time asymmetry: JSX only in the blocks bundle

`resources/js/editor.js` goes through **Vite/esbuild**, which has no JSX pragma configured for
`@wordpress/element` — write it with `createElement`:

```js
import { createElement as el } from '@wordpress/element';
```

`resources/js/blocks/**` goes through **wp-scripts/babel**, which does — write JSX there. Mixing the
two up produces a build error that reads like a syntax error and sends people looking in the wrong
file.

## 6. Admin/sidebar CSS

Import it from the Vite editor entry (`import '../css/editor-sidebar.css';`) so it lands in wp-admin
rather than in the canvas. Constraint that pays off: **use the native WP admin palette only, never the
brand colours.** The sidebar is WordPress's UI, not the site's; a brand-coloured inspector looks
broken next to core panels and breaks when WP changes its admin theme. Style rhythm inside named panel
classes (`.mytheme-block-panel`) rather than globally.

## Verify

Open a page with one of your sections and one core block. Check, in the canvas: correct font; a custom
utility that only exists in `@layer utilities` actually applies; a white CTA's label is readable; the
core heading picks up prose styling and your section does not; your section is full-bleed and the core
blocks stay in the content column. If `editor.css` has grown past ~40 lines, something was copied that
should have been imported.
