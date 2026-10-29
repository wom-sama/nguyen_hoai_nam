// ignore_for_file: depend_on_referenced_packages

import 'package:camera/camera.dart';
import 'package:camera_platform_interface/camera_platform_interface.dart'
    as platform;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:nguyen_hoai_nam/core/api_client.dart';
import 'package:nguyen_hoai_nam/features/translation/camera_frame.dart';

CameraImage frame(
  List<platform.CameraImagePlane> planes, {
  ImageFormatGroup format = ImageFormatGroup.yuv420,
}) => CameraImage.fromPlatformInterface(
  platform.CameraImageData(
    format: platform.CameraImageFormat(
      format,
      raw: format == ImageFormatGroup.nv21 ? 17 : 35,
    ),
    planes: planes,
    height: 2,
    width: 4,
  ),
);
platform.CameraImagePlane plane(
  List<int> bytes,
  int stride, [
  int pixelStride = 1,
]) => platform.CameraImagePlane(
  bytes: Uint8List.fromList(bytes),
  bytesPerRow: stride,
  bytesPerPixel: pixelStride,
);
const rear = CameraDescription(
  name: '0',
  lensDirection: CameraLensDirection.back,
  sensorOrientation: 90,
);

void main() {
  test(
    'YUV planes honor row padding and chroma pixel strides when packing VU',
    () {
      final input = cameraFrameInput(
        frame([
          plane([1, 2, 3, 4, 99, 99, 5, 6, 7, 8], 6),
          plane([21, 99, 22], 4, 2),
          plane([31, 99, 32], 4, 2),
        ]),
        rear,
        DeviceOrientation.portraitUp,
      );
      expect(input.bytes, [1, 2, 3, 4, 5, 6, 7, 8, 31, 21, 32, 22]);
      expect(input.metadata!.format, InputImageFormat.nv21);
      expect(input.metadata!.bytesPerRow, 4);
      expect(input.filePath, isNull);
    },
  );
  test('one-plane NV21 is copied without retaining native buffer', () {
    final bytes = Uint8List.fromList(List.generate(12, (index) => index));
    final image = frame([
      platform.CameraImagePlane(bytes: bytes, bytesPerRow: 4),
    ], format: ImageFormatGroup.nv21);
    final input = cameraFrameInput(image, rear, DeviceOrientation.portraitUp);
    bytes[0] = 200;
    expect(input.bytes, List.generate(12, (index) => index));
  });
  test('one-plane NV21 removes padding from both luma and chroma rows', () {
    final input = cameraFrameInput(
      frame([
        plane([
          1,
          2,
          3,
          4,
          99,
          99,
          5,
          6,
          7,
          8,
          99,
          99,
          31,
          21,
          32,
          22,
          99,
          99,
        ], 6),
      ], format: ImageFormatGroup.nv21),
      rear,
      DeviceOrientation.portraitUp,
    );
    expect(input.bytes, [1, 2, 3, 4, 5, 6, 7, 8, 31, 21, 32, 22]);
  });
  test('CameraX one-plane NV21 remains readable when labelled yuv420', () {
    final input = cameraFrameInput(
      frame([plane(List.generate(12, (index) => index), 4)]),
      rear,
      DeviceOrientation.portraitUp,
    );
    expect(input.bytes, List.generate(12, (index) => index));
    expect(input.metadata!.format, InputImageFormat.nv21);
  });
  test('rear rotation compensates each device orientation', () {
    final image = frame([
      plane(List.filled(12, 0), 4),
    ], format: ImageFormatGroup.nv21);
    for (final pair in [
      (DeviceOrientation.portraitUp, InputImageRotation.rotation90deg),
      (DeviceOrientation.landscapeLeft, InputImageRotation.rotation0deg),
      (DeviceOrientation.portraitDown, InputImageRotation.rotation270deg),
      (DeviceOrientation.landscapeRight, InputImageRotation.rotation180deg),
    ]) {
      expect(
        cameraFrameInput(image, rear, pair.$1).metadata!.rotation,
        pair.$2,
      );
    }
  });
  test('front camera rotation adds device compensation', () {
    const front = CameraDescription(
      name: '1',
      lensDirection: CameraLensDirection.front,
      sensorOrientation: 270,
    );
    final image = frame([
      plane(List.filled(12, 0), 4),
    ], format: ImageFormatGroup.nv21);
    expect(
      cameraFrameInput(
        image,
        front,
        DeviceOrientation.portraitUp,
      ).metadata!.rotation,
      InputImageRotation.rotation270deg,
    );
    expect(
      cameraFrameInput(
        image,
        front,
        DeviceOrientation.landscapeLeft,
      ).metadata!.rotation,
      InputImageRotation.rotation0deg,
    );
  });
  test(
    'invalid plane buffers fail clearly instead of producing corrupt OCR',
    () {
      expect(
        () => cameraFrameInput(
          frame([
            plane([1], 4),
          ], format: ImageFormatGroup.nv21),
          rear,
          DeviceOrientation.portraitUp,
        ),
        throwsA(isA<ApiException>()),
      );
    },
  );
}
