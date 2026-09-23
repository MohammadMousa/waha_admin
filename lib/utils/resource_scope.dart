// Shared logic for the two resource URL shapes:
//   org-level (global): '{org}'          — branchName == null
//   branch-level:       '{org}/{branch}' — branchName == a real store's name
//
// Never decide "is this global" by comparing strings/ids (a branch's name may
// legitimately coincide with its org's slug) — the caller always knows which
// scope it means (no store selected vs. a specific store selected) and passes
// that explicitly as `branchName`.

/// Public resource URL prefix: '/resource/{result}/{dir}/{name}'.
String resourceBaseFor(String orgSlug, String? branchName) =>
    branchName == null ? orgSlug : '$orgSlug/$branchName';

/// The `{store}` path segment for the admin resource API — a real branch name,
/// or the org's slug to mean "global" (store_id IS NULL server-side).
String apiScopeFor(String orgSlug, String? branchName) => branchName ?? orgSlug;

/// Rewrites a previously-saved `/resource/.../{dir}/{name}` path to use the
/// CURRENT resourceBase, keeping only its directory/filename tail. Heals links
/// saved under a stale org/store identifier (e.g. before an org's slug
/// changed) the next time a page is reopened and re-saved. Leaves anything
/// that isn't a `/resource/...` path (http(s), data:, etc.) untouched.
String healResourceUrl(String rawSrc, String currentResourceBase) {
  final path = rawSrc.startsWith('http')
      ? (Uri.tryParse(rawSrc)?.path ?? rawSrc)
      : rawSrc;
  final parts = path.split('/').where((p) => p.isNotEmpty).toList();
  final resourceIdx = parts.indexOf('resource');
  if (resourceIdx == -1 || parts.length < resourceIdx + 3) return rawSrc;
  final dir = parts[parts.length - 2];
  final name = parts.last;
  return '/resource/$currentResourceBase/$dir/$name';
}
