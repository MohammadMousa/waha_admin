/// A role as returned by the roles API (built-in or an organization's own).
class RoleInfo {
  final int id;
  final String name;
  final String? description;
  final bool builtIn;
  final bool fixed;
  final int? organizationId;
  final List<String> permissions;
  final int assignedCount;

  const RoleInfo({
    required this.id,
    required this.name,
    this.description,
    required this.builtIn,
    required this.fixed,
    this.organizationId,
    required this.permissions,
    required this.assignedCount,
  });

  factory RoleInfo.fromJson(Map<String, dynamic> j) => RoleInfo(
        id: (j['id'] as num).toInt(),
        name: j['name'] as String,
        description: j['description'] as String?,
        builtIn: j['builtIn'] == true,
        fixed: j['fixed'] == true,
        organizationId: (j['organizationId'] as num?)?.toInt(),
        permissions: ((j['permissions'] as List?) ?? const []).map((e) => e.toString()).toList(),
        assignedCount: (j['assignedCount'] as num?)?.toInt() ?? 0,
      );
}

/// One permission the server knows about.
class PermissionInfo {
  final String key;
  final String description;
  final bool assignableToRoles;

  const PermissionInfo({required this.key, required this.description, required this.assignableToRoles});

  factory PermissionInfo.fromJson(Map<String, dynamic> j) => PermissionInfo(
        key: j['key'] as String,
        description: (j['description'] as String?) ?? '',
        assignableToRoles: j['assignableToRoles'] != false,
      );
}

/// A role given to one person for one scope (company, branch group or branch).
class RoleAssignment {
  final int roleId;
  final String? roleName;
  final String scopeType;
  final int scopeId;

  const RoleAssignment({required this.roleId, this.roleName, required this.scopeType, required this.scopeId});

  factory RoleAssignment.fromJson(Map<String, dynamic> j) => RoleAssignment(
        roleId: (j['roleId'] as num).toInt(),
        roleName: j['roleName'] as String?,
        scopeType: j['scopeType'] as String,
        scopeId: (j['scopeId'] as num?)?.toInt() ?? 0,
      );
}
