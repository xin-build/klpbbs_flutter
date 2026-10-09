import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../core/pc_gpu_policy.dart';
export '../core/pc_gpu_policy.dart';

class PcGpuService {
  PcGpuService({MethodChannel methodChannel = channel})
      : _channel = methodChannel;
  static final PcGpuService instance = PcGpuService();
  static const channelName = 'klpbbs/pc_gpu';
  static const channel = MethodChannel(channelName);
  final MethodChannel _channel;
  static bool get supportedPlatform => !kIsWeb && Platform.isWindows;

  Future<PcGpuSnapshot> _status(String method,
      [Map<String, Object?>? arguments]) async {
    if (!supportedPlatform) throw StateError('显卡偏好仅支持 Windows 客户端');
    try {
      final result =
          await _channel.invokeMapMethod<Object?, Object?>(method, arguments);
      if (result == null) throw const FormatException('GPU response is empty');
      return PcGpuSnapshot.fromMap(result);
    } on MissingPluginException {
      throw StateError('此版本尚未提供 Windows 显卡接口，请更新客户端后重试');
    } on PlatformException catch (error) {
      throw StateError(error.message ?? '本机显卡设置未能完成（${error.code}）');
    }
  }

  Future<PcGpuSnapshot> read() => _status('getStatus');
  Future<PcGpuSnapshot> save(PcGpuPreference preference) async {
    final snapshot =
        await _status('savePreference', {'preference': preference.wire});
    snapshot.confirmSavedPreference(preference);
    return snapshot;
  }

  Future<void> openWindowsGraphicsSettings() async {
    if (!supportedPlatform) throw StateError('仅 Windows 支持系统图形设置');
    try {
      final opened =
          await _channel.invokeMethod<bool>('openWindowsGraphicsSettings');
      if (opened != true) throw StateError('Windows 图形设置未能打开');
    } on PlatformException catch (error) {
      throw StateError(error.message ?? 'Windows 图形设置未能打开');
    } on MissingPluginException {
      throw StateError('此版本尚未提供 Windows 系统设置入口');
    }
  }
}
