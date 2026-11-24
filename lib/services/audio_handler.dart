import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

import '../models/player_settings.dart';
import '../models/track.dart';

/// 백그라운드 재생 + 잠금화면/알림창 컨트롤을 담당하는 AudioHandler.
///
/// 큐(재생 순서)를 직접 관리한다. just_audio 에는 한 번에 한 곡만 로드하고,
/// 곡이 끝났을 때(completed) 반복/셔플 규칙에 따라 다음 곡을 결정한다.
///  - 반복 끄기 : 다음 곡으로 인덱스 이동 후 pause() 상태로 대기
///  - 전체 반복 : 다음 곡 자동 재생 (마지막 곡 이후 처음으로)
///  - 한 곡 반복: 현재 곡 처음부터 다시 재생
/// 곡이 끝까지 재생될 때마다 [completedStream] 으로 알린다(재생 횟수 집계용).
class HagioAudioHandler extends BaseAudioHandler with SeekHandler {
  HagioAudioHandler() {
    _init();
  }

  final AudioPlayer _player = AudioPlayer();
  final Random _random = Random();

  /// 현재 큐(원래 순서)
  List<Track> _tracks = const [];

  /// 재생 순서: _tracks 의 인덱스 목록 (셔플 시 섞임)
  List<int> _order = const [];

  /// _order 안에서 현재 곡의 위치. 현재 곡이 큐에 없으면 -1
  int _orderPos = -1;

  Track? _current;
  RepeatModeSetting _repeat = RepeatModeSetting.off;
  bool _shuffle = false;

  bool _handlingCompletion = false;
  int _consecutiveErrors = 0;
  int _loadToken = 0;

  final _currentCtrl = StreamController<Track?>.broadcast();
  final _errorCtrl = StreamController<String>.broadcast();
  final _completedCtrl = StreamController<Track>.broadcast();
  final _settingsCtrl = StreamController<void>.broadcast();
  final _pausedAtEndCtrl = StreamController<Track?>.broadcast();

  // ───────────────────────── 공개 getter ─────────────────────────

  AudioPlayer get player => _player;
  Track? get currentTrack => _current;
  List<Track> get queueTracks => List.unmodifiable(_tracks);
  RepeatModeSetting get repeatSetting => _repeat;
  bool get shuffleEnabled => _shuffle;

  /// 현재 곡 변경
  Stream<Track?> get currentTrackStream => _currentCtrl.stream;

  /// 사용자에게 보여줄 오류 메시지
  Stream<String> get errorStream => _errorCtrl.stream;

  /// 곡이 끝까지 재생 완료됨
  Stream<Track> get completedStream => _completedCtrl.stream;

  /// 반복/셔플이 외부(블루투스·잠금화면 등)에서 바뀜
  Stream<void> get settingsChangedStream => _settingsCtrl.stream;

  /// '반복 끄기' 규칙으로 곡이 끝난 뒤 다음 곡에서 일시정지됨
  Stream<Track?> get pausedAtEndStream => _pausedAtEndCtrl.stream;

  // ───────────────────────── 초기화 ─────────────────────────

  void _init() {
    _player.playbackEventStream.listen(
      (_) => _broadcastState(),
      onError: (Object e, StackTrace st) {
        debugPrint('playback error: $e');
        _errorCtrl.add('재생 중 오류가 발생했습니다.');
      },
    );
    _player.playingStream.listen((playing) {
      _broadcastState();
      if (playing) {
        // 재생이 시작되면 곡 정보를 다시 알려 준다.
        // 차량 헤드유닛은 블루투스(AVRCP)로 '재생 중' 상태와 곡 정보를 받아야
        // 오디오 소스를 휴대폰으로 자동 전환하는 경우가 많다.
        final item = mediaItem.valueOrNull;
        if (item != null) mediaItem.add(item);
      }
    });
    _player.speedStream.listen((_) => _broadcastState());
    _player.processingStateStream.listen((state) {
      if (state == ProcessingState.completed) {
        unawaited(_handleCompletion());
      }
    });
  }

  // ───────────────────────── 큐 관리 ─────────────────────────

  /// 새 큐를 구성하고 [start] 곡부터 재생.
  /// [start] 가 큐에 없으면 그 곡을 먼저 재생하고, 다음 곡부터 큐를 따른다.
  Future<void> playQueue(
    List<Track> tracks, {
    Track? start,
    bool autoplay = true,
    Duration? position,
  }) async {
    _tracks = List.of(tracks);
    Track? first = start;
    if (first == null && _tracks.isNotEmpty) {
      first = _shuffle ? _tracks[_random.nextInt(_tracks.length)] : _tracks.first;
    }
    if (first == null) return;

    _current = first;
    _rebuildOrder();
    _consecutiveErrors = 0;
    await _loadTrack(first, autoplay: autoplay, position: position);
  }

  /// 재생 중인 곡은 유지하면서 큐만 교체 (정렬/선택 변경 시)
  void syncQueue(List<Track> tracks) {
    _tracks = List.of(tracks);
    _rebuildOrder();
    _broadcastState();
  }

  void _rebuildOrder() {
    final curIdx = _current == null
        ? -1
        : _tracks.indexWhere((t) => t.path == _current!.path);

    final order = List<int>.generate(_tracks.length, (i) => i);
    if (_shuffle) {
      order.shuffle(_random);
      if (curIdx >= 0) {
        order.remove(curIdx);
        order.insert(0, curIdx);
      }
    }
    _order = order;
    _orderPos = curIdx < 0 ? -1 : _order.indexOf(curIdx);
    queue.add(_order.map((i) => _tracks[i].toMediaItem()).toList());
  }

  void _reshuffle({int? avoidFirst}) {
    final order = List<int>.generate(_tracks.length, (i) => i)..shuffle(_random);
    if (avoidFirst != null && order.length > 1 && order.first == avoidFirst) {
      final tmp = order[0];
      order[0] = order[1];
      order[1] = tmp;
    }
    _order = order;
    queue.add(_order.map((i) => _tracks[i].toMediaItem()).toList());
  }

  /// 다음 위치 (끝이면 처음으로, 셔플이면 새로 섞음)
  int _nextPos() {
    if (_order.isEmpty) return -1;
    if (_orderPos < 0) return 0;
    final next = _orderPos + 1;
    if (next < _order.length) return next;
    if (_shuffle && _order.length > 1) {
      _reshuffle(avoidFirst: _order[_orderPos]);
    }
    return 0;
  }

  int _previousPos() {
    if (_order.isEmpty) return -1;
    if (_orderPos <= 0) return _order.length - 1;
    return _orderPos - 1;
  }

  Future<bool> _loadAt(int pos, {required bool autoplay, Duration? position}) {
    if (pos < 0 || pos >= _order.length) return Future.value(false);
    _orderPos = pos;
    return _loadTrack(_tracks[_order[pos]], autoplay: autoplay, position: position);
  }

  Future<bool> _loadTrack(
    Track track, {
    required bool autoplay,
    Duration? position,
  }) async {
    final token = ++_loadToken;
    _current = track;
    _currentCtrl.add(track);
    mediaItem.add(track.toMediaItem());
    _broadcastState();

    try {
      if (!autoplay && _player.playing) {
        await _player.pause();
      }
      if (!await File(track.path).exists()) {
        throw FileSystemException('파일이 존재하지 않습니다', track.path);
      }

      final duration = await _player.setAudioSource(
        AudioSource.file(track.path, tag: track.toMediaItem()),
        initialPosition: position,
      );
      if (token != _loadToken) return false; // 그 사이 다른 곡이 요청됨

      if (duration != null) {
        mediaItem.add(track.toMediaItem(duration: duration));
      }
      _consecutiveErrors = 0;
      if (autoplay) {
        await _activateSession();
        // play() 의 Future 는 재생이 멈출 때 완료되므로 await 하지 않음
        unawaited(_player.play());
      }
      _broadcastState();
      return true;
    } on PlayerInterruptedException {
      return false;
    } catch (e) {
      if (token != _loadToken) return false;
      debugPrint('load failed (${track.path}): $e');
      _consecutiveErrors++;
      _errorCtrl.add('재생할 수 없는 파일입니다: ${track.fileName}');

      // 손상/지원 불가 파일은 건너뛰고 다음 곡 시도 (무한 루프 방지)
      if (autoplay && _order.length > 1 && _consecutiveErrors < _order.length) {
        return _loadAt(_nextPos(), autoplay: true);
      }
      _broadcastState();
      return false;
    }
  }

  // ───────────────────────── 곡 종료 처리 ─────────────────────────

  Future<void> _handleCompletion() async {
    if (_handlingCompletion) return;
    _handlingCompletion = true;
    try {
      final finished = _current;
      if (finished != null) _completedCtrl.add(finished);

      switch (_repeat) {
        case RepeatModeSetting.one:
          await _player.seek(Duration.zero);
          unawaited(_player.play());
          return;

        case RepeatModeSetting.all:
          if (_order.isEmpty) {
            await _player.seek(Duration.zero);
            unawaited(_player.play());
            return;
          }
          await _loadAt(_nextPos(), autoplay: true);
          return;

        case RepeatModeSetting.off:
          // 다음 곡으로 포커스만 이동하고 일시정지 상태로 대기
          await _player.pause();
          if (_order.isEmpty) {
            await _player.seek(Duration.zero);
            return;
          }
          await _loadAt(_nextPos(), autoplay: false);
          _pausedAtEndCtrl.add(_current);
          return;
      }
    } finally {
      _handlingCompletion = false;
    }
  }

  // ───────────────────────── 재생 설정 ─────────────────────────

  Future<void> setRepeatSetting(RepeatModeSetting mode) async {
    _repeat = mode;
    _broadcastState();
    _settingsCtrl.add(null);
  }

  Future<void> setShuffleEnabled(bool enabled) async {
    if (_shuffle == enabled) return;
    _shuffle = enabled;
    _rebuildOrder();
    _broadcastState();
    _settingsCtrl.add(null);
  }

  Future<void> setVolume(double volume) =>
      _player.setVolume(volume.clamp(0.0, 1.0));

  /// 현재 위치 기준 상대 이동 (음수면 뒤로)
  Future<void> seekRelative(Duration offset) async {
    final duration = _player.duration;
    if (duration == null) return;
    var target = _player.position + offset;
    if (target < Duration.zero) target = Duration.zero;
    if (target > duration) target = duration;
    await _player.seek(target);
  }

  // ───────────────────────── AudioHandler 오버라이드 ─────────────────────────
  // (잠금화면 / 알림창 / 블루투스 / 이어폰 버튼에서도 호출됨)

  @override
  Future<void> play() async {
    final current = _current;
    if (current == null) return;
    if (_player.processingState == ProcessingState.idle) {
      await _loadTrack(current, autoplay: true, position: _player.position);
      return;
    }
    if (_player.processingState == ProcessingState.completed) {
      await _player.seek(Duration.zero);
    }
    await _activateSession();
    unawaited(_player.play());
  }

  /// 오디오 포커스를 명시적으로 요청하고 미디어 세션을 활성화.
  /// 블루투스 차량/헤드셋이 이 앱을 '현재 재생 중인 앱'으로 인식하게 한다.
  Future<void> _activateSession() async {
    try {
      final session = await AudioSession.instance;
      await session.setActive(true);
    } catch (e) {
      debugPrint('audio session activate failed: $e');
    }
  }

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> stop() async {
    await _player.stop();
    _broadcastState();
  }

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> skipToNext() => _skip(forward: true);

  @override
  Future<void> skipToPrevious() async {
    // 3초 이상 재생됐으면 현재 곡 처음으로
    if (_player.position > const Duration(seconds: 3)) {
      await _player.seek(Duration.zero);
      return;
    }
    await _skip(forward: false);
  }

  Future<void> _skip({required bool forward}) async {
    if (_order.isEmpty) return;
    final wasPlaying = _player.playing &&
        _player.processingState != ProcessingState.completed;
    _consecutiveErrors = 0;
    final pos = forward ? _nextPos() : _previousPos();
    await _loadAt(pos, autoplay: wasPlaying);
  }

  @override
  Future<void> skipToQueueItem(int index) => _loadAt(index, autoplay: true);

  @override
  Future<void> fastForward() => seekRelative(const Duration(seconds: 10));

  @override
  Future<void> rewind() => seekRelative(const Duration(seconds: -10));

  @override
  Future<void> setSpeed(double speed) => _player.setSpeed(speed);

  @override
  Future<void> setRepeatMode(AudioServiceRepeatMode repeatMode) =>
      setRepeatSetting(switch (repeatMode) {
        AudioServiceRepeatMode.none => RepeatModeSetting.off,
        AudioServiceRepeatMode.one => RepeatModeSetting.one,
        _ => RepeatModeSetting.all,
      });

  @override
  Future<void> setShuffleMode(AudioServiceShuffleMode shuffleMode) =>
      setShuffleEnabled(shuffleMode != AudioServiceShuffleMode.none);

  /// 최근 앱 목록에서 앱을 밀어 없앴을 때: 재생 중이 아니면 서비스 종료
  @override
  Future<void> onTaskRemoved() async {
    if (!_player.playing) await stop();
  }

  // ───────────────────────── 상태 브로드캐스트 ─────────────────────────

  void _broadcastState() {
    final playing = _player.playing;
    playbackState.add(playbackState.value.copyWith(
      controls: [
        MediaControl.skipToPrevious,
        MediaControl.rewind,
        if (playing) MediaControl.pause else MediaControl.play,
        MediaControl.fastForward,
        MediaControl.skipToNext,
      ],
      systemActions: const {
        MediaAction.play,
        MediaAction.pause,
        MediaAction.playPause,
        MediaAction.stop,
        MediaAction.skipToNext,
        MediaAction.skipToPrevious,
        MediaAction.seek,
        MediaAction.seekForward,
        MediaAction.seekBackward,
      },
      androidCompactActionIndices: const [0, 2, 4],
      processingState: switch (_player.processingState) {
        ProcessingState.idle => AudioProcessingState.idle,
        ProcessingState.loading => AudioProcessingState.loading,
        ProcessingState.buffering => AudioProcessingState.buffering,
        ProcessingState.ready => AudioProcessingState.ready,
        ProcessingState.completed => AudioProcessingState.completed,
      },
      playing: playing,
      updatePosition: _player.position,
      bufferedPosition: _player.bufferedPosition,
      speed: _player.speed,
      queueIndex: _orderPos >= 0 ? _orderPos : null,
      repeatMode: switch (_repeat) {
        RepeatModeSetting.off => AudioServiceRepeatMode.none,
        RepeatModeSetting.all => AudioServiceRepeatMode.all,
        RepeatModeSetting.one => AudioServiceRepeatMode.one,
      },
      shuffleMode:
          _shuffle ? AudioServiceShuffleMode.all : AudioServiceShuffleMode.none,
    ));
  }
}
