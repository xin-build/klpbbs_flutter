import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:image/image.dart' as img;

enum AvatarImageFormat { jpeg, gif, apng }

class AvatarImageInspection {
  final int width, height, frames, loopCount;
  final AvatarImageFormat animationFormat;
  final Uint8List preview;
  const AvatarImageInspection(this.width, this.height, this.frames,
      this.loopCount, this.animationFormat, this.preview);
  bool get animated => frames > 1;
}

/// Coordinates are fractions of the available crop travel, after rotation.
class AvatarCrop {
  final double horizontal, vertical, zoom;
  final int quarterTurns;
  const AvatarCrop({
    this.horizontal = .5,
    this.vertical = .5,
    this.zoom = 1,
    this.quarterTurns = 0,
  });
}

class PreparedAvatar {
  final List<Uint8List> variants;
  final AvatarImageFormat format;
  final int frames, loopCount;
  final List<int> durations, sizes;
  final Uint8List preview;
  const PreparedAvatar(this.variants, this.format, this.frames, this.loopCount,
      this.durations, this.sizes, this.preview);
  bool get animated => frames > 1;
  int get byteLength =>
      variants.fold(0, (total, bytes) => total + bytes.length);
}

/// Image work runs off the UI isolate. Limits are checked from headers before
/// decoding the animation, and apply to both selecting and cropping a file.
class AvatarImageProcessor {
  static const maxFileBytes = 8 * 1024 * 1024;
  static const maxDimension = 4096, maxFrames = 120;
  static const maxDecodedPixels = 16 * 1024 * 1024;
  static const maxUploadBytes = 2 * 1024 * 1024;

  static Future<AvatarImageInspection> inspect(Uint8List bytes) =>
      Isolate.run(() => inspectSync(bytes));

  static Future<PreparedAvatar> prepare(Uint8List bytes, AvatarCrop crop,
          {bool keepAnimation = true}) =>
      Isolate.run(() => prepareSync(bytes, crop, keepAnimation: keepAnimation));

  static ({img.Image image, AvatarImageFormat format}) _decode(
      Uint8List bytes) {
    if (bytes.isEmpty || bytes.length > maxFileBytes) {
      throw const FormatException('请选择小于 8 MB 的头像图片');
    }
    final decoder = img.findDecoderForData(bytes);
    if (decoder == null ||
        !const {
          img.ImageFormat.jpg,
          img.ImageFormat.png,
          img.ImageFormat.gif,
          img.ImageFormat.webp
        }.contains(decoder.format)) {
      throw const FormatException('请选择 JPG、PNG、GIF、APNG 或 WebP 图片');
    }
    final info = decoder.startDecode(bytes);
    if (info == null || info.width < 1 || info.height < 1) {
      throw const FormatException('图片无法读取，请重新选择');
    }
    final frames = math.max(1, info.numFrames);
    if (info.width > maxDimension ||
        info.height > maxDimension ||
        frames > maxFrames ||
        info.width * info.height * frames > maxDecodedPixels) {
      throw const FormatException('图片尺寸或动画帧数过多，请先缩小图片');
    }
    final decoded = decoder.decode(bytes);
    if (decoded == null || decoded.numFrames != frames) {
      throw const FormatException('图片数据不完整，请重新选择');
    }
    // PngDecoder reads acTL.repeat but does not transfer it to decoded images.
    if (info is img.PngInfo) decoded.loopCount = info.repeat;
    // GIF frames can each have a different local palette. The image package's
    // animation crop/rotate helpers reuse the first frame's palette, so decode
    // every frame to RGBA before transforming it. This also lets downscaling
    // interpolate alpha rather than resizing palette indices.
    final oriented = _mapFrames(
        decoded,
        (frame) => img.bakeOrientation(frame).convert(
            format: img.Format.uint8, numChannels: 4, noAnimation: true));
    return (
      image: oriented,
      format: decoder.format == img.ImageFormat.png
          ? AvatarImageFormat.apng
          : AvatarImageFormat.gif
    );
  }

  static void _timing(img.Image destination, img.Image source) {
    destination.loopCount = source.loopCount;
    for (var index = 0; index < destination.numFrames; index++) {
      destination.frames[index].frameDuration =
          source.frames[index].frameDuration;
    }
  }

  static img.Image _mapFrames(
      img.Image source, img.Image Function(img.Image) transform) {
    img.Image? result;
    for (final frame in source.frames) {
      final transformed = transform(img.Image.from(frame, noAnimation: true));
      transformed.frameDuration = frame.frameDuration;
      transformed.loopCount = source.loopCount;
      if (result == null) {
        result = transformed;
      } else {
        result.addFrame(transformed);
      }
    }
    return result!;
  }

  static Uint8List _encodeGif(img.Image image) {
    final encoder = img.GifEncoder(repeat: image.loopCount);
    for (final frame in image.frames) {
      // GIF permits one fully transparent palette entry. The default RGBA
      // quantizer discards alpha, so reserve that entry explicitly. APNG data
      // never passes through this conversion and retains partial alpha.
      final quantizer = img.NeuralQuantizer(frame, numberOfColors: 255);
      final palette = img.PaletteUint8(256, 4);
      for (var index = 0; index < 255; index++) {
        palette.setRgba(
            index,
            quantizer.palette.getRed(index),
            quantizer.palette.getGreen(index),
            quantizer.palette.getBlue(index),
            255);
      }
      palette.setRgba(255, 0, 0, 0, 0);
      final indexed = img.Image(
          width: frame.width,
          height: frame.height,
          numChannels: 1,
          palette: palette);
      for (final pixel in frame) {
        indexed.setPixelIndex(pixel.x, pixel.y,
            pixel.a < 128 ? 255 : quantizer.getColorIndex(pixel));
      }
      encoder.addFrame(indexed, duration: frame.frameDuration ~/ 10);
    }
    return encoder.finish()!;
  }

  static Uint8List _encode(img.Image image, AvatarImageFormat format) {
    if (format == AvatarImageFormat.gif) return _encodeGif(image);
    if (format == AvatarImageFormat.apng) return img.encodePng(image);
    // Canvas JPEG uses an opaque backing. Alpha is flattened explicitly so a
    // transparent static image cannot acquire an unintended dark surround.
    final background = img.Image(width: image.width, height: image.height);
    img.fill(background, color: img.ColorRgb8(255, 255, 255));
    img.compositeImage(background, image.frames.first);
    return img.encodeJpg(background, quality: 92);
  }

  static AvatarImageInspection inspectSync(Uint8List bytes) {
    final decoded = _decode(bytes), source = decoded.image;
    final ratio = math.min(1.0, 512 / math.max(source.width, source.height));
    final preview = img.copyResize(source,
        width: math.max(1, (source.width * ratio).round()),
        height: math.max(1, (source.height * ratio).round()),
        interpolation: img.Interpolation.average);
    _timing(preview, source);
    return AvatarImageInspection(
        source.width,
        source.height,
        source.numFrames,
        source.loopCount,
        decoded.format,
        _encode(
            preview,
            source.hasAnimation
                ? AvatarImageFormat.gif
                : AvatarImageFormat.jpeg));
  }

  static PreparedAvatar prepareSync(Uint8List bytes, AvatarCrop crop,
      {bool keepAnimation = true}) {
    if (!crop.horizontal.isFinite ||
        !crop.vertical.isFinite ||
        !crop.zoom.isFinite ||
        crop.zoom < 1 ||
        crop.zoom > 4 ||
        crop.horizontal < 0 ||
        crop.horizontal > 1 ||
        crop.vertical < 0 ||
        crop.vertical > 1) {
      throw const FormatException('头像裁剪范围无效');
    }
    final decoded = _decode(bytes);
    var source = decoded.image;
    final animated = source.hasAnimation && keepAnimation;
    if (!animated) {
      source = img.Image.from(source.frames.first, noAnimation: true);
    }
    if (crop.quarterTurns % 4 != 0) {
      final rotated =
          img.copyRotate(source, angle: (crop.quarterTurns % 4) * 90);
      _timing(rotated, source);
      source = rotated;
    }
    final side = math.max(
        1, (math.min(source.width, source.height) / crop.zoom).floor());
    final cropped = img.copyCrop(source,
        x: ((source.width - side) * crop.horizontal).round(),
        y: ((source.height - side) * crop.vertical).round(),
        width: side,
        height: side);
    _timing(cropped, source);
    final format = animated ? decoded.format : AvatarImageFormat.jpeg;
    final variants = <Uint8List>[], sizes = <int>[];
    Uint8List? preview;
    for (final target in const [200, 120, 48]) {
      final size = math.min(side, target);
      final resized = img.copyResize(cropped,
          width: size, height: size, interpolation: img.Interpolation.average);
      _timing(resized, cropped);
      variants.add(_encode(resized, format));
      preview ??= format == AvatarImageFormat.apng
          ? _encode(resized, AvatarImageFormat.gif)
          : variants.last;
      sizes.add(size);
    }
    final result = PreparedAvatar(
        List.unmodifiable(variants),
        format,
        cropped.numFrames,
        cropped.loopCount,
        List.unmodifiable(cropped.frames.map((frame) => frame.frameDuration)),
        List.unmodifiable(sizes),
        preview!);
    if (result.byteLength > maxUploadBytes) {
      throw const FormatException('裁剪后的动画仍然过大，请减少帧数或使用静态头像');
    }
    return result;
  }
}
