import 'package:flutter/material.dart';

import '../models/track.dart';
import '../utils/formatters.dart';

/// 재생목록/파일목록 공용 행
class TrackTile extends StatelessWidget {
  const TrackTile({
    super.key,
    required this.track,
    required this.selected,
    required this.isCurrent,
    required this.onTap,
    required this.onSelectChanged,
    this.onLongPress,
    this.playCount,
    this.trailingBadge,
  });

  final Track track;
  final bool selected;
  final bool isCurrent;
  final VoidCallback onTap;
  final ValueChanged<bool> onSelectChanged;
  final VoidCallback? onLongPress;

  /// null 이면 재생 횟수를 표시하지 않음 (파일 목록)
  final int? playCount;

  /// 추가 배지 (예: 재생목록에 이미 있음)
  final Widget? trailingBadge;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return ListTile(
      selected: isCurrent,
      selectedTileColor: cs.primary.withValues(alpha: 0.08),
      onTap: onTap,
      onLongPress: onLongPress,
      leading: Checkbox(
        value: selected,
        onChanged: (v) => onSelectChanged(v ?? false),
        visualDensity: VisualDensity.compact,
      ),
      title: Row(
        children: [
          if (isCurrent) ...[
            Icon(Icons.graphic_eq_rounded, size: 16, color: cs.primary),
            const SizedBox(width: 4),
          ],
          Expanded(
            child: Text(
              track.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w500,
                color: isCurrent ? cs.primary : null,
              ),
            ),
          ),
        ],
      ),
      subtitle: Text(
        track.subtitle,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: cs.onSurfaceVariant),
      ),
      trailing: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            formatDuration(track.duration),
            style: theme.textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant),
          ),
          if (playCount != null && playCount! > 0) ...[
            const SizedBox(height: 3),
            _CountBadge(count: playCount!),
          ] else if (trailingBadge != null) ...[
            const SizedBox(height: 3),
            trailingBadge!,
          ],
        ],
      ),
    );
  }
}

class _CountBadge extends StatelessWidget {
  const _CountBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: cs.secondaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        '▶ $count회',
        style: TextStyle(fontSize: 10, color: cs.onSecondaryContainer),
      ),
    );
  }
}
