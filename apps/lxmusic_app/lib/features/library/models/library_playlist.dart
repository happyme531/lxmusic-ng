class LibraryPlaylist {
  const LibraryPlaylist({
    required this.id,
    required this.name,
    required this.musicFileNames,
    this.isBuiltinFavorite = false,
    this.createdAt,
  });

  final String id;
  final String name;
  final List<String> musicFileNames;
  final bool isBuiltinFavorite;
  final DateTime? createdAt;

  bool contains(String fileName) => musicFileNames.contains(fileName);

  LibraryPlaylist copyWith({
    String? id,
    String? name,
    List<String>? musicFileNames,
    bool? isBuiltinFavorite,
    DateTime? createdAt,
  }) {
    return LibraryPlaylist(
      id: id ?? this.id,
      name: name ?? this.name,
      musicFileNames: musicFileNames ?? this.musicFileNames,
      isBuiltinFavorite: isBuiltinFavorite ?? this.isBuiltinFavorite,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        'musicFileNames': musicFileNames,
        'isBuiltinFavorite': isBuiltinFavorite,
        'createdAt': createdAt?.toIso8601String(),
      };

  factory LibraryPlaylist.fromJson(Map<String, Object?> json) {
    return LibraryPlaylist(
      id: json['id'] as String,
      name: json['name'] as String,
      musicFileNames: (json['musicFileNames'] as List? ?? const <Object?>[])
          .whereType<String>()
          .toList(),
      isBuiltinFavorite: json['isBuiltinFavorite'] as bool? ?? false,
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'] as String)
          : null,
    );
  }
}
