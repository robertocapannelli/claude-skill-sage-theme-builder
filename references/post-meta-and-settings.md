# Post meta, sidebar panels & settings pages — without ACF

Everything ACF Pro was reached for — typed meta, repeaters, an options page — has a native equivalent
that ships with WordPress and costs no plugin dependency. This file is the end-to-end recipe. It all
lives in the **mu-plugin** (content model), never the theme.

## The three-part wiring, and the trap in it

⚠️ **`register_post_meta(..., ['show_in_rest' => true])` is not enough: the post type must declare
`custom-fields` in `supports`.** That support is what adds the `meta` property to the type's REST
schema. Without it, `useEntityProp('postType', …, 'meta')` reads `undefined`, and **every field typed
in the sidebar panel is discarded on save, silently** — no error, no console warning, and the front
end keeps showing the old values because `get_post_meta()` reads the database, not REST.

All three, always:

```php
register_post_type('book', [
    'public'       => true,
    'show_in_rest' => true,                                   // 1. type is REST-visible
    'supports'     => ['title', 'editor', 'custom-fields'],   // 2. type exposes `meta` in its schema
]);

register_post_meta('book', 'mytheme_isbn', [
    'type'         => 'string',
    'single'       => true,
    'default'      => '',
    'show_in_rest' => true,                                   // 3. this key is REST-visible
    'sanitize_callback' => 'sanitize_text_field',
    'auth_callback'     => fn ($allowed, $key, $post_id) => current_user_can('edit_post', $post_id),
]);
```

One-line diagnosis when a panel silently loses its values:

```bash
wp eval 'print_r(rest_do_request(new WP_REST_Request("OPTIONS","/wp/v2/book"))->get_data()["schema"]["properties"]["meta"] ?? "MISSING");'
```

`MISSING` → `custom-fields` is absent. Assert it in an integration test; it is a one-word regression
that costs an afternoon.

Note the `auth_callback` signature: `($allowed, $meta_key, $post_id, $user_id, $cap, $caps)`. A
zero-argument closure works by accident but throws away the post id — `current_user_can('edit_post',
$post_id)` is the correct check.

## Sanitization is where validation lives

The `sanitize_callback` is not a formality — it is the only place a bad value can be stopped before it
reaches a template. Pick it per key rather than defaulting everything to `sanitize_text_field`:

```php
'sanitize_callback' => match ($key) {
    'mytheme_cta_url'  => 'esc_url_raw',
    'mytheme_cta_text' => 'sanitize_textarea_field',   // sanitize_text_field() eats newlines
    default            => 'sanitize_text_field',
},
```

Enums and dates should **reject**, not pass through:

```php
// enum
'sanitize_callback' => fn ($v) => in_array($v, ['open', 'closed'], true) ? $v : 'open',

// a date that must exist in the calendar — '2027-02-31' round-trips wrong through strtotime()
'sanitize_callback' => function ($value) {
    $value = trim((string) $value);
    $date  = \DateTimeImmutable::createFromFormat('!Y-m-d', $value);

    return ($date && $date->format('Y-m-d') === $value) ? $value : '';
},
```

## Repeaters: one array meta with a full JSON schema

An ACF repeater becomes **one array meta**. Order is array order; there are no `field_xxxxx` keys and
no shadow `_meta` rows, and it works over REST for free.

```php
register_post_meta('project', 'mytheme_stats', [
    'type'          => 'array',
    'single'        => true,
    'default'       => [],
    'auth_callback' => $auth,
    'show_in_rest'  => [
        'schema' => [
            'type'  => 'array',
            'items' => [
                'type'       => 'object',
                'properties' => [
                    'value'  => ['type' => 'number'],
                    'suffix' => ['type' => 'string'],
                    'label'  => ['type' => 'string'],
                ],
            ],
        ],
    ],
]);
```

`show_in_rest` must be an **array carrying an explicit `schema`** — REST refuses array/object meta
without one. Typing `value` as `number` is doing real work: it stops the class of bug where a caption
saved without its digits later fatals a template that does arithmetic on it.

## Named functions, not closures, on hooks a test must replay

```php
// A named function rather than an inline block: wp-phpunit's tear_down() calls
// unregister_all_meta_keys(), so from the second test on, every registration made on `init` is gone.
// Re-firing the whole `init` hook to get them back would also re-register the blocks and trip
// _doing_it_wrong().
function mytheme_register_book_meta(): void { /* … */ }

add_action('init', function () {
    mytheme_register_book_meta();
    // … post types, taxonomies
}, 0);
```

Load the textdomain **before** registration (`priority < 0`): `register_post_type()` freezes its
labels at registration time, so an untranslated `__()` there stays untranslated forever.

```php
add_action('init', fn () => load_muplugin_textdomain('mytheme', 'lang'), -10);
```

## Sidebar panels

```js
// resources/js/editor.js — Vite/esbuild, so createElement rather than JSX
import { createElement as el } from '@wordpress/element';
import { registerPlugin } from '@wordpress/plugins';
import { PluginDocumentSettingPanel, store as editorStore } from '@wordpress/editor';
import { useSelect } from '@wordpress/data';
import { useEntityProp } from '@wordpress/core-data';
import { TextControl, Button, Flex } from '@wordpress/components';
import { __ } from '@wordpress/i18n';

function BookPanel() {
    const postType = useSelect((select) => select(editorStore).getCurrentPostType(), []);
    const [meta, setMeta] = useEntityProp('postType', 'book', 'meta');

    if (postType !== 'book') return null;      // guard AFTER every hook, never before

    const m   = meta || {};
    const set = (key) => (value) => setMeta({ ...m, [key]: value });   // spread the whole bag

    return el(PluginDocumentSettingPanel,
        { name: 'mytheme-book', title: __('Book details', 'sage'), className: 'mytheme-panel' },
        el(TextControl, {
            __nextHasNoMarginBottom: true,
            label: __('ISBN', 'sage'),
            value: m.mytheme_isbn || '',
            onChange: set('mytheme_isbn'),
        }),
    );
}

registerPlugin('mytheme-book-panel', { render: BookPanel });
```

Non-negotiables in that shape:

- **Hooks first, guard second.** `if (postType !== …) return null` before a `useEntityProp` call is a
  hooks-order violation that breaks as soon as the user switches post types.
- **`setMeta` always with a fresh spread of the whole meta bag.** `setMeta({ one: v })` drops every
  other queued field — a bug that looks exactly like "the other field doesn't save".
- One panel per post type, each `registerPlugin`'d separately.

Repeater UI inside a panel:

```js
const rows    = Array.isArray(m.mytheme_stats) ? m.mytheme_stats : [];
const setRows = (next) => setMeta({ ...m, mytheme_stats: next });
const update  = (i, key, value) => setRows(rows.map((r, j) => (j === i ? { ...r, [key]: value } : r)));
const move    = (from, to) => {
    if (to < 0 || to >= rows.length) return;
    const next = [...rows];
    const [row] = next.splice(from, 1);
    next.splice(to, 0, row);
    setRows(next);
};
// numeric fields coerced client-side to match the REST schema type
onChange: (v) => update(i, 'value', parseFloat(v) || 0),
```

Reorder with ↑/↓ buttons rather than drag handles: keyboard reachable, no dependency. Cap the row
count by hiding the *Add* button rather than by erroring after the fact.

## A native settings page (replacing an ACF options page)

Pure Settings API, no dependencies. Declare the fields once as data, render them with one generic
callback:

```php
add_action('admin_menu', function () {
    add_options_page(
        __('Theme Settings', 'mytheme'), __('Theme Settings', 'mytheme'),
        'manage_options', 'mytheme-settings', 'mytheme_settings_render_page'
    );
});

add_action('admin_init', function () {
    foreach (mytheme_settings_fields() as $field) {
        register_setting('mytheme_options', $field['name'], [
            'type'              => 'string',
            'sanitize_callback' => $field['sanitize'] ?? 'sanitize_text_field',
        ]);
    }

    add_settings_section('mytheme_contact', __('Contacts', 'mytheme'), '__return_false', 'mytheme-settings');

    foreach (mytheme_settings_fields() as $field) {
        add_settings_field(
            $field['name'], $field['label'], 'mytheme_settings_render_field',
            'mytheme-settings', $field['section'], $field      // $field arrives as $args
        );
    }
});
```

```php
function mytheme_settings_render_page(): void { ?>
    <div class="wrap">
        <h1><?php echo esc_html(get_admin_page_title()); ?></h1>
        <form method="post" action="options.php">
            <?php
            settings_fields('mytheme_options');
            do_settings_sections('mytheme-settings');
            submit_button();
            ?>
        </form>
    </div>
<?php }
```

`'__return_false'` as the section callback when the section needs no intro copy.

**Repeater on a settings page** (partner logos, social links) — outside the scalar loop:

- Rows named `options_partner_logos[<i>][url]`; the index is arbitrary because the sanitizer
  re-indexes with `array_values()`.
- A `<template>` holding one row rendered with an `__i__` placeholder; JS clones it and string-replaces
  the placeholder. No build step: `wp_enqueue_media()` plus
  `wp_register_script($h, '', ['jquery-ui-sortable'], null, true)` and `wp_add_inline_script($h, …)`,
  all guarded by `if ($hook !== 'settings_page_mytheme-settings') return;`.
- **The sanitizer is the validator**: drop rows without a URL, `absint()` the attachment id, whitelist
  any enum, `array_values()` at the end.

**One-shot maintenance actions** (seed content, re-sync something) belong on this page as forms
posting to `admin-post.php` with `wp_nonce_field()`, reporting back through query args rendered as an
`is-dismissible` notice. Make them idempotent, always.

## Option and meta key names are a contract

Renaming a key does not clear a field: it **orphans the value silently**. The old value stays in the
database under the old name, the admin screen looks empty, and every consumer (schema graph, templates,
composers) stops finding it without a single error.

Keep the keys stable. The one legitimate reason to change them is that the **format** changed too
(flat numbered keys becoming an array meta, a repeater becoming a textarea) — and then it is a
migration, with a script (`content-migrations.md`), run on every environment.
