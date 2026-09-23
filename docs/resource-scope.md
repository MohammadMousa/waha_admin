# Resource Scope (Global vs. Branch)

How the admin app decides whether a resource/landing-page operation targets an organization's global scope or one specific branch. See `waha/docs/resource-management.md` for the underlying URL scheme and data model this builds on.

---

## The rule

Global scope is `store_id IS NULL` on the backend — there is no "global store" row to point at. The admin app mirrors that directly: **no branch selected (`Store? selected == null`) means global**, full stop. Nothing here is ever decided by comparing a store's name against the org's slug, or by hardcoding a specific store id as "the" global one — both were tried in the past and both broke the moment an org's slug diverged from a branch's name.

Two small pure functions in `lib/utils/resource_scope.dart` are the single source of truth for this, used by every screen that builds a resource or landing-page URL:

```dart
String resourceBaseFor(String orgSlug, String? branchName) =>
    branchName == null ? orgSlug : '$orgSlug/$branchName';

String apiScopeFor(String orgSlug, String? branchName) => branchName ?? orgSlug;
```

`resourceBaseFor` builds the public `/resource/...` URL prefix; `apiScopeFor` builds the `{store}` path segment for the admin resource API (which accepts a real branch name *or* the org's own slug to mean global). Any screen that needs either derives them from `(selectedStore?.name, orgSlug)` — never from a `Store` object standing in for "global."

`orgSlug` itself comes from any already-fetched `Store.orgSlug` (all stores in an org carry it) — there's no separate "get my org" call needed today, since an admin session only ever deals with one org's stores at a time.

---

## UI convention: "Select Branch" is a real, selectable item

Every branch dropdown (`landing_pages_screen.dart`, `advertisements_screen.dart`) includes an explicit `DropdownMenuItem<Store?>(value: null, ...)` labeled "Select Branch" as its first entry — not just a `hint:` that disappears once something is picked. Without it, there's no way back to global scope once a branch has been selected once. If you add a new branch-scoped screen, include this item; don't rely on the hint-only pattern.

---

## Saving heals stale links, but only on save

Every landing/ad page's HTML embeds `<img src="/resource/...">` values baked in at save time. If an org's slug or a branch's name ever changes after a page was saved, those embedded links keep the *old* identifier — nothing rewrites them automatically. `landing_editor_screen.dart` and `advertisements_screen.dart` re-derive each slide's `src` against the *current* `resourceBaseFor(...)` every time an existing page is reopened (`healResourceUrl()` in `resource_scope.dart`), so simply opening and re-saving a page fixes it. A page that's never reopened stays on the old identifier indefinitely — there is no background migration.

`_duplicatePage` (`landing_pages_screen.dart`) heals the same way before copying, so duplicating an old page doesn't propagate its stale links into the new one.

---

## Known gap (backend-side, not fixed here)

`ResourceAdminController`'s branch-name lookup isn't scoped by organization — see the "Known limitations" section of `waha/docs/resource-management.md`. Harmless with one org today; something to fix before a second org exists.

---

## Deliberately out of scope

Products, categories, and employee-avatar screens (`products_screen.dart`, `categories_admin_screen.dart`, `employee_edit_screen.dart`) still key their shared image bucket off a hardcoded `'waha'` store name rather than the pattern above — same underlying issue, different resource type, not yet migrated.
