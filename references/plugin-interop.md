# Living with third-party plugins

Principle 0 says the theme depends only on WordPress + Sage. That is a design rule; this file is what
it means in practice, because "no dependency" does not mean "no interaction". Plugins filter your
content, own data you display, and register post types you need to list.

## Degrade to nothing, never to half

When an optional plugin is absent, a section that needs it renders **nothing** — no empty card, no
heading with a blank space under it, no "form unavailable" notice.

```php
$form_id = mytheme_resolve_form_id($attributes);

if (! $form_id) {
    return '';        // the whole section disappears, cleanly
}
```

Resolve identifiers through a fallback chain, most specific first: the block attribute set in the
inspector → a map written by your own provisioning step → a legacy option key from the previous
implementation. Each link is one `?:`.

Test it. One integration test per affected block asserting empty output with the plugin absent, and an
explicit exemption list in the "every block renders markup" test (`testing.md`) so the two do not
fight.

The same shape covers plugin-registered data an editor must pick from: if the plugin registers its post
type **without `show_in_rest`**, `getEntityRecords()` cannot see it — inject the list into the editor
as an inline script with an empty-array default (`block-editor-parity.md`) rather than adding a REST
route you would then have to secure.

## ⚠️ Know the priority map of `the_content`

Filters on `the_content` are a queue, and third-party plugins insert themselves into it:

| Priority | What runs |
|---|---|
| 9 | *(free — where restorative filters belong)* |
| 10 | most plugins, including image/lazy-load optimizers |
| 11 | `do_blocks()` in some configurations / more plugins |
| 12 | core's `wp_filter_content_tags()` — adds `width`, `height`, `srcset`, `sizes`, `loading` |

An optimizer that replaces `src` with a base64 placeholder runs at **10**, before core at **12**. Core
can then no longer resolve the attachment, so dimensions land only on the `<noscript>` copy. Without
dimensions the placeholder is as tall as the column is wide — the page is born too long and collapses
as images decode. Classic CLS with no obvious cause.

**Any filter that must see the `<img>` with its real `src` has to hook at priority ≤ 9**, right after
`do_blocks()`:

```php
add_filter('the_content', function (string $html): string {
    // re-add width/height/srcset where missing, promote the first image of a singular
    // view to loading="eager" fetchpriority="high"
    return $html;
}, 9);
```

Two details from doing this for real: use core's own helpers
(`wp_img_tag_add_width_and_height_attr()`, `wp_img_tag_add_srcset_and_sizes_attr()`) and only when the
attribute is missing; and memoise "first image of this post" in a `static` array keyed by post id,
because content is filtered more than once per request. If the optimizer has an exclusion list, add
your eager-loaded class to it.

## ⚠️ WP-CLI is not admin

A plugin that transforms its own stored markup on output typically guards the transform with
`! is_admin()`, so the editor never re-saves the expanded form. **WP-CLI does not satisfy
`is_admin()`.** So a maintenance script that reads a plugin-owned record and saves it back reads the
*expanded* value and writes it as the source — destroying the original syntax in the database,
permanently, with no error.

Rule: **any code that reads and re-saves content owned by a plugin must suspend that plugin's own
filters for the duration** — and the same goes for the plugin's `after_save` hooks:

```php
remove_filter('some_plugin_properties', 'some_plugin_expand', 10);
remove_action('some_plugin_after_save', 'some_plugin_rebuild', 10);
// … read, modify, save …
// restore
```

Assume you will need a repair script for the databases already damaged before you noticed
(`content-migrations.md`), and write it with `--dry-run`.

## One canonical accessor for context-sensitive data

If a business rule says a value is sometimes not shown — a client name under NDA, a price only for
logged-in users — that rule lives in **one** method, and every consumer calls it. Including:

- templates and blocks,
- the JSON-LD graph,
- any machine-readable output (`llms.txt`, feeds), which is the worst place to bypass it precisely
  because those files are explicitly opened to crawlers.

When a mu-plugin needs an accessor that lives in the theme, call it under `class_exists()` — the
mu-plugin must survive a theme switch:

```php
$client = class_exists(\App\Support\Project::class)
    ? \App\Support\Project::client($id)
    : '';
```

## Branching on a plugin at load time

`if (defined('SOME_PLUGIN_VERSION'))` chosen once at file load means **both branches ship**. Detect at
runtime where you can (`function_exists`, `is_plugin_active`), and where a load-time branch is
genuinely necessary, test both passes (`testing.md`).

Coupling to a plugin's public API is a decision, not an accident. If you do it — reading an SEO
plugin's schema graph rather than emitting your own, say — record why in the project's CLAUDE.md,
because the failure mode when the plugin is swapped is silent and structural, not a crash.

## Formatter and tooling interop

Third-party opinions also arrive through your tools. A Laravel-preset formatter (Pint) rewrites
alternative PHP syntax into braces and reformats concatenation — run it on `app/` and ordinary PHP,
never on block render templates or mu-plugins that were never passed through it. One run there buries
a real one-line change under hundreds of lines of noise.
