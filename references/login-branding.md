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
- **Reuse the project's asset helper** when it has one (e.g. an `asset_url()` that wraps
  `Vite::asset()` in a try/catch and handles retired images) instead of the loop above, and point at
  the logo file the header actually uses — often a WebP, not `logo.svg`/`logo.png`. A theme without
  `add_theme_support('custom-logo')` has no Site Logo to read: skip step 1 rather than leave a branch
  that never runs.

## A light logo needs a dark page

Look at the logo before writing CSS. Core's login background is light grey: a white (or white + one
brand colour) logo disappears on it. Then the page takes the site's dark surface token, and:

- **Never set `color` on `body.login`.** It inherits into the white form card and the message box,
  and the labels and "You are now logged out" turn light grey on white. Colour only what sits on
  the dark background: `#nav a`, `#backtoblog a`, `.privacy-policy-page-link a`, the
  `.language-switcher` label and its secondary `.button` (core's blue outline otherwise).
- Keep the form card core's white: every core state (errors, reset password, interim login) stays
  legible without restyling each one.
- Brand the primary button (`.button-primary`, hover/focus with a visible ring), the input focus
  border, the show-password eye and the `.message`/`.notice` left border with the accent colour.
- Copy the token values into the inline CSS with a comment naming `tokens.css`: the login page does
  not load `app.css`, so custom properties are not available there.

## Verify

Open `/wp-login.php?loggedout=true` in a browser (it shows the message box as well as the form) and
check: logo visible and centred, labels and message text dark on white, links readable on the dark
background, language switcher (present when more than one language is installed) not WordPress blue.

## Test

One integration test is enough: with a Site Logo attachment set, `login_logo_url()` returns its URL;
with none and no file, it returns `null`. See `testing.md`.
