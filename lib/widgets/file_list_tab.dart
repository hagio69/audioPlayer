import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/library_provider.dart';
import '../providers/player_provider.dart';
import 'dialogs.dart';
import 'empty_state.dart';
import 'sort_menu_button.dart';
import 'track_tile.dart';

/// '파일 목록' 탭
/// - 폴더 선택 → 하위 폴더까지 오디오 파일 스캔
/// - 탭: 폴더 전체를 큐로 재생
/// - 체크박스 다중 선택 → '재생목록에 추가'
class FileListTab extends StatelessWidget {
  const FileListTab({super.key});

  @override
  Widget build(BuildContext context) {
    final library = context.watch<LibraryProvider>();
    final currentPath = context.select<PlayerProvider, String?>((p) => p.currentTrack?.path);
    final tracks = library.sortedFolderTracks;
    final selection = library.folderSelection;

    Widget body;
    if (library.scanning && tracks.isEmpty) {
      body = _ScanningView(done: library.scanDone, total: library.scanTotal);
    } else if (library.folderPath == null) {
      body = EmptyState(
        icon: Icons.folder_open_rounded,
        title: '폴더를 선택하세요',
        message: '선택한 폴더(하위 폴더 포함)에서\nMP3, M4A, WAV 등 오디오 파일을 찾습니다.',
        actions: [
          FilledButton.icon(
            icon: const Icon(Icons.create_new_folder_outlined),
            label: const Text('폴더 선택'),
            onPressed: () => pickFolderFlow(context),
          ),
          if (Platform.isIOS)
            OutlinedButton.icon(
              icon: const Icon(Icons.folder_shared_outlined),
              label: const Text('앱 폴더 보기'),
              onPressed: library.scanAppDocuments,
            ),
        ],
      );
    } else if (tracks.isEmpty) {
      body = EmptyState(
        icon: library.scanError != null ? Icons.error_outline_rounded : Icons.music_off_rounded,
        title: library.scanError != null ? '폴더를 읽을 수 없습니다' : '오디오 파일이 없습니다',
        message: library.scanError ??
            (Platform.isIOS && library.folderPath == library.storage.documentsDir
                ? '파일 앱 > 나의 iPhone > hagioAudioPlayer 폴더에\n음악 파일을 복사한 뒤 새로고침하세요.'
                : '다른 폴더를 선택해 보세요.'),
        actions: [
          FilledButton.tonalIcon(
            icon: const Icon(Icons.create_new_folder_outlined),
            label: const Text('다른 폴더 선택'),
            onPressed: () => pickFolderFlow(context),
          ),
          OutlinedButton.icon(
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('새로고침'),
            onPressed: library.rescan,
          ),
        ],
      );
    } else {
      body = ListView.builder(
        padding: const EdgeInsets.only(bottom: 16),
        itemCount: tracks.length,
        itemBuilder: (context, i) {
          final t = tracks[i];
          return TrackTile(
            key: ValueKey(t.path),
            track: t,
            selected: selection.contains(t.path),
            isCurrent: t.path == currentPath,
            trailingBadge: _InPlaylistBadge(
              indexes: library.playlistsContaining(t.path),
            ),
            onTap: () => context.read<PlayerProvider>().playFromFolder(t),
            onSelectChanged: (_) => library.toggleFolderSelection(t.path),
            onLongPress: () => library.toggleFolderSelection(t.path),
          );
        },
      );
    }

    return Column(
      children: [
        const _FolderHeader(),
        if (library.scanning && tracks.isNotEmpty)
          LinearProgressIndicator(
            minHeight: 2,
            value: library.scanTotal > 0 ? library.scanDone / library.scanTotal : null,
          ),
        Expanded(child: body),
        if (selection.isNotEmpty) _AddToPlaylistBar(count: selection.length),
      ],
    );
  }
}

/// 폴더 선택 → 권한 거부 시 안내 다이얼로그
Future<void> pickFolderFlow(BuildContext context) async {
  final library = context.read<LibraryProvider>();
  final result = await library.pickFolder();
  if (!context.mounted) return;

  switch (result) {
    case FolderPickResult.permissionDenied:
      await showPermissionDeniedDialog(
        context,
        permanentlyDenied: false,
        onRetry: () => pickFolderFlow(context),
      );
    case FolderPickResult.permissionPermanentlyDenied:
      await showPermissionDeniedDialog(context, permanentlyDenied: true);
    case FolderPickResult.failed:
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(library.scanError ?? '폴더를 불러오지 못했습니다.')),
      );
    case FolderPickResult.success:
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('오디오 파일 ${library.sortedFolderTracks.length}개를 찾았습니다.')),
      );
    case FolderPickResult.cancelled:
      break;
  }
}

class _FolderHeader extends StatelessWidget {
  const _FolderHeader();

  @override
  Widget build(BuildContext context) {
    final library = context.watch<LibraryProvider>();
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final count = library.sortedFolderTracks.length;
    final allSelected = count > 0 && library.folderSelection.length == count;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 4, 0),
      child: Column(
        children: [
          Row(
            children: [
              Icon(Icons.folder_rounded, size: 18, color: cs.primary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  library.folderName ?? '선택된 폴더 없음',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall,
                ),
              ),
              IconButton(
                tooltip: '새로고침',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.refresh_rounded),
                onPressed: library.folderPath == null || library.scanning ? null : library.rescan,
              ),
              if (Platform.isIOS)
                IconButton(
                  tooltip: '앱 폴더 보기',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.folder_shared_outlined),
                  onPressed: library.scanning ? null : library.scanAppDocuments,
                ),
              TextButton.icon(
                icon: const Icon(Icons.create_new_folder_outlined, size: 18),
                label: const Text('폴더 선택'),
                onPressed: library.scanning ? null : () => pickFolderFlow(context),
              ),
            ],
          ),
          if (library.folderPath != null)
            Row(
              children: [
                Expanded(
                  child: Text(
                    library.scanning
                        ? '분석 중 ${library.scanDone}/${library.scanTotal}'
                        : '$count개 파일',
                    style: theme.textTheme.labelLarge?.copyWith(color: cs.onSurfaceVariant),
                  ),
                ),
                SortMenuButton(
                  option: library.folderSort,
                  onChanged: library.setFolderSort,
                ),
                IconButton(
                  tooltip: allSelected ? '전체 선택 해제' : '전체 선택',
                  visualDensity: VisualDensity.compact,
                  icon: Icon(allSelected ? Icons.deselect_rounded : Icons.select_all_rounded),
                  onPressed: count == 0
                      ? null
                      : (allSelected ? library.clearFolderSelection : library.selectAllFolder),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _ScanningView extends StatelessWidget {
  const _ScanningView({required this.done, required this.total});

  final int done;
  final int total;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 16),
          Text(total == 0 ? '오디오 파일 검색 중...' : '메타데이터 분석 중 $done / $total'),
        ],
      ),
    );
  }
}

class _InPlaylistBadge extends StatelessWidget {
  const _InPlaylistBadge({required this.indexes});

  final List<int> indexes;

  @override
  Widget build(BuildContext context) {
    if (indexes.isEmpty) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.playlist_add_check_rounded, size: 14, color: cs.primary),
        Text(
          indexes.map((i) => '${i + 1}').join(','),
          style: TextStyle(fontSize: 10, color: cs.primary),
        ),
      ],
    );
  }
}

/// 선택한 파일을 재생목록1 / 재생목록2 중 하나에 추가
class _AddToPlaylistBar extends StatelessWidget {
  const _AddToPlaylistBar({required this.count});

  final int count;

  Future<void> _add(BuildContext context, int index) async {
    final library = context.read<LibraryProvider>();
    final added = library.addSelectedFolderTracksToPlaylist(index);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(added > 0
          ? '${library.playlistName(index)}에 $added곡을 추가했습니다.'
          : '선택한 곡이 이미 ${library.playlistName(index)}에 있습니다.'),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final library = context.watch<LibraryProvider>();
    final cs = Theme.of(context).colorScheme;

    return Material(
      color: cs.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 6, 8, 6),
        child: Row(
          children: [
            Expanded(child: Text('$count개 선택')),
            TextButton(
              onPressed: library.clearFolderSelection,
              child: const Text('취소'),
            ),
            PopupMenuButton<int>(
              tooltip: '재생목록에 추가',
              onSelected: (i) => _add(context, i),
              itemBuilder: (_) => [
                for (var i = 0; i < LibraryProvider.playlistCount; i++)
                  PopupMenuItem<int>(
                    value: i,
                    child: Text('${library.playlistName(i)}에 추가'),
                  ),
              ],
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: cs.primary,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.playlist_add_rounded, size: 18, color: cs.onPrimary),
                    const SizedBox(width: 6),
                    Text('재생목록에 추가',
                        style: TextStyle(color: cs.onPrimary, fontWeight: FontWeight.w600)),
                    Icon(Icons.arrow_drop_up_rounded, color: cs.onPrimary),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
