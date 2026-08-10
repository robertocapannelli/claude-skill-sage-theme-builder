# Custom mu-plugin for functionality

All non-presentation logic lives in a project mu-plugin, never in the theme. This keeps the theme
swappable and the content model stable.

## Why mu-plugin (vs regular plugin)
- **Always active** — can't be accidentally deactivated by a client, and survives theme switches.
- Right home for the **content model** (CPTs, taxonomies) and **business logic** the site depends on.
- Trade-off: mu-plugins don't show update/deactivate UI and the loader auto-includes only PHP files in
  the mu-plugins **root**. For anything with structure (classes, assets), use a **loader file +
  subdirectory** pattern below. If the client needs to toggle it, a regular plugin is acceptable — but
  the boundary rule (no logic in the theme) is the non-negotiable part.

## Loader + subdirectory pattern
```
wp-content/mu-plugins/
├── <project>-core.php         # loader (lives in root so WP auto-includes it)
└── <project>-core/            # the actual plugin code
    ├── plugin.php
    └── src/
        ├── PostTypes/
        ├── Taxonomies/
        ├── Rest/
        └── Services/
```

```php
// wp-content/mu-plugins/<project>-core.php
<?php
/* Loader for <project> core mu-plugin */
require_once __DIR__ . '/<project>-core/plugin.php';
```

## Register a CPT (content model → mu-plugin, NOT theme)
```php
// <project>-core/src/PostTypes/Product.php

// Load the textdomain BEFORE anything registers labels: register_post_type() freezes them at
// registration time, so an untranslated __() there stays untranslated forever.
add_action('init', fn () => load_muplugin_textdomain('mytheme', 'lang'), -10);

add_action('init', function () {
    register_post_type('product', [
        'labels'       => ['name' => __('Products', 'mytheme'), 'singular_name' => __('Product', 'mytheme')],
        'public'       => true,
        'has_archive'  => true,
        'show_in_rest' => true,          // editable in the block editor / queryable via REST
        'supports'     => ['title', 'editor', 'thumbnail', 'excerpt', 'custom-fields'],
        'rewrite'      => ['slug' => 'products'],
    ]);

    mytheme_register_product_meta();     // a NAMED function — see post-meta-and-settings.md
}, 0);
```

⚠️ `custom-fields` in `supports` is not optional when the type has meta edited from the block editor:
it is what puts `meta` in the REST schema. Without it every sidebar field is discarded on save,
silently. Full explanation, sanitization patterns, repeaters and the native settings page:
**`post-meta-and-settings.md`**.

## Custom REST endpoint (data a block/template consumes)
```php
add_action('rest_api_init', function () {
    register_rest_route('<project>/v1', '/featured', [
        'methods'             => 'GET',
        'permission_callback' => '__return_true',
        'callback'            => fn () => array_map(
            fn ($p) => ['id' => $p->ID, 'title' => get_the_title($p), 'url' => get_permalink($p)],
            get_posts(['post_type' => 'product', 'posts_per_page' => 6])
        ),
    ]);
});
```

The theme then **consumes** this — a block's `render_callback`/View Composer calls a service or the
endpoint and passes plain data to Blade. The view never queries.

## What belongs here
CPTs, taxonomies, meta registration tied to the content model, REST routes, WP-CLI commands, cron jobs,
third-party API clients, webhooks, e-commerce/business rules, integrations. Anything that answers "this
must keep working if the theme changes" with *yes*.

## Key names are a contract

Renaming an option or meta key does not clear a field — it **orphans the value silently**. The data
stays in the database under the old name, the admin screen looks empty, and every reader (templates,
the schema graph, composers) stops finding it with no error at all. Treat a rename as a migration
(`content-migrations.md`), and only ever do it when the *format* changed too.

## What does NOT belong here
Markup, Blade, Tailwind, block edit components, `theme.json`/tokens, asset enqueuing for theme styling.
That's all theme.