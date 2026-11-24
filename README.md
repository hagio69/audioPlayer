# hagioAudioPlayer

Flutter로 만든 iOS/Android 로컬 오디오 플레이어입니다. (상태 관리: Provider)

## 1. 프로젝트 생성 및 파일 덮어쓰기

Dart 패키지 이름은 소문자+밑줄만 허용되므로 패키지명은 `hagio_audio_player`, 폴더/표시 이름은 `hagioAudioPlayer`로 합니다.

```bash
flutter create --org com.hagio --project-name hagio_audio_player --platforms android,ios hagioAudioPlayer
cd hagioAudioPlayer
# 이 압축 파일의 내용을 프로젝트 폴더에 덮어쓰기 (pubspec.yaml, analysis_options.yaml, lib/, android/...)
rm -f test/widget_test.dart          # 기본 카운터 테스트는 이 앱과 맞지 않으므로 삭제
flutter pub get
```

> 버전 충돌로 `pub get`이 실패하면 `flutter pub upgrade --major-versions` 를 실행하세요.

## 2. 폴더 구조

```
hagioAudioPlayer/
├─ pubspec.yaml
├─ analysis_options.yaml
├─ lib/
│  ├─ main.dart                     # AudioService/AudioSession 초기화, Provider 주입
│  ├─ app.dart                      # MaterialApp + 다크 테마
│  ├─ models/
│  │  ├─ track.dart                 # 곡 모델 (경로/제목/아티스트/앨범/길이)
│  │  └─ player_settings.dart       # 반복 모드 enum, 배속·타이머 옵션
│  ├─ services/
│  │  ├─ audio_handler.dart         # just_audio + audio_service (큐/반복/셔플/종료 처리)
│  │  ├─ storage_service.dart       # shared_preferences 저장/복원
│  │  ├─ file_scan_service.dart     # 폴더 스캔, 파일 가져오기
│  │  ├─ metadata_service.dart      # 태그 파싱 (Isolate)
│  │  └─ permission_service.dart    # Android 권한 (API 33 분기)
│  ├─ providers/
│  │  ├─ library_provider.dart      # 재생목록/파일목록/선택/정렬/재생 횟수
│  │  └─ player_provider.dart       # 재생 제어/설정/취침 타이머/선택 큐 동기화
│  ├─ utils/
│  │  ├─ sort_option.dart           # 파일 이름·앨범·아티스트, 오름/내림
│  │  └─ formatters.dart
│  ├─ screens/
│  │  ├─ home_screen.dart           # 앱바 + 플레이어 + 탭
│  │  └─ settings_sheet.dart        # 환경 설정 모달
│  └─ widgets/
│     ├─ player_panel.dart
│     ├─ now_playing_info.dart
│     ├─ seek_bar.dart
│     ├─ player_controls.dart       # 재생 제어 / 배속 / 타이머 / 반복 / 셔플 / 음량
│     ├─ playlist_tab.dart
│     ├─ file_list_tab.dart
│     ├─ track_tile.dart
│     ├─ sort_menu_button.dart
│     ├─ empty_state.dart
│     └─ dialogs.dart               # 권한 거부 안내, 확인, 앱 정보
├─ android/app/src/main/
│  ├─ AndroidManifest.xml           # (전체 교체)
│  └─ kotlin/com/hagio/hagio_audio_player/MainActivity.kt   # (전체 교체)
└─ ios/
   ├─ Runner/Info.plist.additions.xml   # Info.plist 에 추가할 키
   └─ Podfile.snippet.rb                # Podfile 수정 내용
```

## 3. Android 설정

1. `android/app/src/main/AndroidManifest.xml` 을 제공된 파일로 교체
   - `WAKE_LOCK`, `FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_MEDIA_PLAYBACK`, `POST_NOTIFICATIONS`
   - `READ_MEDIA_AUDIO`(13+), `READ_EXTERNAL_STORAGE`(12 이하, maxSdkVersion=32)
   - `AudioService` 서비스(`foregroundServiceType="mediaPlayback"`), `MediaButtonReceiver`
2. `MainActivity.kt` 를 `AudioServiceActivity` 상속으로 교체
   (`--org`를 다르게 줬다면 첫 줄 package 와 폴더 경로를 맞춰주세요)
3. `android/app/build.gradle.kts` 의 `compileSdk`가 35 이상인지 확인 (permission_handler 12 요구). 최신 Flutter 기본값이면 그대로 두면 됩니다.

## 4. iOS 설정

1. `ios/Runner/Info.plist` 의 `<dict>` 안에 `Info.plist.additions.xml` 의 키 추가
   - `UIBackgroundModes` → `audio` (백그라운드 재생, 잠금화면 컨트롤)
   - `UIFileSharingEnabled`, `LSSupportsOpeningDocumentsInPlace` (파일 앱에 앱 폴더 노출)
2. `ios/Podfile` 을 `Podfile.snippet.rb` 처럼 수정 (platform 13.0, permission_handler 매크로)
3. `cd ios && pod install`
4. Xcode > Runner > Signing & Capabilities 에서 **Background Modes → Audio, AirPlay, and Picture in Picture** 가 체크됐는지 확인

### iOS 파일 접근 방식

iOS는 다른 앱 폴더를 자유롭게 읽을 수 없습니다. 그래서 두 가지 방법을 제공합니다.

- **앱 폴더 (권장)**: 파일 앱 > 나의 iPhone > hagioAudioPlayer 폴더에 음악을 복사 → 앱의 "앱 폴더 보기". 앱을 다시 켜도 그대로 유지됩니다.
- **폴더 선택**: 파일 앱의 폴더를 선택해 스캔합니다. 다만 iOS 보안 정책상 앱을 다시 시작하면 접근이 끊길 수 있습니다.
- **파일 직접 선택**(재생목록 탭 ➕): 고른 파일은 앱 폴더의 `Imported`로 복사되어 영구 보관됩니다.

## 5. 동작 메모

- **재생목록 2개**: 탭에 재생목록1 · 재생목록2 · 파일 목록이 있습니다. 탭을 길게 누르거나 ✏️ 버튼으로 이름을 바꿀 수 있습니다. 파일 목록에서 선택한 곡은 "재생목록에 추가"를 눌러 원하는 목록에 넣습니다.
- **이어 듣기**: 곡·위치·출처(어느 재생목록인지)를 3초마다, 일시정지·곡 변경·앱 전환 시 즉시 저장합니다. 앱을 다시 열면 그 곡의 그 위치에서 일시정지 상태로 준비되고 ▶ 를 누르면 이어서 재생됩니다.
- **블루투스 차량**: 재생 시작 시 오디오 포커스를 명시적으로 요청하고 미디어 세션 상태·곡 정보를 다시 보내 차량이 소스를 휴대폰으로 전환하도록 합니다.
- **배터리 최적화 제외**(Android): 화면을 끈 채 오래 재생하면 기기가 앱을 종료하는 것을 막습니다. 처음 실행 시 한 번 안내하며, 설정에서 다시 할 수 있습니다.

- 재생목록에서 체크박스로 여러 곡을 선택하면 **선택한 곡만으로 큐**가 구성되고, 셔플/반복도 그 안에서만 적용됩니다. 선택을 모두 해제하면 재생 중인 곡을 유지한 채 전체 목록 큐로 돌아갑니다.
- **반복 끄기**: 곡이 끝나면 다음 곡으로 인덱스를 옮긴 뒤 일시정지 상태로 기다립니다. 마지막 곡이면 첫 곡으로 이동합니다.
- **재생 횟수**: 곡이 끝까지 재생됐을 때만 1회 올라갑니다(한 곡 반복도 매번 집계). 곡을 길게 누르거나 ⋮ 메뉴, 설정에서 초기화할 수 있습니다.
- **이전 곡**: 3초 넘게 재생된 상태면 현재 곡을 처음부터, 아니면 이전 곡으로 이동합니다.
- **배속 버튼**: 탭하면 0.8x→1.0x→1.25x→1.5x→2.0x 순환, 길게 누르면 목록에서 선택.
- **소리 버튼**: 탭하면 음량 슬라이더, 길게 누르면 음소거.
- **재생 슬라이더**: 드래그하는 동안 처음 위치까지 다른 색으로 표시되고, 가운데에 "처음 1:23 → 2:45 (+1:22)"가 나타납니다.
- 손상되었거나 지원하지 않는 파일은 오류 안내 후 자동으로 다음 곡으로 넘어갑니다.
- 저장 항목: 재생목록(경로+메타데이터), 반복/셔플/배속/음량, 재생 횟수, 정렬, 마지막 폴더, 마지막 곡과 재생 위치.
