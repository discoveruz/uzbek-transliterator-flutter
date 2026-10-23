import 'package:flutter/material.dart';
import 'package:yangi_alifbo/convert_page.dart';
import 'package:yangi_alifbo/engine.dart';
import 'package:yangi_alifbo/settings.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await RustLib.init();
  // Read before the first frame, so a dark choice does not flash light.
  final themeMode = ValueNotifier(await const Settings().themeMode());
  runApp(YangiAlifboApp(themeMode: themeMode));
}

/// The app, light, dark or in the system's mode, as chosen in Settings.
class YangiAlifboApp extends StatelessWidget {
  const YangiAlifboApp({super.key, required this.themeMode});

  final ValueNotifier<ThemeMode> themeMode;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: themeMode,
      builder: (context, mode, _) => MaterialApp(
        title: 'Yangi alifbo',
        debugShowCheckedModeBanner: false,
        theme: _theme(Brightness.light),
        darkTheme: _theme(Brightness.dark),
        themeMode: mode,
        home: ConvertPage(themeMode: themeMode),
      ),
    );
  }
}

ThemeData _theme(Brightness brightness) {
  final colors = ColorScheme.fromSeed(seedColor: const Color(0xFF0F766E), brightness: brightness);
  final rounded = RoundedRectangleBorder(borderRadius: BorderRadius.circular(16));
  return ThemeData(
    colorScheme: colors,
    scaffoldBackgroundColor: colors.surface,
    appBarTheme: AppBarTheme(backgroundColor: colors.surface, scrolledUnderElevation: 0, centerTitle: false),
    cardTheme: CardThemeData(elevation: 0, margin: EdgeInsets.zero, color: colors.surfaceContainerLow, shape: rounded),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    bottomSheetTheme: const BottomSheetThemeData(showDragHandle: true),
  );
}
