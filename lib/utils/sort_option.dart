import '../models/track.dart';

enum SortField {
  fileName('파일 이름'),
  album('앨범'),
  artist('아티스트');

  const SortField(this.label);
  final String label;
}

/// 정렬 기준 + 방향(오름/내림)
class SortOption {
  const SortOption({this.field = SortField.fileName, this.ascending = true});

  final SortField field;
  final bool ascending;

  SortOption copyWith({SortField? field, bool? ascending}) => SortOption(
        field: field ?? this.field,
        ascending: ascending ?? this.ascending,
      );

  String encode() => '${field.name}:${ascending ? 'asc' : 'desc'}';

  static SortOption decode(String? raw) {
    if (raw == null) return const SortOption();
    final parts = raw.split(':');
    final field = SortField.values.firstWhere(
      (f) => f.name == parts.first,
      orElse: () => SortField.fileName,
    );
    final ascending = parts.length < 2 || parts[1] != 'desc';
    return SortOption(field: field, ascending: ascending);
  }

  /// 정렬된 새 리스트 반환 (원본 불변)
  List<Track> apply(Iterable<Track> tracks) {
    final list = List<Track>.of(tracks);
    list.sort(_compare);
    return list;
  }

  int _compare(Track a, Track b) {
    switch (field) {
      case SortField.fileName:
        return _dir(_cmp(a.fileName, b.fileName));
      case SortField.album:
        final empty = _emptyLast(a.album, b.album);
        if (empty != 0) return empty;
        final c = _cmp(a.album, b.album);
        if (c != 0) return _dir(c);
        return _dir(_cmp(a.fileName, b.fileName));
      case SortField.artist:
        final empty = _emptyLast(a.artist, b.artist);
        if (empty != 0) return empty;
        final c = _cmp(a.artist, b.artist);
        if (c != 0) return _dir(c);
        final c2 = _cmp(a.album, b.album);
        if (c2 != 0) return _dir(c2);
        return _dir(_cmp(a.fileName, b.fileName));
    }
  }

  int _dir(int c) => ascending ? c : -c;

  /// 값이 비어있는 항목(알 수 없음)은 정렬 방향과 무관하게 항상 뒤로
  static int _emptyLast(String a, String b) {
    if (a.isEmpty && b.isNotEmpty) return 1;
    if (a.isNotEmpty && b.isEmpty) return -1;
    return 0;
  }

  static int _cmp(String a, String b) =>
      a.toLowerCase().compareTo(b.toLowerCase());

  @override
  bool operator ==(Object other) =>
      other is SortOption &&
      other.field == field &&
      other.ascending == ascending;

  @override
  int get hashCode => Object.hash(field, ascending);
}
