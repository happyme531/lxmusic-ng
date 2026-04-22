import 'package:flutter/material.dart';

import '../../library/models/music_file.dart';

class FileSelectionCard extends StatelessWidget {
  const FileSelectionCard({
    super.key,
    required this.file,
    required this.onSelectFromLibrary,
  });

  final MusicFile? file;
  final VoidCallback onSelectFromLibrary;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: file != null
            ? ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                    Icons.music_note,
                    color: scheme.onPrimaryContainer,
                  ),
                ),
                title: Text(
                  file!.fileName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  '${file!.durationLabel} · ${file!.formatId} · ${file!.trackCount} 轨',
                ),
                trailing: TextButton(
                  onPressed: onSelectFromLibrary,
                  child: const Text('更换'),
                ),
              )
            : Center(
                child: Column(
                  children: [
                    Icon(
                      Icons.folder_open_outlined,
                      size: 48,
                      color: scheme.outline,
                    ),
                    const SizedBox(height: 12),
                    FilledButton.tonal(
                      onPressed: onSelectFromLibrary,
                      child: const Text('从曲库选择文件'),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}
