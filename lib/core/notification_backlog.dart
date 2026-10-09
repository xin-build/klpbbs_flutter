import 'dart:async';
import 'dart:collection';

/// 应用启动时 UI 还没有订阅，事件先暂存；只交给第一位订阅者一次。
class NotificationBacklog<T> {
  final _pending = Queue<T>();
  late final StreamController<T> _controller = StreamController<T>.broadcast(onListen: _flush);
  final int capacity;
  NotificationBacklog({this.capacity = 8});

  Stream<T> get stream => _controller.stream;
  void add(T message) {
    if (_controller.isClosed) return;
    if (_controller.hasListener) { _controller.add(message); return; }
    if (_pending.length >= capacity) _pending.removeFirst();
    _pending.addLast(message);
  }
  void _flush() {
    scheduleMicrotask(() {
      while (_controller.hasListener && _pending.isNotEmpty && !_controller.isClosed) {
        _controller.add(_pending.removeFirst());
      }
    });
  }
  void clear() => _pending.clear();
  Future<void> close() async { _pending.clear(); await _controller.close(); }
}
