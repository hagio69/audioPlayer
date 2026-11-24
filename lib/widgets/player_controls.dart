import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:provider/provider.dart';

import '../models/player_settings.dart';
import '../providers/player_provider.dart';
import '../utils/formatters.dart';

/// 1행: 이전 곡 / 30초 뒤로 / 10초 뒤로 / 재생·일시정지 / 10초 앞으로 / 30초 앞으로 / 다음 곡
/// 모든 버튼을 Expanded + FittedBox 로 배치 → 좁은 화면에서도 한 줄 유지, 오버플로우 없음
class TransportControls extends StatelessWidget {
  const TransportControls({super.key});

  @override
  Widget build(BuildContext context) {
    final player = context.read<PlayerProvider>();
    return SizedBox(
      height: 64,
      child: Row(
        children: [
          _CtrlButton(
            icon: Icons.skip_previous_rounded,
            tooltip: '이전 곡',
            size: 32,
            onTap: player.previous,
          ),
          _CtrlButton(
            icon: Icons.replay_30_rounded,
            tooltip: '30초 뒤로',
            onTap: () => player.seekRelative(-30),
          ),
          _CtrlButton(
            icon: Icons.replay_10_rounded,
            tooltip: '10초 뒤로',
            onTap: () => player.seekRelative(-10),
          ),
          const Expanded(
            flex: 2,
            child: Center(
              child: FittedBox(fit: BoxFit.scaleDown, child: _PlayPauseButton()),
            ),
          ),
          _CtrlButton(
            icon: Icons.forward_10_rounded,
            tooltip: '10초 앞으로',
            onTap: () => player.seekRelative(10),
          ),
          _CtrlButton(
            icon: Icons.forward_30_rounded,
            tooltip: '30초 앞으로',
            onTap: () => player.seekRelative(30),
          ),
          _CtrlButton(
            icon: Icons.skip_next_rounded,
            tooltip: '다음 곡',
            size: 32,
            onTap: player.next,
          ),
        ],
      ),
    );
  }
}

class _CtrlButton extends StatelessWidget {
  const _CtrlButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.size = 26,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Tooltip(
        message: tooltip,
        child: InkResponse(
          onTap: onTap,
          radius: 24,
          child: SizedBox(
            height: 56,
            child: Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Icon(icon, size: size),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PlayPauseButton extends StatefulWidget {
  const _PlayPauseButton();

  @override
  State<_PlayPauseButton> createState() => _PlayPauseButtonState();
}

class _PlayPauseButtonState extends State<_PlayPauseButton> {
  late final Stream<PlayerState> _stream;

  @override
  void initState() {
    super.initState();
    _stream = context.read<PlayerProvider>().playerStateStream;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return StreamBuilder<PlayerState>(
      stream: _stream,
      builder: (context, snap) {
        final state = snap.data;
        final processing = state?.processingState;
        final loading = processing == ProcessingState.loading ||
            processing == ProcessingState.buffering;
        final playing = (state?.playing ?? false) && processing != ProcessingState.completed;

        return SizedBox(
          width: 60,
          height: 60,
          child: FilledButton(
            style: FilledButton.styleFrom(
              shape: const CircleBorder(),
              padding: EdgeInsets.zero,
              backgroundColor: cs.primary,
              foregroundColor: cs.onPrimary,
            ),
            onPressed: () => context.read<PlayerProvider>().togglePlayPause(),
            child: loading
                ? SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2.5, color: cs.onPrimary),
                  )
                : Icon(playing ? Icons.pause_rounded : Icons.play_arrow_rounded, size: 34),
          ),
        );
      },
    );
  }
}

/// 2행: 재생속도 / 타이머 / 반복 / 셔플 / 소리
/// 5개 버튼을 같은 너비로 한 줄 배치 (아이콘 + 아래 작은 글자)
class SecondaryControls extends StatelessWidget {
  const SecondaryControls({super.key});

  @override
  Widget build(BuildContext context) {
    return const Row(
      children: [
        Expanded(child: _SpeedButton()),
        SizedBox(width: 6),
        Expanded(child: _SleepTimerButton()),
        SizedBox(width: 6),
        Expanded(child: _RepeatButton()),
        SizedBox(width: 6),
        Expanded(child: _ShuffleButton()),
        SizedBox(width: 6),
        Expanded(child: _VolumeButton()),
      ],
    );
  }
}

/// 배속: 탭하면 순환, 길게 누르면 목록에서 선택
class _SpeedButton extends StatelessWidget {
  const _SpeedButton();

  @override
  Widget build(BuildContext context) {
    final speed = context.select<PlayerProvider, double>((p) => p.speed);
    final player = context.read<PlayerProvider>();
    return _ToolButton(
      icon: Icons.speed_rounded,
      label: formatSpeed(speed),
      tooltip: '재생 속도 (탭: 변경, 길게: 선택)',
      active: speed != 1.0,
      onTap: player.cycleSpeed,
      onLongPress: () async {
        final selected = await showModalBottomSheet<double>(
          context: context,
          builder: (ctx) => SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Padding(
                  padding: EdgeInsets.only(bottom: 8),
                  child: Text('재생 속도', style: TextStyle(fontWeight: FontWeight.w600)),
                ),
                for (final s in kSpeedOptions)
                  ListTile(
                    title: Text(formatSpeed(s)),
                    trailing: s == speed ? const Icon(Icons.check_rounded) : null,
                    onTap: () => Navigator.pop(ctx, s),
                  ),
              ],
            ),
          ),
        );
        if (selected != null) await player.setSpeed(selected);
      },
    );
  }
}

/// 취침 타이머: 15/30/60분, 취소 / 남은 시간 카운트다운 표시
class _SleepTimerButton extends StatelessWidget {
  const _SleepTimerButton();

  @override
  Widget build(BuildContext context) {
    final remaining = context.select<PlayerProvider, Duration?>((p) => p.sleepRemaining);
    final player = context.read<PlayerProvider>();

    return PopupMenuButton<int>(
      tooltip: '취침 타이머',
      padding: EdgeInsets.zero,
      onSelected: (m) {
        if (m == 0) {
          player.cancelSleepTimer();
        } else {
          player.startSleepTimer(m);
        }
      },
      itemBuilder: (_) => [
        for (final m in kSleepTimerMinutes)
          PopupMenuItem<int>(value: m, child: Text('$m분 후 일시정지')),
        if (remaining != null) ...[
          const PopupMenuDivider(),
          const PopupMenuItem<int>(value: 0, child: Text('타이머 취소')),
        ],
      ],
      child: _ToolFace(
        icon: remaining != null ? Icons.bedtime_rounded : Icons.bedtime_outlined,
        label: remaining != null ? formatCountdown(remaining) : '타이머',
        active: remaining != null,
      ),
    );
  }
}

class _RepeatButton extends StatelessWidget {
  const _RepeatButton();

  @override
  Widget build(BuildContext context) {
    final repeat = context.select<PlayerProvider, RepeatModeSetting>((p) => p.repeat);
    return _ToolButton(
      icon: repeat == RepeatModeSetting.one ? Icons.repeat_one_rounded : Icons.repeat_rounded,
      label: switch (repeat) {
        RepeatModeSetting.off => '반복끄기',
        RepeatModeSetting.all => '전체반복',
        RepeatModeSetting.one => '한곡반복',
      },
      tooltip: '${repeat.label} (탭하여 변경)',
      active: repeat != RepeatModeSetting.off,
      onTap: context.read<PlayerProvider>().cycleRepeat,
    );
  }
}

class _ShuffleButton extends StatelessWidget {
  const _ShuffleButton();

  @override
  Widget build(BuildContext context) {
    final shuffle = context.select<PlayerProvider, bool>((p) => p.shuffle);
    return _ToolButton(
      icon: shuffle ? Icons.shuffle_on_rounded : Icons.shuffle_rounded,
      label: shuffle ? '셔플' : '셔플끔',
      tooltip: shuffle ? '셔플 켜짐' : '셔플 꺼짐',
      active: shuffle,
      onTap: context.read<PlayerProvider>().toggleShuffle,
    );
  }
}

/// 소리: 탭하면 버튼 옆에 세로 음량 조절바, 길게 누르면 음소거 토글
class _VolumeButton extends StatelessWidget {
  const _VolumeButton();

  @override
  Widget build(BuildContext context) {
    final volume = context.select<PlayerProvider, double>((p) => p.volume);
    final player = context.read<PlayerProvider>();
    return _ToolButton(
      icon: _volumeIcon(volume),
      label: '소리 ${(volume * 100).round()}',
      tooltip: '음량 (탭: 조절, 길게: 음소거)',
      active: volume < 1.0,
      onTap: () => _showVolumePopup(context),
      onLongPress: () => player.setVolume(volume == 0 ? 1.0 : 0.0, persist: true),
    );
  }
}

IconData _volumeIcon(double v) => v == 0
    ? Icons.volume_off_rounded
    : v < 0.5
        ? Icons.volume_down_rounded
        : Icons.volume_up_rounded;

/// [buttonContext] 위젯의 화면 위치를 기준으로, 그 옆(왼쪽, 공간 없으면 오른쪽)에
/// 세로 음량 조절바를 띄운다. 바깥을 누르면 닫힌다.
Future<void> _showVolumePopup(BuildContext buttonContext) {
  final box = buttonContext.findRenderObject() as RenderBox?;
  if (box == null || !box.hasSize) return Future.value();
  final origin = box.localToGlobal(Offset.zero);
  final buttonSize = box.size;

  return showGeneralDialog<void>(
    context: buttonContext,
    barrierDismissible: true,
    barrierLabel: '음량 닫기',
    barrierColor: Colors.black26,
    transitionDuration: const Duration(milliseconds: 150),
    pageBuilder: (ctx, _, __) {
      final screen = MediaQuery.sizeOf(ctx);
      final padding = MediaQuery.paddingOf(ctx);
      const width = 68.0;
      const height = 240.0;
      const gap = 6.0;

      // 버튼 왼쪽에 우선 배치, 공간이 없으면 오른쪽
      var left = origin.dx - width - gap;
      if (left < 8) left = origin.dx + buttonSize.width + gap;
      left = left.clamp(8.0, screen.width - width - 8);

      // 버튼과 세로 가운데를 맞추되 화면 밖으로 나가지 않게
      var top = origin.dy + buttonSize.height / 2 - height / 2;
      top = top.clamp(padding.top + 8, screen.height - padding.bottom - height - 8);

      return Stack(
        children: [
          Positioned(
            left: left,
            top: top,
            width: width,
            height: height,
            child: const _VerticalVolumePanel(),
          ),
        ],
      );
    },
    transitionBuilder: (ctx, anim, _, child) => FadeTransition(
      opacity: anim,
      child: ScaleTransition(
        scale: Tween(begin: 0.92, end: 1.0).animate(anim),
        child: child,
      ),
    ),
  );
}

class _VerticalVolumePanel extends StatelessWidget {
  const _VerticalVolumePanel();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.surfaceContainerHighest,
      elevation: 8,
      borderRadius: BorderRadius.circular(20),
      child: Consumer<PlayerProvider>(
        builder: (context, player, _) {
          final v = player.volume;
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Column(
              children: [
                Text(
                  '${(v * 100).round()}%',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
                // 세로 슬라이더: 위로 올리면 커지고 아래로 내리면 작아짐
                Expanded(
                  child: RotatedBox(
                    quarterTurns: 3,
                    child: Slider(
                      value: v,
                      onChanged: (x) => player.setVolume(x),
                      onChangeEnd: (x) => player.setVolume(x, persist: true),
                    ),
                  ),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: v == 0 ? '음소거 해제' : '음소거',
                  icon: Icon(_volumeIcon(v), size: 22),
                  onPressed: () => player.setVolume(v == 0 ? 1.0 : 0.0, persist: true),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ───────────────────────── 공용 버튼 ─────────────────────────

class _ToolButton extends StatelessWidget {
  const _ToolButton({
    required this.icon,
    required this.label,
    required this.tooltip,
    required this.onTap,
    this.onLongPress,
    this.active = false,
  });

  final IconData icon;
  final String label;
  final String tooltip;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        onLongPress: onLongPress,
        child: _ToolFace(icon: icon, label: label, active: active),
      ),
    );
  }
}

/// 아이콘 위, 글자 아래. 폭이 좁으면 FittedBox 로 자동 축소
class _ToolFace extends StatelessWidget {
  const _ToolFace({required this.icon, required this.label, this.active = false});

  final IconData icon;
  final String label;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final fg = active ? cs.onPrimaryContainer : cs.onSurface;
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
      decoration: BoxDecoration(
        color: active ? cs.primaryContainer : cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 20, color: active ? fg : cs.onSurfaceVariant),
            const SizedBox(height: 2),
            Text(
              label,
              maxLines: 1,
              style: TextStyle(
                fontSize: 11,
                color: fg,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
