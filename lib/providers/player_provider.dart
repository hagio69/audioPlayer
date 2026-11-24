import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:just_audio/just_audio.dart';

import '../models/player_settings.dart';
import '../models/track.dart';
import '../services/audio_handler.dart';
import '../services/storage_service.dart';
import 'library_provider.dart';

/// 현재 재생 큐가 어디에서 왔는지
enum QueueSource { none, playlist, folder }

/// 재생 제어, 재생 설정(반복/셔플/배속/음량), 취침 타이머,
/// 재생목록 선택 상태에 따른 큐 동기화, 마지막 재생 위치 저장/복원을 담당.
class PlayerProvider extends ChangeNotifier with WidgetsBindingObserver {
  PlayerProvider({
    required this.handler,
    required this.library,
    required this.storage,
  }) {
    _subs.add(handler.currentTrackStream.listen((t) {
      _current = t;
      // 곡이 바뀐 순간에는 플레이어가 아직 이전 곡의 위치를 갖고 있으므로 0으로 저장
      _savePlayback(force: true, position: Duration.zero);
      notifyListeners();
    }));
    _subs.add(handler.completedStream
        .listen((t) => library.incrementPlayCount(t.path)));
    _subs.add(handler.errorStream.listen(_messageCtrl.add));
    _subs.add(handler.pausedAtEndStream.listen((t) {
      _messageCtrl.add(
          '반복 끄기 상태라 다음 곡${t == null ? '' : '(${t.title})'}에서 일시정지했습니다. '
          '계속 재생하려면 반복을 "전체"로 바꾸세요.');
    }));
    _subs.add(handler.settingsChangedStream.listen((_) {
      _repeat = handler.repeatSetting;
      _shuffle = handler.shuffleEnabled;
      storage.saveRepeat(_repeat);
      storage.saveShuffle(_shuffle);
      notifyListeners();
    }));
    _subs.add(handler.player.playingStream.listen((playing) {
      if (!playing) _savePlayback(force: true);
    }));
    _subs.add(handler.player.positionStream.listen((_) => _savePlayback()));

    library.addListener(_onLibraryChanged);
    WidgetsBinding.instance.addObserver(this);
  }

  final HagioAudioHandler handler;
  final LibraryProvider library;
  final StorageService storage;

  final List<StreamSubscription<dynamic>> _subs = [];
  final _messageCtrl = StreamController<String>.broadcast();

  QueueSource _source = QueueSource.none;
  int _playlistIndex = 0;
  Track? _current;
  RepeatModeSetting _repeat = RepeatModeSetting.off;
  bool _shuffle = false;
  double _speed = 1.0;
  double _volume = 1.0;

  DateTime? _sleepEndsAt;
  Duration? _sleepRemaining;
  Timer? _sleepTimer;

  int _queueSignature = 0;
  DateTime _lastSave = DateTime.fromMillisecondsSinceEpoch(0);

  /// 이번 실행에서 알림 권한을 이미 확인했는지
  bool _notificationChecked = false;

  /// 복원이 끝나기 전에는 저장하지 않는다.
  /// (앱 시작 직후 '재생 안 함' 상태가 저장된 위치를 덮어쓰는 문제 방지)
  bool _restored = false;

  // ───────────────────────── getter ─────────────────────────

  Track? get currentTrack => _current;
  QueueSource get source => _source;
  int get playlistIndex => _playlistIndex;
  RepeatModeSetting get repeat => _repeat;
  bool get shuffle => _shuffle;
  double get speed => _speed;
  double get volume => _volume;
  Duration? get sleepRemaining => _sleepRemaining;
  bool get sleepTimerActive => _sleepEndsAt != null;
  int get queueLength => handler.queueTracks.length;

  /// 재생목록에서 다중 선택된 곡만으로 큐가 구성되어 있는가
  bool get isSelectionQueue =>
      _source == QueueSource.playlist && library.hasPlaylistSelection(_playlistIndex);

  Stream<Duration> get positionStream => handler.player.positionStream;
  Stream<Duration?> get durationStream => handler.player.durationStream;
  Stream<PlayerState> get playerStateStream => handler.player.playerStateStream;

  /// 사용자 안내 메시지 (SnackBar)
  Stream<String> get messageStream => _messageCtrl.stream;

  String get _sourceKey => switch (_source) {
        QueueSource.playlist => 'playlist:$_playlistIndex',
        QueueSource.folder => 'folder',
        QueueSource.none => 'none',
      };

  // ───────────────────────── 초기화 / 복원 ─────────────────────────

  Future<void> init() async {
    try {
      _repeat = storage.loadRepeat();
      _shuffle = storage.loadShuffle();
      _speed = storage.loadSpeed();
      _volume = storage.loadVolume();

      await handler.setRepeatSetting(_repeat);
      await handler.setShuffleEnabled(_shuffle);
      await handler.setSpeed(_speed);
      await handler.setVolume(_volume);
      notifyListeners();

      await _restoreLastPlayback();
    } catch (e) {
      debugPrint('restore failed: $e');
    } finally {
      _restored = true;
    }
  }

  /// 마지막으로 듣던 곡을 마지막 위치에서 일시정지 상태로 불러온다.
  /// ▶ 를 누르면 그 위치부터 이어서 재생된다.
  Future<void> _restoreLastPlayback() async {
    final lastPath = storage.loadLastTrackPath();
    if (lastPath == null) return;

    // 1) 저장된 출처에서 먼저 찾기
    final sourceKey = storage.loadLastSource() ?? '';
    QueueSource? source;
    var index = 0;
    if (sourceKey.startsWith('playlist:')) {
      index = int.tryParse(sourceKey.substring('playlist:'.length)) ?? 0;
      if (index >= 0 &&
          index < LibraryProvider.playlistCount &&
          library.isInPlaylist(index, lastPath)) {
        source = QueueSource.playlist;
      }
    } else if (sourceKey == 'folder' &&
        library.sortedFolderTracks.any((t) => t.path == lastPath)) {
      source = QueueSource.folder;
    }

    // 2) 못 찾으면 다른 재생목록 → 파일 목록 순서로 찾기
    if (source == null) {
      final inLists = library.playlistsContaining(lastPath);
      if (inLists.isNotEmpty) {
        source = QueueSource.playlist;
        index = inLists.first;
      } else if (library.sortedFolderTracks.any((t) => t.path == lastPath)) {
        source = QueueSource.folder;
      }
    }
    if (source == null) return;

    _source = source;
    _playlistIndex = index;
    final queue = _queueFor(source, index);
    final track = queue.where((t) => t.path == lastPath).firstOrNull ??
        (source == QueueSource.playlist
            ? library.sortedPlaylist(index).where((t) => t.path == lastPath).firstOrNull
            : null);
    if (track == null) return;

    _queueSignature = _signature(queue);
    await handler.playQueue(
      queue,
      start: track,
      autoplay: false,
      position: storage.loadLastPosition(),
    );
    notifyListeners();
  }

  // ───────────────────────── 큐 구성 ─────────────────────────

  List<Track> _queueFor(QueueSource source, int index) => switch (source) {
        QueueSource.playlist => library.hasPlaylistSelection(index)
            ? library.selectedPlaylistTracks(index)
            : library.sortedPlaylist(index),
        QueueSource.folder => library.sortedFolderTracks,
        QueueSource.none => const <Track>[],
      };

  int _signature(List<Track> queue) => Object.hashAll(queue.map((t) => t.path));

  /// 재생목록 정렬/선택/편집이 바뀌면 재생 중인 곡은 유지한 채 큐만 갱신.
  /// 선택이 모두 해제되면 자동으로 전체 재생목록 큐로 돌아간다.
  void _onLibraryChanged() {
    if (_source == QueueSource.none) return;
    final queue = _queueFor(_source, _playlistIndex);
    final sig = _signature(queue);
    if (sig == _queueSignature) {
      notifyListeners(); // 재생목록 이름 변경 등 표시만 갱신
      return;
    }
    _queueSignature = sig;
    handler.syncQueue(queue);
    notifyListeners();
  }

  /// 재생을 시작하기 전에 한 번, 알림 권한을 확인/요청한다.
  /// (미디어 알림이 떠야 잠금화면 컨트롤·차량 연동·백그라운드 유지가 동작)
  Future<void> _checkNotificationPermission() async {
    if (_notificationChecked) return;
    _notificationChecked = true;
    try {
      final ok = await library.permissions.ensureNotificationPermission();
      if (!ok) {
        _messageCtrl.add('알림 권한이 꺼져 있어 잠금화면·알림창 컨트롤과 차량 연동이 '
            '동작하지 않을 수 있습니다. 환경 설정에서 허용해 주세요.');
      }
    } catch (e) {
      debugPrint('notification permission check failed: $e');
    }
  }

  Future<void> _startQueue(QueueSource source, {int index = 0, Track? start}) async {
    await _checkNotificationPermission();
    final queue = _queueFor(source, index);
    if (queue.isEmpty && start == null) {
      _messageCtrl.add('재생할 곡이 없습니다.');
      return;
    }
    _source = source;
    _playlistIndex = index;
    _queueSignature = _signature(queue);
    await handler.playQueue(queue, start: start);
    notifyListeners();
  }

  /// [index]번 재생목록의 곡 탭 → 그 재생목록(또는 선택 곡) 큐로 재생
  Future<void> playFromPlaylist(int index, Track track) =>
      _startQueue(QueueSource.playlist, index: index, start: track);

  /// [index]번 재생목록의 선택 곡(없으면 전체)을 처음부터 재생
  Future<void> playPlaylist(int index) =>
      _startQueue(QueueSource.playlist, index: index);

  /// 파일 목록의 곡 탭 → 폴더 전체를 큐로 재생
  Future<void> playFromFolder(Track track) =>
      _startQueue(QueueSource.folder, start: track);

  // ───────────────────────── 재생 제어 ─────────────────────────

  Future<void> togglePlayPause() async {
    if (handler.currentTrack == null) {
      for (var i = 0; i < LibraryProvider.playlistCount; i++) {
        if (library.playlistTracks(i).isNotEmpty) {
          await playPlaylist(i);
          return;
        }
      }
      if (library.sortedFolderTracks.isNotEmpty) {
        await _startQueue(QueueSource.folder);
      } else {
        _messageCtrl.add('재생할 곡이 없습니다. 파일 목록에서 폴더를 선택해 주세요.');
      }
      return;
    }
    final p = handler.player;
    if (p.playing && p.processingState != ProcessingState.completed) {
      await handler.pause();
    } else {
      await _checkNotificationPermission();
      await handler.play();
    }
  }

  Future<void> next() => handler.skipToNext();

  Future<void> previous() => handler.skipToPrevious();

  Future<void> seek(Duration position) async {
    await handler.seek(position);
    _savePlayback(force: true);
  }

  Future<void> seekRelative(int seconds) =>
      handler.seekRelative(Duration(seconds: seconds));

  // ───────────────────────── 배속 ─────────────────────────

  Future<void> setSpeed(double speed) async {
    _speed = speed;
    notifyListeners();
    await handler.setSpeed(speed);
    await storage.saveSpeed(speed);
  }

  /// 0.8 → 1.0 → 1.25 → 1.5 → 2.0 → 0.8 ...
  Future<void> cycleSpeed() {
    final idx = kSpeedOptions.indexOf(_speed);
    final next = kSpeedOptions[(idx + 1) % kSpeedOptions.length];
    return setSpeed(next);
  }

  // ───────────────────────── 반복 / 셔플 ─────────────────────────

  Future<void> setRepeat(RepeatModeSetting mode) async {
    _repeat = mode;
    notifyListeners();
    await handler.setRepeatSetting(mode);
    await storage.saveRepeat(mode);
  }

  Future<void> cycleRepeat() => setRepeat(_repeat.next);

  Future<void> setShuffle(bool enabled) async {
    _shuffle = enabled;
    notifyListeners();
    await handler.setShuffleEnabled(enabled);
    await storage.saveShuffle(enabled);
  }

  Future<void> toggleShuffle() => setShuffle(!_shuffle);

  // ───────────────────────── 음량 ─────────────────────────

  /// 드래그 중에는 persist=false, 손을 뗄 때 persist=true
  Future<void> setVolume(double volume, {bool persist = false}) async {
    _volume = volume.clamp(0.0, 1.0);
    notifyListeners();
    await handler.setVolume(_volume);
    if (persist) await storage.saveVolume(_volume);
  }

  // ───────────────────────── 취침 타이머 ─────────────────────────
  // 사용자가 15/30/60분을 직접 고를 때만 동작한다. (앱 재시작 시 저장/복원하지 않음)

  void startSleepTimer(int minutes) {
    _sleepTimer?.cancel();
    _sleepEndsAt = DateTime.now().add(Duration(minutes: minutes));
    _sleepRemaining = Duration(minutes: minutes);
    _sleepTimer = Timer.periodic(const Duration(seconds: 1), (_) => _tickSleep());
    _messageCtrl.add('$minutes분 후 재생이 일시정지됩니다.');
    notifyListeners();
  }

  void cancelSleepTimer({bool notify = true}) {
    _sleepTimer?.cancel();
    _sleepTimer = null;
    _sleepEndsAt = null;
    _sleepRemaining = null;
    if (notify) notifyListeners();
  }

  void _tickSleep() {
    final end = _sleepEndsAt;
    if (end == null) return;
    final remaining = end.difference(DateTime.now());
    if (remaining <= Duration.zero) {
      cancelSleepTimer();
      handler.pause();
      _messageCtrl.add('취침 타이머가 끝나 재생을 일시정지했습니다.');
      return;
    }
    _sleepRemaining = remaining;
    notifyListeners();
  }

  // ───────────────────────── 저장 ─────────────────────────

  void _savePlayback({bool force = false, Duration? position}) {
    if (!_restored) return;
    final current = _current;
    if (current == null) return; // 재생 정보가 없으면 기존 저장값 유지
    final now = DateTime.now();
    if (!force && now.difference(_lastSave) < const Duration(seconds: 3)) return;
    _lastSave = now;
    storage.saveLastPlayback(
      trackPath: current.path,
      position: position ?? handler.player.position,
      source: _sourceKey,
    );
  }

  /// 앱이 백그라운드로 가거나 종료될 때 즉시 저장
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _savePlayback(force: true);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    library.removeListener(_onLibraryChanged);
    for (final s in _subs) {
      s.cancel();
    }
    _sleepTimer?.cancel();
    _messageCtrl.close();
    super.dispose();
  }
}
