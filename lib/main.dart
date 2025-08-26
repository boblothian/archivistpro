import 'package:flutter/material.dart';

import 'home_page_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ArchiveReaderApp());
}

class ArchiveReaderApp extends StatelessWidget {
  const ArchiveReaderApp({super.key});

  @override
  Widget build(BuildContext context) {
    const seed = Colors.indigo;

    return MaterialApp(
      title: 'Archivist',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.system,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: seed,
        brightness: Brightness.light,
        visualDensity: VisualDensity.adaptivePlatformDensity,
        cardTheme: const CardThemeData(
          elevation: 2,
          margin: EdgeInsets.all(8),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(18)),
          ),
        ),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: seed,
        brightness: Brightness.dark,
        visualDensity: VisualDensity.adaptivePlatformDensity,
        cardTheme: const CardThemeData(
          elevation: 2,
          margin: EdgeInsets.all(8),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(18)),
          ),
        ),
      ),
      home: const HomePageScreen(),
    );
  }
}
