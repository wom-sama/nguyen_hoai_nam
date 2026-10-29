import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:nguyen_hoai_nam/features/face/face_frame.dart';

void main() {
  testWidgets(
    'a selected NV21 frame becomes an upright PNG with preserved pixels',
    (tester) async {
      final frame = InputImage.fromBytes(
        bytes: Uint8List.fromList([
          16,
          235,
          16,
          235,
          16,
          235,
          16,
          235,
          128,
          128,
          128,
          128,
        ]),
        metadata: InputImageMetadata(
          size: const ui.Size(4, 2),
          rotation: InputImageRotation.rotation90deg,
          format: InputImageFormat.nv21,
          bytesPerRow: 4,
        ),
      );
      await tester.runAsync(() async {
        final png = await faceFramePng(frame);
        expect(png.take(8), [137, 80, 78, 71, 13, 10, 26, 10]);
        final codec = await ui.instantiateImageCodec(png);
        final decoded = await codec.getNextFrame();
        expect(decoded.image.width, 2);
        expect(decoded.image.height, 4);
        final rgba = (await decoded.image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        ))!.buffer.asUint8List();
        expect(rgba.take(8), [0, 0, 0, 255, 0, 0, 0, 255]);
        expect(rgba.skip(8).take(4), [255, 255, 255, 255]);
        decoded.image.dispose();
        codec.dispose();
      });
    },
  );
}
