import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

/// 폴더 스캔 및 파일 가져오기(복사)
class FileScanService {
  static const Set<String> supportedExtensions = {
    '.mp3',
    '.m4a',
    '.aac',
    '.wav',
    '.flac',
    '.ogg',
    '.opus',
  };

  /// 파일 선택기에 넘길 확장자 목록 (점 제외)
  static List<String> get pickerExtensions =>
      supportedExtensions.map((e) => e.substring(1)).toList();

  static bool isSupported(String path) =>
      supportedExtensions.contains(p.extension(path).toLowerCase());

  /// [dirPath] 아래의 지원 오디오 파일 경로를 모두 찾는다.
  /// 접근할 수 없는 하위 폴더는 건너뛴다. 숨김 폴더/파일(.xxx)은 제외.
  Future<List<String>> scanFolder(String dirPath, {bool recursive = true}) async {
    final dir = Directory(dirPath);
    if (!await dir.exists()) {
      throw FileSystemException('폴더를 찾을 수 없습니다', dirPath);
    }

    final found = <String>[];
    final stream = dir
        .list(recursive: recursive, followLinks: false)
        .handleError(
          (Object e) => debugPrint('scan skip: $e'),
          test: (e) => e is FileSystemException,
        );

    await for (final entity in stream) {
      if (entity is! File) continue;
      if (_isHidden(entity.path, dirPath)) continue;
      if (isSupported(entity.path)) found.add(entity.path);
    }
    return found;
  }

  bool _isHidden(String path, String root) {
    final rel = p.relative(path, from: root);
    return p.split(rel).any((seg) => seg.startsWith('.'));
  }

  /// 파일 선택기로 고른 파일(임시 캐시에 있음)을 앱 Documents/Imported 로 복사.
  /// 앱 재시작 후에도 재생목록 경로가 유효하도록 하기 위함.
  Future<List<String>> importFiles(
    List<String> sourcePaths,
    String documentsDir,
  ) async {
    final destDir = Directory(p.join(documentsDir, 'Imported'));
    await destDir.create(recursive: true);

    final result = <String>[];
    for (final src in sourcePaths) {
      if (!isSupported(src)) continue;
      try {
        final srcFile = File(src);
        var dest = p.join(destDir.path, p.basename(src));

        if (p.equals(src, dest)) {
          result.add(dest);
          continue;
        }

        if (await File(dest).exists()) {
          // 같은 이름 + 같은 크기면 이미 가져온 파일로 간주
          if (await File(dest).length() == await srcFile.length()) {
            result.add(dest);
            continue;
          }
          dest = await _uniquePath(dest);
        }

        await srcFile.copy(dest);
        result.add(dest);
      } catch (e) {
        debugPrint('import failed ($src): $e');
      }
    }
    return result;
  }

  Future<String> _uniquePath(String path) async {
    final dir = p.dirname(path);
    final base = p.basenameWithoutExtension(path);
    final ext = p.extension(path);
    var i = 1;
    while (true) {
      final candidate = p.join(dir, '$base ($i)$ext');
      if (!await File(candidate).exists()) return candidate;
      i++;
    }
  }
}
