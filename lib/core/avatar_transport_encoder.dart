import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';

/// Encodes the cropper's three image fields without blocking the UI isolate.
/// Authentication, the declared endpoint and the fresh formhash remain the
/// caller's responsibility; this helper has no network or account state.
class AvatarTransportEncoder {
  AvatarTransportEncoder._();

  static const defaultMaxSourceBytes = 2 * 1024 * 1024;

  static Future<Map<String, String>> encode(
    List<Uint8List> variants, {
    required bool useBase64,
    int maxSourceBytes = defaultMaxSourceBytes,
  }) async {
    _validate(variants, maxSourceBytes);
    // The caller may change selection or dispose the page while encoding.
    // Snapshot the bounded input so later mutations cannot change the payload.
    final snapshot = variants.map(Uint8List.fromList).toList(growable: false);
    return Isolate.run(() => encodeSync(snapshot,
        useBase64: useBase64, maxSourceBytes: maxSourceBytes));
  }

  static Map<String, String> encodeSync(
    List<Uint8List> variants, {
    required bool useBase64,
    int maxSourceBytes = defaultMaxSourceBytes,
  }) {
    _validate(variants, maxSourceBytes);
    return Map.unmodifiable({
      for (var index = 0; index < variants.length; index++)
        'avatar${index + 1}':
            useBase64 ? base64Encode(variants[index]) : _hex(variants[index]),
    });
  }

  static void _validate(List<Uint8List> variants, int maxSourceBytes) {
    if (maxSourceBytes < 1) {
      throw ArgumentError.value(maxSourceBytes, 'maxSourceBytes');
    }
    if (variants.length != 3 || variants.any((bytes) => bytes.isEmpty)) {
      throw const FormatException('头像需要三份有效的裁剪图片');
    }
    var length = 0;
    for (final bytes in variants) {
      length += bytes.length;
      if (length > maxSourceBytes) {
        throw const FormatException('头像图片过大，请减少帧数或使用静态头像');
      }
    }
  }

  static String _hex(Uint8List bytes) {
    const digits = [
      48,
      49,
      50,
      51,
      52,
      53,
      54,
      55,
      56,
      57,
      65,
      66,
      67,
      68,
      69,
      70,
    ];
    final output = Uint8List(bytes.length * 2);
    for (var index = 0; index < bytes.length; index++) {
      final value = bytes[index];
      output[index * 2] = digits[value >> 4];
      output[index * 2 + 1] = digits[value & 15];
    }
    return ascii.decode(output);
  }
}
