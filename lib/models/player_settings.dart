/// 반복 모드
enum RepeatModeSetting {
  off,
  all,
  one;

  String get label => switch (this) {
        RepeatModeSetting.off => '반복 끄기',
        RepeatModeSetting.all => '전체 반복',
        RepeatModeSetting.one => '한 곡 반복',
      };

  String get shortLabel => switch (this) {
        RepeatModeSetting.off => '끄기',
        RepeatModeSetting.all => '전체',
        RepeatModeSetting.one => '한 곡',
      };

  String get description => switch (this) {
        RepeatModeSetting.off => '곡이 끝나면 다음 곡으로 이동한 뒤 일시정지 상태로 대기합니다.',
        RepeatModeSetting.all => '목록(큐) 전체를 계속 반복 재생합니다.',
        RepeatModeSetting.one => '현재 곡을 계속 반복 재생합니다.',
      };

  RepeatModeSetting get next => switch (this) {
        RepeatModeSetting.off => RepeatModeSetting.all,
        RepeatModeSetting.all => RepeatModeSetting.one,
        RepeatModeSetting.one => RepeatModeSetting.off,
      };

  static RepeatModeSetting fromName(String? name) => RepeatModeSetting.values
      .firstWhere((e) => e.name == name, orElse: () => RepeatModeSetting.off);
}

/// 선택 가능한 재생 속도
const List<double> kSpeedOptions = [0.8, 1.0, 1.25, 1.5, 2.0];

/// 취침 타이머(분)
const List<int> kSleepTimerMinutes = [15, 30, 60];
