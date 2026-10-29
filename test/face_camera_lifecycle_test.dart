// CameraPlatform is the camera plugin's existing platform testing API.
// ignore_for_file: depend_on_referenced_packages
import 'dart:async';

import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nguyen_hoai_nam/features/face/face_capture.dart';

class _Camera extends CameraPlatform {
  final errors = StreamController<CameraErrorEvent>.broadcast();
  final calls = <String>[];
  Completer<void>? gate;
  bool fail = false;
  int count = 0;
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
      const Stream.empty();
  @override
  Widget buildPreview(int id) =>
      ColoredBox(key: ValueKey('preview$id'), color: Colors.black);
  @override
  Future<void> dispose(int id) async {
    calls.add('dispose$id');
  }
}

Future<void> open(WidgetTester tester) async {
  await tester.pumpWidget(
    const MaterialApp(home: FaceCaptureScreen(enrolling: true)),
  );
  await tester.pump();
  await tester.pump();
}

void main() {
  late CameraPlatform previous;
  late _Camera camera;
  setUp(() {
    previous = CameraPlatform.instance;
    camera = _Camera();
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
