# Native Gutenberg blocks in Sage 11

**Default pattern: dynamic block, PHP render template, React only in the editor.** Field-tested across
20+ blocks in production. It satisfies every constraint at once — native WP APIs, rich back-end
editing, zero React shipped to visitors, semantic + schema-ready markup, and no list of blocks to
maintain anywhere.

```
Editor (back end):  React edit()   → InspectorControls, ServerSideRender preview
Storage:            attributes in block.json (typed, with defaults), save: () => null
Front end:          render.php     → plain PHP template + Tailwind, server-rendered
```

## File layout

```
resources/blocks/<name>/block.json        # metadata + attributes + defaults
resources/blocks/<name>/render.php        # server-side render (PHP template style)
resources/blocks/_helpers.php             # shared render helpers, function_exists()-guarded
resources/js/blocks/index.js              # editor bundle entry — the ONLY manual list
resources/js/blocks/<name>/index.js       # registerBlockType + edit()
public/blocks/index.js + index.asset.php  # wp-scripts output (gitignored, built)
```

Two bundlers, disjoint outputs: **Vite** builds the theme's CSS/JS into `public/build/`, **wp-scripts
(webpack)** builds the editor bundle into `public/blocks/`. See `architecture.md`.

Why render templates in PHP rather than Blade: the template lives next to its `block.json`, WordPress
loads it natively via `"render": "file:./render.php"`, and it keeps working in contexts where the
Acorn view layer is not booted (REST previews, WP-CLI, integration tests). Blade rendering is
documented at the bottom as the alternative.

## Auto-registration — one glob, no list

```php
// app/blocks.php
require_once get_theme_file_path('resources/blocks/_helpers.php');

add_action('init', function () {
    $editor_asset = get_theme_file_path('public/blocks/index.asset.php');

    if (file_exists($editor_asset)) {                 // theme must boot before the first build
        $asset = require $editor_asset;

        wp_register_script(
            'mytheme/blocks-editor',
            get_theme_file_uri('public/blocks/index.js'),
            $asset['dependencies'],                   // wp-* handles, computed by wp-scripts
            $asset['version']
        );
    }

    foreach (glob(get_theme_file_path('resources/blocks/*/block.json')) as $block_json) {
        register_block_type($block_json);
    }
});
```

**Creating the folder registers the block.** There is no array to update, so the thing that can drift
is the filesystem versus the registry — which is exactly what the parity tests assert
(`testing.md`).

**One editor script for all blocks.** wp-scripts emits `index.asset.php` with the `wp-*` dependency
array and a content hash; register that handle once and every `block.json` points at it:

```json
"editorScript": "mytheme/blocks-editor"
```

This replaces the `editor.deps.json` + manual `wp_enqueue_script` loop that Sage's stock editor entry
uses. Keep `resources/js/editor.js` (Vite) for editor UI that is **not** blocks — sidebar panels,
editor filters — and the wp-scripts bundle for the blocks themselves.

## block.json (apiVersion 3)

```json
{
  "$schema": "https://schemas.wp.org/trunk/block.json",
  "apiVersion": 3,
  "name": "mytheme/faq",
  "title": "FAQ",
  "category": "mytheme",
  "icon": "editor-help",
  "description": "Frequently asked questions with an accordion.",
  "textdomain": "sage",
  "supports": { "html": false, "multiple": true },
  "attributes": {
    "heading": { "type": "string", "default": "" },
    "items": {
      "type": "array",
      "default": [{ "q": "", "a": "", "open": false }]
    }
  },
  "editorScript": "mytheme/blocks-editor",
  "render": "file:./render.php"
}
```

- `apiVersion: 3` → iframed editor canvas (required for the CSS parity trick in
  `block-editor-parity.md`).
- `"supports": {"html": false}` removes the *Edit as HTML* escape hatch, which otherwise lets an
  editor break the markup contract your schema and CSS depend on.
- `textdomain` must match the PHP domain, or `wp_set_script_translations()` finds nothing (`i18n.md`).
- Repeaters are `type: "array"` with an object-shaped default.
- **Visible copy defaults to `""`.** `block.json` defaults are not translatable, so copy typed there
  is English on an Italian site. Seed placeholder copy through a default variation instead (below).
- **Defaults are load-bearing.** `render_block()` fills every unset attribute from `block.json` on
  every render, so a block saved as a bare void comment `<!-- wp:mytheme/faq /-->` renders today's
  defaults, not the ones it was inserted with. Changing a default rewrites published pages silently —
  see `content-migrations.md`.

## render.php

```php
<?php
/**
 * FAQ block — front-end render.
 *
 * @var array     $attributes Block attributes.
 * @var string    $content    Inner blocks markup.
 * @var \WP_Block $block      Block instance.
 */

defined('ABSPATH') || exit;

require_once dirname(__DIR__).'/_helpers.php';

$heading = $attributes['heading'] ?? '';
$items   = $attributes['items'] ?? [];
?>
<section <?= get_block_wrapper_attributes(['class' => 'mx-auto max-w-site px-6 py-16']) ?>>
  <?php if ($heading) : ?>
    <h2 class="text-3xl font-extrabold"><?= wp_kses_post($heading) ?></h2>
  <?php endif; ?>

  <?php foreach ($items as $item) : ?>
    <?php if (empty($item['q'])) { continue; } // half-filled row: skip it, don't render an empty <details> ?>
    <details class="group py-4"<?= ! empty($item['open']) ? ' open' : '' ?>>
      <summary class="cursor-pointer font-medium"><?= esc_html($item['q']) ?></summary>
      <div class="mt-2"><?= wp_kses_post($item['a'] ?? '') ?></div>
    </details>
  <?php endforeach; ?>
</section>
```

Conventions that are not stylistic:

- **`get_block_wrapper_attributes()` on the outermost element**, always. It merges `align`, custom
  class names, `anchor` and the layout support attributes. A block that hand-writes `class="…"`
  silently drops everything the editor set. Assert it in a test (`testing.md`).
- **Never do arithmetic on an attribute.** `0 + $attributes['value']` is a fatal `TypeError` in PHP 8
  the moment someone saves a non-numeric string, and it takes the whole page down. Funnel every
  numeric attribute through one coercion helper in `_helpers.php` that degrades to `0`, and use the
  same helper in templates so script and template can never disagree.
- **Skip half-filled repeater rows** rather than rendering empty shells — and skip them in the JSON-LD
  too, with the same predicate.
- `defined('ABSPATH') || exit;` at the top of every PHP file (after `namespace`/`use` if present).
- **Do not run Laravel Pint (or any Laravel preset formatter) on these files.** The preset rewrites
  alternative syntax (`if : … endif;`) into braces and mangles concatenation, turning a one-line diff
  into a full-file rewrite.

## Shared helpers

`resources/blocks/_helpers.php` holds render helpers used by several blocks (inline SVG icons, value
coercion, formatting). Every function is guarded:

```php
if (! function_exists('mytheme_icon')) {
    function mytheme_icon(string $slug, string $class = ''): string { /* … */ }
}
```

Each `render.php` `require_once`s it, and `app/blocks.php` does too so Blade templates can call the
same helpers. The guard makes repeated includes free.

When a helper is backed by a registry (an icon table, a size map), add a **bidirectional drift test**:
every entry the editor can choose must resolve, and vice versa.

## edit() — the back-end experience

```jsx
// resources/js/blocks/faq/index.js
import { registerBlockType } from '@wordpress/blocks';
import { useBlockProps, InspectorControls } from '@wordpress/block-editor';
import { PanelBody, TextControl, TextareaControl, ToggleControl, Button, Flex } from '@wordpress/components';
import ServerSideRender from '@wordpress/server-side-render';
import { __ } from '@wordpress/i18n';
import metadata from '../../../blocks/faq/block.json';

registerBlockType(metadata, {
    edit({ attributes, setAttributes }) {
        const items = attributes.items || [];

        const update = (i, key, value) => {
            const next = [...items];
            next[i] = { ...next[i], [key]: value };
            setAttributes({ items: next });
        };
        const add    = () => setAttributes({ items: [...items, { q: '', a: '', open: false }] });
        const remove = (i) => setAttributes({ items: items.filter((_, x) => x !== i) });
        const move   = (i, delta) => {
            const target = i + delta;
            if (target < 0 || target >= items.length) return;
            const next = [...items];
            [next[i], next[target]] = [next[target], next[i]];
            setAttributes({ items: next });
        };

        return (
            <div { ...useBlockProps() }>
                <InspectorControls>
                    <PanelBody title={ __('Content', 'sage') }>
                        <TextControl
                            __nextHasNoMarginBottom
                            label={ __('Heading', 'sage') }
                            value={ attributes.heading || '' }
                            onChange={ (heading) => setAttributes({ heading }) }
                        />
                    </PanelBody>
                    <PanelBody title={ __('Questions', 'sage') }>
                        { items.map((item, i) => (
                            <div key={ i }>
                                <TextControl __nextHasNoMarginBottom label={ __('Question', 'sage') }
                                    value={ item.q } onChange={ (v) => update(i, 'q', v) } />
                                <TextareaControl __nextHasNoMarginBottom label={ __('Answer', 'sage') }
                                    value={ item.a } onChange={ (v) => update(i, 'a', v) } />
                                <ToggleControl __nextHasNoMarginBottom label={ __('Open by default', 'sage') }
                                    checked={ !! item.open } onChange={ (v) => update(i, 'open', v) } />
                                <Flex>
                                    <Button size="small" onClick={ () => move(i, -1) } disabled={ i === 0 }>↑</Button>
                                    <Button size="small" onClick={ () => move(i, 1) } disabled={ i === items.length - 1 }>↓</Button>
                                    <Button size="small" isDestructive onClick={ () => remove(i) }>
                                        { __('Remove', 'sage') }
                                    </Button>
                                </Flex>
                            </div>
                        )) }
                        <Button variant="secondary" onClick={ add }>{ __('Add question', 'sage') }</Button>
                    </PanelBody>
                </InspectorControls>

                <ServerSideRender block={ metadata.name } attributes={ attributes } />
            </div>
        );
    },
    save() { return null; },
});
```

Rules behind that shape:

- **`registerBlockType(metadata, …)` imports the same `block.json` the PHP registers.** Name and
  attribute schema physically cannot drift.
- **`save() { return null; }`** — mandatory for a dynamic block. If it ever returns markup, that
  markup freezes into `post_content` and outlives your template.
- **`<ServerSideRender>` as the block body**: the canvas preview *is* `render.php`'s output, so there
  is exactly one template to keep faithful instead of two that drift. All editing therefore happens in
  `InspectorControls` panels, not inline.
- **Reorder with ↑/↓ buttons, not drag handles** — keyboard reachable, and no dependency.
- `__nextHasNoMarginBottom` on every control silences the WP 6.7+ deprecation and gives correct
  spacing.
- Media: `MediaUploadCheck` > `MediaUpload`, storing id + url + alt together:
  `onSelect={(m) => setAttributes({ imageId: m.id, imageUrl: m.sizes?.large?.url || m.url, imageAlt: m.alt || '' })}`.

`resources/js/blocks/index.js` is a flat list of `import './<name>/index.js';`. Webpack needs a static
entry, so this is the one manual list in the system — and the JS parity test asserts it matches the
folders on disk.

## Everything visible is editable — no exceptions

**Every piece of content a visitor can see on the front end must be editable from the block's
controls.** If `render.php` prints it, an editor can change it — or deliberately empty it — without a
developer. A hard-coded headline, a fixed image or a CTA label typed into the template is a bug, not a
shortcut: the first copy change becomes a deploy.

Map every visible element to an attribute and a control:

| Visible element | Attribute(s) | Control |
|---|---|---|
| Heading, eyebrow, label, button text | `string` | `TextControl` |
| Paragraph / multi-line text | `string` | `TextareaControl` (plain) or `RichText` in the panel when bold/links/lists are wanted — then `wp_kses_post()` on output |
| Heading level, where the block can sit in different outlines | `string` (`h2`…`h4`) | `SelectControl` |
| Image | `imageId`, `imageUrl`, `imageAlt` (+ `focalPoint` if cropped/cover) | `MediaUploadCheck` › `MediaUpload` with **Replace** and **Remove**, `TextControl` for alt (pre-filled from the library, overridable), `FocalPointPicker` |
| Background / decorative image | same, `imageAlt` empty by design | as above, labelled "decorative" |
| Video / embed | `videoUrl` or `videoId`, `posterId` | `MediaUpload` (`allowedTypes: ['video']`) or `TextControl` + validation |
| Link / button | `linkUrl`, `linkLabel`, `linkNewTab` | `__experimentalLinkControl` (or `TextControl` for the URL) + `TextControl` + `ToggleControl` |
| Icon | `icon` (key of a fixed set) | `SelectControl` / icon picker over the theme's set — never free SVG |
| Repeated items (cards, stats, FAQs, logos) | `array` of objects | the repeater pattern above: add, remove, ↑/↓, every field of the item editable |
| Optional element (eyebrow, secondary CTA, badge) | its content attribute | empty = **not rendered** (no empty tag, no stray spacing); a `ToggleControl` only when it is on/off without content |
| Colour/variant that changes what is visible | `string` from a fixed list | `SelectControl` or block `styles` — tokens only, no free hex |

Rules:

- **No visible literal in `render.php`.** The only strings allowed in the template are
  screen-reader-only labels and structural ARIA text, and those go through `__()` (`i18n.md`).
  Placeholder copy that makes the block look right on insert comes from the default variation below,
  never from `block.json` defaults.

### Placeholder copy: a default variation, in the editor's language

`block.json` defaults can't be translated, and changing them later rewrites published pages
(`content-migrations.md`). So copy attributes default to `""`, and the copy a new block starts with is
written **into its attributes at insertion** by a default variation defined in JS, where `__()` works:

```js
registerBlockType(metadata, {
    variations: [{
        name: 'default',
        isDefault: true,
        title: metadata.title,
        scope: ['inserter'],
        attributes: {
            heading: __('Frequently asked questions', 'sage'),
            items: [{ q: __('Question', 'sage'), a: __('Answer', 'sage'), open: false }],
        },
    }],
    edit, save: () => null,
});
```

The source strings are English and go through the Italian catalog like every other string; the
inserted block stores Italian copy as content, which is what it is. And since nothing visible lives in
the defaults, changing placeholder copy later is a code change, not a database migration.
- **Images always come with alt control** and the attachment id (for `srcset` via
  `wp_get_attachment_image()`), never a URL alone.
- **Every attribute in `block.json` has a control in `edit()`**, and every control writes an attribute
  that `render.php` reads. An attribute with no control is invisible dead weight; a control nobody
  renders is a lie to the editor.
- Content coming from a post (title, excerpt, featured image) is edited where it lives — the post —
  and the block offers the override described in *Blocks that inherit from a post* below.
- Group controls in panels by what the editor sees, top to bottom (Content, Image, Button, Items,
  Appearance), and give every control a label in the site's editor language via `__()`.

Enforce it with the parity test (`testing.md`): for each block, every key under `attributes` in
`block.json` must appear in the block's `edit()` source. It costs ten lines and catches the most common
regression — a field added to the template and the schema, but not to the editor.

Before closing a block, walk the rendered front end element by element and name the control that
changes each one. If you cannot name it, the block is not done.

## Naming: structure, not content

Name a block after **the shape of the section**, never after the page content it happens to show.
`split-stats` (text + CTA on the left, statistics on the right) survives being reused; `white-label`
— named after the service it advertised on the home page — lied the day another page reused the same
pattern. A wrong name is not cosmetic: renaming a block is a database migration
(`content-migrations.md`), because `glob()` registration has no alias or deprecation path.

## Blocks that inherit from a post

A block can take its content from an existing post (featured project, highlighted article) with an
`postId`-style attribute, using the rule *attribute set → it wins; attribute empty → inherit*:

```php
$source_id = (int) ($attributes['postId'] ?? 0);
$source    = $source_id ? get_post($source_id) : null;

// A trashed or unpublished source must not empty the section — fall back to the attributes.
if (! $source || $source->post_type !== 'project' || $source->post_status !== 'publish') {
    $source_id = 0;
}

if ($source_id) {
    if ($title === '')  { $title = esc_html(html_entity_decode(get_the_title($source_id), ENT_QUOTES)); }
    if ($text === '' && has_excerpt($source_id)) { $text = get_the_excerpt($source_id); }
    if ($url === '')    { $url = get_permalink($source_id) ?: ''; }
}
```

⚠️ **This only works if the editor blanks the inheritable attributes when a source is picked.**
`render_block()` fills unset attributes from `block.json` defaults on every render, and those defaults
are not empty — so a block carrying only `postId` would show the default copy forever. Selecting a
source must explicitly write empty values; deselecting must restore the defaults **read from the
imported metadata**, never re-typed. (With copy defaults at `""`, `blank` and `defaults` coincide for
copy fields; the pattern still matters for everything else, and for older blocks with non-empty
defaults.)

```js
const INHERITED = ['title', 'text', 'imageId', 'imageUrl', 'imageAlt', 'url'];
const blank    = { title: '', text: '', imageId: undefined, imageUrl: '', imageAlt: '', url: '' };
const defaults = Object.fromEntries(
    INHERITED.map((key) => [key, metadata.attributes[key]?.default])
);

<SelectControl
    value={ postId || 0 }
    options={ options }
    onChange={ (v) => {
        const id = Number(v);
        setAttributes({ postId: id, ...(id ? blank : defaults) });
    } }
/>
```

Note the two escaping paths for one field: an author-typed override may legitimately carry markup
(`wp_kses_post`), while an inherited post title is plain text whose entities must be decoded
(`esc_html(html_entity_decode(…, ENT_QUOTES))`).

Post picker:

```js
const posts = useSelect((select) => select(coreStore).getEntityRecords('postType', 'project', {
    per_page: -1, status: 'publish', orderby: 'title', order: 'asc', _fields: 'id,title',
}), []);
```

Prefer core helpers inside `render.php` over hand-built markup: `get_the_post_thumbnail($id, 'large',
['class' => …, 'loading' => 'lazy'])` brings `srcset`, `width`/`height` and `decoding` along for free.

## Inserter category, patterns, block styles

```php
add_filter('block_categories_all', function (array $categories): array {
    array_unshift($categories, [
        'slug'  => 'mytheme',
        'title' => __('My Theme', 'sage'),
        'icon'  => null,
    ]);
    return $categories;
});

add_action('init', function () {
    register_block_pattern_category('mytheme', ['label' => __('My Theme', 'sage')]);
    register_block_style('core/paragraph', ['name' => 'lead', 'label' => __('Lead', 'sage')]);
});
```

`register_block_style()` only *surfaces* a variant in the Styles panel — the CSS already exists once
in the front-end stylesheet, and the canvas receives that file verbatim. Never ship a second
stylesheet for it.

## Documentation conventions

Every block ships with a meaningful `title`, `description` and `keywords` in `block.json` (this is
what editors read in the inserter), an attributes table in a per-block `README.md` or a docblock at
the top of `render.php`, and `supports` locked down so editors cannot break the layout.

## Alternative: Blade-rendered blocks

If you want the Acorn view layer (components, `@include`, composers) inside blocks, replace
`"render": "file:./render.php"` with a `render_callback` handing off to Blade:

```php
register_block_type($block_json, [
    'render_callback' => fn (array $attributes, string $content, $block) =>
        \Roots\view('blocks.faq', compact('attributes', 'content', 'block'))->render(),
]);
```

Cost: the view layer must be booted (extra work in tests — see `testing.md`), the template lives away
from its `block.json`, and the block dies on a non-Sage theme. Use it when blocks genuinely reuse
Blade components; otherwise the PHP template is less machinery. **Pick one per project and stay
consistent** — a codebase with both is a codebase where nobody knows where the markup is.

## When a STATIC block is right instead

Use `save()` returning markup (no server render) only when **all** of these hold: content is purely
static, needs no server-side data, computes no JSON-LD, and the client benefits from markup frozen
into `post_content` so it survives the theme being removed. Otherwise dynamic wins — restyling,
dynamic data and server-rendered schema all depend on it. Document the choice per block.

## Common mistakes

- **Editor throws `wp is not defined` / missing deps.** The `wp-*` dependency array came from somewhere
  other than `index.asset.php`. Register the handle from that file; don't hand-write dependencies.
- **A block renders its defaults instead of the saved content.** Something writes only part of the
  attribute set — see the inheritance section above.
- **A block renders nothing after a rename.** There is no alias: old `post_content` still says the old
  name. Migrate the database (`content-migrations.md`).
- **A text, image or link on the front end has no control in the editor.** Hard-coded in `render.php`
  or an attribute without a control — see *Everything visible is editable*.
- **The block's own classes are missing on the wrapper.** You wrote `class="…"` instead of merging
  through `get_block_wrapper_attributes()`.
- **A Tailwind class typed by the editor into an attribute does nothing.** Tailwind never scans block
  attributes — you need `theme(static)` (`design-to-blade.md`).
- **Registering CPTs or business queries here.** That is mu-plugin territory (`mu-plugins.md`).
