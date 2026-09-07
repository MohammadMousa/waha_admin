class Organization {
  final int id;
  final String name;

  const Organization({required this.id, required this.name});

  factory Organization.fromJson(Map<String, dynamic> j) => Organization(
        id: (j['id'] as num).toInt(),
        name: j['name'] as String,
      );
}
