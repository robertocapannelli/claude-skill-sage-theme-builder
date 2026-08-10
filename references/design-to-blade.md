# Design → tokens → Blade

The goal is **faithful** reproduction: pixel-accurate where it matters, but expressed as a reusable
token + component system, not one-off markup.

## 1. Read the design

**Figma link → use the Figma MCP** (don't ask the user to export screenshots you can fetch yourself):
- `get_design_context` for structure, layers, auto-layout, spacing, and styles of a node.
- `get_variable_defs` to pull design variables (colors, type, spacing) — these map almost 1:1 to
  Tailwind `@theme` tokens.
- `get_screenshot` for visual reference while building.
Work node-by-node (section → component), not the whole file at once.

**HTML/CSS files →** read them directly; extract the implicit design system (recurring colors, font
sizes, spacing rhythm) before porting. Treat inline/utility soup as a thing to *normalize* into tokens,
not copy verbatim.

**Static images →** infer the system; state assumptions (e.g. "I read the body scale as 16/18/20px").

## 2. Encode design tokens (Tailwind v4, CSS-first)

Tailwind v4 is configured in CSS — there is normally no `tailwind.config.js`. The entry is six lines:

```css
/* resources/css/app.css */
@import "tailwindcss" theme(static);
@import "./tokens.css";
@source "../../app/**/*.php";
@source "../**/*.blade.php";
@source "../**/*.js";
@source "../blocks/**/*.php";
```

```css
/* resources/css/tokens.css — single source of truth */
@theme static {
  /* Colors — become bg-brand / text-brand AND theme.json palette entries */
  --color-brand: #1e3a8a;
  --color-accent: #f59e0b;
  --color-ink: #0f172a;
  --color-paper: #ffffff;

  /* Type */
  --font-sans: "Inter", ui-sans-serif, system-ui, sans-serif;
  --font-mono: "IBM Plex Mono", ui-monospace, monospace;
  --text-h1: 3rem;
  --text-h1--line-height: 1.1;

  /* Layout / motion */
  --container-site: 1280px;                     /* → max-w-site */
  --radius-card: 0.75rem;                       /* → rounded-card */
  --ease-brand: cubic-bezier(0.2, 0.7, 0.2, 1); /* → ease-brand */
}
```

Four things there are load-bearing on WordPress:

- **Tokens in their own file**, imported by the entry, so both bundles and `wordpressThemeJson()` read
  one source instead of a copy.
- ⚠️ **`theme(static)` / `@theme static` is required.** HTML written by an editor — a
  `<span class="text-accent">` typed into a block's *Title (HTML)* field — lives inside the block's
  serialized attributes, which Tailwind never scans. Without `static` that utility is never generated
  and the class silently does nothing. This is the single most common "why isn't my class working"
  on this stack.
- ⚠️ **`@source` must name the PHP.** Tailwind v4's auto-detection does not walk into `app/**/*.php` or
  `resources/blocks/**/*.php`, which is exactly where the block markup lives.
- **Semantic names, and names that read as utilities.** `--color-brand`, not `--color-blue-700`;
  `--container-site` because it becomes `max-w-site`. The editor exposes these choices to authors, so
  they are UI copy as much as code.

Because Sage runs `wordpressThemeJson()` on build, these tokens land in the generated `theme.json` —
the block editor's colour picker, font sizes and font families match the design with no extra work.
Verify the mapping flags in `vite.config.js` (`disableTailwindColors`, `...Fonts`, `...FontSizes`,
`...BorderRadius`) are `false` unless you have a reason.

In the **source** `theme.json`, turn off every *default* and *custom* palette and size, so the only
choices in the editor are your tokens:

```json
"settings": {
  "layout": { "contentSize": "48rem" },
  "color": { "custom": false, "defaultPalette": false, "defaultGradients": false, "duotone": [] },
  "typography": { "defaultFontSizes": false, "customFontSize": false }
}
```

### Layer order is a correctness concern, not style

`app.css` reads: `@font-face` → `@layer base` → `@layer utilities` → unlayered component/prose rules.
Remember that **anything unlayered beats every layered rule**, regardless of specificity — that is the
cascade-layers spec. It is why prose rules can legitimately override utilities inside `.entry-content`,
and it is also the mechanism behind the invisible-CTA bug in `block-editor-parity.md`. When you write
an override, decide deliberately whether it belongs in a layer.

### Fonts: self-hosted

```css
@font-face {
  font-family: 'Inter';
  font-style: normal;
  font-weight: 400 800;             /* one variable file covers the range */
  font-display: swap;
  src: url('../fonts/inter-var-latin.woff2') format('woff2');
  unicode-range: U+0000-00FF, U+0131, U+0152-0153, …;
}
```

- **Relative URLs** (`../fonts/…`): Vite fingerprints the files and copies them into the build. An
  absolute URL breaks that.
- Only the subsets the site needs, each with its `unicode-range`, so the browser fetches `latin-ext`
  only on pages that require it.
- Two reasons, both non-negotiable in Europe: a Google Fonts URL sends every visitor's IP to a third
  party before any consent, bypassing whatever consent layer the site has; and it costs two
  render-blocking requests to another origin.
- Check the licence (SIL OFL allows self-hosting). To regenerate, fetch the Google Fonts CSS with a
  modern User-Agent — with an old one the API returns `.ttf` instead of `.woff2` — and take the
  `woff2` URLs of the subsets you want along with their `unicode-range` declarations.

## 3. Decompose into Blade components

Map each repeating UI unit to a component in `resources/views/components/`:

```blade
{{-- resources/views/components/card.blade.php --}}
@props(['title', 'href' => null, 'eyebrow' => null])

<article {{ $attributes->merge(['class' => 'rounded-card bg-paper p-6 shadow-sm']) }}>
    @isset($eyebrow)
        <p class="text-sm font-medium text-accent">{{ $eyebrow }}</p>
    @endisset
    <h3 class="mt-2 text-xl font-semibold text-ink">
        @isset($href)<a href="{{ $href }}" class="hover:underline">{{ $title }}</a>@else{{ $title }}@endisset
    </h3>
    <div class="mt-3 text-ink/80">{{ $slot }}</div>
</article>
```

Used as `<x-card title="..." eyebrow="..." :href="$url">…</x-card>`.

Rules:
- **Semantic landmarks**: `header`, `nav`, `main`, `section` (with an accessible name), `article`,
  `footer`. This is half of the "SEO/LLM-friendly" requirement.
- **No data fetching in views.** If a component needs data, prepare it in a **View Composer**:

```php
// app/View/Composers/FeaturedPosts.php
namespace App\View\Composers;

use Roots\Acorn\View\Composer;

class FeaturedPosts extends Composer
{
    protected static $views = ['partials.featured-posts'];

    public function with(): array
    {
        return ['posts' => get_posts(['posts_per_page' => 3])];
    }
}
```

- One component = one responsibility. Build the smallest set that reconstructs the whole design.

## 4. Faithfulness checklist
- Spacing/typography read from tokens, not magic numbers.
- States covered (hover/focus/active, empty, long-text overflow).
- Responsive: match the design's breakpoints; mobile-first utilities.
- Accessibility: contrast from tokens, focus-visible styles, alt text slots, semantic headings.