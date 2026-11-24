import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../models/playlist.dart';
import '../models/track.dart';
import '../services/file_scan_service.dart';
import '../services/metadata_service.dart';
import '../services/permission_service.dart';
import '../services/storage_service.dart';
import '../utils/sort_option.dart';

enum FolderPickResult {
  success,
  cancelled,
  permissionDenied,
  permissionPermanentlyDenied,
  failed,
}

/// 파일 목록(폴더 스캔 결과), 재생목록 2개, 선택 상태, 정렬, 재생 횟수를 관리.
class LibraryProvider extends ChangeNotifier {
  LibraryProvider({
    required this.storage,
    FileScanService? scanner,
    MetadataService? metadata,
    PermissionService? permissions,
  })  : scanner = scanner ?? FileScanService(),
        metadata = metadata ?? MetadataService(),
        permissions = permissions ?? PermissionService();

  /// 재생목록 개수와 기본 이름
  static const List<String> defaultPlaylistNames = ['재생목록1', '재생목록2'];
  static int get playlistCount => defaultPlaylistNames.length;
  static const int maxNameLength = 20;

  final StorageService storage;
  final FileScanService scanner;
  final MetadataService metadata;
  final PermissionService permissions;

  // ── 재생목록 ──
  List<Playlist> _playlists = [
    for (final n in defaultPlaylistNames) Playlist(name: n),
  ];
  final List<Set<String>> _selections = [for (final _ in defaultPlaylistNames) <String>{}];
  final List<List<Track>?> _sortedCache = List.filled(defaultPlaylistNames.length, null);
  final List<Set<String>?> _pathCache = List.filled(defaultPlaylistNames.length, null);

  // ── 파일 목록 ──
  List<Track> _folderTracks = [];
  String? _folderPath;
  SortOption _folderSort = const SortOption();
  final Set<String> _folderSelection = {};
  List<Track>? _sortedFolderCache;

  Map<String, int> _playCounts = {};

  bool _initializing = true;
  bool _scanning = false;
  bool _importing = false;
  int _scanDone = 0;
  int _scanTotal = 0;
  String? _scanError;

  final _messageCtrl = StreamController<String>.broadcast();

  // ───────────────────────── getter ─────────────────────────

  bool get initializing => _initializing;
  bool get scanning => _scanning;
  bool get importing => _importing;
  int get scanDone => _scanDone;
  int get scanTotal => _scanTotal;
  String? get scanError => _scanError;
  String? get folderPath => _folderPath;
  String? get folderName => _folderPath == null
      ? null
      : (_folderPath == storage.documentsDir ? '앱 폴더' : p.basename(_folderPath!));

  /// 사용자 안내 메시지 (SnackBar)
  Stream<String> get messageStream => _messageCtrl.stream;

  // 재생목록 (index: 0, 1)
  String playlistName(int i) => _playlists[i].name;
  List<String> get playlistNames => _playlists.map((pl) => pl.name).toList();
  List<Track> playlistTracks(int i) => List.unmodifiable(_playlists[i].tracks);
  SortOption playlistSort(int i) => _playlists[i].sort;

  List<Track> sortedPlaylist(int i) =>
      _sortedCache[i] ??= List.unmodifiable(_playlists[i].sort.apply(_playlists[i].tracks));

  Set<String> playlistSelection(int i) => UnmodifiableSetView(_selections[i]);
  bool hasPlaylistSelection(int i) => _selections[i].isNotEmpty;

  /// 선택된 곡 (현재 정렬 순서 유지)
  List<Track> selectedPlaylistTracks(int i) => sortedPlaylist(i)
      .where((t) => _selections[i].contains(t.path))
      .toList(growable: false);

  bool isInPlaylist(int i, String path) =>
      (_pathCache[i] ??= _playlists[i].tracks.map((t) => t.path).toSet()).contains(path);

  /// 이 곡이 들어 있는 재생목록 번호들
  List<int> playlistsContaining(String path) => [
        for (var i = 0; i < _playlists.length; i++)
          if (isInPlaylist(i, path)) i,
      ];

  // 파일 목록
  SortOption get folderSort => _folderSort;

  List<Track> get sortedFolderTracks =>
      _sortedFolderCache ??= List.unmodifiable(_folderSort.apply(_folderTracks));

  Set<String> get folderSelection => UnmodifiableSetView(_folderSelection);
  bool get hasFolderSelection => _folderSelection.isNotEmpty;

  List<Track> get selectedFolderTracks => sortedFolderTracks
      .where((t) => _folderSelection.contains(t.path))
      .toList(growable: false);

  int playCountOf(String path) => _playCounts[path] ?? 0;

  void _invalidatePlaylist(int i) {
    _sortedCache[i] = null;
    _pathCache[i] = null;
  }

  void _invalidateFolder() => _sortedFolderCache = null;

  Future<void> _savePlaylists() => storage.savePlaylists(_playlists);

  // ───────────────────────── 초기화 / 복원 ─────────────────────────

  Future<void> init() async {
    _folderSort = storage.loadFolderSort();
    _playCounts = storage.loadPlayCounts();
    _playlists = storage.loadPlaylists(defaultPlaylistNames);

    // 사라진 파일 정리
    var removed = 0;
    for (final pl in _playlists) {
      final existing = <Track>[];
      for (final t in pl.tracks) {
        if (await File(t.path).exists()) existing.add(t);
      }
      removed += pl.tracks.length - existing.length;
      pl.tracks
        ..clear()
        ..addAll(existing);
    }
    for (var i = 0; i < _playlists.length; i++) {
      _invalidatePlaylist(i);
    }
    await _savePlaylists();
    if (removed > 0) {
      _messageCtrl.add('찾을 수 없는 파일 $removed개를 재생목록에서 제외했습니다.');
    }
    _initializing = false;
    notifyListeners();

    // 마지막 폴더 복원
    final last = storage.loadLastFolder();
    var restored = false;
    if (last != null &&
        await Directory(last).exists() &&
        await permissions.hasAudioPermission()) {
      restored = await scanFolder(last, silent: true);
    }
    // iOS 는 기본으로 앱 Documents 폴더를 보여줌
    if (!restored && Platform.isIOS) {
      await scanFolder(storage.documentsDir, silent: true);
    }
  }

  // ───────────────────────── 재생목록 이름 ─────────────────────────

  void renamePlaylist(int i, String name) {
    var trimmed = name.trim();
    if (trimmed.isEmpty) trimmed = defaultPlaylistNames[i];
    if (trimmed.length > maxNameLength) trimmed = trimmed.substring(0, maxNameLength);
    if (trimmed == _playlists[i].name) return;
    _playlists[i].name = trimmed;
    _savePlaylists();
    notifyListeners();
  }

  // ───────────────────────── 폴더 선택 / 스캔 ─────────────────────────

  Future<FolderPickResult> pickFolder() async {
    final perm = await permissions.requestAudioPermission();
    switch (perm) {
      case AudioPermissionResult.denied:
        return FolderPickResult.permissionDenied;
      case AudioPermissionResult.permanentlyDenied:
        return FolderPickResult.permissionPermanentlyDenied;
      case AudioPermissionResult.granted:
        break;
    }

    String? dir;
    try {
      dir = await FilePicker.platform.getDirectoryPath(
        dialogTitle: '오디오 폴더 선택',
      );
    } catch (e) {
      debugPrint('getDirectoryPath error: $e');
      _scanError = '폴더를 선택할 수 없습니다.';
      notifyListeners();
      return FolderPickResult.failed;
    }
    if (dir == null || dir.isEmpty || dir == '/') {
      return FolderPickResult.cancelled;
    }

    final ok = await scanFolder(dir);
    return ok ? FolderPickResult.success : FolderPickResult.failed;
  }

  /// iOS: 파일 앱 > 나의 iPhone > hagioAudioPlayer 폴더
  Future<bool> scanAppDocuments() => scanFolder(storage.documentsDir);

  Future<bool> rescan() async {
    final dir = _folderPath;
    if (dir == null) return false;
    return scanFolder(dir);
  }

  Future<bool> scanFolder(String dir, {bool silent = false}) async {
    if (_scanning) return false;
    _scanning = true;
    _scanDone = 0;
    _scanTotal = 0;
    _scanError = null;
    _folderPath = dir;
    _folderSelection.clear();
    notifyListeners();

    try {
      final paths = await scanner.scanFolder(dir);
      _scanTotal = paths.length;
      notifyListeners();

      // 재생목록에 이미 있는 곡은 메타데이터 재사용
      final known = <String, Track>{
        for (final pl in _playlists)
          for (final t in pl.tracks) t.path: t,
      };
      final unknown = paths.where((path) => !known.containsKey(path)).toList();
      final already = paths.length - unknown.length;

      final parsed = await metadata.readTracks(
        unknown,
        onProgress: (done, total) {
          _scanDone = already + done;
          notifyListeners();
        },
      );
      final parsedMap = {for (final t in parsed) t.path: t};

      _folderTracks = [
        for (final path in paths) known[path] ?? parsedMap[path] ?? Track.fromPath(path),
      ];
      _scanDone = paths.length;
      _invalidateFolder();
      await storage.saveLastFolder(dir);
      return true;
    } catch (e) {
      debugPrint('scan error: $e');
      _folderTracks = [];
      _invalidateFolder();
      _scanError = Platform.isIOS
          ? '폴더를 읽을 수 없습니다. 파일 앱에서 음악을 앱 폴더(hagioAudioPlayer)로 복사한 뒤 "앱 폴더 보기"를 이용해 주세요.'
          : '폴더를 읽을 수 없습니다. 권한과 폴더 위치를 확인해 주세요.';
      if (!silent) _messageCtrl.add(_scanError!);
      return false;
    } finally {
      _scanning = false;
      notifyListeners();
    }
  }

  // ───────────────────────── 재생목록 편집 ─────────────────────────

  /// 중복을 제외하고 [i]번 재생목록에 추가. 추가된 개수 반환.
  int addTracksToPlaylist(int i, Iterable<Track> tracks) {
    final pl = _playlists[i];
    final existing = pl.tracks.map((t) => t.path).toSet();
    var added = 0;
    for (final t in tracks) {
      if (existing.add(t.path)) {
        pl.tracks.add(t);
        added++;
      }
    }
    if (added > 0) {
      _invalidatePlaylist(i);
      _savePlaylists();
      notifyListeners();
    }
    return added;
  }

  int addSelectedFolderTracksToPlaylist(int i) {
    final added = addTracksToPlaylist(i, selectedFolderTracks);
    _folderSelection.clear();
    notifyListeners();
    return added;
  }

  /// 파일 선택기에서 여러 파일을 직접 골라 [i]번 재생목록에 추가 (앱 폴더로 복사)
  /// 반환값: 추가된 곡 수, 취소 시 null
  Future<int?> importFilesToPlaylist(int i) async {
    FilePickerResult? result;
    try {
      result = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        type: FileType.custom,
        allowedExtensions: FileScanService.pickerExtensions,
        dialogTitle: '재생목록에 추가할 오디오 파일 선택',
      );
    } catch (e) {
      debugPrint('pickFiles error: $e');
      _messageCtrl.add('파일을 선택할 수 없습니다.');
      return 0;
    }
    if (result == null) return null;

    final sources = result.paths.whereType<String>().toList();
    if (sources.isEmpty) return 0;

    _importing = true;
    notifyListeners();
    try {
      final copied = await scanner.importFiles(sources, storage.documentsDir);
      final skipped = sources.length - copied.length;
      if (skipped > 0) {
        _messageCtrl.add('지원하지 않거나 읽을 수 없는 파일 $skipped개를 건너뛰었습니다.');
      }
      final tracks = await metadata.readTracks(copied);
      final added = addTracksToPlaylist(i, tracks);

      try {
        await FilePicker.platform.clearTemporaryFiles();
      } catch (_) {}

      if (_folderPath == storage.documentsDir) {
        unawaited(scanFolder(storage.documentsDir, silent: true));
      }
      return added;
    } finally {
      _importing = false;
      notifyListeners();
    }
  }

  void removeFromPlaylist(int i, Iterable<String> paths) {
    final set = paths.toSet();
    if (set.isEmpty) return;
    _playlists[i].tracks.removeWhere((t) => set.contains(t.path));
    _selections[i].removeAll(set);
    _invalidatePlaylist(i);
    _savePlaylists();
    notifyListeners();
  }

  void removeSelectedFromPlaylist(int i) =>
      removeFromPlaylist(i, Set.of(_selections[i]));

  void clearPlaylist(int i) {
    _playlists[i].tracks.clear();
    _selections[i].clear();
    _invalidatePlaylist(i);
    _savePlaylists();
    notifyListeners();
  }

  // ───────────────────────── 선택 ─────────────────────────

  void togglePlaylistSelection(int i, String path) {
    if (!_selections[i].remove(path)) _selections[i].add(path);
    notifyListeners();
  }

  void selectAllPlaylist(int i) {
    _selections[i]
      ..clear()
      ..addAll(_playlists[i].tracks.map((t) => t.path));
    notifyListeners();
  }

  void clearPlaylistSelection(int i) {
    if (_selections[i].isEmpty) return;
    _selections[i].clear();
    notifyListeners();
  }

  void toggleFolderSelection(String path) {
    if (!_folderSelection.remove(path)) _folderSelection.add(path);
    notifyListeners();
  }

  void selectAllFolder() {
    _folderSelection
      ..clear()
      ..addAll(_folderTracks.map((t) => t.path));
    notifyListeners();
  }

  void clearFolderSelection() {
    if (_folderSelection.isEmpty) return;
    _folderSelection.clear();
    notifyListeners();
  }

  // ───────────────────────── 정렬 ─────────────────────────

  void setPlaylistSort(int i, SortOption option) {
    if (option == _playlists[i].sort) return;
    _playlists[i].sort = option;
    _invalidatePlaylist(i);
    _savePlaylists();
    notifyListeners();
  }

  void setFolderSort(SortOption option) {
    if (option == _folderSort) return;
    _folderSort = option;
    _invalidateFolder();
    storage.saveFolderSort(option);
    notifyListeners();
  }

  // ───────────────────────── 재생 횟수 ─────────────────────────

  void incrementPlayCount(String path) {
    _playCounts[path] = (_playCounts[path] ?? 0) + 1;
    storage.savePlayCounts(_playCounts);
    notifyListeners();
  }

  void resetPlayCount(String path) {
    if (_playCounts.remove(path) == null) return;
    storage.savePlayCounts(_playCounts);
    notifyListeners();
  }

  void resetPlayCounts(Iterable<String> paths) {
    for (final path in paths) {
      _playCounts.remove(path);
    }
    storage.savePlayCounts(_playCounts);
    notifyListeners();
  }

  void resetAllPlayCounts() {
    _playCounts.clear();
    storage.savePlayCounts(_playCounts);
    notifyListeners();
  }

  Future<bool> openAppSettings() => permissions.openSettings();

  @override
  void dispose() {
    _messageCtrl.close();
    super.dispose();
  }
}
