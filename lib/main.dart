import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'home_page_screen.dart'; // <-- new import for home screen

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final tempDir = await getTemporaryDirectory();
  if (tempDir.existsSync()) {
    for (var file in tempDir.listSync()) {
      final ext = file.path.toLowerCase();
      if (ext.endsWith('.pdf') || ext.endsWith('.epub')) {
        file.deleteSync();
      }
    }
  }

  runApp(ArchiveReaderApp());
}

class ArchiveReaderApp extends StatelessWidget {
  const ArchiveReaderApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Archive Reader',
      theme: ThemeData(primarySwatch: Colors.indigo),
      home: HomePageScreen(), // <-- use new home screen here
    );
  }
}
