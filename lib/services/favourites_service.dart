import 'package:shared_preferences/shared_preferences.dart';

class FavoritesService {
  FavoritesService._();
  static final FavoritesService instance = FavoritesService._();

  static const _key = 'favourites_identifiers';
  Set<String> _ids = {};

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _ids = (prefs.getStringList(_key) ?? const <String>[]).toSet();
  }

  bool isFavourite(String identifier) => _ids.contains(identifier);

  Set<String> all() => _ids;

  Future<void> setFavourite(String identifier, bool fav) async {
    final prefs = await SharedPreferences.getInstance();
    if (fav) {
      _ids.add(identifier);
    } else {
      _ids.remove(identifier);
    }
    await prefs.setStringList(_key, _ids.toList());
  }
}
