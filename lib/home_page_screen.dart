import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:reorderables/reorderables.dart';

import 'collection_detail_screen.dart';
import 'reading_lists_screen.dart';

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
      home: HomePageScreen(),
    );
  }
}

class HomePageScreen extends StatefulWidget {
  const HomePageScreen({super.key});

  @override
  _HomePageScreenState createState() => _HomePageScreenState();
}

class _HomePageScreenState extends State<HomePageScreen> {
  List<Map<String, String>> categories = [
    {'name': 'Classic Literature', 'collection': 'greatbooks'},
    {'name': 'Books', 'collection': 'internetarchivebooks'},
    {'name': 'Magazines', 'collection': 'magazine_rack'},
    {'name': 'Comics', 'collection': 'comics_inbox'},
    {'name': 'Video', 'collection': 'moviesandfilms'},
    {'name': 'My Reading List', 'collection': 'reading_list'},
  ];

  final List<Map<String, String>> availableCollections = [
    {'name': 'Project Gutenberg', 'collection': 'gutenberg'},
    {'name': 'American Libraries', 'collection': 'americana'},
    {'name': 'Canadian Libraries', 'collection': 'toronto'},
    {'name': 'Universal Library', 'collection': 'universallibrary'},
    {'name': "Children's Library", 'collection': 'childrenslibrary'},
  ];

  void _showAddCollectionsDialog() async {
    final selected = <String>{};

    await showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: Text('Add Collections'),
            content: SingleChildScrollView(
              child: Column(
                children:
                    availableCollections.map((col) {
                      final isSelected = categories.any(
                        (c) => c['collection'] == col['collection'],
                      );
                      return CheckboxListTile(
                        value:
                            isSelected || selected.contains(col['collection']),
                        onChanged:
                            isSelected
                                ? null
                                : (value) {
                                  setState(() {
                                    if (value == true) {
                                      selected.add(col['collection']!);
                                    } else {
                                      selected.remove(col['collection']);
                                    }
                                  });
                                },
                        title: Text(col['name']!),
                      );
                    }).toList(),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () {
                  setState(() {
                    categories.addAll(
                      availableCollections.where(
                        (c) => selected.contains(c['collection']!),
                      ),
                    );
                  });
                  Navigator.pop(context);
                },
                child: Text('Add'),
              ),
            ],
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Select Category'),
        actions: [
          IconButton(
            icon: Icon(Icons.add),
            onPressed: _showAddCollectionsDialog,
            tooltip: 'Add Collections',
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(8),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final crossAxisCount = (constraints.maxWidth / 180).floor();
            return SingleChildScrollView(
              child: ReorderableWrap(
                spacing: 8,
                runSpacing: 8,
                needsLongPressDraggable: true,
                onReorder: (oldIndex, newIndex) {
                  setState(() {
                    final item = categories.removeAt(oldIndex);
                    categories.insert(newIndex, item);
                  });
                },
                children: List.generate(categories.length, (index) {
                  final category = categories[index];

                  return SizedBox(
                    width: 160,
                    child: Card(
                      key: ValueKey(category['collection']),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: InkWell(
                        onTap: () {
                          if (category['name'] == 'My Reading List') {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => ReadingListScreen(),
                              ),
                            );
                          } else {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder:
                                    (_) => CollectionDetailScreen(
                                      categoryName: category['name']!,
                                      collectionName: category['collection'],
                                      customQuery: category['customQuery'],
                                    ),
                              ),
                            );
                          }
                        },
                        child: Padding(
                          padding: const EdgeInsets.all(8),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              category['name'] == 'My Reading List'
                                  ? Icon(
                                    Icons.favorite,
                                    color: Colors.red,
                                    size: 100,
                                  )
                                  : CachedNetworkImage(
                                    imageUrl:
                                        category['collection'] != null
                                            ? 'https://archive.org/services/img/${category['collection']}'
                                            : 'https://archive.org/images/logo.png',
                                    height: 120,
                                    fit: BoxFit.cover,
                                    errorWidget:
                                        (_, __, ___) => Icon(Icons.image),
                                  ),
                              const SizedBox(height: 8),
                              Text(
                                category['name']!,
                                textAlign: TextAlign.center,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                }),
              ),
            );
          },
        ),
      ),
    );
  }
}
