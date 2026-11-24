import '../utils/sort_option.dart';
import 'track.dart';

/// 이름을 바꿀 수 있는 재생목록 1개
class Playlist {
  Playlist({
    required this.name,
    List<Track>? tracks,
    this.sort = const SortOption(),
  }) : tracks = tracks ?? [];

  String name;
  final List<Track> tracks;
  SortOption sort;
}
