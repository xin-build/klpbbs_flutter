/// Local module/layout edits. Dragging and cancelling never write preferences.
class DiyLayoutDraft {
  final Map<String, Object> _values;
  final Map<String, Object> _baseline;
  final Map<String, Object> _defaults;
  DiyLayoutDraft(Map<String, Object> values,
      {required Map<String, Object> defaults})
      : _values = _copy(values),
        _baseline = _copy(values),
        _defaults = _copy(defaults);

  static Map<String, Object> _copy(Map<String, Object> source) => {
        for (final entry in source.entries)
          entry.key: entry.value is List<String>
              ? List<String>.from(entry.value as List<String>)
              : entry.value,
      };
  static bool _same(Object? a, Object? b) {
    if (a is List && b is List) {
      if (a.length != b.length) return false;
      for (var i = 0; i < a.length; i++) {
        if (a[i] != b[i]) return false;
      }
      return true;
    }
    return a == b;
  }

  Map<String, Object> get changes => Map.unmodifiable({
        for (final entry in _values.entries)
          if (!_same(entry.value, _baseline[entry.key]))
            entry.key: entry.value is List<String>
                ? List<String>.unmodifiable(entry.value as List<String>)
                : entry.value,
      });
  bool get hasChanges => changes.isNotEmpty;
  Set<String> conflicts(Map<String, Object> current) => {
        for (final key in changes.keys)
          if (!_same(current[key], _baseline[key]) &&
              !_same(current[key], _values[key]))
            key,
      };
  void resetDiyLayout() {
    _values
      ..clear()
      ..addAll(_copy(_defaults));
  }

  List<String> get homeModules =>
      List.from(_values['homeModules'] as List<String>);
  List<String> get forumModules =>
      List.from(_values['forumModules'] as List<String>);
  List<String> get threadRightModules =>
      List.from(_values['threadRightModules'] as List<String>);
  bool get threadLeftEnabled => _values['threadLeftEnabled'] as bool;
  bool get threadRightEnabled => _values['threadRightEnabled'] as bool;
  double get threadForumSidebarWidth =>
      (_values['threadForumSidebarWidth'] as num).toDouble();
  double get threadRightWidth =>
      (_values['threadRightWidth'] as num).toDouble();
  double get threadContentMaxWidth =>
      (_values['threadContentMaxWidth'] as num).toDouble();
  double get threadReaderFontSize =>
      (_values['threadReaderFontSize'] as num).toDouble();
  double get threadReaderLineHeight =>
      (_values['threadReaderLineHeight'] as num).toDouble();
  void setHomeModules(List<String> value) =>
      _values['homeModules'] = List<String>.from(value);
  void setForumModules(List<String> value) =>
      _values['forumModules'] = List<String>.from(value);
  void setThreadRightModules(List<String> value) =>
      _values['threadRightModules'] = List<String>.from(value);
  void setThreadLeftEnabled(bool value) => _values['threadLeftEnabled'] = value;
  void setThreadRightEnabled(bool value) =>
      _values['threadRightEnabled'] = value;
  void setThreadForumSidebarWidth(double value) =>
      _values['threadForumSidebarWidth'] = value;
  void setThreadRightWidth(double value) => _values['threadRightWidth'] = value;
  void setThreadContentMaxWidth(double value) =>
      _values['threadContentMaxWidth'] = value;
  void setThreadReaderFontSize(double value) =>
      _values['threadReaderFontSize'] = value;
  void setThreadReaderLineHeight(double value) =>
      _values['threadReaderLineHeight'] = value;
  void updateThreadForumSidebarWidth(double value) =>
      setThreadForumSidebarWidth(value);
  void updateThreadRightWidth(double value) => setThreadRightWidth(value);
  void updateThreadContentMaxWidth(double value) =>
      setThreadContentMaxWidth(value);
}
