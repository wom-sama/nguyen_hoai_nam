import 'package:camera/camera.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import '../../core/api_client.dart';

/// Creates an owned, tightly packed Android NV21 buffer for ML Kit.
/// CameraX can label a requested one-plane NV21 frame as yuv420.
InputImage cameraFrameInput(
  CameraImage image,
  CameraDescription camera,
  DeviceOrientation orientation,
) {
  const orientations = {
    DeviceOrientation.portraitUp: 0,
    DeviceOrientation.landscapeLeft: 90,
    DeviceOrientation.portraitDown: 180,
    DeviceOrientation.landscapeRight: 270,
  };
  final compensation = orientations[orientation]!;
  final degrees = camera.lensDirection == CameraLensDirection.front
      ? (camera.sensorOrientation + compensation) % 360
      : (camera.sensorOrientation - compensation + 360) % 360;
  final rotation = InputImageRotationValue.fromRawValue(degrees);
  final width = image.width, height = image.height;
  if (rotation == null ||
      width <= 0 ||
      height <= 0 ||
      width.isOdd ||
      height.isOdd ||
      (image.format.group != ImageFormatGroup.nv21 &&
          image.format.group != ImageFormatGroup.yuv420)) {
    throw _unsupported();
  }
  final bytes = Uint8List(width * height * 3 ~/ 2);
  var output = 0;
  if (image.planes.length == 1) {
    final plane = image.planes.single;
    if (plane.bytesPerRow < width) throw _unsupported();
    for (var row = 0; row < height + height ~/ 2; row++) {
      final start = row * plane.bytesPerRow;
      if (start + width > plane.bytes.length) throw _unsupported();
      bytes.setRange(output, output + width, plane.bytes, start);
      output += width;
    }
  } else if (image.planes.length == 3) {
    final y = image.planes[0], u = image.planes[1], v = image.planes[2];
    for (final entry in [(y, width), (u, width ~/ 2), (v, width ~/ 2)]) {
      if (entry.$1.bytesPerRow <
          (entry.$2 - 1) * (entry.$1.bytesPerPixel ?? 1) + 1) {
        throw _unsupported();
      }
    }
    int sample(Plane plane, int row, int column) {
      final stride = plane.bytesPerPixel ?? 1;
      final index = row * plane.bytesPerRow + column * stride;
      if (stride <= 0 ||
          plane.bytesPerRow <= 0 ||
          index < 0 ||
          index >= plane.bytes.length) {
        throw _unsupported();
      }
      return plane.bytes[index];
    }

    for (var row = 0; row < height; row++) {
      for (var column = 0; column < width; column++) {
        bytes[output++] = sample(y, row, column);
      }
    }
    for (var row = 0; row < height ~/ 2; row++) {
      for (var column = 0; column < width ~/ 2; column++) {
        bytes[output++] = sample(v, row, column);
        bytes[output++] = sample(u, row, column);
      }
    }
  } else {
    throw _unsupported();
  }
  return InputImage.fromBytes(
    bytes: bytes,
    metadata: InputImageMetadata(
      size: Size(width.toDouble(), height.toDouble()),
      rotation: rotation,
      format: InputImageFormat.nv21,
      bytesPerRow: width,
    ),
  );
}

ApiException _unsupported() => const ApiException(
  'CAMERA_FRAME_UNSUPPORTED',
  'Chưa đọc được hình ảnh từ camera trên thiết bị này. Hãy thử lại hoặc chọn ảnh để dịch.',
);
