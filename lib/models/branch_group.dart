class BranchGroup {
  final int id;
  final String name;
  final int organizationId;

  const BranchGroup({
    required this.id,
    required this.name,
    required this.organizationId,
  });

  factory BranchGroup.fromJson(Map<String, dynamic> j) => BranchGroup(
        id: (j['id'] as num).toInt(),
        name: j['name'] as String,
        organizationId: (j['organizationId'] as num).toInt(),
      );
}
