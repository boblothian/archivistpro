import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_pdfview/flutter_pdfview.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PdfViewerScreen extends StatefulWidget {
  final File? file; // pass this if you already downloaded
  final String? url; // OR pass a URL to let the viewer download
  final String? filenameHint; // used for cache filename when url is provided

  const PdfViewerScreen({super.key, this.file, this.url, this.filenameHint})
    : assert((file != null) ^ (url != null), 'Provide file OR url');

  @override
  State<PdfViewerScreen> createState() => _PdfViewerScreenState();
}

class _PdfViewerScreenState extends State<PdfViewerScreen> {
  PDFViewController? _pdf;
  int _pages = 0;
  int _page = 0;
  int? _initialPage;
  late String _prefsKey;

  bool _readyToLoad = false; // mount PDFView only when file ready
  bool _isPageVisible = false;
  bool _downloading = false;
  double _progress = 0;

  File? _localFile;

  @override
  void initState() {
    super.initState();
    _prefsKey = 'last_page_${(widget.file?.path ?? widget.url!).hashCode}';
    _init();
  }

  Future<void> _init() async {
    await _checkAndPromptResume();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    if (widget.file != null) {
      _localFile = widget.file;
    } else {
      _downloading = true;
      setState(() {});
      _localFile = await _downloadToCache(widget.url!, widget.filenameHint);
      _downloading = false;
    }

    setState(() => _readyToLoad = true);
  }

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  Future<void> _checkAndPromptResume() async {
    final prefs = await SharedPreferences.getInstance();
    final lastPage = prefs.getInt(_prefsKey) ?? 0;
    if (lastPage > 0) {
      final shouldResume = await showDialog<bool>(
        context: context,
        builder:
            (context) => AlertDialog(
              title: const Text('Resume Reading'),
              content: Text('Resume from page ${lastPage + 1}?'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('No'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Yes'),
                ),
              ],
            ),
      );
      if (shouldResume == true) _initialPage = lastPage;
    }
  }

  Future<void> _saveLastPage(int page) async {
    final prefs = await SharedPreferences.getInstance();
    prefs.setInt(_prefsKey, page);
  }

  // ---------- Fast, cached, streamed download ----------
  Future<File> _downloadToCache(String url, String? filenameHint) async {
    final dir = await getApplicationDocumentsDirectory();
    final cacheDir = Directory(p.join(dir.path, 'ia_cache'));
    await cacheDir.create(recursive: true);

    final name = filenameHint ?? Uri.parse(url).pathSegments.last;
    final file = File(p.join(cacheDir.path, name));

    // Reuse if size matches
    try {
      final head = await http
          .head(Uri.parse(url))
          .timeout(const Duration(seconds: 20));
      final remoteLen = int.tryParse(head.headers['content-length'] ?? '') ?? 0;
      if (await file.exists() &&
          remoteLen > 0 &&
          (await file.length()) == remoteLen) {
        return file;
      }
    } catch (_) {
      // HEAD may fail; fall back to GET
    }

    final client = http.Client();
    final req = http.Request('GET', Uri.parse(url));
    req.headers['Accept-Encoding'] = 'gzip';
    final res = await client.send(req).timeout(const Duration(minutes: 2));
    if (res.statusCode != 200) {
      client.close();
      throw HttpException('HTTP ${res.statusCode}');
    }

    final total = res.contentLength ?? 0;
    int received = 0;

    final tmp = File('${file.path}.part');
    final sink = tmp.openWrite();

    await for (final chunk in res.stream) {
      received += chunk.length;
      sink.add(chunk);
      if (total > 0) {
        _progress = received / total;
        if (mounted) setState(() {});
      }
    }
    await sink.close();
    await tmp.rename(file.path);
    client.close();
    return file;
  }
  // -----------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          if (_readyToLoad && _localFile != null)
            AnimatedOpacity(
              opacity: _isPageVisible ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 250),
              child: PDFView(
                filePath: _localFile!.path,
                // Keep rendering work minimal for speed:
                swipeHorizontal: true,
                autoSpacing: false,
                pageFling: true,
                fitEachPage: false, // less relayout work
                fitPolicy:
                    FitPolicy.WIDTH, // render to width; faster feels snappier
                defaultPage: _initialPage ?? 0,
                onRender: (pages) async {
                  setState(() {
                    _pages = pages ?? 0;
                    _isPageVisible = true;
                  });
                  if (_initialPage != null && _pdf != null) {
                    await _pdf!.setPage(_initialPage!);
                  }
                },
                onViewCreated: (c) async {
                  _pdf = c;
                  final p = await c.getCurrentPage();
                  setState(() => _page = p ?? 0);
                },
                onPageChanged: (page, total) {
                  setState(() {
                    _page = page ?? 0;
                    _pages = total ?? 0;
                  });
                  _saveLastPage(_page);
                },
              ),
            ),

          // Top back button
          Positioned(
            top: 32,
            left: 8,
            child: SafeArea(
              child: IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.white),
                onPressed: () => Navigator.pop(context),
              ),
            ),
          ),

          // Page indicator
          if (_readyToLoad && _isPageVisible)
            Positioned(
              bottom: 16,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    'Page ${_page + 1} / $_pages',
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                  ),
                ),
              ),
            ),

          // Download overlay
          if (_downloading || (!_readyToLoad && widget.url != null))
            Container(
              color: Colors.black,
              padding: const EdgeInsets.symmetric(horizontal: 32),
              alignment: Alignment.center,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  LinearProgressIndicator(
                    value:
                        _progress > 0
                            ? _progress
                            : null, // null = indeterminate
                    backgroundColor: Colors.grey[800],
                    color: Colors.blueAccent, // change bar color here
                    minHeight: 6,
                  ),
                  const SizedBox(height: 12),
                  if (_progress > 0)
                    Text(
                      '${(_progress * 100).toStringAsFixed(0)}%',
                      style: const TextStyle(color: Colors.white),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
