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

Tailwind v4 is configured in CSS. Put the system in `resources/css/app.css`:

```css
@import "tailwindcss";

@theme {
  /* Colors — become bg-brand, text-brand, and theme.json palette entries */
  --color-brand: #1e3a8a;
  --color-accent: #f59e0b;
  --color-ink: #0f172a;
  --color-paper: #ffffff;

  /* Type scale */
  --font-sans: "Inter", ui-sans-serif, system-ui, sans-serif;
  --text-h1: 3rem;
  --text-h1--line-height: 1.1;

  /* Spacing / radii / breakpoints as needed */
  --radius-card: 0.75rem;
}
```

Because Sage runs `wordpressThemeJson()` on build, these tokens are mapped into the generated
`theme.json` — so the **block editor color picker, font sizes, and font families match the design
automatically**. Verify mapping flags in `vite.config.js` (`disableTailwindColors`, `...Fonts`,
`...FontSizes`) are `false` unless you have a reason.

Naming: name tokens **semantically** (`--color-brand`, `--color-surface`) not literally
(`--color-blue-700`), so the editor exposes meaningful choices and re-skinning is trivial.

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