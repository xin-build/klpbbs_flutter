import 'dart:async';

import 'discuz_avatar_declaration.dart';

typedef AvatarAppearanceFetch = Future<DiscuzAvatarDeclaration?> Function(
    int uid, String scope);

class _AppearanceRequest {
  final int uid, revision, generation;
  final String scope;
  final Completer<DiscuzAvatarDeclaration?> completer = Completer();
  bool started = false;
  _AppearanceRequest(this.uid, this.scope, this.revision, this.generation);
}

/// Read-only, bounded background resolution for templates that omit pendants.
/// Website pages can satisfy queued lookups in bulk. Failed and negative reads
/// have their own expiry, and stale replies never overwrite a newer declaration.
class AvatarAppearanceLookup {
  final AvatarAppearanceFetch fetch;
  final String Function() currentScope;
  final DiscuzAvatarDeclaration? Function(int uid) read;
  final int Function(int uid) revision;
  final void Function(DiscuzAvatarDeclaration declaration) publish;
  final DateTime Function() now;
  final int concurrency, capacity, queueCapacity;
  final Duration successTtl, failureTtl;
  final _checkedUntil = <int, ({DateTime until, int revision})>{};
  final _requests = <int, _AppearanceRequest>{};
  String? _scope;
  int _active = 0, _generation = 0;
  bool _drainScheduled = false;

  AvatarAppearanceLookup({
    required this.fetch,
    required this.currentScope,
    required this.read,
    required this.revision,
    required this.publish,
    DateTime Function()? now,
    this.concurrency = 2,
    this.capacity = 512,
    this.queueCapacity = 128,
    this.successTtl = const Duration(minutes: 30),
    this.failureTtl = const Duration(minutes: 1),
  }) : now = now ?? DateTime.now {
    assert(concurrency > 0 && capacity > 0 && queueCapacity > 0);
  }

  void useScope(String scope) {
    if (_scope == scope) return;
    _scope = scope;
    _generation++;
    _checkedUntil.clear();
    for (final request in _requests.values) {
      if (!request.completer.isCompleted) request.completer.complete(null);
    }
    _requests.clear();
  }

  /// The mobile plugin has already declared these avatar regions on this page;
  /// fetching a profile for each of its rows would duplicate the same evidence.
  void observed(int uid) {
    useScope(currentScope());
    if (uid <= 0) return;
    _cache(uid, successTtl);
    final request = _requests[uid];
    if (request != null && !request.started) {
      _requests.remove(uid);
      request.completer.complete(read(uid));
    }
  }

  Future<DiscuzAvatarDeclaration?> resolve(int uid) {
    useScope(currentScope());
    if (uid <= 0) return Future.value(null);
    final until = _checkedUntil[uid];
    if (until != null &&
        now().isBefore(until.until) &&
        until.revision == revision(uid)) {
      final expiry = _checkedUntil.remove(uid)!;
      _checkedUntil[uid] = expiry;
      return Future.value(read(uid));
    }
    // Declarations already supplied by a page/model need no cold-start query.
    if (until == null && read(uid)?.faceUrl != null) {
      observed(uid);
      return Future.value(read(uid));
    }
    final pending = _requests[uid];
    if (pending != null) return pending.completer.future;
    if (_requests.length >= queueCapacity) return Future.value(read(uid));
    final request =
        _AppearanceRequest(uid, _scope!, revision(uid), _generation);
    _requests[uid] = request;
    _scheduleDrain();
    return request.completer.future;
  }

  void _cache(int uid, Duration ttl) {
    _checkedUntil.remove(uid);
    _checkedUntil[uid] = (until: now().add(ttl), revision: revision(uid));
    while (_checkedUntil.length > capacity) {
      _checkedUntil.remove(_checkedUntil.keys.first);
    }
  }

  void _scheduleDrain() {
    if (_drainScheduled) return;
    _drainScheduled = true;
    scheduleMicrotask(() {
      _drainScheduled = false;
      useScope(currentScope());
      while (_active < concurrency) {
        final queued =
            _requests.values.where((request) => !request.started).firstOrNull;
        if (queued == null) break;
        queued.started = true;
        _active++;
        unawaited(_run(queued));
      }
    });
  }

  Future<void> _run(_AppearanceRequest request) async {
    DiscuzAvatarDeclaration? value;
    try {
      final result = await fetch(request.uid, request.scope);
      if (_isCurrent(request)) {
        if (result?.uid == request.uid) {
          if (revision(request.uid) == request.revision) publish(result!);
          _cache(request.uid, successTtl);
          value = read(request.uid);
        } else {
          _cache(request.uid, failureTtl);
        }
      }
    } catch (_) {
      if (_isCurrent(request)) _cache(request.uid, failureTtl);
    } finally {
      _active--;
      if (identical(_requests[request.uid], request)) {
        _requests.remove(request.uid);
      }
      if (!request.completer.isCompleted) request.completer.complete(value);
      _scheduleDrain();
    }
  }

  bool _isCurrent(_AppearanceRequest request) =>
      request.scope == currentScope() &&
      request.scope == _scope &&
      request.generation == _generation;
}
