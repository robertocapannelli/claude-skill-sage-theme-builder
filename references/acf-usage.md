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

## How to wire it cleanly

**Define fields in PHP** (versionable, code-reviewable) rather than only in the admin UI. Where the
field group describes a content model that must outlive the theme (CPT meta, options used by logic),
**register it from the mu-plugin**, not the theme. Theme-only presentational meta can live in the theme.

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

**Or use local JSON sync** (`acf-json/` folder) so admin-UI edits are committed to the repo — acceptable
when a non-dev edits field groups, but keep the JSON in version control.

**Always guard** with `function_exists('get_field')` / `acf_add_local_field_group` so the site degrades
gracefully if ACF is ever deactivated.

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