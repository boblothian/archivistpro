// lib/services/sfw_filter.dart
/// Ultra-minimal SFW filter — checks only title + identifier.
class SfwFilter {
  static final List<RegExp> _patterns = [
    RegExp(r'(?i)(^|\W)(nsfw|xxx|hentai|porn(?:ography)?)($|\W)'),
    RegExp(r'(?i)(^|\W)r-?18($|\W)'),
    RegExp(r'(?i)18\+'),
  ];

  /// Returns true when the item is safe to show.
  static bool isClean(Map<String, String> item) {
    final title = item['title'] ?? '';
    final id = item['identifier'] ?? '';
    for (final re in _patterns) {
      if (re.hasMatch(title) || re.hasMatch(id)) return false; // not clean
    }
    return true;
  }
}
