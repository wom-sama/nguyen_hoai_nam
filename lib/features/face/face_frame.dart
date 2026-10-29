import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

/// Encode the selected, owned NV21 frame without a native still-capture request.
Future<Uint8List> faceFramePng(InputImage frame) async {
  final meta = frame.metadata!, bytes = frame.bytes!;
  final width = meta.size.width.toInt(), height = meta.size.height.toInt();
  final rotation = meta.rotation.rawValue;
  final rotated = rotation == 90 || rotation == 270;
  final outWidth = rotated ? height : width;
  final outHeight = rotated ? width : height;
  final rgba = Uint8List(width * height * 4);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final chroma = width * height + (y ~/ 2) * width + (x & ~1);
      final luminance = (bytes[y * width + x] - 16).clamp(0, 255).toInt();
      final v = bytes[chroma] - 128, u = bytes[chroma + 1] - 128;
      final (dx, dy) = switch (rotation) {
        90 => (height - 1 - y, x),
        180 => (width - 1 - x, height - 1 - y),
        270 => (y, width - 1 - x),
        _ => (x, y),
      };
      final at = (dy * outWidth + dx) * 4;
      rgba[at] = ((298 * luminance + 409 * v + 128) >> 8).clamp(0, 255).toInt();
      rgba[at + 1] = ((298 * luminance - 100 * u - 208 * v + 128) >> 8)
          .clamp(0, 255)
          .toInt();
      rgba[at + 2] = ((298 * luminance + 516 * u + 128) >> 8)
          .clamp(0, 255)
          .toInt();
      rgba[at + 3] = 255;
    }
  }
  final decoded = Completer<ui.Image>();
  ui.decodeImageFromPixels(
    rgba,
    outWidth,
    outHeight,
    ui.PixelFormat.rgba8888,
    decoded.complete,
  );
  final image = await decoded.future;
  try {
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    if (png == null) throw const FormatException('Frame encoding failed');
    return png.buffer.asUint8List(png.offsetInBytes, png.lengthInBytes);
  } finally {
    image.dispose();
  }
}
