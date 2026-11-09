class AdminPaymentMethodView {
  final int id;
  final String key;
  final Map<String, dynamic>? displayName;
  final String provider;
  final bool effectiveActive;
  final bool hasStoreOverride;
  // Only sent by the server-wide list.
  final List<String> availableModes;
  final bool offlineCapable;
  final int sortOrder;
  final String? paymentUrl;
  final int? iconResourceId;

  const AdminPaymentMethodView({
    required this.id,
    required this.key,
    required this.displayName,
    required this.provider,
    required this.effectiveActive,
    required this.hasStoreOverride,
    this.availableModes = const [],
    this.offlineCapable = false,
    this.sortOrder = 0,
    this.paymentUrl,
    this.iconResourceId,
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
        availableModes: ((json['availableModes'] as List?) ?? const []).map((e) => e.toString()).toList(),
        offlineCapable: json['offlineCapable'] as bool? ?? false,
        sortOrder: (json['sortOrder'] as num?)?.toInt() ?? 0,
        paymentUrl: json['paymentUrl'] as String?,
        iconResourceId: (json['iconResourceId'] as num?)?.toInt(),
      );
}
