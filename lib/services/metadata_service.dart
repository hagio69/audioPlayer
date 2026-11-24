import 'dart:io';
import 'dart:isolate';
import 'dart:math';

import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'package:path/path.dart' as p;

import '../models/track.dart';

/// 오디오 파일 태그(제목/아티스트/앨범/길이) 파싱.
/// UI 끊김을 막기 위해 별도 Isolate 에서 배치 단위로 처리한다.
class MetadataService {
  static const int _batchSize = 40;

  Future<List<Track>> readTracks(
    List<String> paths, {
    void Function(int done, int total)? onProgress,
  }) async {
    final result = <Track>[];
    if (paths.isEmpty) return result;

    for (var i = 0; i < paths.length; i += _batchSize) {
      final chunk = paths.sublist(i, min(i + _batchSize, paths.length));
      List<Map<String, dynamic>> maps;
      try {
        maps = await _parseInIsolate(chunk);
      } catch (_) {
        // Isolate 실패 시 파일명 기반으로 대체
        maps = chunk.map(_fallback).toList();
      }
      result.addAll(maps.map(Track.fromJson));
      onProgress?.call(result.length, paths.length);
    }
    return result;
  }
}

// ── 아래는 Isolate 로 전달되므로 반드시 top-level 함수여야 함 ──

Future<List<Map<String, dynamic>>> _parseInIsolate(List<String> chunk) =>
    Isolate.run(() => _parseChunk(chunk));

List<Map<String, dynamic>> _parseChunk(List<String> paths) =>
    paths.map(_parseOne).toList();

Map<String, dynamic> _parseOne(String path) {
  try {
    final meta = readMetadata(File(path), getImage: false);
    return {
      'path': path,
      'title': _clean(meta.title) ?? p.basenameWithoutExtension(path),
      'artist': _clean(meta.artist) ?? '',
      'album': _clean(meta.album) ?? '',
      'durationMs': meta.duration?.inMilliseconds,
    };
  } catch (_) {
    // 태그 없음 / 지원하지 않는 형식 / 손상 파일 → 파일명 사용
    return _fallback(path);
  }
}

Map<String, dynamic> _fallback(String path) => {
      'path': path,
      'title': p.basenameWithoutExtension(path),
      'artist': '',
      'album': '',
      'durationMs': null,
    };

String? _clean(String? s) {
  if (s == null) return null;
  final t = s.replaceAll('\u0000', '').trim();
  return t.isEmpty ? null : t;
}
