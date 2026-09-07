class Store {
  final int id;
  final String name;
  final String? orgSlug;
  final Map<String, String>? displayName;
  final String? currency;
  final int? imageResourceId;

  const Store({
    required this.id,
    required this.name,
    this.orgSlug,
    this.displayName,
    this.currency,
    this.imageResourceId,
  });

  // Public URL prefix for resource serving:
  //   global store (name == orgSlug) → '{org}'
  //   branch store                   → '{org}/{branch}'
  String get resourceBase {
    final org = orgSlug;
    if (org == null || org == name) return name;
    return '$org/$name';
  }

  String label([String languageCode = 'en']) {
    final map = displayName;
    if (map == null) return name;
    return map[languageCode] ?? map['en'] ?? name;
  }

  factory Store.fromJson(Map<String, dynamic> json) => Store(
        id: (json['id'] as num).toInt(),
        name: json['name'] as String,
        orgSlug: json['orgSlug'] as String?,
        displayName: (json['displayName'] as Map<String, dynamic>?)
            ?.map((k, v) => MapEntry(k, v as String)),
        currency: json['currency'] as String?,
        imageResourceId: json['imageResourceId'] as int?,
      );
}
