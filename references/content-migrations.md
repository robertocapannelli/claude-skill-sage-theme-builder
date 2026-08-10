# Content migrations

Some code changes are also **database** changes. The code ships through git; the content does not. If
you change one without the other, the site degrades silently — which is worse than breaking, because
nobody notices for a week.

## What counts as a migration

| Change | Why the database moves too |
|---|---|
| Renaming a block | `post_content` still carries `<!-- wp:old/name -->`; there is no alias in `glob()` registration |
| Renaming a CPT slug | Post rows, meta, term relationships and permalinks all key off it |
| Renaming an option or meta key | The value stays under the old name; readers just stop finding it |
| Changing a data **format** (flat keys → array meta) | The old shape is still in the DB |
| Changing a block's **attribute defaults** | Every instance saved without that attribute renders the new default |

That last one is the least obvious and the most dangerous.

## The defaults trap

`render_block()` fills unset attributes from `block.json` on **every** render. A block inserted and
saved without touching anything is stored as a bare void comment:

```html
<!-- wp:mytheme/split-stats /-->
```

It has no attributes at all — it renders whatever the defaults say *today*. Change the defaults and
published pages change with them, with no edit, no revision and no trace. So:

**Before changing defaults, freeze the old ones into the attributes of every existing instance.** The
migration writes them explicitly; only then may `block.json` change.

## Script skeleton

Every migration in the project is the same shape. Copy it.

```bash
#!/usr/bin/env bash
#
# rename-split-stats-block.sh — renames mytheme/white-label to mytheme/split-stats
# and freezes the previous attribute defaults into every existing instance.
#
# Why a script: the code rename cannot reach post_content. Until this runs, the three pages
# using the block render nothing.
#
# Run on EVERY environment (local, staging, production), once each, right after deploying
# the renamed code.
#
#   ./bin/rename-split-stats-block.sh --dry-run
#   ./bin/rename-split-stats-block.sh
#
# Idempotent: a second run finds no occurrence of the old name and exits without writing.

set -euo pipefail

DRY=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY=1; shift ;;
    -y|--yes)  YES=1; shift ;;
    -h|--help) sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; exit 1 ;;
  esac
done

wp --version >/dev/null 2>&1 || { echo "wp-cli unavailable, or not in the WordPress root" >&2; exit 1; }

# wp-cli prints PHP deprecations on stdout; strip them or they pollute parsed output.
wp_run() { wp "$@" 2>/dev/null | tr -d '\r' | sed '/^Deprecated: /d' | cat -s; }

read -r -d '' MIGRATION <<'PHP' || true
$dry = getenv('MYTHEME_DRY') === '1';
// … see the PHP below …
PHP

MYTHEME_DRY="$DRY" wp_run eval "$MIGRATION"

[[ $DRY -eq 1 ]] && exit 0
wp_run cache flush
echo "Remember: this must be run on every environment."
```

Points that are not stylistic:

- **The header comment is the documentation.** What changes, why the code alone cannot do it, the
  invocation, and an explicit paragraph on what makes a second run a no-op.
- **The whole migration is one PHP heredoc passed to `wp eval`.** You need `json_decode()` on the saved
  attributes and WordPress's own escaping to write them back; doing that in shell means pushing URLs
  and quotes through a shell, where every special character is a new way to be wrong. Pass the dry-run
  flag as an **environment variable**, never by interpolating into the heredoc.
- `--dry-run` exits before any confirmation or cache flush.

## The PHP: rewrite the delimiter, not the post

```php
$old = 'mytheme/white-label';
$new = 'mytheme/split-stats';

// Copied out of block.json BEFORE the defaults were changed.
$frozen = [
    'heading' => 'The previous default heading, verbatim',
    'stats'   => [/* the previous default array, verbatim */],
];

global $wpdb;

$rows = $wpdb->get_results($wpdb->prepare(
    "SELECT ID, post_type, post_title FROM {$wpdb->posts} WHERE post_content LIKE %s",
    '%wp:'.$wpdb->esc_like($old).'%'
));

// save() returns null, so the block is always stored as a void comment. The attribute group
// is OPTIONAL: a block saved untouched is just `<!-- wp:ns/name /-->`.
$pattern = '#<!--\s+wp:'.preg_quote($old, '#').'(?:\s+(\{.*?\}))?\s+/-->#s';

foreach ($rows as $row) {
    $content = get_post_field('post_content', $row->ID);

    $updated = preg_replace_callback($pattern, function (array $m) use ($frozen, $new) {
        $saved = (isset($m[1]) && $m[1] !== '') ? (json_decode($m[1], true) ?: []) : [];

        $attrs = [];
        foreach ($frozen as $key => $default) {                 // frozen defaults first…
            $attrs[$key] = array_key_exists($key, $saved) ? $saved[$key] : $default;   // …saved always wins
        }
        foreach ($saved as $key => $value) {                    // then anything else the editor set
            if (! array_key_exists($key, $attrs)) {
                $attrs[$key] = $value;
            }
        }

        return '<!-- wp:'.$new.' '.serialize_block_attributes($attrs).' /-->';
    }, $content);

    if ($updated === $content) {
        continue;                                               // idempotent
    }
    // … write, see below …
}
```

- **Regex on the single delimiter, not `parse_blocks()` + `serialize_blocks()`.** The round trip
  re-serializes the *entire* post, normalising whitespace and attribute order in blocks that have
  nothing to do with the migration, and turning a one-line change into an unreviewable diff.
- ⚠️ **`serialize_block_attributes()`, never `wp_json_encode()`.** Gutenberg escapes `--`, `<`, `>` and
  `&` inside the attribute JSON, because that JSON lives inside an HTML comment: a `--` in a heading
  written with plain `wp_json_encode()` terminates the comment early and corrupts the block. This is
  the single most common defect in hand-written block migrations.
- Only materialise attributes whose default actually changed. Freezing everything makes future default
  changes impossible to apply.
- If the block has inner content (not `save: () => null`), also rewrite the closing delimiter
  `<!-- /wp:old/name -->`.

## Two write paths, and why

The `LIKE` sweep matches **revisions and autosaves** too — a restored revision must not resurrect the
old name.

```php
if ($row->post_type === 'revision') {
    // wp_update_post() on a revision rewrites it as a normal post.
    $wpdb->update($wpdb->posts, ['post_content' => $updated], ['ID' => $row->ID]);
    clean_post_cache($row->ID);
} else {
    // wp_update_post() expects slashed input and calls wp_unslash(): without wp_slash() the
    // escaped quotes inside the attribute JSON disappear and the block stops parsing.
    $result = wp_update_post(['ID' => $row->ID, 'post_content' => wp_slash($updated)], true);
}
```

The alternative — `$wpdb->update()` for **every** row — is legitimate and simpler: no slashing concern,
no `save_post` side effects, no new revision. The trade-off is that nothing downstream of `save_post`
runs (caches you invalidate there, search indexes, `llms.txt` transients), so you must flush those
yourself. Pick one deliberately and say which in the header comment.

## Meta and option migrations

Same skeleton, different body, plus:

- **Idempotence comes from a read guard at the top**: "already populated → touch nothing". Never from
  a flag file.
- **Do not delete the legacy keys** in the same pass. Leave them as a safety copy, with the cleanup
  command written in the header for a later manual run once the change has been live for a while.
- **Invalid rows are reported and skipped**, never silently coerced
  (`filter_var($url, FILTER_VALIDATE_URL)`).
- **Value coercion must call the same helper the runtime uses.** If the script rounds one way and the
  template another, they will disagree exactly once, on the one record nobody checks.

## The repair variant

When a migration overwrites something an editor may have customised, stash the previous value **the
first time only**:

```php
if (get_post_meta($id, '_mytheme_pre_repair', true) === '') {
    update_post_meta($id, '_mytheme_pre_repair', $previous);
}
```

and open the header with an explicit `WARNING:` block listing exactly what would be lost.

## Sequencing the deploy

There is a window between deploying renamed code and running the migration, during which existing
instances render nothing. Two options:

- **Swap** — deploy, then immediately run the script. The window is seconds. Fine for most sites.
- **Alias shim** — temporarily register the old name too, pointing at the same render, migrate at
  leisure, then remove the shim in a follow-up deploy. Zero downtime, more moving parts, and note it
  **will fail the block-registry parity test** (`testing.md`) unless you exempt the shim explicitly for
  the duration. That exemption is the reminder to remove it.

## Checklist for any migration

- [ ] Header explains what, why, how to run, and what makes it idempotent
- [ ] `--dry-run` prints the plan and writes nothing
- [ ] Defaults frozen **before** `block.json` changes
- [ ] `serialize_block_attributes()` for block attributes
- [ ] Revisions handled on their own write path
- [ ] Legacy data left in place as a safety copy, cleanup documented
- [ ] Verified with a second run that reports zero changes
- [ ] Tracked per environment — the real risk is running it on staging and forgetting production
