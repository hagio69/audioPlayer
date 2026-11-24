import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/track.dart';
import '../providers/library_provider.dart';
import '../providers/player_provider.dart';
import 'dialogs.dart';
import 'empty_state.dart';
import 'sort_menu_button.dart';
import 'track_tile.dart';

/// 재생목록 탭 ([index]: 0 = 재생목록1, 1 = 재생목록2)
/// - 탭: 해당 곡부터 재생
/// - 체크박스: 다중 선택 → 선택 곡만으로 재생 큐 구성 (해제 시 전체 목록 기준)
/// - 길게 누르기: 곡 메뉴(재생 횟수 초기화, 제거 등)
class PlaylistTab extends StatelessWidget {
  const PlaylistTab({super.key, required this.index});

  final int index;

  @override
  Widget build(BuildContext context) {
    final library = context.watch<LibraryProvider>();
    final currentPath = context.select<PlayerProvider, String?>((p) => p.currentTrack?.path);
    final tracks = library.sortedPlaylist(index);
    final selection = library.playlistSelection(index);

    return Column(
      children: [
        _Toolbar(index: index, count: tracks.length),
        if (selection.isNotEmpty) _SelectionBanner(index: index, count: selection.length),
        if (library.importing) const LinearProgressIndicator(minHeight: 2),
        Expanded(
          child: tracks.isEmpty
              ? EmptyState(
                  icon: Icons.queue_music_rounded,
                  title: '${library.playlistName(index)}이(가) 비어 있습니다',
                  message: '파일 목록에서 곡을 선택해 추가하거나\n파일을 직접 골라 추가하세요.',
                  actions: [
                    OutlinedButton.icon(
                      icon: const Icon(Icons.folder_open_rounded),
                      label: const Text('파일 목록으로'),
                      onPressed: () => DefaultTabController.of(context)
                          .animateTo(LibraryProvider.playlistCount),
                    ),
                    FilledButton.tonalIcon(
                      icon: const Icon(Icons.library_add_rounded),
                      label: const Text('파일 직접 선택'),
                      onPressed: () => _importFiles(context, index),
                    ),
                  ],
                )
              : ListView.builder(
                  padding: const EdgeInsets.only(bottom: 16),
                  itemCount: tracks.length,
                  itemBuilder: (context, i) {
                    final t = tracks[i];
                    return TrackTile(
                      key: ValueKey(t.path),
                      track: t,
                      selected: selection.contains(t.path),
                      isCurrent: t.path == currentPath,
                      playCount: library.playCountOf(t.path),
                      onTap: () => context.read<PlayerProvider>().playFromPlaylist(index, t),
                      onSelectChanged: (_) => library.togglePlaylistSelection(index, t.path),
                      onLongPress: () => _showTrackMenu(context, index, t),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

Future<void> _importFiles(BuildContext context, int index) async {
  final library = context.read<LibraryProvider>();
  final added = await library.importFilesToPlaylist(index);
  if (!context.mounted || added == null) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(added > 0
          ? '${library.playlistName(index)}에 $added곡을 추가했습니다.'
          : '추가된 곡이 없습니다 (이미 있거나 지원하지 않는 파일).'),
    ),
  );
}

Future<void> _showTrackMenu(BuildContext context, int index, Track track) {
  final library = context.read<LibraryProvider>();
  final player = context.read<PlayerProvider>();
  final selected = library.playlistSelection(index).contains(track.path);
  final count = library.playCountOf(track.path);
  final otherIndexes = [
    for (var i = 0; i < LibraryProvider.playlistCount; i++)
      if (i != index) i,
  ];

  return showModalBottomSheet<void>(
    context: context,
    builder: (ctx) => SafeArea(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(track.title, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text('${track.subtitle}\n${track.fileName}',
                  maxLines: 2, overflow: TextOverflow.ellipsis),
              isThreeLine: true,
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.play_arrow_rounded),
              title: const Text('재생'),
              onTap: () {
                Navigator.pop(ctx);
                player.playFromPlaylist(index, track);
              },
            ),
            ListTile(
              leading: Icon(selected ? Icons.check_box_outline_blank : Icons.check_box_outlined),
              title: Text(selected ? '선택 해제' : '선택'),
              onTap: () {
                Navigator.pop(ctx);
                library.togglePlaylistSelection(index, track.path);
              },
            ),
            for (final other in otherIndexes)
              ListTile(
                leading: const Icon(Icons.playlist_add_rounded),
                title: Text('${library.playlistName(other)}에도 추가'),
                enabled: !library.isInPlaylist(other, track.path),
                onTap: () {
                  Navigator.pop(ctx);
                  library.addTracksToPlaylist(other, [track]);
                },
              ),
            ListTile(
              leading: const Icon(Icons.restart_alt_rounded),
              title: Text('재생 횟수 초기화 (현재 $count회)'),
              enabled: count > 0,
              onTap: () {
                Navigator.pop(ctx);
                library.resetPlayCount(track.path);
              },
            ),
            ListTile(
              leading: const Icon(Icons.playlist_remove_rounded),
              title: Text('${library.playlistName(index)}에서 제거'),
              onTap: () {
                Navigator.pop(ctx);
                library.removeFromPlaylist(index, [track.path]);
              },
            ),
          ],
        ),
      ),
    ),
  );
}

class _Toolbar extends StatelessWidget {
  const _Toolbar({required this.index, required this.count});

  final int index;
  final int count;

  @override
  Widget build(BuildContext context) {
    final library = context.watch<LibraryProvider>();
    final theme = Theme.of(context);
    final selection = library.playlistSelection(index);
    final allSelected = count > 0 && selection.length == count;
    final name = library.playlistName(index);

    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
      child: Row(
        children: [
          IconButton(
            tooltip: '이름 편집',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.edit_rounded, size: 18),
            onPressed: () => showRenamePlaylistDialog(context, index),
          ),
          Expanded(
            child: Text(
              '$count곡',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          SortMenuButton(
            option: library.playlistSort(index),
            onChanged: (o) => library.setPlaylistSort(index, o),
          ),
          IconButton(
            tooltip: allSelected ? '전체 선택 해제' : '전체 선택',
            visualDensity: VisualDensity.compact,
            icon: Icon(allSelected ? Icons.deselect_rounded : Icons.select_all_rounded),
            onPressed: count == 0
                ? null
                : () {
                    if (allSelected) {
                      library.clearPlaylistSelection(index);
                    } else {
                      library.selectAllPlaylist(index);
                    }
                  },
          ),
          IconButton(
            tooltip: '파일 직접 선택해 추가',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.library_add_rounded),
            onPressed: library.importing ? null : () => _importFiles(context, index),
          ),
          PopupMenuButton<String>(
            tooltip: '더보기',
            icon: const Icon(Icons.more_vert_rounded),
            onSelected: (v) async {
              switch (v) {
                case 'rename':
                  await showRenamePlaylistDialog(context, index);
                case 'reset_counts':
                  final confirmed = await showConfirmDialog(
                    context,
                    title: '재생 횟수 초기화',
                    message: selection.isNotEmpty
                        ? '선택한 ${selection.length}곡의 재생 횟수를 초기화할까요?'
                        : '$name 전체 곡의 재생 횟수를 초기화할까요?',
                    confirmLabel: '초기화',
                  );
                  if (!confirmed) return;
                  library.resetPlayCounts(selection.isNotEmpty
                      ? selection.toList()
                      : library.playlistTracks(index).map((t) => t.path).toList());
                case 'clear':
                  final cleared = await showConfirmDialog(
                    context,
                    title: '$name 비우기',
                    message: '$name의 모든 곡을 제거할까요? (파일은 삭제되지 않습니다)',
                    confirmLabel: '비우기',
                    destructive: true,
                  );
                  if (cleared) library.clearPlaylist(index);
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'rename', child: Text('이름 편집')),
              PopupMenuItem(
                value: 'reset_counts',
                enabled: count > 0,
                child: Text(selection.isNotEmpty ? '선택 곡 재생 횟수 초기화' : '재생 횟수 초기화'),
              ),
              PopupMenuItem(
                value: 'clear',
                enabled: count > 0,
                child: Text('$name 비우기'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 선택 곡 큐 안내 배너
class _SelectionBanner extends StatelessWidget {
  const _SelectionBanner({required this.index, required this.count});

  final int index;
  final int count;

  @override
  Widget build(BuildContext context) {
    final library = context.read<LibraryProvider>();
    final player = context.read<PlayerProvider>();
    final cs = Theme.of(context).colorScheme;

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 2, 12, 4),
      padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
      decoration: BoxDecoration(
        color: cs.tertiaryContainer.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.playlist_play_rounded, size: 20, color: cs.onTertiaryContainer),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '$count곡 선택 · 선택한 곡만 재생 큐로 사용',
              maxLines: 2,
              style: TextStyle(fontSize: 12, color: cs.onTertiaryContainer),
            ),
          ),
          IconButton(
            tooltip: '선택 곡 재생',
            visualDensity: VisualDensity.compact,
            icon: Icon(Icons.play_circle_fill_rounded, color: cs.onTertiaryContainer),
            onPressed: () => player.playPlaylist(index),
          ),
          IconButton(
            tooltip: '선택 항목 제거',
            visualDensity: VisualDensity.compact,
            icon: Icon(Icons.delete_outline_rounded, color: cs.onTertiaryContainer),
            onPressed: () async {
              final ok = await showConfirmDialog(
                context,
                title: '선택 항목 제거',
                message: '선택한 $count곡을 ${library.playlistName(index)}에서 제거할까요?',
                confirmLabel: '제거',
                destructive: true,
              );
              if (ok) library.removeSelectedFromPlaylist(index);
            },
          ),
          TextButton(
            onPressed: () => library.clearPlaylistSelection(index),
            child: const Text('해제'),
          ),
        ],
      ),
    );
  }
}
