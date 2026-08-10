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

```php
<?php
// inside resources/blocks/faq/render.php — the block's schema travels with the block
$schema = [];

foreach ($items as $item) {
    if (empty($item['q'])) {
        continue;                       // the same predicate the accordion uses: they must agree
    }

    $schema[] = [
        '@type'          => 'Question',
        'name'           => wp_strip_all_tags($item['q']),
        'acceptedAnswer' => ['@type' => 'Answer', 'text' => wp_strip_all_tags($item['a'] ?? '')],
    ];
}
?>
<?php if ($schema) : ?>
  <script type="application/ld+json"><?= wp_json_encode(
      ['@context' => 'https://schema.org', '@type' => 'FAQPage', 'mainEntity' => $schema],
      JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE
  ) ?></script>
<?php endif; ?>
```

Always sanitize dynamic values (`wp_strip_all_tags`, `esc_url`) and encode with `wp_json_encode`.

**Emit nothing rather than something invalid.** If a node's required properties are missing, skip the
node: an invalid node in Search Console is worse than an absent one. Real example: Google rejects a
`JobPosting` that says neither where the work happens nor that it is remote — so fall back to the
organisation's address, and if that is missing too, do not emit the node at all. The same reasoning
applies to a `Product` without an offer, an `Article` without a date, an FAQ with no complete pair.

Validate dates and enums in the **`sanitize_callback`** of the meta they come from
(`post-meta-and-settings.md`), not in the template — by render time it is too late to do anything but
drop the node.

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
### `llms.txt` — the pattern

A plain-text map of the site for LLM crawlers (emerging convention, not a standard). Worth shipping,
and cheap:

- Serve `/llms.txt` (an index) and `/llms-full.txt` (the content) from a **mu-plugin** with a rewrite
  rule, so it survives a theme switch.
- Generate from the real content, cache in a transient, invalidate on `save_post`.
- Open `robots.txt` to the AI crawlers you want to allow, in the same place.
- ⚠️ **This is the worst place to bypass a canonical accessor.** A value the site is not supposed to
  expose — a client under NDA, a draft price — leaks here precisely because the file is explicitly
  opened to crawlers. Every read goes through the one method that owns the rule
  (`plugin-interop.md`), guarded with `class_exists()` when the method lives in the theme.

## Verify
Run rendered pages through a structured-data validator. Confirm the graph is complete and valid, nodes
are connected by `@id`, and required properties are present. If an SEO plugin is active, sanity-check
that duplicated nodes don't disagree.