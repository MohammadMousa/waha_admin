class ResourceDirectory {
  final int id;
  final String name;
  const ResourceDirectory({required this.id, required this.name});
  factory ResourceDirectory.fromJson(Map<String, dynamic> json) =>
      ResourceDirectory(id: (json['id'] as num).toInt(), name: json['name'] as String);
}

class ResourceAsset {
  final int id;
  final String name;
  final String mimeType;
  final int sizeBytes;
  final String sha256;
  const ResourceAsset({
    required this.id,
    required this.name,
    required this.mimeType,
    required this.sizeBytes,
    required this.sha256,
  });
  factory ResourceAsset.fromJson(Map<String, dynamic> json) => ResourceAsset(
        id: (json['id'] as num).toInt(),
        name: json['name'] as String,
        mimeType: json['mimeType'] as String,
        sizeBytes: (json['sizeBytes'] as num).toInt(),
        sha256: json['sha256'] as String,
      );
  bool get isImage => mimeType.startsWith('image/');
  bool get isHtml {
    if (mimeType == 'text/html') return true;
    final n = name.toLowerCase();
    return n.endsWith('.html') || n.endsWith('.htm');
  }
  String publicUrl(String store, String dir) => '/resource/$store/$dir/$name';
}

class PickedResource {
  final int resourceId;
  final String publicUrl;
  const PickedResource({required this.resourceId, required this.publicUrl});
}
