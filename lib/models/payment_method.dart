class AdminPaymentMethodView {
  final int id;
  final String key;
  final Map<String, dynamic>? displayName;
  final String provider;
  final bool effectiveActive;
  final bool hasStoreOverride;

  const AdminPaymentMethodView({
    required this.id,
    required this.key,
    required this.displayName,
    required this.provider,
    required this.effectiveActive,
    required this.hasStoreOverride,
  });

  factory AdminPaymentMethodView.fromJson(Map<String, dynamic> json) =>
      AdminPaymentMethodView(
        id: (json['id'] as num).toInt(),
        key: json['key'] as String,
        displayName: json['displayName'] as Map<String, dynamic>?,
        provider: json['provider'] as String,
        // The server-wide list sends a plain "active" instead.
        effectiveActive: json['effectiveActive'] as bool? ?? json['active'] as bool? ?? true,
        hasStoreOverride: json['hasStoreOverride'] as bool? ?? false,
      );
}
