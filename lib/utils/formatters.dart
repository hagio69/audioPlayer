/// 1:23 / 1:02:03 형식
String formatDuration(Duration? d) {
  if (d == null) return '--:--';
  final total = d.inSeconds < 0 ? 0 : d.inSeconds;
  final h = total ~/ 3600;
  final m = (total % 3600) ~/ 60;
  final s = (total % 60).toString().padLeft(2, '0');
  if (h > 0) return '$h:${m.toString().padLeft(2, '0')}:$s';
  return '$m:$s';
}

/// 0.8x, 1.0x, 1.25x ...
String formatSpeed(double speed) => '${speed}x';

/// 취침 타이머 남은 시간 (mm:ss 또는 h:mm:ss)
String formatCountdown(Duration d) => formatDuration(d);
