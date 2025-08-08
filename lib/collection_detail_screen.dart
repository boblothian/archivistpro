import 'dart:convert';
import 'dart:io';

import 'package:archivecomics/video_player_screen.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'archive_item_screen.dart';
import 'image_viewer_screen.dart';
import 'pdf_viewer_screen.dart';
import 'text_viewer_screen.dart';

class CollectionDetailScreen extends StatefulWidget {
  final String categoryName;
  final String? collectionName;
  final String? customQuery;

  CollectionDetailScreen({
    required this.categoryName,
    this.collectionName,
    this.customQuery,
  });

  @override
  _CollectionDetailScreenState createState() => _CollectionDetailScreenState();
}

class _CollectionDetailScreenState extends State<CollectionDetailScreen> {
  List<Map<String, String>> _items = [];
  bool _loading = true;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _fetchCollectionItems();
  }

  Future<void> _fetchCollectionItems({String searchQuery = ''}) async {
    final String baseQuery =
        widget.customQuery ?? 'collection:${widget.collectionName}';

    String fullQuery;
    if (searchQuery.isNotEmpty) {
      final encoded = searchQuery.replaceAll('"', '\"');
      fullQuery =
          '($baseQuery) AND (title:"$encoded" OR subject:"$encoded" OR description:"$encoded" OR creator:"$encoded" OR collection:"$encoded" OR keywords:"$encoded" OR tags:"$encoded" OR notes:"$encoded")';
    } else {
      fullQuery = baseQuery;
    }

    final url =
        'https://archive.org/advancedsearch.php?q=${Uri.encodeQueryComponent(fullQuery)}&fl[]=identifier&fl[]=title&fl[]=mediatype&fl[]=subject&fl[]=creator&fl[]=keywords&fl[]=tags&sort[]=downloads+desc&rows=1000&page=1&output=json';

    print('Archive query URL → $url');

    final response = await http.get(Uri.parse(url));

    if (response.statusCode == 200) {
      final json = jsonDecode(response.body);
      final docs = json['response']['docs'] as List;
      final items =
          docs.map<Map<String, String>>((doc) {
            return {
              'identifier': doc['identifier'].toString(),
              'title': (doc['title'] ?? 'No Title').toString(),
              'thumb': 'https://archive.org/services/img/${doc['identifier']}',
              'mediatype': doc['mediatype'] ?? '',
            };
          }).toList();

      setState(() {
        _items = items;
        _loading = false;
      });
    } else {
      setState(() => _loading = false);
    }
  }

  List<Map<String, String>> get _filteredItems {
    return _items.where((item) {
      final title = item['title']!.toLowerCase();
      return title.contains(_searchQuery.toLowerCase());
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.categoryName),
        bottom: PreferredSize(
          preferredSize: Size.fromHeight(56),
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: TextField(
              decoration: InputDecoration(
                hintText: 'Search titles...',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onChanged: (value) => setState(() => _searchQuery = value),
            ),
          ),
        ),
      ),
      body:
          _loading
              ? Center(child: CircularProgressIndicator())
              : GridView.builder(
                padding: EdgeInsets.all(8),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  childAspectRatio: 0.8,
                ),
                itemCount: _filteredItems.length,
                itemBuilder: (context, index) {
                  final item = _filteredItems[index];
                  return GestureDetector(
                    onTap: () => _openItem(context, item),
                    child: Card(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
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
                                (context, url, error) =>
                                    const Icon(Icons.broken_image),
                          ),
                          SizedBox(height: 8),
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
      Navigator.push(
        context,
        MaterialPageRoute(
          builder:
              (_) => CollectionDetailScreen(
                categoryName: item['title']!,
                collectionName: identifier,
              ),
        ),
      );
      return;
    }

    final files = json['files'] as List<dynamic>;

    final videoExtensions = ['.mp4', '.webm', '.ogv', '.mkv'];
    final videoFiles =
        files.where((file) {
          final name = file['name']?.toString().toLowerCase() ?? '';
          return videoExtensions.any((ext) => name.endsWith(ext));
        }).toList();

    if (videoFiles.isNotEmpty) {
      final video = videoFiles.first;
      final videoUrl =
          'https://archive.org/download/$identifier/${video['name']}';
      final title = item['title']!;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => VideoPlayerScreen(videoUrl: videoUrl, title: title),
        ),
      );
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
              if (ext.endsWith('.pdf')) {
                type = 'PDF';
              } else if (ext.endsWith('.epub')) {
                type = 'EPUB';
              } else if (ext.endsWith('.cbz')) {
                type = 'CBZ';
              } else if (ext.endsWith('.cbr')) {
                type = 'CBR';
              } else if (ext.endsWith('.zip')) {
                type = 'ZIP';
              } else if (ext.endsWith('.rar')) {
                type = 'RAR';
              }
              return {'name': name, 'type': type};
            })
            .toList();

    if (readableFiles.length > 1) {
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
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ImageViewerScreen(imageUrls: imageUrls),
        ),
      );
      return;
    }

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('No supported media found.')));
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
