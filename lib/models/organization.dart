class Organization {
  final int id;
  final String name;
  final String type; // COMPANY | BRANCH_GROUP
  final int? parentId;

  const Organization({
    required this.id,
    required this.name,
    required this.type,
    this.parentId,
  });

  factory Organization.fromJson(Map<String, dynamic> j) => Organization(
        id: (j['id'] as num).toInt(),
        name: j['name'] as String,
        type: j['type'] as String? ?? 'BRANCH_GROUP',
        parentId: j['parentId'] != null ? (j['parentId'] as num).toInt() : null,
      );

  String label() => name;
}
