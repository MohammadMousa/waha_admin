class Device {
  final int id;
  final String username;
  final String? name;
  final String? deviceKey;
  final String deviceType;
  final int? organizationId;
  final int? storeId;
  final String? storeName;
  final bool enabled;
  final String? createdAt;
  final DateTime? lockedUntil;

  bool get isLocked => lockedUntil != null && lockedUntil!.isAfter(DateTime.now().toUtc());

  const Device({
    required this.id,
    required this.username,
    this.name,
    this.deviceKey,
    required this.deviceType,
    this.organizationId,
    this.storeId,
    this.storeName,
    required this.enabled,
    this.createdAt,
    this.lockedUntil,
  });

  factory Device.fromJson(Map<String, dynamic> j) => Device(
        id: (j['id'] as num).toInt(),
        username: j['username'] as String,
        name: j['name'] as String?,
        deviceKey: j['deviceKey'] as String?,
        deviceType: j['deviceType'] as String? ?? 'KIOSK',
        organizationId: j['organizationId'] == null ? null : (j['organizationId'] as num).toInt(),
        storeId: j['storeId'] == null ? null : (j['storeId'] as num).toInt(),
        storeName: j['storeName'] as String?,
        enabled: j['enabled'] as bool? ?? true,
        createdAt: j['createdAt'] as String?,
        lockedUntil: j['lockedUntil'] == null
            ? null
            : DateTime.tryParse(j['lockedUntil'] as String),
      );

  String get displayName => (name != null && name!.isNotEmpty) ? name! : username;
}
