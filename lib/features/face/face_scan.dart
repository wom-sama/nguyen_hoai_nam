import 'dart:typed_data';
import 'dart:ui';

import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

import 'face_scan_gate.dart';
export 'face_scan_gate.dart';

export 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart'
    show InputImage;

typedef FaceScanEncoder = Future<Uint8List> Function(InputImage image);

abstract class FaceScanner {
  Future<List<FaceScanObservation>> scan(InputImage image);
  Future<void> close();
}

class MlKitFaceScanner implements FaceScanner {
  final FaceDetector _detector = FaceDetector(
    options: FaceDetectorOptions(
      // The plugin guarantees Euler Y only in accurate mode; the framing gate
      // requires this pose value. Calls remain throttled with one in flight.
      performanceMode: FaceDetectorMode.accurate,
      enableLandmarks: true,
      enableTracking: true,
      minFaceSize: .1,
    ),
  );

  @override
  Future<List<FaceScanObservation>> scan(InputImage image) async => [
    for (final face in await _detector.processImage(image))
      FaceScanObservation(
        bounds: face.boundingBox,
        yaw: face.headEulerAngleY,
        pitch: face.headEulerAngleX,
        roll: face.headEulerAngleZ,
        trackingId: face.trackingId,
        eyesVisible:
            face.landmarks[FaceLandmarkType.leftEye] != null &&
            face.landmarks[FaceLandmarkType.rightEye] != null,
      ),
  ];

  @override
  Future<void> close() => _detector.close();
}

Size uprightFaceFrameSize(InputImage image) {
  final meta = image.metadata!;
  final degrees = meta.rotation.rawValue;
  return degrees == 90 || degrees == 270
      ? Size(meta.size.height, meta.size.width)
      : meta.size;
}
