class Store {
  final int id;
  final String name;
  final Map<String, String>? displayName;
  final String? currency;
  final int? imageResourceId;

  const Store({
    required this.id,
    required this.name,
    this.displayName,
    this.currency,
    this.imageResourceId,
  });

  String label([String languageCode = 'en']) {
    final map = displayName;
    if (map == null) return name;
    return map[languageCode] ?? map['en'] ?? name;
  }

  factory Store.fromJson(Map<String, dynamic> json) => Store(
        id: (json['id'] as num).toInt(),
        name: json['name'] as String,
        displayName: (json['displayName'] as Map<String, dynamic>?)
            ?.map((k, v) => MapEntry(k, v as String)),
        currency: json['currency'] as String?,
        imageResourceId: json['imageResourceId'] as int?,
      );
}
