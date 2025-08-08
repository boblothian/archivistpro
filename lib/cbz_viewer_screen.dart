import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

class CbzViewerScreen extends StatefulWidget {
  final File cbzFile;
  final String title;

  const CbzViewerScreen({
    super.key,
    required this.cbzFile,
    required this.title,
  });

  @override
  State<CbzViewerScreen> createState() => _CbzViewerScreenState();
}

class _CbzViewerScreenState extends State<CbzViewerScreen> {
  List<File> _images = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _extractImages();
  }

  Future<void> _extractImages() async {
    try {
      final bytes = await widget.cbzFile.readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);
      final tempDir = await getTemporaryDirectory();

      List<File> images = [];
      for (final file in archive) {
        if (!file.isFile) continue;
        final ext = file.name.toLowerCase();
        if (ext.endsWith('.jpg') ||
            ext.endsWith('.jpeg') ||
            ext.endsWith('.png')) {
          final outFile = File('${tempDir.path}/${file.name}');
          await outFile.writeAsBytes(file.content as List<int>);
          images.add(outFile);
        }
      }

      images.sort((a, b) => a.path.compareTo(b.path));

      if (mounted) {
        setState(() {
          _images = images;
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('Error extracting CBZ: $e');
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body:
          _loading
              ? const Center(child: CircularProgressIndicator())
              : PageView.builder(
                itemCount: _images.length,
                itemBuilder: (context, index) {
                  return Image.file(_images[index], fit: BoxFit.contain);
                },
              ),
    );
  }
}
