# Login screen branding

`/wp-login.php` (and every `/wp-admin` redirect to it) must show **the site's company logo**, never the
WordPress logo — on every project, from the kickoff (`project-kickoff.md`). It is presentation, so it
lives in the theme: `app/login.php`, added to the bootstrap manifest in `functions.php`
(`collect(['setup', 'filters', 'blocks', 'schema', 'login'])`).

## Source of the logo, in order

1. The **Site Logo** set in the admin (`custom_logo` theme mod; `site_logo` option on newer cores) —
   the editor can change it without a deploy.
2. The theme's own `resources/images/logo.svg` (or `.png`), resolved through Vite so it is
   fingerprinted in `public/build/`. `resources/js/app.js` must keep Sage's
   `import.meta.glob(['../images/**', '../fonts/**'])`, or the file is missing from the manifest.
3. Nothing found → leave core's default rather than render an empty box, and log a notice in
   `WP_DEBUG` so the gap is noticed.

## `app/login.php`

```php
<?php

namespace App;

use Illuminate\Support\Facades\Vite;

defined('ABSPATH') || exit;

/**
 * Resolve the logo shown on the login screen: admin Site Logo first, theme asset second.
 */
function login_logo_url(): ?string
{
    $id = (int) (get_theme_mod('custom_logo') ?: get_option('site_logo'));
    if ($id && ($url = wp_get_attachment_image_url($id, 'medium'))) {
        return $url;
    }

    foreach (['logo.svg', 'logo.png'] as $file) {
        if (file_exists(get_theme_file_path("resources/images/{$file}"))) {
            try {
                return Vite::asset("resources/images/{$file}");
            } catch (\Throwable $e) {
                // Not in the manifest yet (no build): fall through.
            }
        }
    }

    if (defined('WP_DEBUG') && WP_DEBUG) {
        error_log('[theme] No logo for the login screen: set a Site Logo or add resources/images/logo.svg');
    }

    return null;
}

add_action('login_enqueue_scripts', function () {
    if (! $url = login_logo_url()) {
        return;
    }

    $css = sprintf(
        '#login h1 a, .login h1 a {'
        .'background-image: url("%s"); background-size: contain; background-position: center;'
        .'background-repeat: no-repeat; width: 100%%; max-width: 320px; height: 96px; margin-bottom: 24px;}',
        esc_url($url)
    );

    wp_add_inline_style('login', $css);
});

add_filter('login_headerurl', fn () => home_url('/'));
add_filter('login_headertext', fn () => get_bloginfo('name', 'display'));
```

Notes:

- `wp_add_inline_style('login', …)` — core enqueues the `login` handle before `login_enqueue_scripts`
  fires, so no extra stylesheet request.
- The link goes to the site's home and the accessible text is the site name, not "Powered by
  WordPress".
- Tune `height` to the logo's aspect ratio (a wide wordmark: ~64px; a square mark: ~120px). Colours of
  the login form are optional; the logo is not.
- The theme renders fine without it: this is presentation, and it degrades to core's default.

## Test

One integration test is enough: with a Site Logo attachment set, `login_logo_url()` returns its URL;
with none and no file, it returns `null`. See `testing.md`.
