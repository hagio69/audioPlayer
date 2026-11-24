import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/player_settings.dart';
import '../models/playlist.dart';
import '../models/track.dart';
import '../utils/sort_option.dart';

/// shared_preferences 기반 로컬 상태 저장소.
///
/// iOS는 앱 업데이트/재설치 시 앱 컨테이너 경로(UUID)가 바뀌므로
/// 앱 Documents 폴더 아래 경로는 '@docs/상대경로' 형태로 저장했다가 복원한다.
class StorageService {
  StorageService._(this._prefs, this._docsDir);

  static Future<StorageService> create() async {
    final prefs = await SharedPreferences.getInstance();
    final docs = await getApplicationDocumentsDirectory();
    return StorageService._(prefs, docs.path);
  }

  final SharedPreferences _prefs;
  final String _docsDir;

  static const _docsToken = '@docs';

  static const _kPlaylists = 'playlists_v2';
  static const _kLegacyPlaylist = 'playlist_v1';
  static const _kLegacyPlaylistSort = 'playlist_sort';
  static const _kPlayCounts = 'play_counts_v1';
  static const _kRepeat = 'repeat_mode';
  static const _kShuffle = 'shuffle';
  static const _kSpeed = 'speed';
  static const _kVolume = 'volume';
  static const _kLastFolder = 'last_folder';
  static const _kFolderSort = 'folder_sort';
  static const _kLastTrack = 'last_track_path';
  static const _kLastPosition = 'last_position_ms';
  static const _kLastSource = 'last_source';
  static const _kBatteryPrompted = 'battery_prompted';

  /// 앱 Documents 폴더 (iOS: 파일 앱에서 보이는 앱 폴더)
  String get documentsDir => _docsDir;

  // ───────────────────────── 경로 인코딩 ─────────────────────────

  String _normalize(String path) {
    // iOS에서 '/private/var/...' 와 '/var/...' 가 섞여 나오는 경우 통일
    if (path.startsWith('/private/var/')) return path.substring('/private'.length);
    return path;
  }

  String encodePath(String path) {
    final norm = _normalize(path);
    final docs = _normalize(_docsDir);
    if (p.equals(norm, docs)) return _docsToken;
    if (p.isWithin(docs, norm)) {
      return '$_docsToken/${p.relative(norm, from: docs)}';
    }
    return path;
  }

  String decodePath(String stored) {
    if (stored == _docsToken) return _docsDir;
    if (stored.startsWith('$_docsToken/')) {
      return p.join(_docsDir, stored.substring(_docsToken.length + 1));
    }
    return stored;
  }

  List<Track> _decodeTracks(List<dynamic> list) => list.map((e) {
        final map = Map<String, dynamic>.from(e as Map);
        map['path'] = decodePath(map['path'] as String);
        return Track.fromJson(map);
      }).toList();

  List<Map<String, dynamic>> _encodeTracks(List<Track> tracks) => tracks.map((t) {
        final m = t.toJson();
        m['path'] = encodePath(t.path);
        return m;
      }).toList();

  // ───────────────────────── 재생목록 (여러 개) ─────────────────────────

  /// [defaultNames.length] 개의 재생목록을 불러온다.
  /// 이전 버전(재생목록 1개)의 데이터가 있으면 첫 번째 재생목록으로 옮긴다.
  List<Playlist> loadPlaylists(List<String> defaultNames) {
    final result = <Playlist>[];
    final raw = _prefs.getString(_kPlaylists);

    if (raw != null) {
      try {
        final list = jsonDecode(raw) as List<dynamic>;
        for (final e in list) {
          final map = Map<String, dynamic>.from(e as Map);
          final name = (map['name'] as String?)?.trim() ?? '';
          result.add(Playlist(
            name: name.isEmpty ? defaultNames[result.length % defaultNames.length] : name,
            tracks: _decodeTracks(map['tracks'] as List<dynamic>? ?? const []),
            sort: SortOption.decode(map['sort'] as String?),
          ));
        }
      } catch (e) {
        debugPrint('playlists decode error: $e');
        result.clear();
      }
    } else {
      // v1 → v2 마이그레이션
      final legacyRaw = _prefs.getString(_kLegacyPlaylist);
      if (legacyRaw != null) {
        try {
          result.add(Playlist(
            name: defaultNames.first,
            tracks: _decodeTracks(jsonDecode(legacyRaw) as List<dynamic>),
            sort: SortOption.decode(_prefs.getString(_kLegacyPlaylistSort)),
          ));
        } catch (_) {}
      }
    }

    while (result.length < defaultNames.length) {
      result.add(Playlist(name: defaultNames[result.length]));
    }
    return result.take(defaultNames.length).toList();
  }

  Future<void> savePlaylists(List<Playlist> playlists) {
    final data = playlists
        .map((pl) => {
              'name': pl.name,
              'sort': pl.sort.encode(),
              'tracks': _encodeTracks(pl.tracks),
            })
        .toList();
    return _prefs.setString(_kPlaylists, jsonEncode(data));
  }

  // ───────────────────────── 재생 횟수 ─────────────────────────

  Map<String, int> loadPlayCounts() {
    final raw = _prefs.getString(_kPlayCounts);
    if (raw == null) return {};
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      return map.map((k, v) => MapEntry(decodePath(k), (v as num).toInt()));
    } catch (_) {
      return {};
    }
  }

  Future<void> savePlayCounts(Map<String, int> counts) {
    final encoded = counts.map((k, v) => MapEntry(encodePath(k), v));
    return _prefs.setString(_kPlayCounts, jsonEncode(encoded));
  }

  // ───────────────────────── 재생 설정 ─────────────────────────

  RepeatModeSetting loadRepeat() =>
      RepeatModeSetting.fromName(_prefs.getString(_kRepeat));

  Future<void> saveRepeat(RepeatModeSetting mode) =>
      _prefs.setString(_kRepeat, mode.name);

  bool loadShuffle() => _prefs.getBool(_kShuffle) ?? false;

  Future<void> saveShuffle(bool value) => _prefs.setBool(_kShuffle, value);

  double loadSpeed() {
    final v = _prefs.getDouble(_kSpeed) ?? 1.0;
    return kSpeedOptions.contains(v) ? v : 1.0;
  }

  Future<void> saveSpeed(double speed) => _prefs.setDouble(_kSpeed, speed);

  double loadVolume() => (_prefs.getDouble(_kVolume) ?? 1.0).clamp(0.0, 1.0);

  Future<void> saveVolume(double volume) => _prefs.setDouble(_kVolume, volume);

  // ───────────────────────── 폴더 ─────────────────────────

  SortOption loadFolderSort() =>
      SortOption.decode(_prefs.getString(_kFolderSort));

  Future<void> saveFolderSort(SortOption o) =>
      _prefs.setString(_kFolderSort, o.encode());

  String? loadLastFolder() {
    final raw = _prefs.getString(_kLastFolder);
    return raw == null ? null : decodePath(raw);
  }

  Future<void> saveLastFolder(String? path) => path == null
      ? _prefs.remove(_kLastFolder)
      : _prefs.setString(_kLastFolder, encodePath(path));

  // ───────────────────────── 마지막 재생 곡 / 위치 / 출처 ─────────────────────────

  String? loadLastTrackPath() {
    final raw = _prefs.getString(_kLastTrack);
    return raw == null ? null : decodePath(raw);
  }

  Duration loadLastPosition() =>
      Duration(milliseconds: _prefs.getInt(_kLastPosition) ?? 0);

  /// 'playlist:0', 'playlist:1', 'folder'
  String? loadLastSource() => _prefs.getString(_kLastSource);

  Future<void> saveLastPlayback({
    required String trackPath,
    required Duration position,
    required String source,
  }) async {
    await _prefs.setString(_kLastTrack, encodePath(trackPath));
    await _prefs.setInt(_kLastPosition, position.inMilliseconds);
    await _prefs.setString(_kLastSource, source);
  }

  // ───────────────────────── 기타 ─────────────────────────

  bool get batteryPrompted => _prefs.getBool(_kBatteryPrompted) ?? false;

  Future<void> setBatteryPrompted() => _prefs.setBool(_kBatteryPrompted, true);
}
