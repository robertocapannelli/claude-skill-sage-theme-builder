# Native Gutenberg blocks in Sage 11

**Default pattern: dynamic block, React editor, server-rendered Blade front end.** This satisfies all
constraints at once — native WP APIs, rich back-end editing, no React shipped to visitors, semantic +
schema-ready markup generated in Blade/Tailwind.

```
Editor (back end):  React edit.js  → InspectorControls, RichText, MediaUpload
Storage:            attributes in block.json (typed, documented), save: () => null
Front end:          render_callback → \Roots\view('blocks.{name}', $data) → Blade + Tailwind
```

## Scaffolding

Two routes. Prefer the package on Sage 11 for correct wiring; hand-roll when you need full control.

**Option A — `imagewize/sage-native-block` (Sage 11+ Acorn package):**
```bash
composer require imagewize/sage-native-block --dev
wp acorn sage-native-block:add <namespace>/<block-name>
```
It scaffolds `block.json`, `index.js`, `edit.jsx`, `save.jsx`, CSS, and adds registration to setup.
After scaffolding, **convert to dynamic** (set `save` to return `null`, add a `render_callback` that
delegates to Blade) unless a static block is genuinely the right call (see bottom).

**Option B — hand-rolled** (structure below). Use when the package's templates don't fit.

## File layout (hand-rolled, dynamic)

```
resources/js/blocks/hero/
├── block.json
├── index.js          # registerBlockType, imports edit
└── edit.jsx          # editor UI
resources/views/blocks/hero.blade.php   # front-end + editor preview markup (server)
app/Blocks/Hero.php   # (optional) registration + render_callback, or do it in setup.php
```

### block.json (apiVersion 3)
```json
{
  "$schema": "https://schemas.wp.org/trunk/block.json",
  "apiVersion": 3,
  "name": "sage/hero",
  "title": "Hero",
  "category": "theme",
  "icon": "cover-image",
  "description": "Full-width hero with heading, subheading, CTA and background image.",
  "keywords": ["hero", "header", "intro"],
  "supports": { "html": false, "align": ["full"], "anchor": true },
  "attributes": {
    "heading":   { "type": "string", "source": "html", "selector": "h1" },
    "subheading":{ "type": "string" },
    "ctaLabel":  { "type": "string" },
    "ctaUrl":    { "type": "string" },
    "imageId":   { "type": "number" },
    "imageUrl":  { "type": "string" }
  },
  "editorScript": "file:./index.js",
  "render": "file:./render.php"
}
```
You can use either `"render": "file:./render.php"` (WP 6.1+ native) **or** a PHP `render_callback`
passed to `register_block_type`. With Sage, the cleanest is a thin `render.php`/callback that hands off
to Blade so all markup lives in one place.

### Registration + Blade hand-off
```php
// app/setup.php (or app/Blocks/Hero.php booted from a provider)
add_action('init', function () {
    register_block_type(get_theme_file_path('resources/js/blocks/hero'), [
        'render_callback' => function (array $attributes, string $content, $block) {
            return \Roots\view('blocks.hero', [
                'a'       => $attributes,
                'content' => $content,
                'block'   => $block,
            ])->render();
        },
    ]);
});
```

### edit.jsx — the back-end editing experience (the "ben editabile" requirement)
```jsx
import { __ } from '@wordpress/i18n';
import {
  useBlockProps, RichText, InspectorControls,
  MediaUpload, MediaUploadCheck, URLInputButton,
} from '@wordpress/block-editor';
import { PanelBody, Button } from '@wordpress/components';

export default function Edit({ attributes, setAttributes }) {
  const { heading, subheading, ctaLabel, ctaUrl, imageUrl } = attributes;
  const blockProps = useBlockProps({ className: 'relative isolate bg-ink text-paper p-12' });

  return (
    <>
      <InspectorControls>
        <PanelBody title={__('Background', 'sage')}>
          <MediaUploadCheck>
            <MediaUpload
              onSelect={(m) => setAttributes({ imageId: m.id, imageUrl: m.url })}
              allowedTypes={['image']}
              render={({ open }) => (
                <Button variant="secondary" onClick={open}>
                  {imageUrl ? __('Replace image', 'sage') : __('Select image', 'sage')}
                </Button>
              )}
            />
          </MediaUploadCheck>
        </PanelBody>
      </InspectorControls>

      <div {...blockProps}>
        <RichText tagName="h1" className="text-h1 font-bold"
          value={heading} onChange={(v) => setAttributes({ heading: v })}
          placeholder={__('Hero heading…', 'sage')} />
        <RichText tagName="p" className="mt-4 text-lg"
          value={subheading} onChange={(v) => setAttributes({ subheading: v })}
          placeholder={__('Subheading…', 'sage')} />
        <div className="mt-6 flex items-center gap-3">
          <RichText tagName="span" className="font-medium"
            value={ctaLabel} onChange={(v) => setAttributes({ ctaLabel: v })}
            placeholder={__('CTA label', 'sage')} />
          <URLInputButton url={ctaUrl} onChange={(url) => setAttributes({ ctaUrl: url })} />
        </div>
      </div>
    </>
  );
}
```

### index.js
```js
import { registerBlockType } from '@wordpress/blocks';
import metadata from './block.json';
import Edit from './edit';

registerBlockType(metadata.name, { edit: Edit, save: () => null });
```
Import each block's `index.js` from `resources/js/editor.js` so Vite bundles it into the editor entry.

### Blade front-end view (semantic + schema-aware)
```blade
{{-- resources/views/blocks/hero.blade.php --}}
@php($a = $a ?? [])
<section @if(!empty($a['anchor'])) id="{{ $a['anchor'] }}" @endif
         class="relative isolate bg-ink text-paper p-12"
         aria-label="{{ $a['heading'] ?? 'Hero' }}">
    @if(!empty($a['imageUrl']))
        <img src="{{ $a['imageUrl'] }}" alt="" class="absolute inset-0 -z-10 h-full w-full object-cover" loading="eager" />
    @endif
    @if(!empty($a['heading']))<h1 class="text-h1 font-bold">{!! $a['heading'] !!}</h1>@endif
    @if(!empty($a['subheading']))<p class="mt-4 text-lg">{!! $a['subheading'] !!}</p>@endif
    @if(!empty($a['ctaLabel']) && !empty($a['ctaUrl']))
        <a href="{{ $a['ctaUrl'] }}" class="mt-6 inline-block rounded-card bg-accent px-5 py-3 font-medium text-ink">
            {!! $a['ctaLabel'] !!}
        </a>
    @endif
</section>
```

## Documentation conventions (the "ben documentato" requirement)
Every block ships with:
- A clear `title`, `description`, and `keywords` in `block.json` (this is what editors see).
- An **attributes table** in a per-block `README.md` (or a `@docs` comment block): name, type, source,
  what it controls, default.
- Sensible `supports` (lock down `html`, constrain `align`) so editors can't break the layout.
- A preview that matches the front end (the Blade markup and the `edit.jsx` markup should visually agree).

## Editor styling
Tailwind classes used in `edit.jsx` need the editor stylesheet. Put editor-applicable styles in
`resources/css/editor.css` (enqueued for the block editor) so the in-editor preview matches the front
end. Keep `app.css` for the front end.

## When to use a STATIC block instead
Use `save()` returning markup (no `render_callback`) only when **all** of these hold: content is purely
static, needs no server-side/dynamic data, no JSON-LD to compute server-side, and the client benefits
from markup frozen into `post_content` (survives theme removal). Otherwise prefer dynamic — it's better
for restyling, dynamic data, and server-rendered schema. Never mix: pick per block and document it.

## Common pitfalls
- Editor throws `wp is not defined` / missing deps → `wordpressPlugin()` isn't externalizing or
  `editor.deps.json` isn't being read on enqueue. Check `vite.config.js` and the editor enqueue in setup.
- Block not iframed / styles off → ensure apiVersion 3 and that `editor.css` is injected into the editor.
- Don't register CPTs or business queries here — that's mu-plugin territory (`references/mu-plugins.md`).