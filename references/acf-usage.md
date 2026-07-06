# ACF Pro — when and how

ACF Pro is available, but **not for building Gutenberg blocks** (those are native — see
`references/native-blocks.md`). Use ACF where it's genuinely the lighter, cleaner tool.

## Independence first (principle 0)
ACF is an **optional enhancer**, never a theme dependency. The theme must render correctly with ACF
deactivated. Therefore:
- Every ACF read is guarded (`function_exists('get_field')`) with a sane fallback.
- ACF that backs a **content model** (CPT meta consumed by logic) is registered in the **mu-plugin**,
  not the theme — keep the theme free of it.
- Treat ACF as a convenience for editing UX, not as the source of truth the theme can't live without.
  If a template would break without ACF, that's a design smell — move the data or add a fallback.

## Good fits for ACF
- **Post/page meta** that isn't block content (e.g. a "reading time override", an SEO sidebar value,
  a per-page hero variant flag).
- **Options pages** for global, non-content settings (company phone, social links, default OG image)
  consumed across templates.
- **Complex repeaters/relationships on CPTs** edited outside the block canvas (e.g. a "Team Member"
  CPT with structured fields), especially when an editor expects a classic meta-box UX.

## Poor fits (don't reach for ACF here)
- Anything an editor places visually on a page → native block.
- Simple single meta values → consider native `register_post_meta` + a small meta box; lighter than ACF.
- Block fields → never; we don't use ACF blocks on this stack.

## How to wire it cleanly — two code-based approaches

Both keep field definitions in the repo (never define-in-admin-only). They differ on **who can edit the
definitions**, and that — not performance — is the deciding factor.

**A. PHP registration** (`acf_add_local_field_group` on `acf/init`): the definition lives entirely in
code. Fully dev-controlled, simplest to reason about, but in wp-admin the group shows as registered via
PHP and is **read-only** — an editor can't change fields from the UI.

```php
// In the mu-plugin (content model) — not the theme
add_action('acf/init', function () {
    if (!function_exists('acf_add_local_field_group')) return;
    acf_add_local_field_group([
        'key' => 'group_team_member',
        'title' => 'Team Member',
        'fields' => [
            ['key' => 'field_role',  'label' => 'Role',  'name' => 'role',  'type' => 'text'],
            ['key' => 'field_photo', 'label' => 'Photo', 'name' => 'photo', 'type' => 'image', 'return_format' => 'id'],
        ],
        'location' => [[['param' => 'post_type', 'operator' => '==', 'value' => 'team_member']]],
    ]);
});
```

**B. Local JSON** (`acf-json/` folder + load/save filters): ACF writes each field group to a JSON file on
save and loads it from disk. The group stays **editable in wp-admin *and* tracked in git** — it's the
only way to have automatic, continuous versioning *and* admin editability at the same time. (ACF's manual
PHP/JSON export exists too, but it's a one-shot dump you'd re-import by hand — strictly worse; ignore it.)

**Choosing between them:**
- Field definitions must be changeable from the admin (client/editor owns them, or you want fast
  iteration without a deploy) → **Local JSON**.
- Fields are purely dev-controlled and must never be touched from admin → **PHP**, simpler, done.

**Performance is not the criterion.** PHP vs Local JSON is a wash — both are "local", both skip the DB for
the *definitions*. Local JSON's speed win is against groups stored in the DB (the default when you create
them in admin without JSON), **not** against PHP. In both approaches the *values* (post meta) always live
in the DB; only the *definitions* are versioned.

### Where the `acf-json/` folder goes
When the field group backs a content model that must survive a theme switch, keep `acf-json/` **in the
mu-plugin, not the theme** — same rule as the rest of the content model. Wire the paths **additively** so
you don't clobber other ACF consumers:

```php
// In the mu-plugin
add_filter('acf/settings/load_json', function ($paths) {
    $paths[] = __DIR__ . '/acf-json';   // append — keep the theme's default path working too
    return $paths;
});

// ACF 6.2+: route ONLY your groups to the mu-plugin, leave everyone else on their path
add_filter('acf/json/save_paths', function ($paths, $post) {
    if (isset($post['key']) && str_starts_with($post['key'], 'group_myprefix_')) {
        return [__DIR__ . '/acf-json'];
    }
    return $paths;
}, 10, 2);
```

Without `save_paths`, ACF saves every group to the last registered path — you'd hijack groups owned by
other plugins/themes. Prefix your keys (`group_myprefix_…`) and gate on that.

### Local JSON caveats (read before committing to it)
1. **Two sources of truth**: saving in admin writes both the DB *and* the JSON file.
2. **Semi-manual sync**: after a `git pull` with newer JSON, ACF shows "Sync available" and you must
   click it — alignment is by the `modified` timestamp, not automatic.
3. **Ugly merge conflicts** on large JSON files when two people touch the same group.
4. **A group can't live in both PHP and JSON** — migrating to JSON means *removing* the PHP registration,
   or you get duplicates.
5. **Workflow discipline**: edit fields only in dev, commit the JSON, deploy. Editing field groups in
   production drifts from the repo and gets overwritten on the next deploy.

**Always guard** with `function_exists('get_field')` / `acf_add_local_field_group` so the site degrades
gracefully if ACF is ever deactivated — regardless of which approach you pick.

## Reading ACF in views
Prepare ACF data in a **View Composer**, then pass plain values to the Blade view — keep `get_field()`
calls out of templates so views stay dumb and testable.

```php
// app/View/Composers/TeamMember.php
public function with(): array
{
    return [
        'role'  => get_field('role') ?: '',
        'photo' => wp_get_attachment_image_url((int) get_field('photo'), 'medium'),
    ];
}
```
