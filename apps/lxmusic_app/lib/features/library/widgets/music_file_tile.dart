import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../workbench/providers/workbench_provider.dart';
import '../models/music_file.dart';
import '../providers/music_library_provider.dart';
import '../services/song_export_service.dart';

class MusicFileTile extends ConsumerWidget {
  const MusicFileTile({
    super.key,
    required this.file,
    required this.isFavorite,
    this.selectionMode = false,
    this.selected = false,
    this.showRemoveFromCurrentPlaylist = false,
    this.currentPlaylistName,
    this.onTap,
    this.onLongPress,
    this.onPreview,
    this.onRemoveFromCurrentPlaylist,
  });

  final MusicFile file;
  final bool isFavorite;
  final bool selectionMode;
  final bool selected;
  final bool showRemoveFromCurrentPlaylist;
  final String? currentPlaylistName;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final VoidCallback? onPreview;
  final VoidCallback? onRemoveFromCurrentPlaylist;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;

    return ListTile(
      selected: selectionMode && selected,
      leading: _FormatBadge(formatId: file.formatId),
      title: Text(file.fileName, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        [
          file.durationLabel,
          '${file.trackCount} 轨',
          '${file.noteCount} 音符',
        ].join(' · '),
        style: TextStyle(color: scheme.outline),
      ),
      trailing: selectionMode
          ? Checkbox(value: selected, onChanged: (_) => onTap?.call())
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: '预览',
                  icon: Icon(Icons.piano, color: scheme.primary),
                  onPressed: onPreview,
                ),
                IconButton(
                  tooltip: '导出',
                  icon: Icon(Icons.file_upload_outlined, color: scheme.primary),
                  onPressed: () => _showExportDialog(context, ref),
                ),
                IconButton(
                  tooltip: isFavorite ? '取消收藏' : '收藏',
                  icon: Icon(
                    isFavorite ? Icons.favorite : Icons.favorite_border,
                    color: isFavorite ? scheme.error : scheme.outline,
                  ),
                  onPressed: () {
                    ref
                        .read(musicLibraryProvider.notifier)
                        .toggleFavorite(file.fileName);
                  },
                ),
                PopupMenuButton<_TileAction>(
                  itemBuilder: (context) => <PopupMenuEntry<_TileAction>>[
                    if (showRemoveFromCurrentPlaylist)
                      PopupMenuItem<_TileAction>(
                        value: _TileAction.removeFromCurrentPlaylist,
                        child: Text('从${currentPlaylistName ?? '当前歌单'}移除'),
                      ),
                    PopupMenuItem<_TileAction>(
                      value: _TileAction.deleteFile,
                      child: Text(
                        '删除文件',
                        style: TextStyle(color: scheme.error),
                      ),
                    ),
                  ],
                  onSelected: (action) {
                    switch (action) {
                      case _TileAction.removeFromCurrentPlaylist:
                        onRemoveFromCurrentPlaylist?.call();
                        break;
                      case _TileAction.deleteFile:
                        _showDeleteDialog(context, ref);
                        break;
                    }
                  },
                ),
              ],
            ),
      onTap: onTap,
      onLongPress: onLongPress,
    );
  }

  Future<void> _showExportDialog(BuildContext context, WidgetRef ref) async {
    final format = await showDialog<ExportFormat>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: const Text('导出当前乐曲'),
        children: [
          for (final format in ExportFormat.values)
            SimpleDialogOption(
              onPressed: () => Navigator.of(dialogContext).pop(format),
              child: Text(format.label),
            ),
        ],
      ),
    );
    if (!context.mounted || format == null) {
      return;
    }
    await _export(context, ref, format);
  }

  Future<void> _export(
    BuildContext context,
    WidgetRef ref,
    ExportFormat format,
  ) async {
    final profile = ref.read(selectedProfileProvider);
    final variant = ref.read(selectedVariantProvider);
    final layout = ref.read(selectedLayoutProvider);

    if (format != ExportFormat.originalFile &&
        (profile == null || variant == null || layout == null)) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请先去工作台选择当前配置')));
      return;
    }

    try {
      final prepared = await ref
          .read(songExportServiceProvider)
          .prepareExport(
            file: file,
            format: format,
            profile: profile,
            variant: variant,
            layout: layout,
          );
      final outputPath = await FilePicker.saveFile(
        dialogTitle: '选择导出位置',
        fileName: prepared.fileName,
        type: FileType.custom,
        allowedExtensions: [_extensionFor(file.fileName, format)],
        bytes: prepared.bytes,
      );
      if (!context.mounted || outputPath == null) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('已导出到 $outputPath')));
    } catch (e) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('导出失败: $e')));
    }
  }

  String _extensionFor(String fileName, ExportFormat format) {
    if (format != ExportFormat.originalFile) {
      return format.extension;
    }
    final dot = fileName.lastIndexOf('.');
    return dot >= 0 ? fileName.substring(dot + 1) : 'bin';
  }

  void _showDeleteDialog(BuildContext context, WidgetRef ref) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除文件'),
        content: Text('确定要删除 "${file.fileName}" 吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () async {
              await ref.read(musicLibraryProvider.notifier).deleteFiles(
                <String>[file.fileName],
              );
              if (ctx.mounted) {
                Navigator.pop(ctx);
              }
            },
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }
}

enum _TileAction { removeFromCurrentPlaylist, deleteFile }

class _FormatBadge extends StatelessWidget {
  const _FormatBadge({required this.formatId});

  final String formatId;

  static const _labels = <String, String>{
    'midi': 'MIDI',
    'domiso': 'DMS',
    'skystudio-json': 'SKY',
    'tonejs-json': 'TJS',
    'json-score': 'JSON',
  };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      alignment: Alignment.center,
      child: Text(
        _labels[formatId] ?? '?',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: scheme.onPrimaryContainer,
        ),
      ),
    );
  }
}
