// lib/services/sfw_filter.dart

class SfwFilter {
  // Strong, low false-positive signals only.
  static final RegExp _strong = RegExp(
    r'(?i)\b(nsfw|xxx|porn(?:ography)?|hentai|r-?18|18\+|fetish|hardcore)\b',
  );

  /// Keep: true = safe, false = filter out
  static bool isClean(Map<String, String> item) {
    final title = item['title'] ?? '';
    final ident = item['identifier'] ?? '';
    final subject = item['subject'] ?? ''; // flattened list/string

    // Title/identifier: strong terms
    if (_strong.hasMatch(title) || _strong.hasMatch(ident)) return false;

    // Subjects/tags: strong terms only (no "adult"/"sex" etc.)
    if (_strong.hasMatch(subject)) return false;

    return true;
  }

  /// Optional: add to your IA query so the API excludes obvious NSFW.
  /// Strong terms only, applied to title+subject (NOT description).
  static String serverExclusionSuffix() {
    const terms = [
      'nsfw',
      'xxx',
      'porn',
      'pornography',
      'hentai',
      'r-18',
      'r18',
      '18+',
      'fetish',
      'hardcore',
    ];
    final quoted = terms.map((t) => '"$t"').join(' OR ');
    return ' AND -title:($quoted) AND -subject:($quoted)';
  }
}
