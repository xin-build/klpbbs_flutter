import 'package:flutter/foundation.dart';

import '../core/discuz_avatar_declaration.dart';

class _AvatarNotifier extends ValueNotifier<DiscuzAvatarDeclaration?> {
  _AvatarNotifier() : super(null);
  bool get observed => hasListeners;
  int revision = 0;
}

/// Observed server declarations only. No per-row profile requests or disk data.
/// Subscribers are per UID, so one pendant update does not rebuild an entire feed.
class AvatarAppearanceStore {
  AvatarAppearanceStore._();
  static final instance = AvatarAppearanceStore._();
  final _entries = <int, _AvatarNotifier>{};
  String? _scope;
  int _revisionSerial = 0;
  static const capacity = 768;

  ValueNotifier<DiscuzAvatarDeclaration?> listenable(int uid) => _notifier(uid);

  _AvatarNotifier _notifier(int uid) {
    final old = _entries.remove(uid);
    final result = old ?? _AvatarNotifier();
    _entries[uid] = result;
    _trim(keep: uid);
    return result;
  }

  DiscuzAvatarDeclaration? get(int uid) => _entries[uid]?.value;

  int revision(int uid) => _entries[uid]?.revision ?? 0;

  void forget(int uid) {
    final entry = _entries[uid];
    if (entry != null) {
      entry.revision = ++_revisionSerial;
      entry.value = null;
    }
  }

  void useScope(String scope) {
    if (_scope == scope) return;
    _scope = scope;
    // Retain active listenables while removing the previous account's values.
    for (final entry in _entries.values.toList()) {
      entry.revision = ++_revisionSerial;
      entry.value = null;
    }
    _trim();
  }

  void remember(DiscuzAvatarDeclaration declaration) {
    final notifier = _notifier(declaration.uid);
    final previous = notifier.value;
    final next = DiscuzAvatarDeclaration(
        uid: declaration.uid,
        username: declaration.username.isEmpty
            ? previous?.username ?? ''
            : declaration.username,
        avatarUrl: declaration.avatarUrl ?? previous?.avatarUrl,
        faceUrl: declaration.faceUrl ?? previous?.faceUrl);
    if (previous?.username == next.username &&
        previous?.avatarUrl == next.avatarUrl &&
        previous?.faceUrl == next.faceUrl) {
      return;
    }
    if (declaration.faceUrl != null && previous?.faceUrl != next.faceUrl) {
      notifier.revision = ++_revisionSerial;
    }
    notifier.value = next;
  }

  void _trim({int? keep}) {
    if (_entries.length <= capacity) return;
    final removable = _entries.entries
        .where((entry) => entry.key != keep && !entry.value.observed)
        .map((entry) => entry.key)
        .toList();
    for (final uid in removable) {
      if (_entries.length <= capacity) break;
      _entries.remove(uid)?.dispose();
    }
  }
}
