import 'package:flutter/material.dart';

import 'screens/home_screen.dart';

class HagioApp extends StatelessWidget {
  const HagioApp({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = buildDarkTheme();
    return MaterialApp(
      title: 'hagioAudioPlayer',
      debugShowCheckedModeBanner: false,
      theme: theme,
      darkTheme: theme,
      themeMode: ThemeMode.dark,
      home: const HomeScreen(),
    );
  }
}

/// 다크 테마 기반의 미니멀 테마
ThemeData buildDarkTheme() {
  const background = Color(0xFF0D0F12);
  const surface = Color(0xFF15181D);

  final scheme = ColorScheme.fromSeed(
    seedColor: const Color(0xFF6C8CFF),
    brightness: Brightness.dark,
  ).copyWith(
    surface: surface,
    surfaceContainerHighest: const Color(0xFF1E2229),
  );

  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: scheme,
    scaffoldBackgroundColor: background,
    appBarTheme: const AppBarTheme(
      backgroundColor: background,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      centerTitle: false,
    ),
    dividerTheme: const DividerThemeData(color: Color(0x14FFFFFF), space: 1),
    sliderTheme: const SliderThemeData(
      trackHeight: 3,
      thumbShape: RoundSliderThumbShape(enabledThumbRadius: 7),
      overlayShape: RoundSliderOverlayShape(overlayRadius: 16),
    ),
    listTileTheme: const ListTileThemeData(
      dense: true,
      contentPadding: EdgeInsets.only(left: 4, right: 12),
    ),
    tabBarTheme: TabBarThemeData(
      indicatorSize: TabBarIndicatorSize.tab,
      dividerColor: Colors.white.withValues(alpha: 0.06),
      labelStyle: const TextStyle(fontWeight: FontWeight.w600),
    ),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: surface,
      showDragHandle: true,
    ),
  );
}
