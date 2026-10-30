// CameraPlatform is the camera plugin's existing platform testing API.
// ignore_for_file: depend_on_referenced_packages
import 'dart:async';
import 'dart:typed_data';

import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nguyen_hoai_nam/features/face/face_capture.dart';
import 'package:nguyen_hoai_nam/features/face/face_scan.dart';

class FaceCameraFixture extends CameraPlatform {
  final errors = StreamController<CameraErrorEvent>.broadcast();
  final frames = StreamController<CameraImageData>.broadcast(sync: true);
  final orientations =
      StreamController<DeviceOrientationChangedEvent>.broadcast(sync: true);
  bool emitInitial = true;
  final calls = <String>[];
  Completer<void>? gate;
  bool fail = false;
  int count = 0;
  @override
  bool supportsImageStreaming() => true;
  @override
  Future<List<CameraDescription>> availableCameras() async => [
    const CameraDescription(
      name: '0',
      lensDirection: CameraLensDirection.back,
      sensorOrientation: 90,
    ),
  ];
  @override
  Future<int> createCameraWithSettings(
    CameraDescription description,
    MediaSettings? settings,
  ) async {
    calls.add('create${++count}');
    return count;
  }

  @override
  Future<void> initializeCamera(
    int id, {
    ImageFormatGroup imageFormatGroup = ImageFormatGroup.unknown,
  }) async {
    calls.add('init$id');
    if (fail) throw CameraException('fixture', 'init failed');
    await gate?.future;
  }

  @override
  Stream<CameraInitializedEvent> onCameraInitialized(int id) => Stream.value(
    CameraInitializedEvent(
      id,
      640,
      480,
      ExposureMode.auto,
      true,
      FocusMode.auto,
      true,
    ),
  );
  @override
  Stream<CameraErrorEvent> onCameraError(int id) => errors.stream;
  @override
  Stream<DeviceOrientationChangedEvent> onDeviceOrientationChanged() =>
      orientations.stream;
  @override
  Stream<CameraImageData> onStreamedFrameAvailable(
    int id, {
    CameraImageStreamOptions? options,
  }) => !emitInitial
      ? frames.stream
      : Stream.value(
          CameraImageData(
            format: const CameraImageFormat(ImageFormatGroup.nv21, raw: 17),
            planes: [
              CameraImagePlane(
                bytes: Uint8List.fromList([16, 235, 16, 235, 128, 128]),
                bytesPerRow: 2,
                bytesPerPixel: 1,
              ),
            ],
            height: 2,
            width: 2,
          ),
        );

  Uint8List emitFrame(int luminance) {
    final bytes = Uint8List(640 * 480 * 3 ~/ 2);
    bytes.fillRange(0, 640 * 480, luminance);
    bytes.fillRange(640 * 480, bytes.length, 128);
    frames.add(
      CameraImageData(
        format: const CameraImageFormat(ImageFormatGroup.nv21, raw: 17),
        planes: [
          CameraImagePlane(bytes: bytes, bytesPerRow: 640, bytesPerPixel: 1),
        ],
        width: 640,
        height: 480,
      ),
    );
    return bytes;
  }

  @override
  Widget buildPreview(int id) =>
      ColoredBox(key: ValueKey('preview$id'), color: Colors.black);
  @override
  Future<void> dispose(int id) async {
    calls.add('dispose$id');
  }
}

class _NoFaces implements FaceScanner {
  @override
  Future<List<FaceScanObservation>> scan(InputImage image) async => [];
  @override
  Future<void> close() async {}
}

Future<void> open(WidgetTester tester) async {
  await tester.pumpWidget(
    MaterialApp(home: FaceCaptureScreen(enrolling: true, scanner: _NoFaces())),
  );
  await tester.pump();
  await tester.pump();
}

void main() {
  late CameraPlatform previous;
  late FaceCameraFixture camera;
  setUp(() {
    previous = CameraPlatform.instance;
    camera = FaceCameraFixture();
    CameraPlatform.instance = camera;
  });
  tearDown(() {
    CameraPlatform.instance = previous;
  });
  testWidgets(
    'permission lifecycle bounce does not initialize a second controller',
    (tester) async {
      camera.gate = Completer<void>();
      await open(tester);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(camera.count, 1);
      camera.gate!.complete();
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('preview1')), findsOneWidget);
      expect(camera.calls, ['create1', 'init1']);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    },
  );
  testWidgets('resuming disposes old controller before creating next', (
    tester,
  ) async {
    await open(tester);
    await tester.pumpAndSettle();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pumpAndSettle();
    expect(camera.calls, ['create1', 'init1', 'dispose1', 'create2', 'init2']);
    expect(find.byKey(const ValueKey('preview2')), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });
  testWidgets('failed local controller is disposed before retry', (
    tester,
  ) async {
    camera.fail = true;
    await open(tester);
    await tester.pumpAndSettle();
    expect(camera.calls, ['create1', 'init1', 'dispose1']);
    camera.fail = false;
    await tester.tap(find.text('Thử mở lại camera'));
    await tester.pumpAndSettle();
    expect(camera.calls, ['create1', 'init1', 'dispose1', 'create2', 'init2']);
    expect(find.byKey(const ValueKey('preview2')), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });
}
