/// The Windows Flutter SDK offers a preference, not an arbitrary adapter LUID.
enum PcGpuPreference {
  auto('auto', '自动', '由 Flutter、Windows 与驱动决定'),
  lowPower('lowPower', '节能', '优先低功耗适配器，兼顾续航与温度'),
  highPerformance('highPerformance', '高性能', '优先高性能适配器，适合较重的界面渲染');

  final String wire;
  final String label;
  final String description;
  const PcGpuPreference(this.wire, this.label, this.description);

  static PcGpuPreference parse(Object? value) =>
      values.firstWhere((preference) => preference.wire == value,
          orElse: () => throw const FormatException('Unknown GPU preference'));
}

class PcGpuAdapter {
  final String luid;
  final String name;
  final int vendorId;
  final int deviceId;
  final int dedicatedVideoMemory;
  final int sharedSystemMemory;
  final List<String> aliasLuids;
  final String identitySource;
  const PcGpuAdapter(
      {required this.luid,
      required this.name,
      required this.vendorId,
      required this.deviceId,
      required this.dedicatedVideoMemory,
      required this.sharedSystemMemory,
      this.aliasLuids = const [],
      this.identitySource = 'luid'});

  factory PcGpuAdapter.fromMap(Map<Object?, Object?> map) {
    int integer(String key) {
      final value = map[key];
      if (value is! int || value < 0) {
        throw FormatException('Invalid adapter $key');
      }
      return value;
    }

    final luid = map['luid'];
    final name = map['name'];
    if (luid is! String ||
        !RegExp(r'^[0-9a-fA-F]{8}:[0-9a-fA-F]{8}$').hasMatch(luid) ||
        name is! String ||
        name.trim().isEmpty) {
      throw const FormatException('Invalid GPU adapter identity');
    }
    final aliases = map['aliasLuids'];
    if (aliases != null &&
        (aliases is! List ||
            aliases.any((value) =>
                value is! String ||
                !RegExp(r'^[0-9a-fA-F]{8}:[0-9a-fA-F]{8}$').hasMatch(value)))) {
      throw const FormatException('Invalid GPU alias identity');
    }
    final identities = <String>{
      luid.toLowerCase(),
      if (aliases is List)
        ...aliases.cast<String>().map((value) => value.toLowerCase())
    };
    final identitySource = map['identitySource'] ?? 'luid';
    if (!const {'physical', 'luid'}.contains(identitySource)) {
      throw const FormatException('Invalid GPU identity source');
    }
    return PcGpuAdapter(
        luid: luid.toLowerCase(),
        name: name,
        vendorId: integer('vendorId'),
        deviceId: integer('deviceId'),
        dedicatedVideoMemory: integer('dedicatedVideoMemory'),
        sharedSystemMemory: integer('sharedSystemMemory'),
        aliasLuids: List<String>.unmodifiable(identities),
        identitySource: identitySource as String);
  }
}

class PcGpuSnapshot {
  final bool supported;
  final bool preview;
  final PcGpuPreference preference;
  final PcGpuPreference startupPreference;
  final bool nextStartRequiresRestart;
  final List<PcGpuAdapter> adapters;
  final String? currentLuid;
  final String? currentName;
  final String? inventoryError;
  final String? configurationError;

  PcGpuSnapshot(
      {required this.supported,
      required this.preview,
      required this.preference,
      required this.startupPreference,
      required this.nextStartRequiresRestart,
      required List<PcGpuAdapter> adapters,
      this.currentLuid,
      this.currentName,
      this.inventoryError,
      this.configurationError})
      : adapters = List<PcGpuAdapter>.unmodifiable(adapters) {
    if (nextStartRequiresRestart != (preference != startupPreference)) {
      throw const FormatException('Inconsistent GPU restart state');
    }
  }

  static bool visible({required bool windows, required bool desktop}) =>
      windows && desktop;

  factory PcGpuSnapshot.fromMap(Map<Object?, Object?> map) {
    bool flag(String key) {
      final value = map[key];
      if (value is! bool) throw FormatException('Invalid GPU $key');
      return value;
    }

    String? text(String key) {
      final value = map[key];
      if (value == null || value == '') return null;
      if (value is! String) throw FormatException('Invalid GPU $key');
      return value;
    }

    if (map['canBindSpecificAdapter'] != false) {
      throw const FormatException('Arbitrary GPU binding is unsupported');
    }
    final entries = map['adapters'];
    if (entries is! List) throw const FormatException('Invalid GPU inventory');
    final adapters = entries.map((value) {
      if (value is! Map) throw const FormatException('Invalid GPU adapter');
      return PcGpuAdapter.fromMap(Map<Object?, Object?>.from(value));
    }).toList();
    if (adapters.map((adapter) => adapter.luid).toSet().length !=
        adapters.length) {
      throw const FormatException('Duplicate GPU identities');
    }
    final logicalIds = <String>{};
    for (final adapter in adapters) {
      for (final identity in {adapter.luid, ...adapter.aliasLuids}) {
        if (!logicalIds.add(identity)) {
          throw const FormatException('GPU alias belongs to multiple devices');
        }
      }
    }
    final currentLuid = text('currentLuid')?.toLowerCase();
    if (currentLuid != null &&
        !RegExp(r'^[0-9a-f]{8}:[0-9a-f]{8}$').hasMatch(currentLuid)) {
      throw const FormatException('Invalid current adapter identity');
    }
    return PcGpuSnapshot(
        supported: flag('supported'),
        preview: flag('preview'),
        preference: PcGpuPreference.parse(map['preference']),
        startupPreference: PcGpuPreference.parse(map['startupPreference']),
        nextStartRequiresRestart: flag('nextStartRequiresRestart'),
        adapters: adapters,
        currentLuid: currentLuid,
        currentName: text('currentName'),
        inventoryError: text('inventoryError'),
        configurationError: text('configurationError'));
  }

  /// A preference never predicts which GPU is actually rendering this process.
  bool isCurrent(PcGpuAdapter adapter) =>
      currentLuid != null &&
      (currentLuid == adapter.luid || adapter.aliasLuids.contains(currentLuid));
  bool canSave(PcGpuPreference selected) => supported && selected != preference;

  /// A success envelope alone cannot confirm the requested preference was saved.
  void confirmSavedPreference(PcGpuPreference requested) {
    if (!supported || preference != requested || configurationError != null) {
      throw const FormatException(
          'GPU save receipt did not confirm preference');
    }
  }

  static String memoryLabel(int bytes) {
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).round()} MiB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GiB';
  }
}
