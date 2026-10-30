import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import '../../core/api_client.dart';

/// Decode at bounded dimensions; PNG encoding strips EXIF and other metadata.
Future<String> prepareSettingsImage(
  Uint8List bytes, {
  required bool avatar,
}) async {
  if (bytes.length > 15 * 1024 * 1024) {
    throw const ApiException(
      'IMAGE_SIZE',
      'Ảnh quá lớn. Vui lòng chọn ảnh nhỏ hơn.',
    );
  }
  final maxDimension = avatar ? 512 : 1200;
  final maxBytes = (avatar ? 300 : 650) * 1024;
  final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
  ui.ImageDescriptor? descriptor;
  try {
    descriptor = await ui.ImageDescriptor.encoded(buffer);
    var ratio = math.min(
      1.0,
      maxDimension / math.max(descriptor.width, descriptor.height),
    );
    for (var attempt = 0; attempt < 8; attempt++) {
      final codec = await descriptor.instantiateCodec(
        targetWidth: math.max(1, (descriptor.width * ratio).round()),
        targetHeight: math.max(1, (descriptor.height * ratio).round()),
      );
      try {
        final frame = await codec.getNextFrame();
        try {
          final data = await frame.image.toByteData(
            format: ui.ImageByteFormat.png,
          );
          if (data != null && data.lengthInBytes <= maxBytes) {
            return base64Encode(
              data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
            );
          }
        } finally {
          frame.image.dispose();
        }
      } finally {
        codec.dispose();
      }
      ratio *= .75;
    }
    throw const ApiException(
      'IMAGE_SIZE',
      'Chưa thu nhỏ được ảnh. Vui lòng chọn ảnh khác.',
    );
  } finally {
    descriptor?.dispose();
    buffer.dispose();
  }
}
