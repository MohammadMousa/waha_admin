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
      // First non-empty value: an Arabic-only product is saved with an empty
      // English name, which must not hide the Arabic one.
      for (final v in [m['en'], m['ar'], ...m.values]) {
        final name = (v ?? '').toString().trim();
        if (name.isNotEmpty) return name;
      }
    } catch (_) {}
  }
  return fallback;
}
