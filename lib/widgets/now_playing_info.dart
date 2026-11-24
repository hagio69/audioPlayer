import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/track.dart';
import '../providers/library_provider.dart';
import '../providers/player_provider.dart';

/// 현재 재생 곡 정보 (제목 / 아티스트 · 앨범 / 큐 출처)
class NowPlayingInfo extends StatelessWidget {
  const NowPlayingInfo({super.key});

  @override
  Widget build(BuildContext context) {
    final track = context.select<PlayerProvider, Track?>((p) => p.currentTrack);
    final source = context.select<PlayerProvider, QueueSource>((p) => p.source);
    final queueLength = context.select<PlayerProvider, int>((p) => p.queueLength);
    final playlistIndex = context.select<PlayerProvider, int>((p) => p.playlistIndex);
    final playlistName =
        context.select<LibraryProvider, String>((l) => l.playlistName(playlistIndex));
    final selectionCount = context
        .select<LibraryProvider, int>((l) => l.playlistSelection(playlistIndex).length);
    final selectionQueue = source == QueueSource.playlist && selectionCount > 0;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final queueLabel = switch (source) {
      QueueSource.playlist when selectionCount > 0 => '$playlistName · 선택 $selectionCount곡',
      QueueSource.playlist => '$playlistName · $queueLength곡',
      QueueSource.folder => '파일 목록 · $queueLength곡',
      QueueSource.none => null,
    };

    return Row(
      children: [
        Container(
          width: 60,
          height: 60,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [cs.primary.withValues(alpha: 0.85), cs.tertiary.withValues(alpha: 0.6)],
            ),
          ),
          child: Icon(Icons.music_note_rounded, color: cs.onPrimary, size: 30),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                track?.title ?? '재생 중인 곡 없음',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 2),
              Text(
                track?.subtitle ?? '아래 목록에서 곡을 선택하세요',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
              ),
              if (queueLabel != null) ...[
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: selectionQueue
                        ? cs.tertiaryContainer
                        : cs.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    queueLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
