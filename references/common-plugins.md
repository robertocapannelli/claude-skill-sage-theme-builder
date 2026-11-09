# Plugins that come with the client

`plugin-interop.md` is the general rule (optional, detected at runtime, degrade to nothing). This file
is the field notes for the plugins Italian SMB sites keep bringing: a multilingual SaaS (Weglot), a
consent manager (Cookiebot), Google Site Kit, Contact Form 7 + reCAPTCHA, Rank Math. Each section is a
trap that cost time once. Every integration still lives behind `function_exists`/`class_exists`.

## Weglot (second language as a service)

Weglot translates the **rendered page** and bills per word. The theme's own catalogs (`i18n.md`) are
a different layer: code strings → the main language.

- **Read the language URLs from Weglot's services**, never build a `/en/` prefix by hand:
  `weglot_get_service('Request_Url_Service_Weglot')->get_weglot_url()->getForLanguage($lang)` — the
  call Weglot's own switcher makes. Empty without the plugin or on an excluded URL → every switcher
  disappears.
- **Draw the switcher in the theme** and switch Weglot's off **in code**
  (`add_filter('weglot_button_html', '__return_empty_string')` + dequeue its front CSS/JS): one place,
  no dashboard setting to keep in sync per environment.
- **Do not pay for words the code already has in English.** On a translated request serve the English
  `msgid` (a `gettext_<domain>` filter from `template_include` on) and mark every element that prints
  one with `data-wg-notranslate` (a Blade directive such as `@notranslate` that prints nothing on
  main-language pages). Suspend this inside block render callbacks (blocks mix defaults with saved
  copy) and during `wp_head`/`wp_footer` (JSON-LD cannot carry the attribute).
- ⚠️ **Never put `data-wg-notranslate` on an `<a>`**: Weglot then stops rewriting its `href` to the
  translated URL. Wrap the link text in `<span data-wg-notranslate>` instead. Conversely its link
  rewriting checks **only the `<a>` itself**: the "IT" link of a switcher needs the attribute on the
  link, or it is rewritten to its `/en/` twin.
- An `aria-label` on a container that holds links cannot be excluded without excluding the links: use
  `aria-labelledby` pointing at a `<span hidden data-wg-notranslate>`.
- Weglot strips the language prefix **before** redirect plugins match, and its `wp_redirect` filter
  rewrites targets to the request language: explicit `/en/` redirect targets lose their prefix.

## Cookiebot (consent manager, auto-blocking)

- **Auto-blocking delays inline scripts** it does not recognise. A boot script that must run before
  first paint (page transitions, theme toggles) gets `data-cookieconsent="ignore"`; otherwise it runs
  late and the page can stay black or hidden.
- **Iframes are not caught automatically.** Maps and video embeds get `data-cookieblock-src` +
  `data-cookieconsent="marketing"` and a placeholder; print a plain iframe when the plugin is absent
  or in the editor preview.
- ⚠️ No `display` utility on the `cookieconsent-optin-*`/`optout-*` elements: Cookiebot toggles their
  inline `display`, and a Tailwind `!important` utility beats it.
- **Banner language follows the page**: `add_filter('pre_option_cookiebot-language', …)` returning
  the current language (with Weglot, its current language).
- Without the plugin `[cookie_declaration]` must render nothing, not print as text: register an empty
  shortcode at `init` `PHP_INT_MAX` when `! shortcode_exists()`.
- Test with a **clean browser profile**, never an admin session; "TEST" on the banner off the
  production domain is Cookiebot's internal alias and expected.
- Sync vs async `uc.js` is a GDPR decision (see `performance.md`): do not change it unasked.

## Google Site Kit

- Site Kit emits the GA4/Ads tags **only when `wp_get_environment_type()` is `production`**. Staging
  has no tag to test consent mode against; verify after go-live.
- Connecting Search Console/GA4 on staging ties the properties to the staging domain: re-tie them
  after go-live (put it in the go-live checklist).
- Analytics plugins that send data **from the server** (Microsoft Clarity's plugin sends IP, UA and
  URL on every page view, before consent): do not use them; inject the tag through the consent
  manager instead.

## Contact Form 7 + reCAPTCHA

- **Form markup lives in the repository** (`<mu-plugin>/forms/<name>.form.html` + `.mail.txt`),
  pushed to each site by an idempotent sync script. A CF7 form otherwise exists only in the database.
- The block finds the form **by title**, never by a shortcode hash written into an attribute — the
  hash differs per site.
- CF7's `class:` option accepts only `[-0-9a-zA-Z_]`: bracketed Tailwind utilities cannot travel
  through it. Style fields with semantic classes in `app.css`, shared with the block's placeholder.
- CF7 runs `wpautop` over the template: turn it off per form (`wpcf7_autop_or_not`), not globally.
- reCAPTCHA v3 through CF7's own integration; "ReCaptcha v2 for Contact Form 7" disables v3 — never
  both. Hiding the badge requires the reCAPTCHA notice text in the form.
- Load CF7 and reCAPTCHA **only where a form renders** (`performance.md`).
- Never submit test forms to the client's real recipient; after a `db pull`, deactivate SMTP/mailer
  plugins locally (a Gmail API mailer bypasses the local mail catcher).
- Check PHP parity: recent CF7 releases require PHP 8.3; a lower local PHP takes the whole site to a
  500.

## Rank Math (or another SEO plugin)

- Keeps title, meta, OG, robots, sitemap; the theme turns its JSON-LD off when it emits its own graph
  (`schema-seo.md`).
- **Redirects the client manages alone** → Rank Math's Redirections module, seeded from a CSV by a
  migration script, not code. Its `url_to` is absolute: a search-replace between environments must
  include the `rank_math_*` tables.
- Map old URLs from Search Console (16 months) rather than from the Wayback Machine alone.
