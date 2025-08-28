import 'dart:convert';
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http; // ✅ added
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart'; // ✅ added
import 'package:shared_preferences/shared_preferences.dart';

// Viewers you already have
import 'pdf_viewer_screen.dart';

class ReadingListScreen extends StatefulWidget {
  const ReadingListScreen({super.key});

  @override
  State<ReadingListScreen> createState() => _ReadingListScreenState();
}

class _ReadingListScreenState extends State<ReadingListScreen> {
  static const _prefsKey = 'reading_list';

  final List<_Entry> _items = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  // ---------- load & persist ----------

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_prefsKey) ?? const <String>[];

    final parsed = <_Entry>[];
    for (final s in raw) {
      parsed.add(_Entry.parse(s));
    }

    // Backfill identifier + better thumb when possible
    bool changed = false;
    for (final e in parsed) {
      if ((e.identifier == null || e.identifier!.isEmpty)) {
        final id = _guessIdentifierFromFilename(e.path);
        if (id != null && id.isNotEmpty) {
          e.identifier = id;
          e.thumbUrl ??= _thumbPrimary(id);
          changed = true;
        }
      } else {
        e.thumbUrl ??= _thumbPrimary(e.identifier!);
      }
    }

    if (changed || raw.any((s) => !_Entry._looksJson(s))) {
      await _saveAll(parsed);
    }

    if (!mounted) return;
    setState(() {
      _items
        ..clear()
        ..addAll(parsed);
      _loading = false;
    });
  }

  Future<void> _saveAll(List<_Entry> list) async {
    final prefs = await SharedPreferences.getInstance();
    final updated = list.map((e) => e.toPrefsString()).toList();
    await prefs.setStringList(_prefsKey, updated);
  }

  Future<void> _saveSingle(_Entry e) async {
    final i = _items.indexWhere((x) => identical(x, e));
    if (i >= 0) {
      final clone = List<_Entry>.from(_items);
      clone[i] = e;
      await _saveAll(clone);
    } else {
      await _saveAll(_items);
    }
  }

  // ---------- covers ----------

  String _thumbPrimary(String id) =>
      'https://archive.org/download/$id/__ia_thumb.jpg';
  String _thumbFallback(String id) => 'https://archive.org/services/img/$id';

  String? _guessIdentifierFromFilename(String path) {
    final base = p.basenameWithoutExtension(path);
    if (base.isEmpty) return null;

    var id = base
        .replaceFirst(
          RegExp(r'_(text|bw|color|hq|lq|ocr)$', caseSensitive: false),
          '',
        )
        .replaceFirst(
          RegExp(r'-(text|bw|color|hq|lq|ocr)$', caseSensitive: false),
          '',
        );

    if (id.contains(' ')) id = id.replaceAll(' ', '_');
    return id.length < 3 ? null : id;
  }

  // ---------- UI ----------

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('My Reading List')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('My Reading List')),
      body:
          _items.isEmpty
              ? const Center(child: Text('No saved items yet.'))
              : GridView.builder(
                padding: const EdgeInsets.all(12),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: .72,
                ),
                itemCount: _items.length,
                itemBuilder: (context, i) {
                  final e = _items[i];
                  return Card(
                    clipBehavior: Clip.antiAlias,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: InkWell(
                      onTap: () => _openEntry(e),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(child: _buildThumb(e)),
                          Padding(
                            padding: const EdgeInsets.all(8.0),
                            child: Text(
                              e.title ?? p.basename(e.path),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
    );
  }

  Widget _buildThumb(_Entry e) {
    if ((e.identifier ?? '').isNotEmpty) {
      final id = e.identifier!;
      final primary =
          (e.thumbUrl?.isNotEmpty ?? false) ? e.thumbUrl! : _thumbPrimary(id);
      return CachedNetworkImage(
        imageUrl: primary,
        fit: BoxFit.cover,
        placeholder:
            (_, __) => const Center(child: CircularProgressIndicator()),
        errorWidget:
            (_, __, ___) => CachedNetworkImage(
              imageUrl: _thumbFallback(id),
              fit: BoxFit.cover,
              errorWidget: (_, __, ___) => _fileTypePlaceholder(e.path),
            ),
      );
    }
    return _fileTypePlaceholder(e.path);
  }

  Widget _fileTypePlaceholder(String path) {
    final ext = p.extension(path).toLowerCase();
    IconData icon = Icons.insert_drive_file_outlined;
    if (ext == '.pdf') {
      icon = Icons.picture_as_pdf_outlined;
    } else if (ext == '.epub') {
      icon = Icons.menu_book_outlined;
    } else if (ext == '.cbz' ||
        ext == '.cbr' ||
        ext == '.zip' ||
        ext == '.rar') {
      icon = Icons.auto_stories_outlined;
    } else if (ext == '.txt') {
      icon = Icons.description_outlined;
    } else if (ext == '.jpg' ||
        ext == '.jpeg' ||
        ext == '.png' ||
        ext == '.webp') {
      icon = Icons.image_outlined;
    }
    return Container(
      color: Theme.of(
        context,
      ).colorScheme.surfaceContainerHighest.withOpacity(.5),
      child: Center(child: Icon(icon, size: 56)),
    );
  }

  // ---------- open / repair (re-download) ----------

  Future<void> _openEntry(_Entry e) async {
    final title = e.title ?? p.basename(e.path);
    File? file;

    // 1) Open local if present
    if (e.path.isNotEmpty && !e.path.startsWith('content://')) {
      final local = File(e.path);
      if (await local.exists()) {
        file = local;
      }
    }

    // 2) If missing, try to (re)download to a known, persistent location
    if (file == null && (e.identifier ?? '').isNotEmpty) {
      final repaired = await _redownloadBestForIdentifier(e.identifier!);
      if (repaired != null) {
        e.path = repaired.path;
        await _saveSingle(e); // persist new path
        file = repaired;
      }
    }

    if (file == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('File not found: ${p.basename(e.path)}')),
      );
      return;
    }

    final ext = p.extension(file.path).toLowerCase();
    if (ext == '.pdf') {
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => PdfViewerScreen(file: file!)),
      );
      return;
    }
    if (ext == '.txt') {
      final text = await file.readAsString();
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => _LocalTextViewer(text: text, title: title),
        ),
      );
      return;
    }
    if (ext == '.jpg' || ext == '.jpeg' || ext == '.png' || ext == '.webp') {
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder:
              (_) => _LocalImageViewer(imagePath: file!.path, title: title),
        ),
      );
      return;
    }

    // Other formats: you can add handlers for CBZ/EPUB here if your app supports them locally.
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Unsupported file type: $ext')));
  }

  /// Download the best available file for an IA identifier to app documents dir.
  /// Prefers: PDF > CBZ > EPUB > TXT. Returns the downloaded File or null.
  Future<File?> _redownloadBestForIdentifier(String identifier) async {
    try {
      final metaUrl = 'https://archive.org/metadata/$identifier';
      final resp = await http.get(Uri.parse(metaUrl));
      if (resp.statusCode != 200) return null;

      final json = jsonDecode(resp.body) as Map<String, dynamic>;
      final files = (json['files'] as List).cast<Map<String, dynamic>>();

      String? pick(List<String> exts) {
        final f = files.firstWhere(
          (m) => exts.any(
            (e) => (m['name']?.toString().toLowerCase() ?? '').endsWith(e),
          ),
          orElse: () => {},
        );
        return (f.isEmpty) ? null : f['name']?.toString();
      }

      String? chosen =
          pick(['.pdf']) ?? pick(['.cbz']) ?? pick(['.epub']) ?? pick(['.txt']);

      if (chosen == null) {
        // If the item only has loose images, you could add logic to download them into a folder.
        return null;
      }

      final downloadUrl = 'https://archive.org/download/$identifier/$chosen';
      final ext = p.extension(chosen);
      final dir = await getApplicationDocumentsDirectory();
      final downloadsDir = Directory(p.join(dir.path, 'downloads'));
      if (!await downloadsDir.exists()) {
        await downloadsDir.create(recursive: true);
      }

      // Use a stable filename so we can relocate/repair consistently
      final savePath = p.join(downloadsDir.path, '$identifier$ext');
      final out = File(savePath);
      if (await out.exists()) {
        return out;
      }

      final r = await http.get(Uri.parse(downloadUrl));
      if (r.statusCode != 200) return null;
      await out.writeAsBytes(r.bodyBytes, flush: true);
      return out;
    } catch (_) {
      return null;
    }
  }
}

// ---------- Minimal local viewers for TXT/Images ----------

class _LocalTextViewer extends StatelessWidget {
  const _LocalTextViewer({required this.text, required this.title});
  final String text;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: SelectionArea(
        child: Padding(padding: const EdgeInsets.all(16.0), child: Text(text)),
      ),
    );
  }
}

class _LocalImageViewer extends StatelessWidget {
  const _LocalImageViewer({required this.imagePath, required this.title});
  final String imagePath;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(child: Image.file(File(imagePath), fit: BoxFit.contain)),
    );
  }
}

// ---------- Model ----------

class _Entry {
  _Entry({required this.path, this.identifier, this.title, this.thumbUrl});

  String path; // local file path (may be empty)
  String? identifier; // IA identifier (important for repair)
  String? title;
  String? thumbUrl;

  static bool _looksJson(String s) {
    final t = s.trimLeft();
    return t.startsWith('{') && t.endsWith('}');
  }

  static _Entry parse(String s) {
    if (_looksJson(s)) {
      try {
        final m = jsonDecode(s) as Map<String, dynamic>;
        return _Entry(
          path: (m['path'] ?? '') as String,
          identifier: (m['identifier'] as String?)?.trim(),
          title: (m['title'] as String?)?.trim(),
          thumbUrl: (m['thumbUrl'] as String?)?.trim(),
        );
      } catch (_) {
        /* fallthrough */
      }
    }
    // legacy: just the path string
    return _Entry(path: s);
  }

  String toPrefsString() {
    return jsonEncode({
      'path': path,
      if (identifier != null && identifier!.isNotEmpty)
        'identifier': identifier,
      if (title != null && title!.isNotEmpty) 'title': title,
      if (thumbUrl != null && thumbUrl!.isNotEmpty) 'thumbUrl': thumbUrl,
    });
  }
}
