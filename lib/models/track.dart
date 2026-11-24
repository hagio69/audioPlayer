import 'package:audio_service/audio_service.dart';
import 'package:path/path.dart' as p;

/// 오디오 파일 1개를 나타내는 불변 모델.
/// 동일성(==)은 파일 경로 기준.
class Track {
  const Track({
    required this.path,
    required this.title,
    this.artist = '',
    this.album = '',
    this.durationMs,
  });

  /// 메타데이터가 없을 때 파일 이름으로 기본 Track 생성
  factory Track.fromPath(String path) =>
      Track(path: path, title: p.basenameWithoutExtension(path));

  factory Track.fromJson(Map<String, dynamic> json) {
    final path = json['path'] as String;
    final rawTitle = (json['title'] as String?)?.trim() ?? '';
    return Track(
      path: path,
      title: rawTitle.isEmpty ? p.basenameWithoutExtension(path) : rawTitle,
      artist: (json['artist'] as String?)?.trim() ?? '',
      album: (json['album'] as String?)?.trim() ?? '',
      durationMs: (json['durationMs'] as num?)?.toInt(),
    );
  }

  final String path;
  final String title;
  final String artist;
  final String album;
  final int? durationMs;

  String get fileName => p.basename(path);

  String get displayArtist => artist.isEmpty ? '알 수 없는 아티스트' : artist;

  String get displayAlbum => album.isEmpty ? '알 수 없는 앨범' : album;

  String get subtitle => '$displayArtist · $displayAlbum';

  Duration? get duration => (durationMs == null || durationMs! <= 0)
      ? null
      : Duration(milliseconds: durationMs!);

  Track copyWith({
    String? path,
    String? title,
    String? artist,
    String? album,
    int? durationMs,
  }) {
    return Track(
      path: path ?? this.path,
      title: title ?? this.title,
      artist: artist ?? this.artist,
      album: album ?? this.album,
      durationMs: durationMs ?? this.durationMs,
    );
  }

  Map<String, dynamic> toJson() => {
        'path': path,
        'title': title,
        'artist': artist,
        'album': album,
        'durationMs': durationMs,
      };

  /// 잠금화면/알림창에 표시할 MediaItem
  MediaItem toMediaItem({Duration? duration}) => MediaItem(
        id: path,
        title: title,
        artist: displayArtist,
        album: displayAlbum,
        duration: duration ?? this.duration,
        extras: {'path': path},
      );

  @override
  bool operator ==(Object other) => other is Track && other.path == path;

  @override
  int get hashCode => path.hashCode;

  @override
  String toString() => 'Track($fileName)';
}
