# Testing a Sage theme + mu-plugins

A theme is not "hard to test". It is testable at three levels, each cheap once wired, and the wiring
has four traps that will eat a day if you meet them cold.

## Does this need a test?

Answer it **explicitly** before considering a new function done — the answer may be "no", but it may
not be skipped. Write one when any of these holds:

- **It has branches.** An `if` on editor input, a fallback, a precedence rule between two options.
  These are the places a regression does not show up on screen.
- **It sanitizes, validates or authorizes.** Nonce, honeypot, escaping, capability, upload MIME. The
  bug here is silent and expensive.
- **It produces output someone else reads.** JSON-LD, `llms.txt`, `robots.txt`, a block's markup —
  breakage stays invisible until Search Console reports it.
- **It depends on state that varies.** Missing content, plugin inactive, empty option, unassigned menu:
  the cases where the site must degrade without breaking.
- **It has broken something once already.** A fixed bug without a test comes back.

Skip it when the function is a pass-through (`get_option()` returned as-is), when the test would
restate the implementation line by line, or when it would assert WordPress's behaviour rather than
yours.

Where it goes: pure logic → `tests/Unit/`; anything touching queries, hooks, rewrites or rendering →
`tests/Integration/`; browser behaviour → the theme's `tests/js/`.

## Three levels

| Level | Runner | Loads | Speed |
|---|---|---|---|
| `tests/Unit/` | PHPUnit + **Brain Monkey** | nothing — every WP function is stubbed | milliseconds |
| `tests/Integration/` | PHPUnit + **wp-phpunit** | real database, mu-plugins, active theme | seconds |
| `<theme>/tests/js/` | **Jest + jsdom** (via wp-scripts) | the editor bundle and front-end JS | fast |

Put the PHP suites at the **repository root**, not inside the theme: they cover theme and mu-plugins
together, and the boundary between them is exactly what you want to exercise.

## Trap 1 — two PHPUnit configs, not one

Procedural WordPress code (mu-plugins, `app/*.php`) declares functions at file scope. The unit suite
`require_once`s those files directly; the integration suite loads them through WordPress's own
bootstrap. Doing both in one process is a **fatal redeclare**.

So: `phpunit.xml.dist` and `phpunit-integration.xml.dist`, two bootstraps, two `cacheResultFile`s.
Never one suite with two groups. Put the strict flags (`failOnWarning`,
`beStrictAboutTestsThatDoNotTestAnything`) on the unit config only — WP core emits warnings of its own.

## Trap 2 — the integration bootstrap drops every table

wp-phpunit runs `DROP TABLE` across the whole configured database. Three layers of guard, all cheap:

```php
// tests/Support/SiteConfig.php — credentials read out of wp-config.php at runtime (never committed),
// but the database NAME is pinned independently and never inherited.
public static function testDatabase(): string
{
    return getenv('WP_TESTS_DB_NAME') ?: 'myproject_test';
}
```

```php
// tests/bootstrap-integration.php — assert before WordPress touches anything
tests_add_filter('muplugins_loaded', function () {
    if (DB_NAME === 'myproject') {
        fwrite(STDERR, "\nRefusing to run: DB_NAME points at the development database.\n");
        exit(1);
    }
});
```

plus a setup script that refuses to create a database resolving to the live name. Reading credentials
from `wp-config.php` at runtime keeps every password out of the repository.

## Trap 3 — Acorn does not finish booting under PHPUnit

`switch_theme()` on `setup_theme` gets `functions.php` and the service providers to run:

```php
// tests/bootstrap-integration.php
putenv('WP_PHPUNIT__TESTS_CONFIG='.__DIR__.'/wp-tests-config.php');
$testsDir = dirname(__DIR__).'/vendor/wp-phpunit/wp-phpunit';
require_once $testsDir.'/includes/functions.php';

tests_add_filter('setup_theme', fn () => switch_theme('my-theme'));

require_once $testsDir.'/includes/bootstrap.php';
```

But Acorn's own boot sees a console request that is neither WP-CLI nor its `acorn` binary and returns
early, so none of the container bindings — `view` included — exist. Blocks, CPTs, hooks and rewrites
work anyway; **anything that renders Blade must bootstrap the kernel by hand**:

```php
protected function bootAcorn(): void
{
    $app = \Roots\Acorn\Application::getInstance();

    if (! $app->isBooted()) {
        $app->make(\Illuminate\Contracts\Console\Kernel::class)->bootstrap();
    }
}
```

`tests/wp-tests-config.php` must point `WP_CONTENT_DIR` at the **real** content directory, not a
fixture — Acorn boots from the theme directory.

## Trap 4 — the meta registry is wiped between tests

wp-phpunit's `tear_down()` calls `unregister_all_meta_keys()`, so from the second test onward every
`register_post_meta()` made on `init` is gone. Re-firing `init` would bring them back *and*
re-register the blocks, tripping `_doing_it_wrong()`. Hence the rule in
`post-meta-and-settings.md`: registrations live in a **named function**, and the test case calls it:

```php
protected function restoreRegisteredMeta(): void
{
    mytheme_register_book_meta();
}
```

Same category of problem: any per-request memoisation must be reset per test, via reflection if it is
a static property.

## Support helpers that pay for themselves

- **Brain Monkey base case** with three stub families always on: translation (`__`, `esc_html__` →
  `returnArg(1)`), sanitisation, and escaping — where escaping must be the **real**
  `htmlspecialchars()`, because a test that checks an attribute is escaped has to see real escaping.
  The unit bootstrap also needs `ABSPATH` defined (mu-plugins open with `defined('ABSPATH') || exit;`)
  plus minimal `WP_Error`/`WP_Post` classes: Brain Monkey stubs functions, not classes or constants.
- **Redirect interception** for handlers that end in `wp_safe_redirect(); exit;`, which would otherwise
  kill the test process:

  ```php
  add_filter('wp_redirect', function ($location, $status) {
      throw new RedirectedException((string) $location, (int) $status);
  }, 10, 2);
  ```

- **A `render(string $url)` helper**: `ob_start()` + `go_to($url)` in a `try/finally`, for anything
  driven by rewrite rules or `template_redirect`.
- **Firing only your own closures on a hook.** When a closure on `admin_init` must be replayed but
  firing the whole hook makes WordPress send headers, walk
  `$GLOBALS['wp_filter'][$hook]->callbacks` and use `ReflectionFunction::getFileName()` to run only the
  ones declared by your file.

## The block tests you write once and never touch again

With `glob()` auto-registration there is no list to maintain — so the test is that **the glob and the
filesystem agree**. Drive everything from disk with data providers, reading defaults out of each
`block.json`:

```php
foreach (glob($root.'/*/block.json') ?: [] as $path) {
    $metadata = json_decode((string) file_get_contents($path), true);
    $defaults = [];
    foreach ($metadata['attributes'] ?? [] as $name => $schema) {
        if (array_key_exists('default', $schema)) {
            $defaults[$name] = $schema['default'];
        }
    }
    $blocks[$metadata['name']] = [$metadata['name'], $defaults];
}
```

```php
private function renderBlock(string $name, array $attributes): string
{
    return render_block([
        'blockName' => $name, 'attrs' => $attributes,
        'innerBlocks' => [], 'innerHTML' => '', 'innerContent' => [],
    ]);
}
```

Five assertions over **every** block, present and future:

1. **Renders with its declared defaults** — non-empty markup, except a curated allowlist of blocks that
   must render `''` (content-driven blocks with nothing to show, blocks whose backing plugin is
   absent). Keep the allowlist explicit so an accidental empty render fails.
2. **Renders with no attributes at all** — an editor who inserts a block and immediately saves sends
   none.
3. **Emits no PHP notices** — install a temporary `set_error_handler(…, E_ALL)` collecting into an
   array, restore it in `finally`, assert the array is empty. This catches the whole class of "typo'd
   attribute key / missing null guard" that otherwise appears as a warning on a live page.
4. **Opens with the wrapper element**:
   ```php
   $this->assertMatchesRegularExpression('/^<(section|div|aside|figure|nav|header|footer|article)\b/', $html);
   ```
   paired with a check that `get_block_wrapper_attributes()` output is present.
5. **XSS smoke** — feed `<script>alert(1)</script>` into each text attribute and assert it does not
   survive.

**Registry parity, both directions, from both sides:**

```php
// PHP: every block.json on disk is registered…
$this->assertTrue(WP_Block_Type_Registry::get_instance()->is_registered($name));

// …and nothing is registered under our namespace that is not on disk.
$registered = array_filter(
    array_keys(WP_Block_Type_Registry::get_instance()->get_all_registered()),
    fn (string $n): bool => str_starts_with($n, 'mytheme/')
);
sort($registered);
$this->assertSame($onDisk, $registered);
```

The JS mirror asserts the same set from the editor bundle: each `block.json` name is registered, each
folder has an `index.js`, `resources/js/blocks/index.js` imports it, `edit` is a function and `save`
returns null-ish (so no stale markup can land in `post_content`). Between them they catch the two
silent failures of this architecture: a block never imported into the entry, and an `edit()` registered
under a name that does not match its `block.json`.

**Attribute ↔ control parity** — the test behind "everything visible is editable"
(`native-blocks.md`). Static, no rendering needed:

```js
// tests/js/attribute-controls.test.js
const fs = require('fs');
const path = require('path');
const blocksDir = path.resolve(__dirname, '../../resources/blocks');

describe.each(fs.readdirSync(blocksDir).filter((d) => fs.existsSync(path.join(blocksDir, d, 'block.json'))))(
    'block %s', (name) => {
        const meta = require(path.join(blocksDir, name, 'block.json'));
        const edit = fs.readFileSync(path.resolve(__dirname, `../../resources/js/blocks/${name}/index.js`), 'utf8');
        test.each(Object.keys(meta.attributes || {}))('attribute %s has a control', (attr) => {
            expect(edit).toMatch(new RegExp(`\\b${attr}\\b`));
        });
    },
);
```

It cannot prove the control is *good*, only that it exists — the element-by-element walk of the front
end in `native-blocks.md` covers the rest.

## Jest with wp-scripts

wp-scripts externalises every `@wordpress/*` import to the `wp.*` globals, so those packages are never
installed — Jest needs mocks:

```js
// jest.config.cjs
const defaults = require('@wordpress/scripts/config/jest-unit.config.js');

module.exports = {
    ...defaults,
    rootDir: __dirname,
    testEnvironment: 'jsdom',
    testMatch: ['<rootDir>/tests/js/**/*.test.js'],
    setupFilesAfterEnv: ['<rootDir>/tests/js/setup.js'],
    moduleNameMapper: {
        ...(defaults.moduleNameMapper || {}),
        '^@wordpress/blocks$': '<rootDir>/tests/js/mocks/wp-blocks.cjs',
        '^@wordpress/i18n$':   '<rootDir>/tests/js/mocks/wp-i18n.cjs',
        '^@wordpress/(block-editor|components|data|core-data|editor|hooks|plugins|server-side-render)$':
            '<rootDir>/tests/js/mocks/wp-ui.cjs',
    },
};
```

Make the UI mock a **Proxy** so unknown imports still evaluate instead of exploding:

```js
module.exports = new Proxy(known, {
    get(target, property) {
        if (property in target) return target[property];
        if (typeof property !== 'string') return undefined;
        if (/^use[A-Z]/.test(property)) return () => ({});   // hooks must not become components
        return passthrough(property);                          // renders its children
    },
});
```

The `@wordpress/blocks` mock keeps a real registry `Map` and stores `settings.save` separately, so a
test can distinguish "the block defined a `save()`" from "it didn't". `tests/js/setup.js` polyfills
what jsdom lacks and front-end JS touches at module scope: `matchMedia`, `IntersectionObserver`,
`ResizeObserver`, `requestAnimationFrame`, `Element.prototype.animate`, `Element.prototype.scrollTo`.

## Fixture trap: block markup in `post_content`

⚠️ A test post whose `post_content` contains a block comment carrying HTML in its attributes must be
written with **`wp_slash()`** *and* by a user with **`unfiltered_html`** — both, or the block degrades
silently instead of failing:

- `wp_insert_post()` expects slashed input and calls `wp_unslash()`. Without `wp_slash()` the
  backslashes in `class=\"lead\"` disappear, the attribute JSON stops parsing, and the block renders
  its **defaults** — an assertion on the text can pass by accident.
- Without `wp_set_current_user()` on an administrator, kses escapes the whole comment (`<!--` →
  `&lt;!--`) and the block is not recognised at all.

## Testing both branches of a conditional dependency

When code picks a branch at load time from `defined('SOME_PLUGIN_VERSION')`, both branches ship — so
run the suite twice:

```php
if (getenv('WP_TESTS_SIMULATE_PLUGIN')) {
    tests_add_filter('muplugins_loaded', function () {
        if (! defined('SOME_PLUGIN_VERSION')) {
            define('SOME_PLUGIN_VERSION', '24.0');
        }
    });
}
```

with the plugin-dependent tests in a PHPUnit `@group`, excluded from the first pass and required in the
second. Wire both passes into one command.

## One entry point

```bash
./bin/test-setup            # once: create the test DB + composer install
./bin/test                  # everything
./bin/test unit             # Brain Monkey
./bin/test integration      # wp-phpunit (both passes)
./bin/test js
./bin/test coverage         # gated behind XDEBUG_MODE=coverage
./bin/test unit --filter NavMenuTest   # extra args pass through to PHPUnit
```

If PHP lives in a container and Node on the host, `bin/test` is where that asymmetry is absorbed —
detect the container, fail with a readable message when it is not running, and let the caller keep
typing one command. Make the unknown-target branch print the script's own header comment as usage.
