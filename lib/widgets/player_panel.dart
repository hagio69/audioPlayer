import 'package:flutter/material.dart';

import 'now_playing_info.dart';
import 'player_controls.dart';
import 'seek_bar.dart';

/// 메인 플레이어 영역
///  ① 곡 정보
///  ② 1행: 이전 곡 / 30초 뒤로 / 10초 뒤로 / 재생 / 10초 앞으로 / 30초 앞으로 / 다음 곡
///  ③ 2행: 재생속도 / 타이머 / 반복 / 셔플 / 소리
///  ④ 재생 위치 슬라이더 + 시간 (드래그 시 처음 위치 표시)
class PlayerPanel extends StatelessWidget {
  const PlayerPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 6),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: const Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 4),
            child: NowPlayingInfo(),
          ),
          SizedBox(height: 8),
          TransportControls(),
          SizedBox(height: 6),
          SecondaryControls(),
          SizedBox(height: 8),
          SeekBar(),
        ],
      ),
    );
  }
}
