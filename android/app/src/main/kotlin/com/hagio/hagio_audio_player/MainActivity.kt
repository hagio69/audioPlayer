package com.hagio.hagio_audio_player

import com.ryanheise.audioservice.AudioServiceActivity

// audio_service 는 FlutterActivity 대신 AudioServiceActivity 를 상속해야
// 백그라운드 재생 중에도 Flutter 엔진이 유지되고 알림창 컨트롤이 동작합니다.
class MainActivity : AudioServiceActivity()
