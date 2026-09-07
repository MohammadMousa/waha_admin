class Employee {
  final int id;
  final String username;
  final String? firstName;
  final String? lastName;
  final String? gender;
  final String? birthDate;
  final String? email;
  final String? phone;
  final String? hiredAt;
  final String? address;
  final String? notes;
  final int? avatarResourceId;
  final bool enabled;
  final String? createdAt;
  final String? roleName;
  final int? storeId;
  final String? storeName;
  final List<int> branchIds;

  const Employee({
    required this.id,
    required this.username,
    this.firstName,
    this.lastName,
    this.gender,
    this.birthDate,
    this.email,
    this.phone,
    this.hiredAt,
    this.address,
    this.notes,
    this.avatarResourceId,
    required this.enabled,
    this.createdAt,
    this.roleName,
    this.storeId,
    this.storeName,
    this.branchIds = const [],
  });

  factory Employee.fromJson(Map<String, dynamic> j) => Employee(
        id: (j['id'] as num).toInt(),
        username: j['username'] as String,
        firstName: j['firstName'] as String?,
        lastName: j['lastName'] as String?,
        gender: j['gender'] as String?,
        birthDate: j['birthDate'] as String?,
        email: j['email'] as String?,
        phone: j['phone'] as String?,
        hiredAt: j['hiredAt'] as String?,
        address: j['address'] as String?,
        notes: j['notes'] as String?,
        avatarResourceId: j['avatarResourceId'] == null ? null : (j['avatarResourceId'] as num).toInt(),
        enabled: j['enabled'] as bool? ?? true,
        createdAt: j['createdAt'] as String?,
        roleName: j['roleName'] as String?,
        storeId: j['storeId'] == null ? null : (j['storeId'] as num).toInt(),
        storeName: j['storeName'] as String?,
        branchIds: (j['branches'] as List?)
                ?.map((b) => ((b as Map<String, dynamic>)['id'] as num).toInt())
                .toList() ??
            const [],
      );

  String get displayName {
    final parts = [firstName, lastName].where((s) => s != null && s.isNotEmpty).toList();
    return parts.isNotEmpty ? parts.join(' ') : username;
  }

  String get initials {
    if (firstName != null && firstName!.isNotEmpty) return firstName![0].toUpperCase();
    return username.isNotEmpty ? username[0].toUpperCase() : '?';
  }
}
