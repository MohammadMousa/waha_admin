import 'dart:convert';

/// Parses a name field that may be a raw JSON string or map like
/// `{"ar":"...","en":"..."}` (as returned by the inventory reports API for
/// `product_name` / `branch_display_name`), preferring English. Falls back
/// to [fallback] (e.g. a plain `branch_name` column) if parsing fails or
/// yields nothing.
String parseLocalizedName(dynamic raw, {String fallback = '—'}) {
  if (raw != null) {
    try {
      final m = (raw is Map)
          ? Map<String, dynamic>.from(raw)
          : Map<String, dynamic>.from(jsonDecode(raw.toString()) as Map);
      final name = (m['en'] ?? m['ar'] ?? '').toString().trim();
      if (name.isNotEmpty) return name;
    } catch (_) {}
  }
  return fallback;
}
