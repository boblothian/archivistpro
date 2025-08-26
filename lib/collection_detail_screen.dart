import 'dart:async';
import 'dart:convert';
import 'dart:io';

// ✅ add these for external/system playback
import 'package:android_intent_plus/android_intent.dart';
import 'package:android_intent_plus/flag.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'archive_item_screen.dart';
import 'image_viewer_screen.dart';
import 'pdf_viewer_screen.dart';
// ✅ single sources
import 'services/filters.dart'; // ArchiveFilters
import 'services/sfw_filter.dart'; // SfwFilter.isClean()
import 'text_viewer_screen.dart';
import 'video_player_screen.dart';

// ---------- Sorting ----------
enum SortMode {
  popularAllTime,
  popularMonth,
  popularWeek,
  newest,
  oldest,
  alphaAZ,
  alphaZA,
}

String _sortParam(SortMode m) {
  switch (m) {
    case SortMode.popularAllTime:
      return 'downloads desc';
    case SortMode.popularMonth:
      return 'month desc'; // downloads last month
    case SortMode.popularWeek:
      return 'week desc'; // downloads last week
    case SortMode.newest:
      return 'publicdate desc'; // most recently published
    case SortMode.oldest:
      return 'publicdate asc';
    case SortMode.alphaAZ:
      return 'titleSorter asc';
    case SortMode.alphaZA:
      return 'titleSorter desc';
  }
}

// ---------- Simple favourites/downloaded stores ----------
class _FavoritesStore {
  static const _key = 'favourites_identifiers';
  Set<String> _ids = {};

  static final _FavoritesStore instance = _FavoritesStore._();
  _FavoritesStore._();

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _ids = (prefs.getStringList(_key) ?? const <String>[]).toSet();
  }

  Set<String> all() => _ids;
}

class _DownloadsStore {
  static const _idSetKey = 'downloads_identifiers';
  static const _readingListKey = 'reading_list';

  static final _DownloadsStore instance = _DownloadsStore._();
  _DownloadsStore._();

  Future<Set<String>> allIdentifiers() async {
    final prefs = await SharedPreferences.getInstance();
    final set = (prefs.getStringList(_idSetKey) ?? const <String>[]).toSet();

    final files = prefs.getStringList(_readingListKey) ?? const <String>[];
    for (final f in files) {
      final name = p.basename(f).toLowerCase();
      final base =
          name.contains('.') ? name.substring(0, name.lastIndexOf('.')) : name;
      if (base.isNotEmpty) set.add(base);
    }
    return set;
  }
}

class CollectionDetailScreen extends StatefulWidget {
  final String categoryName;
  final String? collectionName;
  final String? customQuery;
  final ArchiveFilters filters;

  const CollectionDetailScreen({
    super.key,
    required this.categoryName,
    this.collectionName,
    this.customQuery,
    this.filters = const ArchiveFilters(),
  });

  @override
  State<CollectionDetailScreen> createState() => _CollectionDetailScreenState();
}

class _CollectionDetailScreenState extends State<CollectionDetailScreen> {
  List<Map<String, String>> _items = [];
  bool _loading = true;

  final _searchCtrl = TextEditingController();
  int _requestToken = 0;
  static const int _rows = 120;

  // 🔽 current sort mode
  SortMode _sort = SortMode.popularAllTime;

  @override
  void initState() {
    super.initState();
    unawaited(_FavoritesStore.instance.init());
    _fetchCollectionItems();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  // ---------- Thumbnails helpers ----------
  String _thumbForId(String id) => 'https://archive.org/services/img/$id';
  String _fallbackThumbForId(String id) =>
      'https://archive.org/download/$id/__ia_thumb.jpg';

  // ---------- External/system video player ----------
  Future<void> _playVideo(String url, String title) async {
    final uri = Uri.parse(url);

    if (Platform.isAndroid) {
      // Launch the system/default video-capable app via Intent.
      final intent = AndroidIntent(
        action: 'action_view',
        data: uri.toString(),
        type: 'video/*',
        flags: <int>[Flag.FLAG_ACTIVITY_NEW_TASK],
      );
      await intent.launch();
      return;
    }

    if (Platform.isIOS) {
      // iOS uses AVPlayer; present your in-app player screen.
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => VideoPlayerScreen(videoUrl: url, title: title),
        ),
      );
      return;
    }

    // Desktop/other fallback: open externally (may be a browser)
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _fetchCollectionItems({String searchQuery = ''}) async {
    final int token = ++_requestToken;
    setState(() => _loading = true);

    final String baseQuery =
        widget.customQuery ?? 'collection:${widget.collectionName}';

    const fieldsToSearch = ['title', 'subject', 'description', 'creator'];

    String fullQuery;
    if (searchQuery.isNotEmpty) {
      final phrase = searchQuery.replaceAll('"', r'\"');
      final orClause = fieldsToSearch.map((f) => '$f:"$phrase"').join(' OR ');
      fullQuery = '($baseQuery) AND ($orClause)';
    } else {
      fullQuery = baseQuery;
    }

    final flParams = [
      'identifier',
      'title',
      'mediatype',
      'subject',
      'creator',
      'description',
      // you can add 'publicdate' if you want to display it
    ].map((f) => 'fl[]=$f').join('&');

    // 🔽 use selected sort mode
    final sortParam = Uri.encodeQueryComponent(_sortParam(_sort));

    final url =
        'https://archive.org/advancedsearch.php?'
        'q=${Uri.encodeQueryComponent(fullQuery)}&'
        '$flParams&'
        'sort[]=$sortParam&rows=$_rows&page=1&output=json';

    try {
      final response = await http.get(Uri.parse(url));
      if (!mounted || token != _requestToken) return;
      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        final docs = (json['response']['docs'] as List?) ?? [];

        List<Map<String, String>> items =
            docs.map<Map<String, String>>((doc) {
              final id = (doc['identifier'] ?? '').toString();
              return {
                'identifier': id,
                'title': (doc['title'] ?? 'No Title').toString(),
                'thumb': _thumbForId(id),
                'mediatype': (doc['mediatype'] ?? '').toString(),
                'description': (doc['description'] ?? '').toString(),
                'creator': (doc['creator'] ?? '').toString(),
                'subject': (doc['subject'] ?? '').toString(),
              };
            }).toList();

        // ✅ Apply client-side SFW (title + identifier only)
        if (widget.filters.sfwOnly) {
          items = items.where(SfwFilter.isClean).toList();
        }

        // Favourites filter
        if (widget.filters.favouritesOnly) {
          await _FavoritesStore.instance.init();
          final favs = _FavoritesStore.instance.all();
          items = items.where((m) => favs.contains(m['identifier'])).toList();
        }

        // Downloaded filter
        if (widget.filters.downloadedOnly) {
          final downloaded = await _DownloadsStore.instance.allIdentifiers();
          items =
              items.where((m) {
                final id = (m['identifier'] ?? '').toLowerCase();
                if (id.isEmpty) return false;
                return downloaded.any((d) {
                  final dd = d.toLowerCase();
                  return dd == id || dd.contains(id) || id.contains(dd);
                });
              }).toList();
        }

        setState(() {
          _items = items;
          _loading = false;
        });
      } else {
        setState(() => _loading = false);
      }
    } catch (_) {
      if (!mounted || token != _requestToken) return;
      setState(() => _loading = false);
    }
  }

  void _runSearch() {
    final q = _searchCtrl.text.trim();
    if (q.isEmpty || q.length >= 3) {
      _fetchCollectionItems(searchQuery: q);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.categoryName),
        actions: [
          PopupMenuButton<SortMode>(
            tooltip: 'Sort',
            icon: const Icon(Icons.sort),
            initialValue: _sort,
            onSelected: (m) {
              setState(() => _sort = m);
              _fetchCollectionItems(searchQuery: _searchCtrl.text.trim());
            },
            itemBuilder:
                (context) => const [
                  PopupMenuItem(
                    value: SortMode.popularAllTime,
                    child: Text('Most popular — all time'),
                  ),
                  PopupMenuItem(
                    value: SortMode.popularMonth,
                    child: Text('Most popular — last month'),
                  ),
                  PopupMenuItem(
                    value: SortMode.popularWeek,
                    child: Text('Most popular — last week'),
                  ),
                  PopupMenuDivider(),
                  PopupMenuItem(value: SortMode.newest, child: Text('Newest')),
                  PopupMenuItem(value: SortMode.oldest, child: Text('Oldest')),
                  PopupMenuDivider(),
                  PopupMenuItem(
                    value: SortMode.alphaAZ,
                    child: Text('Alphabetical (A–Z)'),
                  ),
                  PopupMenuItem(
                    value: SortMode.alphaZA,
                    child: Text('Alphabetical (Z–A)'),
                  ),
                ],
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: TextField(
              controller: _searchCtrl,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _runSearch(),
              decoration: InputDecoration(
                hintText: 'Search metadata (min 3 chars)…',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.arrow_forward),
                  onPressed: _runSearch,
                  tooltip: 'Search',
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ),
      ),
      body:
          _loading
              ? Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32.0),
                    child: LinearProgressIndicator(
                      backgroundColor: Colors.grey[300],
                      minHeight: 8,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Loading…',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              )
              : GridView.builder(
                padding: const EdgeInsets.all(8),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  childAspectRatio: 0.8,
                ),
                itemCount: _items.length,
                itemBuilder: (context, index) {
                  final item = _items[index];
                  final id = item['identifier']!;
                  return GestureDetector(
                    onTap: () => _openItem(context, item),
                    child: Card(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          CachedNetworkImage(
                            imageUrl: item['thumb']!,
                            height: 220,
                            fit: BoxFit.cover,
                            placeholder:
                                (context, url) => const Center(
                                  child: CircularProgressIndicator(),
                                ),
                            errorWidget:
                                (context, url, error) => Image.network(
                                  _fallbackThumbForId(id),
                                  height: 220,
                                  fit: BoxFit.cover,
                                  errorBuilder:
                                      (_, __, ___) =>
                                          const Icon(Icons.broken_image),
                                ),
                          ),
                          const SizedBox(height: 8),
                          Padding(
                            padding: const EdgeInsets.all(6.0),
                            child: Text(
                              item['title']!,
                              textAlign: TextAlign.center,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
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

  Future<void> _openItem(BuildContext context, Map<String, String> item) async {
    final identifier = item['identifier']!;
    final metadataUrl = 'https://archive.org/metadata/$identifier';
    final response = await http.get(Uri.parse(metadataUrl));

    if (response.statusCode != 200) return;

    final json = jsonDecode(response.body);
    final mediatype = json['metadata']?['mediatype'];

    if (mediatype == 'collection') {
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder:
              (_) => CollectionDetailScreen(
                categoryName: item['title']!,
                collectionName: identifier,
                filters: widget.filters,
              ),
        ),
      );
      return;
    }

    final files = json['files'] as List<dynamic>;

    final videoExtensions = ['.mp4', '.webm', '.ogv', '.mkv', '.mov', '.avi'];
    final videoFiles =
        files.where((file) {
          final name = file['name']?.toString().toLowerCase() ?? '';
          return videoExtensions.any((ext) => name.endsWith(ext));
        }).toList();

    if (videoFiles.isNotEmpty) {
      final video = videoFiles.first;
      final videoUrl =
          'https://archive.org/download/$identifier/${video['name']}';
      final title = item['title'] ?? identifier;
      await _playVideo(videoUrl, title); // ✅ system/inbuilt playback
      return;
    }

    final readableFiles =
        files
            .where((file) {
              final name = file['name']?.toString().toLowerCase() ?? '';
              return name.endsWith('.pdf') ||
                  name.endsWith('.epub') ||
                  name.endsWith('.cbz') ||
                  name.endsWith('.cbr') ||
                  name.endsWith('.zip') ||
                  name.endsWith('.rar');
            })
            .map<Map<String, String>>((file) {
              final name = file['name'];
              final ext = name.toLowerCase();
              String type = 'OTHER';
              if (ext.endsWith('.pdf'))
                type = 'PDF';
              else if (ext.endsWith('.epub'))
                type = 'EPUB';
              else if (ext.endsWith('.cbz'))
                type = 'CBZ';
              else if (ext.endsWith('.cbr'))
                type = 'CBR';
              else if (ext.endsWith('.zip'))
                type = 'ZIP';
              else if (ext.endsWith('.rar'))
                type = 'RAR';
              return {'name': name, 'type': type};
            })
            .toList();

    if (readableFiles.length > 1) {
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder:
              (_) => ArchiveItemScreen(
                title: item['title']!,
                identifier: identifier,
                files: readableFiles,
              ),
        ),
      );
      return;
    }

    final pdfFile = readableFiles.firstWhere(
      (file) => file['type'] == 'PDF',
      orElse: () => {},
    );

    if (pdfFile.isNotEmpty) {
      final pdfUrl =
          'https://archive.org/download/$identifier/${pdfFile['name']}';
      final localFile = await _downloadPdf(pdfUrl, pdfFile['name']!);
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => PdfViewerScreen(file: localFile)),
      );
      return;
    }

    final textFile = files.firstWhere(
      (file) => file['name'].toString().toLowerCase().endsWith('.txt'),
      orElse: () => null,
    );
    if (textFile != null) {
      final textUrl =
          'https://archive.org/download/$identifier/${textFile['name']}';
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => TextViewerScreen(url: textUrl, title: identifier),
        ),
      );
      return;
    }

    final imageFiles =
        files.where((file) {
          final name = file['name'].toString().toLowerCase();
          return (name.endsWith('.jpg') || name.endsWith('.png')) &&
              !name.contains('thumb') &&
              !name.contains('cover') &&
              !name.contains('small') &&
              !name.contains('medium') &&
              !name.startsWith('__') &&
              !name.contains('back');
        }).toList();

    if (imageFiles.isNotEmpty) {
      final imageUrls =
          imageFiles
              .map<String>(
                (file) =>
                    'https://archive.org/download/$identifier/${file['name']}',
              )
              .toList();
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ImageViewerScreen(imageUrls: imageUrls),
        ),
      );
      return;
    }

    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('No supported media found.')));
  }

  Future<File> _downloadPdf(String url, String filename) async {
    final dir = await getTemporaryDirectory();
    final filePath = p.join(dir.path, filename);
    final file = File(filePath);
    if (await file.exists()) return file;
    final response = await http.get(Uri.parse(url));
    await file.writeAsBytes(response.bodyBytes);
    return file;
  }
}
