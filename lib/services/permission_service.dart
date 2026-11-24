import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';

enum AudioPermissionResult { granted, denied, permanentlyDenied }

/// 저장소/미디어 권한 처리
/// - Android 13(API 33)+ : READ_MEDIA_AUDIO (Permission.audio)
/// - Android 12 이하     : READ_EXTERNAL_STORAGE (Permission.storage)
/// - iOS                 : 문서 선택기(UIDocumentPicker)를 사용하므로 별도 런타임 권한 불필요
class PermissionService {
  int? _sdkInt;

  Future<Permission> _androidPermission() async {
    _sdkInt ??= (await DeviceInfoPlugin().androidInfo).version.sdkInt;
    return _sdkInt! >= 33 ? Permission.audio : Permission.storage;
  }

  Future<bool> hasAudioPermission() async {
    if (!Platform.isAndroid) return true;
    final permission = await _androidPermission();
    final status = await permission.status;
    return status.isGranted || status.isLimited;
  }

  Future<AudioPermissionResult> requestAudioPermission() async {
    if (!Platform.isAndroid) return AudioPermissionResult.granted;

    final permission = await _androidPermission();
    var status = await permission.status;
    if (status.isGranted || status.isLimited) {
      return AudioPermissionResult.granted;
    }

    status = await permission.request();
    if (status.isGranted || status.isLimited) {
      return AudioPermissionResult.granted;
    }
    if (status.isPermanentlyDenied || status.isRestricted) {
      return AudioPermissionResult.permanentlyDenied;
    }
    return AudioPermissionResult.denied;
  }

  // ───────────── 알림 권한 (Android 13 이상) ─────────────
  // 알림 권한이 꺼져 있으면 일부 기기(특히 삼성)에서 미디어 알림이 안 뜨고,
  // 그 결과 잠금화면 컨트롤·차량 블루투스 연동·백그라운드 유지가 모두 동작하지 않는다.

  Future<bool> _needsNotificationPermission() async {
    if (!Platform.isAndroid) return false;
    _sdkInt ??= (await DeviceInfoPlugin().androidInfo).version.sdkInt;
    return _sdkInt! >= 33;
  }

  Future<bool> hasNotificationPermission() async {
    if (!await _needsNotificationPermission()) return true;
    return Permission.notification.isGranted;
  }

  /// 허용 상태면 true. 거부되어 있으면 한 번 요청한다.
  Future<bool> ensureNotificationPermission() async {
    if (!await _needsNotificationPermission()) return true;
    final status = await Permission.notification.status;
    if (status.isGranted) return true;
    if (status.isPermanentlyDenied) return false;
    return (await Permission.notification.request()).isGranted;
  }

  // ───────────── 배터리 최적화 제외 (Android) ─────────────
  // 삼성 등 일부 기기는 배터리 최적화 때문에 화면을 끈 채 오래 재생하면
  // 앱을 강제로 종료해 재생이 멈춘다. 최적화 대상에서 제외하면 방지된다.

  Future<bool> isIgnoringBatteryOptimizations() async {
    if (!Platform.isAndroid) return true;
    return Permission.ignoreBatteryOptimizations.isGranted;
  }

  Future<bool> requestIgnoreBatteryOptimizations() async {
    if (!Platform.isAndroid) return true;
    final status = await Permission.ignoreBatteryOptimizations.request();
    return status.isGranted;
  }

  Future<bool> openSettings() => openAppSettings();
}
