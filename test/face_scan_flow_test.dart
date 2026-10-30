// Uses the installed camera plugin's existing platform test API.
// ignore_for_file: depend_on_referenced_packages
import 'dart:async';
import 'dart:convert';

import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nguyen_hoai_nam/features/face/face_capture.dart';
import 'package:nguyen_hoai_nam/features/face/face_scan.dart';

import 'face_camera_lifecycle_test.dart' show FaceCameraFixture;

class _Scanner implements FaceScanner {
  final inputs = <InputImage>[];
  Completer<List<FaceScanObservation>>? pending;
  int closed = 0;
  @override
  Future<List<FaceScanObservation>> scan(InputImage image) async {
    inputs.add(image);
    if (pending != null) return pending!.future;
    return oneFace(image);
  }

  @override
  Future<void> close() async {
    closed++;
  }
}

List<FaceScanObservation> oneFace(InputImage image) {
  final size = uprightFaceFrameSize(image);
  return [
    FaceScanObservation(
      bounds: Rect.fromLTWH(
        size.width * .25,
        size.height * .25,
        size.width * .5,
        size.height * .5,
      ),
      yaw: 0,
      pitch: 0,
      roll: 0,
      trackingId: 1,
      eyesVisible: true,
    ),
  ];
}

void main() {
  late CameraPlatform previous;
  late FaceCameraFixture camera;
  late _Scanner scanner;
  late Duration at;
  late int returns;
  String? result;
  setUp(() {
    previous = CameraPlatform.instance;
    camera = FaceCameraFixture()..emitInitial = false;
    CameraPlatform.instance = camera;
    scanner = _Scanner();
    at = Duration.zero;
    returns = 0;
    result = null;
  });
  tearDown(() {
    CameraPlatform.instance = previous;
  });

  Future<void> open(WidgetTester tester, FaceScanEncoder encode) async {
    tester.view.physicalSize = const Size(430, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                result = await Navigator.push<String>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => FaceCaptureScreen(
                      enrolling: false,
                      scanner: scanner,
                      scanTime: () => at,
                      encodeFrame: encode,
                    ),
                  ),
                );
                returns++;
              },
              child: const Text('Mở quét'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Mở quét'));
    await tester.pumpAndSettle();
  }

  Future<void> frame(
    WidgetTester tester,
    int milliseconds,
    int luminance,
  ) async {
    at = Duration(milliseconds: milliseconds);
    camera.emitFrame(luminance);
    await tester.pump();
    await tester.pump();
  }

  testWidgets(
    'automatically captures the exact accepted owned frame once, without a shutter button',
    (tester) async {
      InputImage? encoded;
      final encoding = Completer<Uint8List>();
      await open(tester, (image) {
        encoded = image;
        return encoding.future;
      });
      expect(find.text('Chụp và tiếp tục'), findsNothing);
      await frame(tester, 0, 140);
      await frame(tester, 100, 199);
      expect(scanner.inputs, hasLength(1));
      await frame(tester, 350, 141);
      expect(encoded, isNull);
      await frame(tester, 700, 142);
      expect(encoded, same(scanner.inputs.last));
      expect(encoded!.bytes!.first, 142);
      await frame(tester, 1050, 143);
      expect(scanner.inputs, hasLength(3));
      encoding.complete(Uint8List.fromList([1, 2, 3]));
      await tester.pumpAndSettle();
      expect(result, base64Encode([1, 2, 3]));
      expect(returns, 1);
      expect(find.byType(FaceCaptureScreen, skipOffstage: false), findsNothing);
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pumpAndSettle();
      expect(scanner.closed, 1, reason: camera.calls.join(', '));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'only one analysis runs; cancel waits to close scanner and never encodes or returns a late photo',
    (tester) async {
      var encodings = 0;
      scanner.pending = Completer<List<FaceScanObservation>>();
      await open(tester, (_) async {
        encodings++;
        return Uint8List(1);
      });
      final original = camera.emitFrame(140);
      await tester.pump();
      original[0] = 10;
      expect(scanner.inputs.single.bytes!.first, 140);
      await frame(tester, 350, 141);
      await frame(tester, 700, 142);
      expect(scanner.inputs, hasLength(1));
      final cancel = find.text('Hủy quét');
      await tester.ensureVisible(cancel);
      await tester.tap(cancel);
      await tester.pumpAndSettle();
      expect(scanner.closed, 0);
      scanner.pending!.complete(oneFace(scanner.inputs.single));
      await tester.pumpAndSettle();
      expect(find.byType(FaceCaptureScreen, skipOffstage: false), findsNothing);
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pumpAndSettle();
      expect(scanner.closed, 1, reason: camera.calls.join(', '));
      expect(encodings, 0);
      expect(result, isNull);
      expect(returns, 1);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'pause/resume resets hold and disposes before replacement, then captures only after a new hold',
    (tester) async {
      var encodings = 0;
      await open(tester, (_) async {
        encodings++;
        return Uint8List.fromList([9]);
      });
      await frame(tester, 0, 140);
      await frame(tester, 350, 140);
      scanner.pending = Completer<List<FaceScanObservation>>();
      await frame(tester, 700, 140);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(camera.count, 1);
      expect(encodings, 0);
      scanner.pending!.complete(oneFace(scanner.inputs.last));
      scanner.pending = null;
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pumpAndSettle();
      expect(camera.calls, [
        'create1',
        'init1',
        'dispose1',
        'create2',
        'init2',
      ]);
      await frame(tester, 1050, 140);
      await frame(tester, 1400, 140);
      expect(encodings, 0);
      await frame(tester, 1750, 140);
      await tester.pumpAndSettle();
      expect(encodings, 1);
      expect(returns, 1);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'orientation changes invalidate pending detection even if the phone returns before the next frame',
    (tester) async {
      var encodings = 0;
      scanner.pending = Completer<List<FaceScanObservation>>();
      await open(tester, (_) async {
        encodings++;
        return Uint8List.fromList([9]);
      });
      await frame(tester, 0, 140);
      final pending = scanner.pending!;
      camera.orientations.add(
        const DeviceOrientationChangedEvent(DeviceOrientation.landscapeLeft),
      );
      camera.orientations.add(
        const DeviceOrientationChangedEvent(DeviceOrientation.portraitUp),
      );
      pending.complete(oneFace(scanner.inputs.single));
      scanner.pending = null;
      await tester.pumpAndSettle();
      expect(encodings, 0);
      await frame(tester, 700, 140);
      await frame(tester, 1050, 140);
      expect(encodings, 0);
      await frame(tester, 1400, 140);
      await tester.pumpAndSettle();
      expect(encodings, 1);
      expect(returns, 1);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
