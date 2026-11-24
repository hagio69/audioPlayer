import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app.dart';
import 'providers/library_provider.dart';
import 'providers/player_provider.dart';
import 'services/audio_handler.dart';
import 'services/storage_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 음악 재생용 오디오 세션 (전화/다른 앱 재생 시 자동 일시정지 등)
  final session = await AudioSession.instance;
  await session.configure(const AudioSessionConfiguration.music());

  // 백그라운드 재생 + 잠금화면/알림창 미디어 컨트롤
  final handler = await AudioService.init<HagioAudioHandler>(
    builder: HagioAudioHandler.new,
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'com.hagio.hagio_audio_player.channel.audio',
      androidNotificationChannelName: 'hagio 오디오 재생',
      androidNotificationOngoing: true,
      androidStopForegroundOnPause: true,
      // 상태 표시줄 아이콘 (android/app/src/main/res/drawable/ic_stat_music.xml)
      androidNotificationIcon: 'drawable/ic_stat_music',
      fastForwardInterval: Duration(seconds: 10),
      rewindInterval: Duration(seconds: 10),
    ),
  );

  final storage = await StorageService.create();
  final library = LibraryProvider(storage: storage);
  final player = PlayerProvider(handler: handler, library: library, storage: storage);

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<LibraryProvider>.value(value: library),
        ChangeNotifierProvider<PlayerProvider>.value(value: player),
      ],
      child: const HagioApp(),
    ),
  );

  // 화면을 먼저 띄운 뒤 저장된 상태 복원 (로딩 인디케이터 표시)
  unawaited(_bootstrap(library, player));
}

Future<void> _bootstrap(LibraryProvider library, PlayerProvider player) async {
  await library.init();
  await player.init();
}
