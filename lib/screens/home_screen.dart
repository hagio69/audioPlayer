import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/library_provider.dart';
import '../providers/player_provider.dart';
import '../widgets/dialogs.dart';
import '../widgets/file_list_tab.dart';
import '../widgets/player_panel.dart';
import '../widgets/playlist_tab.dart';
import 'settings_sheet.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final List<StreamSubscription<String>> _subs = [];

  @override
  void initState() {
    super.initState();
    final player = context.read<PlayerProvider>();
    final library = context.read<LibraryProvider>();
    _subs
      ..add(player.messageStream.listen(_showMessage))
      ..add(library.messageStream.listen(_showMessage));

    // Android: 처음 한 번 배터리 최적화 제외 안내 (재생 도중 멈춤 방지)
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!Platform.isAndroid || library.storage.batteryPrompted) return;
      await Future<void>.delayed(const Duration(seconds: 1));
      if (!mounted) return;
      await library.storage.setBatteryPrompted();
      if (!mounted) return;
      await showBatteryOptimizationDialog(context);
    });
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 3),
      ));
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final initializing = context.select<LibraryProvider, bool>((l) => l.initializing);
    final theme = Theme.of(context);
    final count = LibraryProvider.playlistCount;

    return DefaultTabController(
      length: count + 1,
      child: Scaffold(
        appBar: AppBar(
          titleSpacing: 16,
          title: Row(
            children: [
              Icon(Icons.graphic_eq_rounded, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              const Flexible(
                child: Text(
                  'hagio Audio Player',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
                ),
              ),
            ],
          ),
          actions: [
            IconButton(
              tooltip: '앱 정보',
              icon: const Icon(Icons.info_outline_rounded),
              onPressed: () => showAppInfoDialog(context),
            ),
            IconButton(
              tooltip: '환경 설정',
              icon: const Icon(Icons.tune_rounded),
              onPressed: () => showSettingsSheet(context),
            ),
            const SizedBox(width: 4),
          ],
        ),
        body: initializing
            ? const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text('재생목록을 불러오는 중...'),
                  ],
                ),
              )
            : SafeArea(
                top: false,
                child: LayoutBuilder(
                  builder: (context, constraints) => Column(
                    children: [
                      // 메인 플레이어: 화면이 작으면 내부 스크롤 (오버플로우 방지)
                      ConstrainedBox(
                        constraints: BoxConstraints(
                          maxHeight: constraints.maxHeight * 0.6,
                        ),
                        child: const SingleChildScrollView(
                          child: PlayerPanel(),
                        ),
                      ),
                      TabBar(
                        tabs: [
                          for (var i = 0; i < count; i++) _PlaylistTabLabel(index: i),
                          const Tab(height: 42, text: '파일 목록'),
                        ],
                      ),
                      Expanded(
                        child: TabBarView(
                          children: [
                            for (var i = 0; i < count; i++) PlaylistTab(index: i),
                            const FileListTab(),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
      ),
    );
  }
}

/// 재생목록 탭 제목 (길게 누르면 이름 편집)
class _PlaylistTabLabel extends StatelessWidget {
  const _PlaylistTabLabel({required this.index});

  final int index;

  @override
  Widget build(BuildContext context) {
    final name = context.select<LibraryProvider, String>((l) => l.playlistName(index));
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onLongPress: () => showRenamePlaylistDialog(context, index),
      child: Tab(
        height: 42,
        child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
    );
  }
}
