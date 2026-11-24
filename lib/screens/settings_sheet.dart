import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/player_settings.dart';
import '../providers/library_provider.dart';
import '../providers/player_provider.dart';
import '../utils/formatters.dart';
import '../widgets/dialogs.dart';

/// 환경 설정 / 재생 모드 모달
Future<void> showSettingsSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      builder: (context, controller) => _SettingsContent(controller: controller),
    ),
  );
}

class _SettingsContent extends StatelessWidget {
  const _SettingsContent({required this.controller});

  final ScrollController controller;

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerProvider>();
    final library = context.read<LibraryProvider>();
    final theme = Theme.of(context);

    // 하단 제스처/내비게이션 바에 마지막 항목이 가려지지 않도록 여백 추가
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;

    return ListView(
      controller: controller,
      padding: EdgeInsets.fromLTRB(20, 0, 20, 32 + bottomInset),
      children: [
        Text('환경 설정', style: theme.textTheme.titleLarge),
        const SizedBox(height: 16),

        // ── 반복 모드 ──
        const _SectionTitle('반복 모드'),
        SizedBox(
          width: double.infinity,
          child: SegmentedButton<RepeatModeSetting>(
            showSelectedIcon: false,
            segments: [
              for (final m in RepeatModeSetting.values)
                ButtonSegment(
                  value: m,
                  label: Text(m.shortLabel),
                  icon: Icon(switch (m) {
                    RepeatModeSetting.off => Icons.repeat_rounded,
                    RepeatModeSetting.all => Icons.repeat_on_rounded,
                    RepeatModeSetting.one => Icons.repeat_one_on_rounded,
                  }),
                ),
            ],
            selected: {player.repeat},
            onSelectionChanged: (s) => player.setRepeat(s.first),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(player.repeat.description, style: theme.textTheme.bodySmall),
        ),
        const SizedBox(height: 8),

        // ── 셔플 ──
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('셔플 (랜덤 재생)'),
          subtitle: const Text('선택된 곡이 있으면 선택 곡 안에서만 섞습니다.'),
          value: player.shuffle,
          onChanged: player.setShuffle,
        ),
        const Divider(),

        // ── 재생 속도 ──
        const _SectionTitle('재생 속도'),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final s in kSpeedOptions)
              ChoiceChip(
                label: Text(formatSpeed(s)),
                selected: player.speed == s,
                onSelected: (_) => player.setSpeed(s),
              ),
          ],
        ),
        const SizedBox(height: 16),
        const Divider(),

        // ── 취침 타이머 ──
        _SectionTitle(
          player.sleepTimerActive
              ? '취침 타이머 · ${formatCountdown(player.sleepRemaining ?? Duration.zero)} 남음'
              : '취침 타이머',
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final m in kSleepTimerMinutes)
              ActionChip(
                avatar: const Icon(Icons.bedtime_outlined, size: 16),
                label: Text('$m분'),
                onPressed: () => player.startSleepTimer(m),
              ),
            if (player.sleepTimerActive)
              ActionChip(
                avatar: const Icon(Icons.close_rounded, size: 16),
                label: const Text('취소'),
                onPressed: player.cancelSleepTimer,
              ),
          ],
        ),
        const SizedBox(height: 16),
        const Divider(),

        // ── 백그라운드 · 잠금화면 ──
        const _SectionTitle('백그라운드 재생 · 잠금화면 · 차량 연동'),
        const _SystemStatusSection(),
        const Divider(),

        // ── 데이터 ──
        const _SectionTitle('데이터'),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.restart_alt_rounded),
          title: const Text('재생 횟수 전체 초기화'),
          onTap: () async {
            final ok = await showConfirmDialog(
              context,
              title: '재생 횟수 초기화',
              message: '모든 곡의 재생 횟수를 0으로 초기화할까요?',
              confirmLabel: '초기화',
            );
            if (ok) library.resetAllPlayCounts();
          },
        ),
        if (Platform.isIOS)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.folder_shared_outlined),
            title: const Text('앱 폴더 다시 스캔'),
            subtitle: const Text('파일 앱 > 나의 iPhone > hagioAudioPlayer 폴더에 음악을 넣으면 여기서 보입니다.'),
            onTap: () {
              Navigator.pop(context);
              library.scanAppDocuments();
            },
          ),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 8),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: Theme.of(context).colorScheme.primary,
            ),
      ),
    );
  }
}

/// 알림 권한 / 배터리 최적화 상태를 실제로 확인해 보여주고, 탭하면 설정으로 안내.
/// 설정 앱에 다녀오면 자동으로 다시 확인한다.
class _SystemStatusSection extends StatefulWidget {
  const _SystemStatusSection();

  @override
  State<_SystemStatusSection> createState() => _SystemStatusSectionState();
}

class _SystemStatusSectionState extends State<_SystemStatusSection>
    with WidgetsBindingObserver {
  bool? _notificationOk;
  bool? _batteryOk;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    final perms = context.read<LibraryProvider>().permissions;
    final n = await perms.hasNotificationPermission();
    final b = await perms.isIgnoringBatteryOptimizations();
    if (!mounted) return;
    setState(() {
      _notificationOk = n;
      _batteryOk = b;
    });
  }

  Future<void> _fixNotification() async {
    final library = context.read<LibraryProvider>();
    final ok = await library.permissions.ensureNotificationPermission();
    if (!ok) await library.openAppSettings(); // 영구 거부 상태면 앱 설정 화면으로
    await _refresh();
  }

  Future<void> _fixBattery() async {
    await showBatteryOptimizationDialog(context);
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    if (Platform.isIOS) {
      return const ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Icon(Icons.lock_clock_outlined),
        title: Text('잠금화면 · 제어 센터 컨트롤 사용'),
        subtitle: Text('재생 중 잠금화면과 제어 센터에서 재생/일시정지, 이전/다음 곡, 10초 이동을 할 수 있습니다.'),
      );
    }

    return Column(
      children: [
        _StatusTile(
          icon: Icons.notifications_active_outlined,
          title: '알림 권한',
          ok: _notificationOk,
          okText: '허용됨 · 알림창/잠금화면에 재생 컨트롤 표시',
          badText: '꺼짐 · 잠금화면 컨트롤과 차량 연동이 동작하지 않습니다. 눌러서 허용하세요.',
          onTap: _fixNotification,
        ),
        _StatusTile(
          icon: Icons.battery_saver_rounded,
          title: '배터리 최적화 제외',
          ok: _batteryOk,
          okText: '제외됨 · 화면이 꺼져도 재생이 유지됩니다',
          badText: '적용 중 · 화면을 끈 채 오래 재생하면 멈출 수 있습니다. 눌러서 제외하세요.',
          onTap: _fixBattery,
        ),
        const Padding(
          padding: EdgeInsets.only(top: 4, bottom: 8),
          child: Text(
            '두 항목이 모두 정상인데도 잠금화면에 컨트롤이 안 보이면, 휴대폰 설정 > 잠금화면 > 알림에서 '
            '"알림 내용 표시"가 켜져 있는지 확인하세요.',
            style: TextStyle(fontSize: 12),
          ),
        ),
      ],
    );
  }
}

class _StatusTile extends StatelessWidget {
  const _StatusTile({
    required this.icon,
    required this.title,
    required this.ok,
    required this.okText,
    required this.badText,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final bool? ok;
  final String okText;
  final String badText;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final state = ok;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(state == null ? '확인 중...' : (state ? okText : badText)),
      trailing: state == null
          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
          : Icon(
              state ? Icons.check_circle_rounded : Icons.error_rounded,
              color: state ? Colors.greenAccent.shade400 : cs.error,
            ),
      onTap: state == true ? null : onTap,
    );
  }
}
