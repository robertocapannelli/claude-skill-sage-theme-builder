# Go-live, and hosting with no shell at all

`remote-environments.md` covers servers `bin/deploy` can reach (`ssh`, or `sftp` without a shell).
Many shared hosts (cPanel and similar) give **neither**: FTP or the
cPanel File Manager only, SSH "on request". This file is what to do then, and the go-live checklist
that applies whatever the transport.

## Ask early

At kickoff (or as soon as production is named), ask: **does production have SSH? SFTP? Which PHP
and database version? Is there a subdomain or a second database for a test copy? Is there a WAF?**
The answers decide whether `bin/deploy` can ever reach production, and they are slow to obtain from a
hosting ticket — ask before the deadline, not on it.

Also compare PHP versions across environments: a plugin update that requires a newer PHP than local
takes the local site to a 500 (CF7 6.2 needs 8.3).

## Manual hand-over: the package is the deliverable

With no programmatic access, Claude prepares, the user uploads. Production is still explicit-only
(principle 10): prepare the package, name the domain, wait for the yes.

- **Build first, ship the build.** `public/build/` is gitignored; it travels in the package.
- **List every file to upload, and mark new files explicitly.** A new Blade partial missing from
  the upload took every front-end page to a 500: WordPress's critical-error page hides the cause, and
  a request to the theme `.php` answers the same 500, so "is the file there?" cannot be checked from
  outside. Generate the list from git, not from memory:

  ```bash
  git diff --name-status <last-deployed-commit> -- wp-content/themes/<theme> wp-content/mu-plugins
  git ls-files --others --exclude-standard -- wp-content/themes/<theme> wp-content/mu-plugins
  ```

  Order the upload so a file is present before the file that requires it (a new `app/*.php` before
  the `functions.php` that loads it).
- After the upload: purge the page cache (cached HTML points at old asset hashes), then
  `wp acorn view:clear` if possible — otherwise the compiled views in `wp-content/cache/acorn` can be
  deleted by hand.
- Rollback = re-upload the files of the previous commit; there is no server backup unless the user
  takes one from the panel. Say so before each upload.

## First publication on a no-shell host

- **Database:** export from staging/local, rewrite URLs (`wp search-replace` locally on a copy,
  including plugin tables such as `rank_math_*` that store absolute URLs), import from phpMyAdmin.
  ⚠️ A MySQL 8 export can carry `utf8mb4_0900_ai_ci`, unknown to MariaDB: the import stops midway.
  Rewrite the collation on schema lines only, or drop the offending table if it is a host plugin's
  log (SiteGround's `sg_*`).
- **Files:** a zip of core + `wp-content` without the old host's plugins and drop-ins (SiteGround
  Optimizer/Security, `object-cache.php`), extracted with the File Manager.
- **Maintenance window on the real domain** when no test copy is possible: a static 503 page from
  `.htaccess` with a bypass cookie for the people testing. Keep the host's own blocks (e.g.
  its PHP-handler block) and drop the old site's rewrite rules (an old importer's `/en/` rules sent
  English URLs to Italian pages).
- **WAF hosts (BitNinja and friends):** scripted requests plus probes of paths such as `/wp-config.php`
  earn the IP a CAPTCHA a script cannot pass. Keep checks few, targeted, from a browser UA; never probe
  sensitive paths.
- A `Require all denied` block can answer with WordPress's 404 page (the 403 document falls through
  to WordPress). Add `ErrorDocument 403 "Forbidden"` inside the block; a 404 on a denied path does not
  prove the rule is missing.
- Staging hosts with a proxy cache (SiteGround) or Cloudflare: purge after each push; a non-browser
  User-Agent may get a 520.

## Go-live checklist

- [ ] Hosting facts asked: SSH/SFTP, PHP, DB engine, WAF, test copy possible or not.
- [ ] Package or `bin/deploy` plan shown; the user named the domain and said yes.
- [ ] Build included; file list complete with new files marked; upload order respected.
- [ ] DB URLs rewritten in core **and** plugin tables; collation compatible.
- [ ] `WP_ENVIRONMENT_TYPE` is `production` (Site Kit and similar emit tags only then).
- [ ] Search Console / GA4 re-tied to the production domain if they were connected on staging;
      sitemap submitted.
- [ ] Consent banner tested with a clean profile: reject keeps tags blocked, accept fires them.
- [ ] Mail: who sends (host or SMTP), test only towards an internal recipient.
- [ ] Page cache configured (no minify/combine) and purged; PageSpeed measured (`performance.md`).
- [ ] Old site and old database kept for rollback; redirects from the old URL families in place.
- [ ] Staging retired or kept? Record it in the project memory, with how deploys work from now on.
