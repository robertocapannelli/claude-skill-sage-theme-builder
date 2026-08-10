# Templates: archives, singles & 404

Archives and single views are **Blade templates, not blocks**. Blocks are for editorial page content;
listing and detail views are structural and belong in the template hierarchy.

## Archives (always Blade)

Every queryable content type gets an archive rendered from a Blade template
(`archive-{post_type}.blade.php`, `taxonomy-{taxonomy}.blade.php`, `archive.blade.php` fallback).

- The listing loops the query and renders each item through a shared card component
  (`<x-card>` / `<x-{type}-card>`), so archive and any home carousel of the same type look identical.
- **Taxonomy archives may show an optional description**: render `term_description()` when present,
  skip cleanly when empty.
- Pagination, empty-state ("no results"), and semantic markup (`<main>`, list semantics) are required.

```blade
{{-- resources/views/taxonomy-category.blade.php --}}
@extends('layouts.app')
@section('content')
  <main>
    <header>
      <h1>{{ single_term_title('', false) }}</h1>
      @if (term_description())
        <div class="prose mt-2">{!! wp_kses_post(term_description()) !!}</div>
      @endif
    </header>

    @if (! have_posts())
      <p>{{ __('Nothing here yet.', 'sage') }}</p>
    @endif

    <ul class="grid gap-6 md:grid-cols-3">
      @while (have_posts()) @php(the_post())
        <li><x-post-card :title="get_the_title()" :href="get_permalink()" /></li>
      @endwhile
    </ul>

    {!! get_the_posts_pagination() !!}
  </main>
@endsection
```

## Singles (always Blade)

**Every archive has a matching single** (`single-{post_type}.blade.php`), also Blade — not block-driven.
The design decides which fields are dynamic; typically: **title, description/content, taxonomies, and an
optional image**. Prepare the data in a View Composer; keep the Blade dumb.

```blade
{{-- resources/views/single-product.blade.php --}}
@extends('layouts.app')
@section('content')
  <main>
    <article>
      <h1>{{ get_the_title() }}</h1>
      @if ($featuredImage)
        <img src="{{ $featuredImage }}" alt="{{ get_the_title() }}" class="w-full rounded-card" loading="eager">
      @endif
      @if ($terms)
        <ul class="mt-3 flex flex-wrap gap-2">
          @foreach ($terms as $term)
            <li><a href="{{ get_term_link($term) }}" class="text-sm text-accent">{{ $term->name }}</a></li>
          @endforeach
        </ul>
      @endif
      <div class="prose mt-6">{!! wp_kses_post(get_the_content()) !!}</div>
    </article>
  </main>
@endsection
```

Fields that don't exist for a given post are omitted, never rendered empty.

## Home lists come from the real archive, not a static block

When the homepage shows a list derived from an archive (latest news carousel, featured products), it
uses a **dynamic display block that loops the actual CPT** — see the "display block" pattern in
`native-blocks.md`. The content is **not editable inside the block**: it's edited only in its post type.
The block exposes presentation controls at most (how many to show, which category), never the item copy.
This guarantees one source of truth and no divergence between the home teaser and the archive.

## Composed pages vs prose pages

A page template must decide which of two things it is rendering, because the two need opposite
treatment:

```blade
{{-- resources/views/page.blade.php --}}
@php($isComposed = collect(parse_blocks(get_the_content()))
        ->contains(fn ($b) => str_starts_with((string) ($b['blockName'] ?? ''), 'mytheme/')))

@if ($isComposed)
    @php(the_content())                        {{-- sections are full-bleed and cap themselves --}}
@else
    <article class="mx-auto max-w-3xl">
        <div class="entry-content">@php(the_content())</div>
    </article>
@endif
```

That wrapper is what keeps the ~100 prose rules (`.entry-content h2`, lists, quotes, links) away from
your sections — without it, a prose link rule will happily repaint a CTA inside a hero. The block
editor has no equivalent separation and needs the JS counterpart described in
`block-editor-parity.md`.

## 404 (always present)

Ship a `404.blade.php`. Its **tone adapts to the site's sector/brand** — the skill infers it from the
design and industry, it does not hardcode jokes. A playful line fits a consumer brand; a sober,
helpful message fits a law firm or a funeral service. Regardless of tone, a 404 must:

- Explain the page wasn't found, in the site's voice.
- Offer a way forward: link home, a search field, and/or key sections.
- Keep the theme's header/footer and styling (it's a real page, not a bare error).
