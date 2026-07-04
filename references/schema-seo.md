# Schema.org, SEO & LLM-readiness

**The theme is independent (principle 0) but not an SEO plugin.** It splits responsibility cleanly:

- **Title / meta description / canonical / OG-Twitter → NOT owned by the theme.** Left to WordPress
  (`add_theme_support('title-tag')`) and whatever SEO plugin the site uses. This lets an external
  plugin (Yoast, Rank Math, …) manage them — a *capability*, not a dependency. With no plugin, WP's
  title tag still works.
- **schema.org JSON-LD → always owned and emitted by the theme**, unconditionally and completely.
  Duplication with an SEO plugin's own schema is accepted by design. A `theme/seo/emit_schema` filter
  lets a project switch it off if ever needed.

## Title / description (defer, don't own)
```php
// app/setup.php
add_action('after_setup_theme', function () {
    add_theme_support('title-tag');   // WP (or an SEO plugin) owns <title>
});
```
Do **not** print `<title>`, meta description, canonical, or OG/Twitter tags from the theme. If a site
has no SEO plugin and the client wants meta descriptions, add them via a small **mu-plugin**, not the
theme — keeps the theme purely presentational and lets the plugin layer remain swappable.

## schema.org (always emit, full graph)
```php
// Emitted unconditionally — duplication with an SEO plugin is acceptable per project decision.
add_action('wp_head', function () {
    if (! apply_filters('theme/seo/emit_schema', true)) {
        return;
    }

    $graph = [
        theme_schema_organization(),
        theme_schema_website(),
        theme_schema_breadcrumbs(),
    ];

    if (is_singular('product')) {
        $graph[] = theme_schema_product(get_queried_object());
    } elseif (is_singular('post')) {
        $graph[] = theme_schema_article(get_queried_object());
    }

    $graph = array_values(array_filter($graph));

    printf(
        '<script type="application/ld+json">%s</script>',
        wp_json_encode(
            ['@context' => 'https://schema.org', '@graph' => $graph],
            JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE
        )
    );
}, 5);
```

Build each node as a small, testable function. Reference nodes by `@id` so the graph is connected
(e.g. an `Article` points to the `Organization` as `publisher`, the `WebPage` as `isPartOf` the
`WebSite`). Example node:

```php
function theme_schema_organization(): array
{
    return [
        '@type' => 'Organization',
        '@id'   => home_url('/#organization'),
        'name'  => get_bloginfo('name'),
        'url'   => home_url('/'),
        'logo'  => ['@type' => 'ImageObject', 'url' => theme_logo_url()],
    ];
}
```

## Where each schema piece lives
- **Site-level** (`Organization`, `WebSite`) → theme (default). Can move to a mu-plugin if it must
  survive a theme switch.
- **Template-level** (`WebPage`, `BreadcrumbList`, `Article`, `Product`) → View Composer / template.
- **Block-level** (`FAQPage` from an FAQ block, `HowTo` from a steps block) → emitted by the block's
  Blade view, so schema travels with the block.

```blade
{{-- inside an FAQ block Blade view --}}
@php
  $ld = [
    '@context' => 'https://schema.org',
    '@type'    => 'FAQPage',
    'mainEntity' => collect($items)->map(fn ($i) => [
      '@type' => 'Question',
      'name'  => wp_strip_all_tags($i['q']),
      'acceptedAnswer' => ['@type' => 'Answer', 'text' => wp_strip_all_tags($i['a'])],
    ])->all(),
  ];
@endphp
<script type="application/ld+json">{!! wp_json_encode($ld, JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE) !!}</script>
```

Always sanitize dynamic values (`wp_strip_all_tags`, `esc_url`) and encode with `wp_json_encode`.

## Type cheat-sheet (match to the project)
- E-commerce / product pages → `Product` + `Offer` (+ `AggregateRating`, `Review` if present).
- Local business / agency site → `LocalBusiness` (or subtype) with address, geo, openingHours.
- Services → `Service` / `ProfessionalService`.
- Blog / editorial → `Article`.
- Navigation → `BreadcrumbList`.
- FAQ / How-to sections → `FAQPage` / `HowTo` (block-level).

## Note on duplication (accepted, with a caveat)
Emitting schema unconditionally can mean two `Organization`/`Article` nodes when an SEO plugin is also
active. This is accepted by project decision. Be aware it can surface Rich Results warnings or split
signals if the two graphs disagree; keep the theme's node data consistent with the plugin's, and use
the `theme/seo/emit_schema` filter to disable the theme graph on sites where the plugin should win.

## Semantic HTML rules (the "always coherent structure" requirement)
- One `<h1>` per page; no skipped heading levels.
- Landmarks: `header`, `nav` (with `aria-label`), `main`, `article`, `aside`, `footer`.
- Lists are lists; buttons are `<button>`, links are `<a>`; images have meaningful `alt` (empty for
  decorative). Time values in `<time datetime>`.
- This semantic skeleton is what both crawlers and LLMs parse — not optional polish.

## Performance & LLM-readiness
- Server-rendered Blade (done), no front-end React (done), responsive images (`srcset`/`sizes`,
  `loading="lazy"` below the fold), preload the LCP image, minimal CSS/JS.
- **`llms.txt`** (optional): a plain-text map of key pages at site root can help LLM crawlers. Emit it
  from the theme or a mu-plugin route. Emerging convention, not a standard — nice-to-have.

## Verify
Run rendered pages through a structured-data validator. Confirm the graph is complete and valid, nodes
are connected by `@id`, and required properties are present. If an SEO plugin is active, sanity-check
that duplicated nodes don't disagree.