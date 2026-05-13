import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'services/settings_service.dart';
import 'views/file_tree_screen.dart';
import 'views/score_screen.dart';
import 'views/practice_screen.dart';
import 'views/history_screen.dart';
import 'views/export_config_screen.dart';


void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();
  await SettingsService.init();
  runApp(const ProviderScope(child: Guitar2App()));
}

class Guitar2App extends StatelessWidget {
  const Guitar2App({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Guitar2',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.black,
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        appBarTheme: AppBarTheme(
          centerTitle: true,
          elevation: 0,
          scrolledUnderElevation: 0,
          backgroundColor: Colors.transparent,
          foregroundColor: Colors.black,
          surfaceTintColor: Colors.transparent,
          shape: const Border(
            bottom: BorderSide(
              color: Color(0xFF5D4037),
              width: 2,
            ),
          ),
        ),
        cardTheme: CardThemeData(
          elevation: 0,
          shape: RoundedRectangleBorder(
            side: BorderSide(color: Colors.black, width: 1.5),
            borderRadius: BorderRadius.circular(8),
          ),
          clipBehavior: Clip.antiAlias,
        ),
      ),
      initialRoute: '/',
      onGenerateRoute: (settings) {
        switch (settings.name) {
          case '/':
            return MaterialPageRoute(
              builder: (_) => const FileTreeScreen(),
              settings: settings,
            );
          case '/score':
            return MaterialPageRoute(
              builder: (_) => const ScoreScreen(),
              settings: settings,
            );
          case '/practice':
            return MaterialPageRoute(
              builder: (_) => const PracticeScreen(),
              settings: settings,
            );
          case '/history':
            return MaterialPageRoute(
              builder: (_) => const HistoryScreen(),
              settings: settings,
            );
          case '/export':
            return MaterialPageRoute(
              builder: (_) => const ExportConfigScreen(),
              settings: settings,
            );
          default:
            return MaterialPageRoute(
              builder: (_) => const FileTreeScreen(),
            );
        }
      },
    );
  }
}
