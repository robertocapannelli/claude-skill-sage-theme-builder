# Navigation: menus & offcanvas

All navigation is **dynamic** through WordPress menus. Never hardcode menu items.

## Registered menus + dynamic rendering

Register menu locations in `setup.php`, render with `wp_nav_menu()` (or a custom Blade walker for full
markup control):

```php
// app/setup.php
add_action('after_setup_theme', function () {
    register_nav_menus([
        'primary' => __('Primary Navigation', 'sage'),
        'mobile'  => __('Mobile Navigation', 'sage'),  // optional; falls back to primary
    ]);
});
```

### Placeholder when no menu is assigned
If a location has no menu, output a clear admin-only placeholder instead of nothing, so the client knows
what to do:

```blade
{{-- resources/views/sections/navigation.blade.php --}}
@if (has_nav_menu('primary'))
    {!! wp_nav_menu([
        'theme_location' => 'primary',
        'container'      => false,
        'menu_class'     => 'flex gap-6',
        'echo'           => false,
        'depth'          => 3,
        'walker'         => new \App\Navigation\TailwindNavWalker(),
    ]) !!}
@elseif (current_user_can('edit_theme_options'))
    <a href="{{ admin_url('nav-menus.php') }}"
       class="rounded bg-accent/10 px-3 py-2 text-sm text-accent">
        {{ __('Assign a menu to “Primary Navigation” under Appearance → Menus', 'sage') }}
    </a>
@endif
```

Show the placeholder only to users who can edit menus (`current_user_can('edit_theme_options')`) — never
to visitors.

## Multi-level (2–3 levels)

Menus must support submenus **2–3 levels deep**. Set `depth` accordingly and make the walker (or Blade
tree renderer) emit nested `<ul>`s with the right ARIA:

- Each item with children: `aria-haspopup="true"` and a toggle carrying `aria-expanded`.
- Desktop: nested dropdowns (hover + focus, keyboard-navigable).
- Mobile: the same tree becomes an **accordion** inside the offcanvas (see below) — submenus expand in
  place, they don't fly out.

A custom `Walker_Nav_Menu` subclass (`app/Navigation/TailwindNavWalker.php`) is the clean way to inject
Tailwind classes and ARIA without filtering markup after the fact.

## Offcanvas mobile menu

Always ship an offcanvas menu for mobile, styled with the theme's own tokens (it must look like the
theme, not a generic drawer).

**Division of labor: Tailwind does all the visual work; a tiny vanilla JS toggle flips the state.**
Tailwind is CSS — it can't open/close on its own. Keep JS to the minimum and drive everything visual
through Tailwind variants.

```blade
{{-- Trigger (in header) --}}
<button type="button" data-offcanvas-toggle aria-expanded="false" aria-controls="offcanvas-menu"
        class="lg:hidden inline-flex items-center justify-center p-2">
    <span class="sr-only">{{ __('Open menu', 'sage') }}</span>
    {{-- icon --}}
</button>

{{-- Panel --}}
<div id="offcanvas-menu" data-offcanvas data-state="closed"
     class="fixed inset-0 z-50 lg:hidden invisible data-[state=open]:visible"
     aria-hidden="true">
    {{-- overlay --}}
    <div data-offcanvas-overlay
         class="absolute inset-0 bg-ink/50 opacity-0 transition-opacity duration-300
                data-[state=open]:opacity-100"></div>
    {{-- drawer: themed with tokens, slides in from the right --}}
    <nav class="absolute right-0 top-0 h-full w-80 max-w-[85%] bg-paper text-ink shadow-xl
                translate-x-full transition-transform duration-300 ease-out
                data-[state=open]:translate-x-0 overflow-y-auto p-6"
         aria-label="{{ __('Mobile', 'sage') }}">
        {{-- render the mobile menu tree here, submenus as accordions --}}
    </nav>
</div>
```

The `data-[state=open]:` variants (and `aria-[expanded=true]:` where useful) are how Tailwind expresses
open/closed — the JS only toggles `data-state`/`aria-expanded`, nothing else. Minimal, dependency-free JS:

```js
// resources/js/app.js — ~a dozen lines, no framework
function initOffcanvas() {
  const panel = document.querySelector('[data-offcanvas]');
  const toggle = document.querySelector('[data-offcanvas-toggle]');
  if (!panel || !toggle) return;
  const overlay = panel.querySelector('[data-offcanvas-overlay]');

  const open = () => { panel.dataset.state = 'open'; toggle.setAttribute('aria-expanded', 'true');
                       panel.setAttribute('aria-hidden', 'false'); document.body.style.overflow = 'hidden';
                       panel.querySelector('a,button')?.focus(); };
  const close = () => { panel.dataset.state = 'closed'; toggle.setAttribute('aria-expanded', 'false');
                        panel.setAttribute('aria-hidden', 'true'); document.body.style.overflow = ''; toggle.focus(); };

  toggle.addEventListener('click', () => panel.dataset.state === 'open' ? close() : open());
  overlay?.addEventListener('click', close);
  document.addEventListener('keydown', (e) => e.key === 'Escape' && panel.dataset.state === 'open' && close());
}
document.addEventListener('DOMContentLoaded', initOffcanvas);
```

Accessibility is non-negotiable: `aria-expanded` on the trigger, Escape to close, focus moves into the
panel on open and back to the trigger on close, and body scroll locked while open. For submenu
accordions inside, reuse the same `data-state` + `aria-expanded` pattern per branch.

**Zero-JS fallback (documented, not default):** a hidden checkbox or `:target` can toggle the panel with
pure CSS, but you lose Escape-to-close and focus management — accessibility regresses. Use only when a
no-JS constraint is explicit.
