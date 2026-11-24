import 'package:flutter/material.dart';

import '../utils/sort_option.dart';

/// 정렬 기준(파일 이름/앨범/아티스트) + 방향(오름/내림) 선택 메뉴
class SortMenuButton extends StatelessWidget {
  const SortMenuButton({
    super.key,
    required this.option,
    required this.onChanged,
  });

  final SortOption option;
  final ValueChanged<SortOption> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PopupMenuButton<Object>(
      tooltip: '정렬',
      onSelected: (value) {
        if (value is SortField) {
          onChanged(option.copyWith(field: value));
        } else if (value is bool) {
          onChanged(option.copyWith(ascending: value));
        }
      },
      itemBuilder: (_) => <PopupMenuEntry<Object>>[
        for (final f in SortField.values)
          CheckedPopupMenuItem<Object>(
            value: f,
            checked: option.field == f,
            child: Text(f.label),
          ),
        const PopupMenuDivider(),
        CheckedPopupMenuItem<Object>(
          value: true,
          checked: option.ascending,
          child: const Text('오름차순 (A→Z)'),
        ),
        CheckedPopupMenuItem<Object>(
          value: false,
          checked: !option.ascending,
          child: const Text('내림차순 (Z→A)'),
        ),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.sort_rounded, size: 18, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(width: 4),
            Text(option.field.label, style: theme.textTheme.labelMedium),
            Icon(
              option.ascending
                  ? Icons.arrow_upward_rounded
                  : Icons.arrow_downward_rounded,
              size: 14,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}
