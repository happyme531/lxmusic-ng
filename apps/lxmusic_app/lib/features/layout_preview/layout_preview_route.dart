class LayoutPreviewRoute {
  const LayoutPreviewRoute._();

  static const String name = 'layoutPreview';
  static const String path = '/layout-preview/:profileId/:layoutId';

  static String location({
    required String profileId,
    required String layoutId,
    String? selectedKeyId,
  }) {
    final uri = Uri(
      path: '/layout-preview/$profileId/$layoutId',
      queryParameters: selectedKeyId == null
          ? null
          : <String, String>{'keyId': selectedKeyId},
    );
    return uri.toString();
  }
}
