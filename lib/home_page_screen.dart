import 'package:archivereader/services/filters.dart';
import 'package:flutter/material.dart';

import 'collection_detail_screen.dart';
import 'reading_lists_screen.dart';

enum Category { classic, books, magazines, comics, video, readingList }

extension CategoryX on Category {
  String get label {
    switch (this) {
      case Category.classic:
        return 'Classic Literature';
      case Category.books:
        return 'Books';
      case Category.magazines:
        return 'Magazines';
      case Category.comics:
        return 'Comics';
      case Category.video:
        return 'Video';
      case Category.readingList:
        return 'My Reading List';
    }
  }

  IconData get icon {
    switch (this) {
      case Category.classic:
        return Icons.museum_outlined;
      case Category.books:
        return Icons.menu_book_outlined;
      case Category.magazines:
        return Icons.local_library_outlined;
      case Category.comics:
        return Icons.auto_stories_outlined;
      case Category.video:
        return Icons.ondemand_video_outlined;
      case Category.readingList:
        return Icons.favorite_outline;
    }
  }
}

class HomePageScreen extends StatefulWidget {
  const HomePageScreen({super.key});

  @override
  State<HomePageScreen> createState() => _HomePageScreenState();
}

class _HomePageScreenState extends State<HomePageScreen> {
  // Quick filter toggles (now hooked up!)
  bool _sfwOnly = true;
  bool _favouritesOnly = false;
  bool _downloadedOnly = false;

  ArchiveFilters get _filters => ArchiveFilters(
    sfwOnly: _sfwOnly,
    favouritesOnly: _favouritesOnly,
    downloadedOnly: _downloadedOnly,
  );

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final wide = c.maxWidth >= 980; // tablet/desktop breakpoint

        return Scaffold(
          // Drawer on phones
          drawer:
              wide
                  ? null
                  : _AppDrawer(
                    sfwOnly: _sfwOnly,
                    onToggleSfw: (v) => setState(() => _sfwOnly = v),
                    onSelect: _openCategory,
                  ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: _onAddCollection,
            icon: const Icon(Icons.add),
            label: const Text('Add Collection'),
          ),
          body: SafeArea(
            child: Row(
              children: [
                // Persistent rail on wide screens
                if (wide) _Rail(onSelect: _openCategory),
                Expanded(
                  child: CustomScrollView(
                    slivers: [
                      SliverAppBar(
                        pinned: true,
                        leading:
                            wide
                                ? null
                                : Builder(
                                  builder:
                                      (ctx) => IconButton(
                                        icon: const Icon(Icons.menu),
                                        onPressed:
                                            () => Scaffold.of(ctx).openDrawer(),
                                        tooltip: 'Menu',
                                      ),
                                ),
                        title: const Text('Archivist'),
                        actions: [
                          IconButton(
                            tooltip: 'Search',
                            icon: const Icon(Icons.search),
                            onPressed: _openSearch,
                          ),
                        ],
                        bottom: PreferredSize(
                          preferredSize: const Size.fromHeight(48),
                          child: _FilterBar(
                            sfwOnly: _sfwOnly,
                            favouritesOnly: _favouritesOnly,
                            downloadedOnly: _downloadedOnly,
                            onChanged:
                                (s, f, d) => setState(() {
                                  _sfwOnly = s;
                                  _favouritesOnly = f;
                                  _downloadedOnly = d;
                                }),
                          ),
                        ),
                      ),

                      // Landing grid of categories
                      SliverPadding(
                        padding: const EdgeInsets.all(16),
                        sliver: _CategoriesGrid(onTap: _openCategory),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // Navigation targets for categories (now pass filters)
  void _openCategory(Category c) {
    switch (c) {
      case Category.readingList:
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const ReadingListScreen()),
        );
        break;

      case Category.magazines:
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => MagazinesHubScreen(filters: _filters),
          ),
        );
        break;

      case Category.classic:
        Navigator.push(
          context,
          MaterialPageRoute(
            builder:
                (_) => CollectionDetailScreen(
                  categoryName: 'Classic Literature',
                  // You can refine this query later
                  customQuery:
                      'collection:internetarchivebooks AND (title:classic OR subject:("Classic" OR "Literature"))',
                  filters: _filters,
                ),
          ),
        );
        break;

      case Category.books:
        Navigator.push(
          context,
          MaterialPageRoute(
            builder:
                (_) => CollectionDetailScreen(
                  categoryName: 'Books',
                  collectionName: 'internetarchivebooks',
                  filters: _filters,
                ),
          ),
        );
        break;

      case Category.comics:
        Navigator.push(
          context,
          MaterialPageRoute(
            builder:
                (_) => CollectionDetailScreen(
                  categoryName: 'Comics',
                  collectionName: 'comics_inbox',
                  filters: _filters,
                ),
          ),
        );
        break;

      case Category.video:
        Navigator.push(
          context,
          MaterialPageRoute(
            builder:
                (_) => CollectionDetailScreen(
                  categoryName: 'Video',
                  customQuery: 'mediatype:movies',
                  filters: _filters,
                ),
          ),
        );
        break;
    }

    // Close drawer if open
    Navigator.of(context).maybePop();
  }

  void _openSearch() {
    showSearch(context: context, delegate: _SimpleSearchDelegate(_filters));
  }

  void _onAddCollection() {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) {
        return Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            bottom: 16 + MediaQuery.of(context).viewInsets.bottom,
            top: 8,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const ListTile(
                leading: Icon(Icons.collections_bookmark_outlined),
                title: Text('Add a popular Archive.org collection'),
                subtitle: Text('Pick a quick toggle or paste a collection ID.'),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _ChipButton(label: 'internetarchivebooks', filters: _filters),
                  _ChipButton(label: 'comics_inbox', filters: _filters),
                  _ChipButton(label: 'videogamemagazines', filters: _filters),
                  _ChipButton(label: 'hobbymagazines', filters: _filters),
                  _ChipButton(label: 'cinemamagazines', filters: _filters),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                decoration: const InputDecoration(
                  labelText: 'Collection identifier',
                  hintText: 'e.g. comics_inbox',
                  prefixIcon: Icon(Icons.tag),
                  border: OutlineInputBorder(),
                ),
                onSubmitted: (id) {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder:
                          (_) => CollectionDetailScreen(
                            categoryName: id,
                            collectionName: id,
                            filters: _filters,
                          ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }
}

/// Drawer (phones)
class _AppDrawer extends StatelessWidget {
  const _AppDrawer({
    required this.sfwOnly,
    required this.onToggleSfw,
    required this.onSelect,
  });

  final bool sfwOnly;
  final ValueChanged<bool> onToggleSfw;
  final ValueChanged<Category> onSelect;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 320,
      child: NavigationDrawer(
        selectedIndex: -1,
        onDestinationSelected: (i) => onSelect(Category.values[i]),
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(28, 18, 16, 4),
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(
                'Archivist',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
              ),
              subtitle: Text('Archive.org reader'),
              leading: FlutterLogo(size: 32),
            ),
          ),
          const Divider(),
          for (final c in Category.values)
            NavigationDrawerDestination(
              icon: Icon(c.icon),
              selectedIcon: Icon(c.icon),
              label: Text(c.label),
            ),
          const Divider(),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 8),
            child: Row(
              children: [
                const Icon(Icons.shield_moon_outlined, size: 20),
                const SizedBox(width: 12),
                const Text('SFW only'),
                const Spacer(),
                Switch(value: sfwOnly, onChanged: onToggleSfw),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}

/// Rail (tablets/desktops)
class _Rail extends StatelessWidget {
  const _Rail({required this.onSelect});
  final ValueChanged<Category> onSelect;

  @override
  Widget build(BuildContext context) {
    return NavigationRail(
      labelType: NavigationRailLabelType.all,
      leading: const Padding(
        padding: EdgeInsets.only(top: 8.0),
        child: FlutterLogo(size: 32),
      ),
      destinations: [
        for (final c in Category.values)
          NavigationRailDestination(icon: Icon(c.icon), label: Text(c.label)),
      ],
      selectedIndex: -1,
      onDestinationSelected: (i) => onSelect(Category.values[i]),
    );
  }
}

/// Category card grid on the landing page
class _CategoriesGrid extends StatelessWidget {
  const _CategoriesGrid({required this.onTap});
  final ValueChanged<Category> onTap;

  int _colsFor(double w) {
    if (w >= 1200) return 5;
    if (w >= 900) return 4;
    if (w >= 600) return 3;
    return 2;
  }

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    final cols = _colsFor(w);
    final items = Category.values;

    return SliverGrid(
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: cols,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
        childAspectRatio: .9,
      ),
      delegate: SliverChildBuilderDelegate((context, index) {
        final c = items[index];
        return Card(
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => onTap(c),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  const SizedBox(height: 8),
                  Icon(c.icon, size: 56),
                  const Spacer(),
                  Text(
                    c.label,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ),
        );
      }, childCount: items.length),
    );
  }
}

/// Filter chips under the AppBar (now drive the filters)
class _FilterBar extends StatelessWidget {
  const _FilterBar({
    required this.sfwOnly,
    required this.favouritesOnly,
    required this.downloadedOnly,
    required this.onChanged,
  });

  final bool sfwOnly;
  final bool favouritesOnly;
  final bool downloadedOnly;
  final void Function(bool sfw, bool fav, bool dld) onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Wrap(
        spacing: 8,
        children: [
          FilterChip(
            label: const Text('SFW only'),
            selected: sfwOnly,
            onSelected: (v) => onChanged(v, favouritesOnly, downloadedOnly),
          ),
          FilterChip(
            label: const Text('Favourites'),
            selected: favouritesOnly,
            onSelected: (v) => onChanged(sfwOnly, v, downloadedOnly),
          ),
          FilterChip(
            label: const Text('Downloaded'),
            selected: downloadedOnly,
            onSelected: (v) => onChanged(sfwOnly, favouritesOnly, v),
          ),
        ],
      ),
    );
  }
}

/// Search that preserves current filters
class _SimpleSearchDelegate extends SearchDelegate<String?> {
  _SimpleSearchDelegate(this.filters);
  final ArchiveFilters filters;

  @override
  List<Widget>? buildActions(BuildContext context) => [
    IconButton(icon: const Icon(Icons.clear), onPressed: () => query = ''),
  ];

  @override
  Widget? buildLeading(BuildContext context) => IconButton(
    icon: const Icon(Icons.arrow_back),
    onPressed: () => close(context, null),
  );

  @override
  Widget buildResults(BuildContext context) => Center(
    child: ElevatedButton.icon(
      onPressed: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder:
                (_) => CollectionDetailScreen(
                  categoryName: 'Search',
                  customQuery: query,
                  filters: filters,
                ),
          ),
        );
      },
      icon: const Icon(Icons.search),
      label: Text('Search "$query"'),
    ),
  );

  @override
  Widget buildSuggestions(BuildContext context) => const SizedBox.shrink();
}

/// Magazines -> grid of popular magazine collections (passes filters through)
class MagazinesHubScreen extends StatelessWidget {
  const MagazinesHubScreen({super.key, required this.filters});
  final ArchiveFilters filters;

  static const _magCollections = [
    {'title': 'Computer Magazines', 'collection': 'computer_magazines'},
    {'title': 'Videogame Magazines', 'collection': 'videogamemagazines'},
    {'title': 'Hobby Magazines', 'collection': 'hobbymagazines'},
    {'title': 'Cinema Magazines', 'collection': 'cinemamagazines'},
    {'title': 'Pulp Magazine Archive', 'collection': 'pulpmagazinearchive'},
  ];

  int _colsFor(double w) {
    if (w >= 1200) return 4;
    if (w >= 900) return 3;
    if (w >= 600) return 2;
    return 1;
  }

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    final cols = _colsFor(w);

    return Scaffold(
      appBar: AppBar(title: const Text('Magazines')),
      body: GridView.builder(
        padding: const EdgeInsets.all(16),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: cols,
          crossAxisSpacing: 16,
          mainAxisSpacing: 16,
          childAspectRatio: 1.1,
        ),
        itemCount: _magCollections.length,
        itemBuilder: (context, i) {
          final item = _magCollections[i];

          return Card(
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder:
                        (_) => CollectionDetailScreen(
                          categoryName: item['title']!,
                          collectionName: item['collection']!,
                          filters: filters,
                        ),
                  ),
                );
              },
              child: Column(
                children: [
                  const Spacer(),
                  const Icon(Icons.local_library_outlined, size: 56),
                  const Spacer(),
                  Padding(
                    padding: const EdgeInsets.all(12.0),
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
}

/// Quick-select chip for the "Add Collection" sheet (passes filters)
class _ChipButton extends StatelessWidget {
  const _ChipButton({required this.label, required this.filters});
  final String label;
  final ArchiveFilters filters;

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      label: Text(label),
      onPressed: () {
        Navigator.pop(context);
        Navigator.push(
          context,
          MaterialPageRoute(
            builder:
                (_) => CollectionDetailScreen(
                  categoryName: label,
                  collectionName: label,
                  filters: filters,
                ),
          ),
        );
      },
    );
  }
}
