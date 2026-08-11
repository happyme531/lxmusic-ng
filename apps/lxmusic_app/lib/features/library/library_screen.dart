import 'dart:developer' as developer;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/platform/file_store.dart';
import '../calibration/calibration_launcher.dart';
import '../workbench/widgets/current_target_action.dart';
import '../workbench/providers/workbench_provider.dart';
import 'models/music_file.dart';
import 'providers/library_selection_provider.dart';
import 'providers/music_library_provider.dart';
import 'services/song_export_service.dart';
import 'widgets/music_file_tile.dart';

void _logPlaylistCreate(String message) {
  developer.log(
    '[PLAYLIST_CREATE] $message',
    name: 'lxmusic.library.playlist_create',
  );
}

Future<void> runMusicImportFlow(
  BuildContext context,
  WidgetRef ref,
  List<PickedFileData> pickedFiles,
) async {
  if (pickedFiles.isEmpty || !context.mounted) return;

  final cancellationToken = MusicImportCancellationToken();
  final progress = ValueNotifier<MusicImportProgress>(
    const MusicImportProgress(
      stage: MusicImportStage.scanning,
      sourceLabel: '正在准备导入',
    ),
  );
  final stopRequested = ValueNotifier<bool>(false);
  final progressDialog = showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (context) => MusicImportProgressDialog(
      progress: progress,
      stopRequested: stopRequested,
      onStop: () {
        stopRequested.value = true;
        cancellationToken.stop();
      },
    ),
  );

  late final MusicImportReport report;
  try {
    await ref.read(musicLibraryProvider.future);
    report = await ref
        .read(musicLibraryProvider.notifier)
        .importFiles(
          pickedFiles,
          cancellationToken: cancellationToken,
          onProgress: (value) => progress.value = value,
          resolveConflict: (conflict) =>
              showMusicImportConflictDialog(context, conflict),
        );
  } catch (error) {
    if (context.mounted) {
      Navigator.of(context, rootNavigator: true).pop();
    }
    await progressDialog;
    progress.dispose();
    stopRequested.dispose();
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('导入失败：$error')));
    }
    return;
  }
  if (context.mounted) {
    Navigator.of(context, rootNavigator: true).pop();
  }
  await progressDialog;
  progress.dispose();
  stopRequested.dispose();
  if (!context.mounted) return;

  if (report.failures.isNotEmpty ||
      report.archives.isNotEmpty ||
      report.reusedCount > 0 ||
      report.skippedCount > 0 ||
      report.ignoredCount > 0 ||
      report.stopped) {
    await showDialog<void>(
      context: context,
      builder: (context) => MusicImportResultDialog(report: report),
    );
    return;
  }
  ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text('成功导入 ${report.importedCount} 个文件')));
}

Future<MusicImportConflictDecision> showMusicImportConflictDialog(
  BuildContext context,
  MusicImportConflict conflict,
) async {
  final decision = await showDialog<MusicImportConflictDecision>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => MusicImportConflictDialog(conflict: conflict),
  );
  return decision ??
      const MusicImportConflictDecision(action: MusicImportConflictAction.stop);
}

class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key});

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> {
  late final SearchController _searchController;

  @override
  void initState() {
    super.initState();
    _searchController = SearchController()
      ..text = ref.read(searchQueryProvider);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = ref.watch(searchQueryProvider);
    if (_searchController.text != query) {
      _searchController.value = TextEditingValue(
        text: query,
        selection: TextSelection.collapsed(offset: query.length),
      );
    }
    final filteredAsync = ref.watch(filteredMusicFilesProvider);
    final libraryAsync = ref.watch(musicLibraryProvider);
    final currentPlaylist = ref.watch(currentPlaylistViewProvider);
    final selectedFiles = ref.watch(librarySelectionProvider);
    final selectionMode = ref.watch(isLibrarySelectionModeProvider);

    return Scaffold(
      appBar: selectionMode
          ? _buildSelectionAppBar(context, ref, filteredAsync, currentPlaylist)
          : _buildNormalAppBar(context, ref, currentPlaylist),
      body: filteredAsync.when(
        data: (files) {
          final library = libraryAsync.value;
          if (files.isEmpty) {
            return _EmptyState(
              hasAnyFile: (library?.files.isNotEmpty ?? false),
              currentPlaylistName: currentPlaylist.name,
              isAllSongs: currentPlaylist.isVirtual,
              hasQuery: ref.watch(searchQueryProvider).trim().isNotEmpty,
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.only(bottom: 24),
            itemCount: files.length,
            itemBuilder: (context, index) {
              final file = files[index];
              return MusicFileTile(
                file: file,
                isFavorite: library?.isFavorite(file.fileName) ?? false,
                selectionMode: selectionMode,
                selected: selectedFiles.contains(file.fileName),
                showRemoveFromCurrentPlaylist:
                    !selectionMode && !currentPlaylist.isVirtual,
                currentPlaylistName: currentPlaylist.name,
                onTap: () {
                  if (selectionMode) {
                    ref
                        .read(librarySelectionProvider.notifier)
                        .toggle(file.fileName);
                    return;
                  }
                  context.go('/workbench', extra: file);
                },
                onLongPress: () {
                  final notifier = ref.read(librarySelectionProvider.notifier);
                  if (selectionMode) {
                    notifier.toggle(file.fileName);
                  } else {
                    notifier.startWith(file.fileName);
                  }
                },
                onPreview: () {
                  ref.read(selectedFileProvider.notifier).select(file);
                  final profile = ref.read(selectedProfileProvider);
                  final variant = ref.read(selectedVariantProvider);
                  final layout = ref.read(selectedLayoutProvider);
                  if (profile == null || variant == null || layout == null) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('请先去工作台选择当前配置')),
                    );
                    context.go('/workbench', extra: file);
                    return;
                  }
                  context.go('/preview');
                },
                onRemoveFromCurrentPlaylist: () async {
                  final removed = await ref
                      .read(musicLibraryProvider.notifier)
                      .removeFilesFromPlaylist(currentPlaylist.id, <String>[
                        file.fileName,
                      ]);
                  if (!context.mounted || removed <= 0) {
                    return;
                  }
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('已从${currentPlaylist.name}移除')),
                  );
                },
              );
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('加载失败: $e')),
      ),
    );
  }

  PreferredSizeWidget _buildNormalAppBar(
    BuildContext context,
    WidgetRef ref,
    LibraryPlaylistView currentPlaylist,
  ) {
    final playlists = ref.watch(availablePlaylistsProvider);
    return AppBar(
      title: const Text('曲库'),
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(108),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: SearchBar(
                      controller: _searchController,
                      hintText: '搜索乐曲...',
                      leading: const Icon(Icons.search),
                      onChanged: (value) {
                        ref.read(searchQueryProvider.notifier).set(value);
                      },
                      padding: const WidgetStatePropertyAll(
                        EdgeInsets.symmetric(horizontal: 16),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.tonalIcon(
                    onPressed: () => _importFiles(context, ref),
                    icon: const Icon(Icons.add),
                    label: const Text('导入'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 40,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    for (final playlist in playlists)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: GestureDetector(
                          onLongPress: playlist.isEditable
                              ? () =>
                                    _showPlaylistActions(context, ref, playlist)
                              : null,
                          child: InputChip(
                            label: Text(playlist.name),
                            selected: currentPlaylist.id == playlist.id,
                            showCheckmark: false,
                            avatar: playlist.isBuiltinFavorite
                                ? const Icon(Icons.favorite, size: 18)
                                : null,
                            onPressed: () {
                              ref
                                  .read(librarySelectionProvider.notifier)
                                  .clear();
                              ref
                                  .read(musicLibraryProvider.notifier)
                                  .setCurrentPlaylist(playlist.id);
                            },
                          ),
                        ),
                      ),
                    ActionChip(
                      avatar: const Icon(Icons.add, size: 18),
                      label: const Text('新建'),
                      onPressed: () => _createPlaylist(context, ref),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
      actions: const [CurrentTargetAction()],
    );
  }

  PreferredSizeWidget _buildSelectionAppBar(
    BuildContext context,
    WidgetRef ref,
    AsyncValue<List<MusicFile>> filteredAsync,
    LibraryPlaylistView currentPlaylist,
  ) {
    final selectedCount = ref.watch(librarySelectionProvider).length;
    return AppBar(
      leading: IconButton(
        icon: const Icon(Icons.close),
        onPressed: () => ref.read(librarySelectionProvider.notifier).clear(),
      ),
      title: Text('已选择 $selectedCount 首'),
      actions: [
        IconButton(
          tooltip: '全选',
          onPressed: () {
            final files = filteredAsync.value ?? const <MusicFile>[];
            ref
                .read(librarySelectionProvider.notifier)
                .selectAll(files.map((file) => file.fileName));
          },
          icon: const Icon(Icons.select_all),
        ),
        IconButton(
          tooltip: '反选',
          onPressed: () {
            final files = filteredAsync.value ?? const <MusicFile>[];
            ref
                .read(librarySelectionProvider.notifier)
                .invert(files.map((file) => file.fileName));
          },
          icon: const Icon(Icons.flip),
        ),
        PopupMenuButton<_BatchAction>(
          onSelected: (action) {
            switch (action) {
              case _BatchAction.addToPlaylist:
                _batchAddToPlaylist(context, ref, currentPlaylist);
                break;
              case _BatchAction.removeFromCurrentPlaylist:
                _batchRemoveFromCurrentPlaylist(context, ref, currentPlaylist);
                break;
              case _BatchAction.export:
                _batchExport(context, ref);
                break;
              case _BatchAction.delete:
                _batchDelete(context, ref);
                break;
            }
          },
          itemBuilder: (context) => <PopupMenuEntry<_BatchAction>>[
            const PopupMenuItem<_BatchAction>(
              value: _BatchAction.addToPlaylist,
              child: Text('批量加入歌单'),
            ),
            if (!currentPlaylist.isVirtual)
              PopupMenuItem<_BatchAction>(
                value: _BatchAction.removeFromCurrentPlaylist,
                child: Text('移出${currentPlaylist.name}'),
              ),
            const PopupMenuItem<_BatchAction>(
              value: _BatchAction.export,
              child: Text('批量导出'),
            ),
            PopupMenuItem<_BatchAction>(
              value: _BatchAction.delete,
              child: Text(
                '批量删除',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _importFiles(BuildContext context, WidgetRef ref) async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: <String>[
        'mid',
        'midi',
        'dms',
        'txt',
        'json',
        if (!kIsWeb) 'zip',
      ],
      allowMultiple: true,
      withData: kIsWeb,
    );
    if (result == null || result.files.isEmpty) {
      return;
    }

    final pickedFiles = result.files
        .map(
          (file) => PickedFileData(
            fileName: file.name,
            sourcePath: file.path,
            bytes: file.bytes,
          ),
        )
        .where((file) => file.hasReadableContent)
        .toList();
    if (pickedFiles.isEmpty) {
      return;
    }
    if (!context.mounted) {
      return;
    }
    await runMusicImportFlow(context, ref, pickedFiles);
  }

  Future<void> _createPlaylist(BuildContext context, WidgetRef ref) async {
    final watch = Stopwatch()..start();
    void logPhase(String phase, [String details = '']) {
      _logPlaylistCreate(
        'phase=$phase elapsed_ms=${watch.elapsedMilliseconds} '
        'scheduler=${WidgetsBinding.instance.schedulerPhase.name} '
        'mounted=${context.mounted}'
        '${details.isEmpty ? '' : ' $details'}',
      );
    }

    final messenger = ScaffoldMessenger.of(context);
    logPhase('dialog_start');
    final name = await _showPlaylistNameDialog(
      context,
      title: '新建歌单',
      confirmLabel: '创建',
    );
    logPhase('dialog_done', 'accepted=${name != null}');
    if (!context.mounted || name == null) {
      logPhase('cancelled');
      return;
    }
    logPhase('provider_start');
    final created = await ref
        .read(musicLibraryProvider.notifier)
        .createPlaylist(name);
    logPhase('provider_done', 'created=$created');
    messenger.showSnackBar(
      SnackBar(content: Text(created ? '歌单已创建' : '歌单创建失败，名称可能重复')),
    );
    logPhase('snackbar_shown');
  }

  Future<void> _showPlaylistActions(
    BuildContext context,
    WidgetRef ref,
    LibraryPlaylistView playlist,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final action = await showModalBottomSheet<_PlaylistAction>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('重命名歌单'),
              onTap: () => Navigator.of(context).pop(_PlaylistAction.rename),
            ),
            ListTile(
              leading: Icon(
                Icons.delete_outline,
                color: Theme.of(context).colorScheme.error,
              ),
              title: Text(
                '删除歌单',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              onTap: () => Navigator.of(context).pop(_PlaylistAction.delete),
            ),
          ],
        ),
      ),
    );
    if (!context.mounted || action == null) {
      return;
    }
    switch (action) {
      case _PlaylistAction.rename:
        final name = await _showPlaylistNameDialog(
          context,
          title: '重命名歌单',
          confirmLabel: '保存',
          initialValue: playlist.name,
        );
        if (!context.mounted || name == null) {
          return;
        }
        final renamed = await ref
            .read(musicLibraryProvider.notifier)
            .renamePlaylist(playlist.id, name);
        messenger.showSnackBar(
          SnackBar(content: Text(renamed ? '歌单已重命名' : '歌单重命名失败')),
        );
        break;
      case _PlaylistAction.delete:
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('删除歌单'),
            content: Text('确定删除歌单“${playlist.name}”吗？歌曲文件不会被删除。'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                style: FilledButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.error,
                  foregroundColor: Theme.of(context).colorScheme.onError,
                ),
                child: const Text('删除'),
              ),
            ],
          ),
        );
        if (!context.mounted || confirmed != true) {
          return;
        }
        final deleted = await ref
            .read(musicLibraryProvider.notifier)
            .deletePlaylist(playlist.id);
        messenger.showSnackBar(
          SnackBar(content: Text(deleted ? '歌单已删除' : '歌单删除失败')),
        );
        break;
    }
  }

  Future<String?> _showPlaylistNameDialog(
    BuildContext context, {
    required String title,
    required String confirmLabel,
    String initialValue = '',
  }) async {
    final watch = Stopwatch()..start();
    void logPhase(String phase, [String details = '']) {
      _logPlaylistCreate(
        'phase=name_dialog_$phase title=$title '
        'elapsed_ms=${watch.elapsedMilliseconds} '
        'scheduler=${WidgetsBinding.instance.schedulerPhase.name} '
        'mounted=${context.mounted}'
        '${details.isEmpty ? '' : ' $details'}',
      );
    }

    logPhase('show_start');
    final result = await showDialog<String>(
      context: context,
      builder: (context) => _PlaylistNameDialog(
        title: title,
        confirmLabel: confirmLabel,
        initialValue: initialValue,
      ),
    );
    logPhase('show_done', 'has_result=${result != null}');
    final trimmed = result?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  Future<void> _batchAddToPlaylist(
    BuildContext context,
    WidgetRef ref,
    LibraryPlaylistView currentPlaylist,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final library = ref.read(musicLibraryProvider).value;
    if (library == null) {
      return;
    }
    final candidates = library.playlists
        .where((playlist) => playlist.id != currentPlaylist.id)
        .toList();
    if (candidates.isEmpty) {
      messenger.showSnackBar(const SnackBar(content: Text('还没有可加入的歌单')));
      return;
    }
    final playlistId = await showDialog<String>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: const Text('加入到歌单'),
        children: [
          for (final playlist in candidates)
            SimpleDialogOption(
              onPressed: () => Navigator.of(dialogContext).pop(playlist.id),
              child: Text(playlist.name),
            ),
        ],
      ),
    );
    if (!context.mounted || playlistId == null) {
      return;
    }
    final added = await ref
        .read(musicLibraryProvider.notifier)
        .addFilesToPlaylist(playlistId, ref.read(librarySelectionProvider));
    messenger.showSnackBar(
      SnackBar(content: Text(added > 0 ? '已加入 $added 首乐曲' : '没有新增乐曲')),
    );
  }

  Future<void> _batchRemoveFromCurrentPlaylist(
    BuildContext context,
    WidgetRef ref,
    LibraryPlaylistView currentPlaylist,
  ) async {
    final selection = ref.read(librarySelectionProvider);
    if (selection.isEmpty) {
      return;
    }
    final removed = await ref
        .read(musicLibraryProvider.notifier)
        .removeFilesFromPlaylist(currentPlaylist.id, selection);
    ref.read(librarySelectionProvider.notifier).clear();
    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已从${currentPlaylist.name}移除 $removed 首乐曲')),
    );
  }

  Future<void> _batchDelete(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final selection = ref.read(librarySelectionProvider);
    if (selection.isEmpty) {
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('批量删除'),
        content: Text('确定删除已选择的 ${selection.length} 首乐曲吗？这会删除实际文件。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (!context.mounted || confirmed != true) {
      return;
    }
    final deleted = await ref
        .read(musicLibraryProvider.notifier)
        .deleteFiles(selection);
    ref.read(librarySelectionProvider.notifier).clear();
    messenger.showSnackBar(SnackBar(content: Text('已删除 $deleted 首乐曲')));
  }

  Future<void> _batchExport(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final library = ref.read(musicLibraryProvider).value;
    if (library == null) {
      return;
    }
    final selection = ref.read(librarySelectionProvider);
    if (selection.isEmpty) {
      return;
    }
    final format = await showDialog<ExportFormat>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: const Text('批量导出'),
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

    final profile = ref.read(selectedProfileProvider);
    final variant = ref.read(selectedVariantProvider);
    final layout = ref.read(selectedLayoutProvider);
    if (format != ExportFormat.originalFile &&
        (profile == null || variant == null || layout == null)) {
      messenger.showSnackBar(const SnackBar(content: Text('批量导出前请先选择当前配置')));
      return;
    }

    try {
      final service = ref.read(songExportServiceProvider);
      final files = library.files
          .where((file) => selection.contains(file.fileName))
          .toList();
      final prepared = <PreparedSongExport>[];
      for (final file in files) {
        prepared.add(
          await service.prepareExport(
            file: file,
            format: format,
            profile: profile,
            variant: variant,
            layout: layout,
          ),
        );
      }
      List<String> outputs;
      if (kIsWeb) {
        outputs = <String>[];
        for (final item in prepared) {
          final outputPath = await FilePicker.saveFile(
            dialogTitle: '下载导出文件',
            fileName: item.fileName,
            type: FileType.custom,
            allowedExtensions: [_extensionForExport(item.fileName)],
            bytes: item.bytes,
          );
          if (outputPath != null) {
            outputs.add(outputPath);
          }
        }
      } else {
        final directoryPath = await FilePicker.getDirectoryPath(
          dialogTitle: '选择导出目录',
        );
        if (!context.mounted || directoryPath == null) {
          return;
        }
        outputs = await service.writePreparedExportsToDirectory(
          exports: prepared,
          directoryPath: directoryPath,
        );
        if (!context.mounted) {
          return;
        }
        messenger.showSnackBar(
          SnackBar(content: Text('已导出 ${outputs.length} 个文件到 $directoryPath')),
        );
        return;
      }
      if (!context.mounted) {
        return;
      }
      messenger.showSnackBar(
        SnackBar(content: Text('已下载 ${outputs.length} 个导出文件')),
      );
    } on CalibrationExportException catch (error) {
      if (!context.mounted) {
        return;
      }
      final goToCalibration = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('需要键位校准'),
          content: Text('$error\n\n批量导出已在打开目录选择器前停止。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('去校准'),
            ),
          ],
        ),
      );
      if (!context.mounted || goToCalibration != true) {
        return;
      }
      await launchCalibration(
        context: context,
        ref: ref,
        profile: profile!,
        layout: layout!,
      );
    } catch (e) {
      if (!context.mounted) {
        return;
      }
      messenger.showSnackBar(SnackBar(content: Text('批量导出失败: $e')));
    }
  }

  String _extensionForExport(String fileName) {
    final dot = fileName.lastIndexOf('.');
    return dot >= 0 ? fileName.substring(dot + 1) : 'bin';
  }
}

class MusicImportConflictDialog extends StatefulWidget {
  const MusicImportConflictDialog({required this.conflict, super.key});

  final MusicImportConflict conflict;

  @override
  State<MusicImportConflictDialog> createState() =>
      _MusicImportConflictDialogState();
}

class _MusicImportConflictDialogState extends State<MusicImportConflictDialog> {
  bool _applyToRemaining = false;

  void _finish(MusicImportConflictAction action) {
    Navigator.of(context).pop(
      MusicImportConflictDecision(
        action: action,
        applyToRemaining: action == MusicImportConflictAction.stop
            ? false
            : _applyToRemaining,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('发现同名曲目'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('曲库或本次导入中已存在：${widget.conflict.fileName}'),
          const SizedBox(height: 8),
          Text(
            '来源：${widget.conflict.sourceLabel}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: _applyToRemaining,
            title: const Text('应用到本次剩余冲突'),
            controlAffinity: ListTileControlAffinity.leading,
            onChanged: (value) {
              setState(() => _applyToRemaining = value ?? false);
            },
          ),
        ],
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => _finish(MusicImportConflictAction.stop),
          child: const Text('停止'),
        ),
        TextButton(
          onPressed: () => _finish(MusicImportConflictAction.skip),
          child: const Text('跳过'),
        ),
        TextButton(
          onPressed: () => _finish(MusicImportConflictAction.rename),
          child: const Text('重命名'),
        ),
        FilledButton(
          onPressed: () => _finish(MusicImportConflictAction.overwrite),
          child: const Text('覆盖'),
        ),
      ],
    );
  }
}

class MusicImportResultDialog extends StatelessWidget {
  const MusicImportResultDialog({required this.report, super.key});

  final MusicImportReport report;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('导入完成'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('成功 ${report.importedCount} 个，失败 ${report.failures.length} 个'),
            if (report.overwrittenCount > 0 ||
                report.renamedCount > 0 ||
                report.reusedCount > 0 ||
                report.skippedCount > 0 ||
                report.ignoredCount > 0) ...<Widget>[
              const SizedBox(height: 4),
              Text(
                '覆盖 ${report.overwrittenCount}，重命名 ${report.renamedCount}，'
                '沿用 ${report.reusedCount}，跳过 ${report.skippedCount}，'
                '忽略 ${report.ignoredCount}',
              ),
            ],
            if (report.stopped) ...<Widget>[
              const SizedBox(height: 8),
              const Text('导入已停止，停止前完成的内容已保留。'),
            ],
            const SizedBox(height: 12),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: report.archives.length + report.failures.length,
                separatorBuilder: (_, _) => const Divider(height: 16),
                itemBuilder: (context, index) {
                  if (index < report.archives.length) {
                    final archive = report.archives[index];
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          archive.playlistName,
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${archive.archiveFileName} · ${archive.memberCount} 首',
                        ),
                      ],
                    );
                  }
                  final failure =
                      report.failures[index - report.archives.length];
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        failure.fileName,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 2),
                      Text(failure.message),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('确定'),
        ),
      ],
    );
  }
}

class MusicImportProgressDialog extends StatelessWidget {
  const MusicImportProgressDialog({
    required this.progress,
    required this.stopRequested,
    required this.onStop,
    super.key,
  });

  final ValueListenable<MusicImportProgress> progress;
  final ValueListenable<bool> stopRequested;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: AlertDialog(
        title: const Text('正在导入曲目'),
        content: SizedBox(
          width: 420,
          child: ValueListenableBuilder<MusicImportProgress>(
            valueListenable: progress,
            builder: (context, value, _) => Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                LinearProgressIndicator(value: value.fraction),
                const SizedBox(height: 16),
                Text(value.sourceLabel),
                if (value.currentFileName case final current?) ...<Widget>[
                  const SizedBox(height: 4),
                  Text(
                    current,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
                if (value.totalCount > 0) ...<Widget>[
                  const SizedBox(height: 8),
                  Text('${value.processedCount} / ${value.totalCount}'),
                ],
                const SizedBox(height: 4),
                Text(
                  '成功 ${value.importedCount} · 沿用 ${value.reusedCount} · '
                  '跳过 ${value.skippedCount} · 失败 ${value.failedCount} · '
                  '忽略 ${value.ignoredCount}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
        actions: <Widget>[
          ValueListenableBuilder<bool>(
            valueListenable: stopRequested,
            builder: (context, stopped, _) => TextButton(
              onPressed: stopped ? null : onStop,
              child: Text(stopped ? '正在停止…' : '停止导入'),
            ),
          ),
        ],
      ),
    );
  }
}

enum _PlaylistAction { rename, delete }

enum _BatchAction { addToPlaylist, removeFromCurrentPlaylist, export, delete }

class _PlaylistNameDialog extends StatefulWidget {
  const _PlaylistNameDialog({
    required this.title,
    required this.confirmLabel,
    required this.initialValue,
  });

  final String title;
  final String confirmLabel;
  final String initialValue;

  @override
  State<_PlaylistNameDialog> createState() => _PlaylistNameDialogState();
}

class _PlaylistNameDialogState extends State<_PlaylistNameDialog> {
  late final TextEditingController _controller;
  final Stopwatch _watch = Stopwatch()..start();

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
    _logPhase('controller_create');
  }

  @override
  void dispose() {
    _logPhase('controller_dispose_start');
    _controller.dispose();
    _logPhase('controller_dispose_done');
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: const InputDecoration(hintText: '输入歌单名称'),
        onSubmitted: (_) => _finish('submit'),
      ),
      actions: [
        TextButton(
          onPressed: () {
            _logPhase('cancel_tap');
            Navigator.of(context).pop();
          },
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => _finish('confirm_tap'),
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }

  void _finish(String phase) {
    _logPhase(phase);
    Navigator.of(context).pop(_controller.text.trim());
  }

  void _logPhase(String phase) {
    _logPlaylistCreate(
      'phase=name_dialog_$phase title=${widget.title} '
      'elapsed_ms=${_watch.elapsedMilliseconds} '
      'scheduler=${WidgetsBinding.instance.schedulerPhase.name} '
      'mounted=$mounted',
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.hasAnyFile,
    required this.currentPlaylistName,
    required this.isAllSongs,
    required this.hasQuery,
  });

  final bool hasAnyFile;
  final String currentPlaylistName;
  final bool isAllSongs;
  final bool hasQuery;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    late final String title;
    late final String subtitle;
    if (!hasAnyFile) {
      title = '还没有音乐文件';
      subtitle = '使用搜索框旁边的导入按钮添加文件';
    } else if (hasQuery) {
      title = '没有匹配的乐曲';
      subtitle = '换个关键词试试';
    } else if (!isAllSongs) {
      title = '歌单还是空的';
      subtitle = '把乐曲加入“$currentPlaylistName”后会显示在这里';
    } else {
      title = '还没有可显示的乐曲';
      subtitle = '试试切换歌单或重新导入';
    }

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.library_music_outlined, size: 64, color: scheme.outline),
          const SizedBox(height: 16),
          Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(color: scheme.outline),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: scheme.outline),
          ),
        ],
      ),
    );
  }
}
