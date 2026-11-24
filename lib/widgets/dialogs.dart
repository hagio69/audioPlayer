import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/library_provider.dart';
import '../services/file_scan_service.dart';

/// 저장소/미디어 권한 거부 안내
Future<void> showPermissionDeniedDialog(
  BuildContext context, {
  required bool permanentlyDenied,
  VoidCallback? onRetry,
}) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      icon: const Icon(Icons.folder_off_outlined),
      title: const Text('오디오 파일 접근 권한 필요'),
      content: Text(
        permanentlyDenied
            ? '기기의 음악 파일을 읽으려면 "음악 및 오디오"(또는 저장소) 권한이 필요합니다.\n\n'
                '권한이 "다시 묻지 않음" 상태입니다. 설정 > 권한에서 직접 허용해 주세요.'
            : '기기의 음악 파일을 읽으려면 "음악 및 오디오"(또는 저장소) 권한이 필요합니다.\n\n'
                '권한을 허용해야 폴더의 오디오 파일을 검색할 수 있습니다.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('닫기'),
        ),
        if (permanentlyDenied)
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              context.read<LibraryProvider>().openAppSettings();
            },
            child: const Text('설정 열기'),
          )
        else if (onRetry != null)
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              onRetry();
            },
            child: const Text('다시 요청'),
          ),
      ],
    ),
  );
}

/// 확인/취소 다이얼로그
Future<bool> showConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = '확인',
  bool destructive = false,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('취소'),
        ),
        FilledButton(
          style: destructive
              ? FilledButton.styleFrom(
                  backgroundColor: Theme.of(ctx).colorScheme.error,
                  foregroundColor: Theme.of(ctx).colorScheme.onError,
                )
              : null,
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return result ?? false;
}

/// 앱 정보
void showAppInfoDialog(BuildContext context) {
  final formats = FileScanService.pickerExtensions.map((e) => e.toUpperCase()).join(', ');
  showAboutDialog(
    context: context,
    applicationName: 'hagioAudioPlayer',
    applicationVersion: '1.0.0',
    applicationIcon: Icon(
      Icons.graphic_eq_rounded,
      size: 40,
      color: Theme.of(context).colorScheme.primary,
    ),
    children: [
      const Text('기기에 저장된 오디오 파일을 재생하는 로컬 오디오 플레이어입니다.'),
      const SizedBox(height: 12),
      Text('지원 형식: $formats'),
      const SizedBox(height: 12),
      const Text(
        '• 재생목록에서 곡을 여러 개 선택하면 선택한 곡만으로 재생 큐가 구성됩니다.\n'
        '• 선택을 모두 해제하면 전체 재생목록 기준으로 돌아갑니다.\n'
        '• 곡을 길게 누르면 재생 횟수 초기화 등 추가 메뉴가 열립니다.\n'
        '• 재생목록 탭을 길게 누르거나 ✏️ 버튼으로 이름을 바꿀 수 있습니다.\n'
        '• 앱을 다시 열면 마지막으로 듣던 곡의 위치에서 이어 들을 수 있습니다.',
      ),
    ],
  );
}

/// 재생목록 이름 편집
Future<void> showRenamePlaylistDialog(BuildContext context, int index) async {
  final library = context.read<LibraryProvider>();
  final controller = TextEditingController(text: library.playlistName(index));
  final name = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('재생목록 이름 편집'),
      content: TextField(
        controller: controller,
        autofocus: true,
        maxLength: LibraryProvider.maxNameLength,
        textInputAction: TextInputAction.done,
        decoration: InputDecoration(
          hintText: LibraryProvider.defaultPlaylistNames[index],
          helperText: '비워 두면 기본 이름으로 돌아갑니다.',
        ),
        onSubmitted: (v) => Navigator.pop(ctx, v),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('취소'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, controller.text),
          child: const Text('저장'),
        ),
      ],
    ),
  );
  if (name != null) library.renamePlaylist(index, name);
}

/// 배터리 최적화 제외 안내 (Android)
Future<void> showBatteryOptimizationDialog(BuildContext context) async {
  final library = context.read<LibraryProvider>();
  final permissions = library.permissions;
  if (await permissions.isIgnoringBatteryOptimizations()) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('이미 배터리 최적화에서 제외되어 있습니다.')),
      );
    }
    return;
  }
  if (!context.mounted) return;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      icon: const Icon(Icons.battery_alert_rounded),
      title: const Text('재생이 중간에 멈추지 않게'),
      content: const Text(
        '삼성 등 일부 휴대폰은 배터리 절약을 위해 화면이 꺼진 채 오래 재생 중인 앱을 '
        '강제로 종료해 음악이 멈출 수 있습니다.\n\n'
        '다음 화면에서 "허용"을 누르면 이 앱을 배터리 최적화 대상에서 제외합니다.',
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('나중에')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('계속')),
      ],
    ),
  );
  if (ok == true) await permissions.requestIgnoreBatteryOptimizations();
}
