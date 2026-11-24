import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/player_provider.dart';
import '../utils/formatters.dart';

/// 실시간 재생 위치 슬라이더 + 현재 시간 / 전체 시간
///
/// 드래그하는 동안:
///  - 드래그를 시작한 '처음 위치'까지 보조 트랙(다른 색)으로 표시
///  - 가운데에 "처음 1:23 → 2:45 (+1:22)" 형태로 처음 위치와 이동량 표시
class SeekBar extends StatefulWidget {
  const SeekBar({super.key});

  @override
  State<SeekBar> createState() => _SeekBarState();
}

class _SeekBarState extends State<SeekBar> {
  late final Stream<Duration> _positionStream;
  late final Stream<Duration?> _durationStream;

  /// 드래그 중인 값(ms). 드래그 중에는 스트림 값 대신 이 값을 표시
  double? _dragValue;

  /// 드래그를 시작한 처음 위치(ms)
  double? _dragStart;

  @override
  void initState() {
    super.initState();
    final player = context.read<PlayerProvider>();
    _positionStream = player.positionStream;
    _durationStream = player.durationStream;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final labelStyle = theme.textTheme.labelSmall?.copyWith(
      color: cs.onSurfaceVariant,
      fontFeatures: const [FontFeature.tabularFigures()],
    );

    return StreamBuilder<Duration?>(
      stream: _durationStream,
      builder: (context, durSnap) {
        final duration = durSnap.data ?? Duration.zero;
        final maxMs = duration.inMilliseconds.toDouble();
        final enabled = maxMs > 0;

        return StreamBuilder<Duration>(
          stream: _positionStream,
          builder: (context, posSnap) {
            final positionMs = (posSnap.data ?? Duration.zero).inMilliseconds.toDouble();
            final value = enabled ? (_dragValue ?? positionMs).clamp(0.0, maxMs) : 0.0;
            final start = _dragStart;

            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  height: 32,
                  child: Slider(
                    min: 0,
                    max: enabled ? maxMs : 1.0,
                    value: value,
                    secondaryTrackValue:
                        (start != null && _dragValue != null) ? start.clamp(0.0, maxMs) : null,
                    secondaryActiveColor: cs.tertiary.withValues(alpha: 0.7),
                    onChangeStart: enabled
                        ? (v) => setState(() {
                              _dragStart = positionMs.clamp(0.0, maxMs);
                              _dragValue = v;
                            })
                        : null,
                    onChanged: enabled ? (v) => setState(() => _dragValue = v) : null,
                    onChangeEnd: enabled
                        ? (v) {
                            context.read<PlayerProvider>().seek(Duration(milliseconds: v.round()));
                            setState(() {
                              _dragValue = null;
                              _dragStart = null;
                            });
                          }
                        : null,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    children: [
                      Text(formatDuration(Duration(milliseconds: value.round())), style: labelStyle),
                      Expanded(
                        child: (start != null && _dragValue != null)
                            ? _StartIndicator(startMs: start, targetMs: value)
                            : const SizedBox.shrink(),
                      ),
                      Text(enabled ? formatDuration(duration) : '--:--', style: labelStyle),
                    ],
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

class _StartIndicator extends StatelessWidget {
  const _StartIndicator({required this.startMs, required this.targetMs});

  final double startMs;
  final double targetMs;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final diff = Duration(milliseconds: (targetMs - startMs).round());
    final sign = diff.isNegative ? '−' : '+';
    final absDiff = Duration(milliseconds: diff.inMilliseconds.abs());

    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: cs.tertiaryContainer,
          borderRadius: BorderRadius.circular(10),
        ),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            '처음 ${formatDuration(Duration(milliseconds: startMs.round()))} → '
            '${formatDuration(Duration(milliseconds: targetMs.round()))} '
            '($sign${formatDuration(absDiff)})',
            style: TextStyle(
              fontSize: 11,
              color: cs.onTertiaryContainer,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ),
    );
  }
}
