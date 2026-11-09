# Performance: measured on production, won with bytes

Principle 7 says performance is a design constraint. This file is what that means once the site is
live and PageSpeed disagrees with you. Everything here was measured on a real Sage 11 site
(mobile PageSpeed 53 → 86) and the order reflects what actually moved the score.

## 1. Measure where it counts

- **Local Lighthouse lies about latency.** Against a local server with zero network latency, a fix
  that removes a round trip looks huge and a fix that removes bytes looks small. On production it is
  the other way round. Use local runs to compare variants, never to predict the production score.
- **The reproducible method:** run a pinned Lighthouse from your machine **against production**, one
  run per variant, and simulate a change before shipping it by blocking the resource:

  ```bash
  npx lighthouse@12.8.2 https://example.com/ --form-factor=mobile --only-categories=performance \
    --output=json --output-path=./lh-base.json --quiet
  npx lighthouse@12.8.2 https://example.com/ --form-factor=mobile --only-categories=performance \
    --blocked-url-patterns='*recaptcha*' --output=json --output-path=./lh-no-recaptcha.json --quiet
  ```

  Read `audits["largest-contentful-paint-element"]` and the LCP breakdown, not only the score.
- **PSI's simulated LCP counts every byte that starts before the real LCP.** Images that lazy-load
  "at once" on a narrow viewport, a high-priority logo, a 700 KB script: all of it becomes "element
  render delay" even when the HTML and CSS are already fast. So the lever is **bytes before the hero**,
  not the order of render-blocking resources. Inlining the whole `app.css` to remove every
  render-blocking stylesheet gave **0 points** and was reverted.
- Production behind a WAF (BitNinja, Imunify, Cloudflare bot fight): keep scripted runs few. Probing
  many URLs, or sensitive paths, gets your IP a CAPTCHA a script cannot pass.

## 2. One image helper, used by every view

Views never write `<img src>` for anything that may be in the media library. A single
`\App\image($source, $size, $attrs)` takes an attachment id **or** a URL:

- id (or a URL it resolves to an id) → `wp_get_attachment_image()`: srcset, sizes, width/height;
- bundled theme asset → a plain tag that still gets `loading`, `decoding` and the file's intrinsic
  `width`/`height` (read with `getimagesize()` from the theme path, memoised) — or PageSpeed flags
  "image elements do not have explicit width and height".

What it adds over core:

- **`sizes` per layout context**, from one map (`image_sizes('card'|'split'|'full'|'gallery'|'tile')`)
  measured on the rendered pages. Core's default assumes full width: a card in a three-column grid
  downloads ~3× what it needs.
- **Lazy by default**; the view marks the hero `'loading' => 'eager', 'fetchpriority' => 'high'`.
  Core decides `loading` from a counter and often omits it, which means eager.
- **One high-priority image per page.** When a view passes `fetchpriority: high`, call
  `wp_high_priority_element_flag(false)` — or core (6.3+) promotes a second image on its own and the
  two compete.
- URL → id resolution: strip the `-1024x768` suffix, also try `-scaled`, skip anything outside the
  uploads dir without a query, cache the answer (`wp_cache_set`, one day). Prefer passing the id
  (`get_post_thumbnail_id()`, a block's `imageId`) everywhere it exists.

## 3. Image sizes and encoding

- Core jumps from 300 to 768 px. Phones at PSI's 1.75× DPR need ~500–610 px for a card, so they take
  the 768 file. Add width-only intermediate sizes (no crop, they join every srcset):

  ```php
  add_image_size('theme-480', 480, 0);
  add_image_size('theme-640', 640, 0);
  ```

- Encode sub-sizes at 75 instead of 82 (≈ −23 % on a 640 px photo, no visible difference at card
  size):

  ```php
  add_filter('wp_editor_set_quality', fn (int $q, string $mime) =>
      in_array($mime, ['image/webp', 'image/jpeg'], true) ? 75 : $q, 10, 2);
  ```

- Existing uploads need their thumbnails regenerated (`wp media regenerate --only-missing` with
  SSH, the *Regenerate Thumbnails* plugin without it). Some old attachments fail with unreadable
  metadata: pre-existing, not caused by the change.
- ⚠️ **Never combine `image_editor_output_format` (JPEG → WebP) with regenerating existing uploads.**
  It rewrites the attachment's **main file** too, not only the sub-sizes. Restoring took a snapshot.

## 4. Theme assets

- Logos and decorative images ship as **WebP** at the size actually displayed, with a `srcset` for
  the small variant (a 240 px logo for phones). A PNG logo loaded with high priority is pure render
  delay: 85 KB → 15 KB moved the score +3 on its own.
- Every bundled `<img>` carries `width`/`height`; lazy below the fold.
- Self-hosted fonts, only the weights used, `font-display: swap` (`design-to-blade.md`).

## 5. Third-party weight: load it only where it is used

- **Core block CSS on demand.** A theme built from its own blocks uses few core ones; the combined
  `block-library` stylesheet is ~19 KB of render-blocking CSS, mostly unused. Use
  `add_filter('should_load_separate_core_block_assets', '__return_true')`, and never ship
  `__return_false` copied from a starter.
- **Contact Form 7 + reCAPTCHA v3 only on pages that render a form.** CF7 enqueues its JS, CSS and
  reCAPTCHA (~700 KB, fetched twice) on every page. Turn the global enqueue off and make the same calls
  when a form is actually rendered:

  ```php
  add_filter('wpcf7_load_js', '__return_false');
  add_filter('wpcf7_load_css', '__return_false');
  add_action('wp', fn () => remove_action('wp_enqueue_scripts', 'wpcf7_recaptcha_enqueue_scripts', 20));

  add_action('wpcf7_shortcode_callback', function () {
      static $done = false;
      if ($done) { return; }
      $done = true;
      foreach (['wpcf7_enqueue_scripts', 'wpcf7_enqueue_styles', 'wpcf7_recaptcha_enqueue_scripts'] as $fn) {
          if (function_exists($fn)) { $fn(); }
      }
  });
  ```

  Footer scripts and late-printed styles make mid-body enqueuing safe. This one change took mobile
  53 → 80 (with the next point).
- **Never hide the LCP element while JS boots.** A page-transition script that holds `<main>` hidden
  until its module runs costs seconds on a cold visit (search, ads, Lighthouse). Hold content only
  when there is a transition to finish (same-origin referrer); landing pages for paid traffic skip
  transitions entirely.
- Consent managers in **sync** mode (Cookiebot `uc.js`) stay render-blocking; that residual (~2 s on
  mobile here) is a GDPR decision, not a theme fix. Leave it to the user and the vendor's advice.

## 6. Page cache

- A host with Apache + OPcache only needs a page-cache plugin (WP Fastest Cache, WP Super Cache):
  page cache, preload, gzip, browser caching **on**; every **minify/combine** option **off** — they
  break consent-manager auto-blocking and inline boot scripts.
- **Purge after every theme upload**: cached HTML points at the old `public/build` hashes, and the
  page loads unstyled or with old JS.

## Checklist

- [ ] `\App\image()` used by every view; `sizes` map measured on the rendered layout.
- [ ] Exactly one `fetchpriority="high"` image per template; everything else lazy.
- [ ] Width-only 480/640 sizes, quality 75; thumbnails regenerated where uploads predate them.
- [ ] Theme logos/assets in WebP at display size, with `width`/`height`.
- [ ] Core block CSS on demand; CF7/reCAPTCHA only where a form renders.
- [ ] No script hides the LCP element on a cold visit.
- [ ] Score measured with pinned Lighthouse against production, variants compared one run each.
