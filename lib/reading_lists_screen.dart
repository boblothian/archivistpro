import 'dart:io';
import 'dart:typed_data';

import 'package:archivecomics/pdf_viewer_screen.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:pdfx/pdfx.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ReadingListScreen extends StatefulWidget {
  const ReadingListScreen({super.key});

  @override
  State<ReadingListScreen> createState() => _ReadingListScreenState();
}

class _ReadingListScreenState extends State<ReadingListScreen> {
  final Map<String, Uint8List?> _thumbnails = {};
  late Directory _thumbDir;
  late Directory _appDir;
  bool _loading = true;
  List<String> _fileNames = [];

  @override
  void initState() {
    super.initState();
    _loadReadingList();
  }

  Future<void> _loadReadingList() async {
    final prefs = await SharedPreferences.getInstance();
    _fileNames = prefs.getStringList('reading_list') ?? [];
    _appDir = await getApplicationDocumentsDirectory();
    _thumbDir = Directory('${_appDir.path}/thumbs');

    for (final name in _fileNames) {
      final thumbFile = File('${_thumbDir.path}/$name.jpg');
      if (await thumbFile.exists()) {
        _thumbnails[name] = await thumbFile.readAsBytes();
      } else {
        final docFile = File('${_appDir.path}/$name');
        if (await docFile.exists()) {
          await _generateThumbnail(docFile, name);
        }
      }
    }

    if (mounted) setState(() => _loading = false);
  }

  Future<void> _generateThumbnail(File file, String filename) async {
    try {
      final doc = await PdfDocument.openData(await file.readAsBytes());
      final page = await doc.getPage(1);
      final image = await page.render(width: 300, height: 400);
      final rawBytes = image?.bytes;
      await page.close();
      await doc.close();

      if (rawBytes != null) {
        final decoded = img.decodeImage(rawBytes);
        if (decoded != null) {
          final resized = img.copyResize(decoded, width: 200);
          final jpeg = img.encodeJpg(resized);
          final thumbFile = File('${_thumbDir.path}/$filename.jpg');
          await thumbFile.writeAsBytes(jpeg);
          if (mounted)
            setState(() => _thumbnails[filename] = Uint8List.fromList(jpeg));
        }
      }
    } catch (e) {
      debugPrint('Failed to generate thumbnail for $filename: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('My Reading List')),
      body:
          _loading
              ? const Center(child: CircularProgressIndicator())
              : _fileNames.isEmpty
              ? const Center(child: Text('No items saved.'))
              : GridView.builder(
                padding: const EdgeInsets.all(8),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                  childAspectRatio: 0.7,
                ),
                itemCount: _fileNames.length,
                itemBuilder: (context, index) {
                  final fileName = _fileNames[index];
                  final thumbBytes = _thumbnails[fileName];

                  return InkWell(
                    onTap: () async {
                      final file = File('${_appDir.path}/$fileName');
                      if (await file.exists()) {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => PdfViewerScreen(file: file),
                          ),
                        );
                        setState(() {});
                      }
                    },
                    child: Column(
                      children: [
                        Expanded(
                          child:
                              thumbBytes != null
                                  ? Image.memory(thumbBytes, fit: BoxFit.cover)
                                  : const Center(child: Text('No preview')),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          fileName,
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12),
                        ),
                      ],
                    ),
                  );
                },
              ),
    );
  }
}
