import 'dart:convert';
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

// ⬇️ Use your existing viewers; adjust import names if your paths differ.
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

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_prefsKey) ?? const <String>[];

    final parsed = <_Entry>[];
    for (final s in raw) {
      parsed.add(_Entry.parse(s));
    }

    // Backfill identifier + preferred thumb (real cover) when possible
    bool changed = false;
    for (final e in parsed) {
      if ((e.identifier == null || e.identifier!.isEmpty)) {
        final id = _guessIdentifierFromFilename(e.path);
        if (id != null && id.isNotEmpty) {
          e.identifier = id;
          e.thumbUrl ??= _thumbPrimary(id); // prefer __ia_thumb.jpg
          changed = true;
        }
      } else {
        e.thumbUrl ??= _thumbPrimary(e.identifier!); // prefer __ia_thumb.jpg
      }
    }

    if (changed || raw.any((s) => !_Entry._looksJson(s))) {
      final updated = parsed.map((e) => e.toPrefsString()).toList();
      await prefs.setStringList(_prefsKey, updated);
    }

    if (!mounted) return;
    setState(() {
      _items
        ..clear()
        ..addAll(parsed);
      _loading = false;
    });
  }

  // ✅ Prefer real cover first, then generic services/img
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
    // If we have an identifier, try real cover first, then services/img; else file-type placeholder.
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
    if (ext == '.pdf')
      icon = Icons.picture_as_pdf_outlined;
    else if (ext == '.epub')
      icon = Icons.menu_book_outlined;
    else if (ext == '.cbz' || ext == '.cbr' || ext == '.zip' || ext == '.rar') {
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
      color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(.5),
      child: Center(child: Icon(icon, size: 56)),
    );
  }

  Future<void> _openEntry(_Entry e) async {
    final file = File(e.path);
    if (!await file.exists()) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('File not found: ${p.basename(e.path)}')),
      );
      return;
    }

    final ext = p.extension(e.path).toLowerCase();
    final title = e.title ?? p.basename(e.path);

    if (ext == '.pdf') {
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => PdfViewerScreen(file: file)),
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
          builder: (_) => _LocalImageViewer(imagePath: e.path, title: title),
        ),
      );
      return;
    }

    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Unsupported file type: $ext')));
  }
}

/// Local minimal viewers so TXT/images open even without remote URLs.

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

/// Persisted reading list entry (supports legacy string & new JSON).
class _Entry {
  _Entry({required this.path, this.identifier, this.title, this.thumbUrl});

  String path; // local file path
  String? identifier;
  String? title;
  String? thumbUrl; // cached cover URL (prefer __ia_thumb.jpg)

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
        /* fall through */
      }
    }
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
