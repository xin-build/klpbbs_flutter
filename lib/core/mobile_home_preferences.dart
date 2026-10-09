/// Persistent mobile modules use stable, known IDs and preserve user order.
class MobileHomePreferences {
  MobileHomePreferences._();

  static const sections = [
    'horn_banner',
    'stats',
    'carousel',
    'quick_actions',
    'forum_nav',
  ];
  static const actions = [
    'papa_ai',
    'forum_nav',
    'checkin',
    'medals',
    'guide',
    'search',
    'rank_god',
    'rank_board',
    'favorites',
    'my_threads',
    'tasks',
    'post_new'
  ];
  static const defaultActions = ['papa_ai', 'guide', 'favorites', 'rank_god'];

  static List<String> normalizeSections(List<String>? value) {
    if (value == null) return [...sections];
    const legacyDefault = [
      'horn_banner',
      'stats',
      'quick_actions',
      'forum_nav',
      'carousel'
    ];
    if (value.length == legacyDefault.length &&
        List.generate(value.length, (i) => value[i] == legacyDefault[i])
            .every((same) => same)) {
      return [...sections];
    }
    final known = value.where(sections.contains).toSet().toList();
    // An explicitly empty selection means all optional modules are hidden.
    return value.isNotEmpty && known.isEmpty ? [...sections] : known;
  }

  static List<String> normalizeActions(List<String>? value) {
    final known = (value ?? defaultActions)
        .where(actions.contains)
        .toSet()
        .take(8)
        .toList();
    for (final fallback in [...defaultActions, ...actions]) {
      if (known.length >= 4) break;
      if (!known.contains(fallback)) known.add(fallback);
    }
    return known;
  }
}
