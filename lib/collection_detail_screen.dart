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

//search parameters
enum SearchScope { metadata, title }

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

class _VideoVariant {
  final String url;
  final String label;
  final String ext; // mp4, mkv, m3u8...
  final int? height; // 1080, 720...
  final int? width;
  final int? sizeBytes; // from metadata when present
  final bool isHls;
  final String? format; // IA format string, if present

  const _VideoVariant({
    required this.url,
    required this.label,
    required this.ext,
    required this.isHls,
    this.height,
    this.width,
    this.sizeBytes,
    this.format,
  });
}

int? _parseHeightFromName(String lowerName) {
  final m1 = RegExp(r'(\d{3,4})p').firstMatch(lowerName);
  if (m1 != null) return int.tryParse(m1.group(1)!);
  final m2 = RegExp(r'(\d{3,4})[xX](\d{3,4})').firstMatch(lowerName);
  if (m2 != null) return int.tryParse(m2.group(2)!);
  return null;
}

String _fmtBytes(int n) {
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  double size = n.toDouble();
  int i = 0;
  while (size >= 1024 && i < units.length - 1) {
    size /= 1024;
    i++;
  }
  return '${size.toStringAsFixed(size >= 10 ? 0 : 1)} ${units[i]}';
}

String _buildVariantLabel({
  required bool isHls,
  required String ext,
  int? height,
  int? sizeBytes,
  String? format,
}) {
  if (isHls) return 'Adaptive (HLS)';
  final parts = <String>[];
  if (height != null) parts.add('${height}p');
  parts.add(ext.toUpperCase());
  if (sizeBytes != null && sizeBytes > 0) parts.add(_fmtBytes(sizeBytes));
  // Avoid long/noisy format strings; show short codec hints if useful.
  if (format != null && format.isNotEmpty) {
    final short = format
        .replaceAll(RegExp(r'\s+Video', caseSensitive: false), '')
        .replaceAll(RegExp(r'MPEG-4', caseSensitive: false), 'MP4');
    if (short.length <= 16) parts.add(short);
  }
  return parts.join(' • ');
}

List<_VideoVariant> _extractVideoVariants(String identifier, List files) {
  final exts = ['.mp4', '.mkv', '.mov', '.webm', '.ogv', '.avi', '.m3u8'];
  final variants = <_VideoVariant>[];

  for (final file in files) {
    final name = (file['name'] ?? '').toString();
    final lower = name.toLowerCase();
    if (!exts.any((e) => lower.endsWith(e))) continue;

    final url = 'https://archive.org/download/$identifier/$name';
    final isHls = lower.endsWith('.m3u8');
    final ext = isHls ? 'm3u8' : p.extension(lower).replaceFirst('.', '');

    final heightMeta = int.tryParse('${file['height'] ?? ''}');
    final widthMeta = int.tryParse('${file['width'] ?? ''}');
    final sizeBytes = int.tryParse('${file['size'] ?? ''}');
    final fmt = file['format']?.toString();

    final height = heightMeta ?? _parseHeightFromName(lower);

    final label = _buildVariantLabel(
      isHls: isHls,
      ext: ext,
      height: height,
      sizeBytes: sizeBytes,
      format: fmt,
    );

    variants.add(
      _VideoVariant(
        url: url,
        label: label,
        ext: ext,
        isHls: isHls,
        height: height,
        width: widthMeta,
        sizeBytes: sizeBytes,
        format: fmt,
      ),
    );
  }

  // Sort: HLS first (adaptive), then by height desc, else by size desc as a proxy.
  variants.sort((a, b) {
    if (a.isHls != b.isHls) return a.isHls ? -1 : 1;
    final ah = a.height ?? 0, bh = b.height ?? 0;
    if (ah != bh) return bh.compareTo(ah);
    final asz = a.sizeBytes ?? 0, bsz = b.sizeBytes ?? 0;
    return bsz.compareTo(asz);
  });

  return variants;
}

Future<int?> _getPreferredVideoHeight() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getInt('preferred_video_height');
}

Future<void> _setPreferredVideoHeight(int height) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setInt('preferred_video_height', height);
}

_VideoVariant _bestMatchForHeight(List<_VideoVariant> list, int pref) {
  // pick the highest <= pref; else the closest above
  _VideoVariant? candidate;
  for (final v in list) {
    if (v.height == null) continue;
    if ((v.height!) <= pref) {
      if (candidate == null || (v.height!) > (candidate.height ?? 0)) {
        candidate = v;
      }
    }
  }
  return candidate ?? list.first;
}

// ✅ FIX: pass BuildContext in; remove mounted usage here
Future<_VideoVariant?> _pickVideoVariant(
  BuildContext context,
  String title,
  List<_VideoVariant> variants,
) async {
  if (variants.isEmpty) return null;
  if (variants.length == 1) return variants.first;

  final pref = await _getPreferredVideoHeight();
  _VideoVariant initial =
      pref != null ? _bestMatchForHeight(variants, pref) : variants.first;

  return showModalBottomSheet<_VideoVariant>(
    context: context,
    showDragHandle: true,
    builder: (context) {
      _VideoVariant selected = initial;
      bool remember = true; // remember last choice by default

      return StatefulBuilder(
        builder: (context, setSheet) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  title: Text('Choose quality'),
                  subtitle: Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const Divider(height: 1),
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: variants.length,
                    itemBuilder: (context, i) {
                      final v = variants[i];
                      return RadioListTile<_VideoVariant>(
                        value: v,
                        groupValue: selected,
                        onChanged: (nv) => setSheet(() => selected = nv!),
                        title: Text(v.label),
                        subtitle:
                            v.isHls ? const Text('Adaptive bitrate') : null,
                      );
                    },
                  ),
                ),
                SwitchListTile(
                  title: const Text('Remember this quality'),
                  value: remember,
                  onChanged: (v) => setSheet(() => remember = v),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Row(
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(context, null),
                        child: const Text('Cancel'),
                      ),
                      const Spacer(),
                      ElevatedButton.icon(
                        onPressed: () async {
                          if (remember && (selected.height != null)) {
                            await _setPreferredVideoHeight(selected.height!);
                          }
                          Navigator.pop(context, selected);
                        },
                        icon: const Icon(Icons.play_arrow),
                        label: const Text('Play'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      );
    },
  );
}

class _CollectionDetailScreenState extends State<CollectionDetailScreen> {
  List<Map<String, String>> _items = [];
  bool _loading = true;

  final _searchCtrl = TextEditingController();
  int _requestToken = 0;
  static const int _rows = 120;

  // 🔽 current sort mode
  SortMode _sort = SortMode.popularAllTime;

  //current search scope
  SearchScope _searchScope = SearchScope.metadata;

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

    final fieldsToSearch =
        _searchScope == SearchScope.metadata
            ? ['title', 'subject', 'description', 'creator']
            : ['title'];

    String fullQuery;
    if (searchQuery.isNotEmpty) {
      final phrase = searchQuery.replaceAll('"', r'\"');
      final orClause = fieldsToSearch.map((f) => '$f:"$phrase"').join(' OR ');
      fullQuery = '($baseQuery) AND ($orClause)';
    } else {
      fullQuery = baseQuery;
    }

    // ✅ server-side SFW (before request)
    if (widget.filters.sfwOnly) {
      fullQuery = '($fullQuery)${SfwFilter.serverExclusionSuffix()}';
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

        String _flat(dynamic v) {
          if (v == null) return '';
          if (v is List)
            return v.whereType<Object>().map((e) => e.toString()).join(', ');
          return v.toString();
        }

        List<Map<String, String>> items =
            docs.map<Map<String, String>>((doc) {
              final id = (doc['identifier'] ?? '').toString();
              return {
                'identifier': id,
                'title':
                    (_flat(doc['title']).isEmpty
                        ? 'No Title'
                        : _flat(doc['title'])),
                'thumb': _thumbForId(id),
                'mediatype': _flat(doc['mediatype']),
                'description': _flat(doc['description']),
                'creator': _flat(doc['creator']),
                'subject': _flat(doc['subject']), // <-- flattened tags
              };
            }).toList();

        // ✅ FIX: client-side SFW actually filters `items`
        if (widget.filters.sfwOnly) {
          var filtered = items.where(SfwFilter.isClean).toList();

          // optional fail-open to avoid empty results on niche collections
          if (filtered.isEmpty && searchQuery.isEmpty) {
            final strong = RegExp(
              r'(?i)\b(nsfw|xxx|porn(?:ography)?|hentai|r-?18|18\+|fetish|hardcore)\b',
            );
            bool titleIdClean(Map<String, String> m) {
              final t = m['title'] ?? '';
              final i = m['identifier'] ?? '';
              return !strong.hasMatch(t) && !strong.hasMatch(i);
            }

            filtered = items.where(titleIdClean).toList();
          }

          items = filtered;
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
            child: Row(
              children: [
                // Search input
                Expanded(
                  child: TextField(
                    controller: _searchCtrl,
                    textInputAction: TextInputAction.search,
                    onSubmitted: (_) => _runSearch(),
                    decoration: InputDecoration(
                      hintText:
                          _searchScope == SearchScope.metadata
                              ? 'Search metadata (min 3 chars)…'
                              : 'Search titles (min 3 chars)…',
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
                const SizedBox(width: 8),
                // Scope dropdown
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    border: Border.all(color: Theme.of(context).dividerColor),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<SearchScope>(
                      value: _searchScope,
                      onChanged: (value) {
                        if (value == null) return;
                        setState(() => _searchScope = value);
                        // Optionally re-run search immediately with the new scope:
                        _runSearch();
                      },
                      items: const [
                        DropdownMenuItem(
                          value: SearchScope.metadata,
                          child: Text('Metadata'),
                        ),
                        DropdownMenuItem(
                          value: SearchScope.title,
                          child: Text('Title'),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
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

    // ✅ Use quality picker
    final variants = _extractVideoVariants(identifier, files);
    if (variants.isNotEmpty) {
      final title = item['title'] ?? identifier;
      final chosen = await _pickVideoVariant(context, title, variants);
      if (chosen != null) {
        await _playVideo(chosen.url, title);
      }
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
