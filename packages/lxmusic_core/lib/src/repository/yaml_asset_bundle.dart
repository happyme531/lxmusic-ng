class YamlAssetBundle {
  YamlAssetBundle(Map<String, String> textAssets)
    : _textAssets = Map.unmodifiable(textAssets);

  final Map<String, String> _textAssets;

  Iterable<String> listFiles(String prefix) {
    final normalizedPrefix = prefix.endsWith('/') ? prefix : '$prefix/';
    return _textAssets.keys
        .where((path) => path.startsWith(normalizedPrefix))
        .toList()
      ..sort();
  }

  String? readText(String path) => _textAssets[path];
}
