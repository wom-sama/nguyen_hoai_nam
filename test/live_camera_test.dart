// CameraPlatform is the camera plugin's existing native testing boundary.
// ignore_for_file: depend_on_referenced_packages
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:nguyen_hoai_nam/core/api_client.dart';
import 'package:nguyen_hoai_nam/core/session.dart';
import 'package:nguyen_hoai_nam/features/translation/live_camera_screen.dart';
import 'package:nguyen_hoai_nam/features/translation/translation_service.dart';
import 'package:nguyen_hoai_nam/ui/theme.dart';

class _Camera extends CameraPlatform {
  final errors = StreamController<CameraErrorEvent>.broadcast();
  final calls = <String>[];
  int count = 0, captures = 0;
  String? photoPath;
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
  }) async {}
  @override
  Future<void> setFlashMode(int id, FlashMode mode) async {}
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
  Future<XFile> takePicture(int id) async {
    captures++;
    return XFile(photoPath ?? 'nonexistent-camera-fixture-$captures.jpg');
  }

  @override
  Future<void> dispose(int id) async {
    calls.add('dispose$id');
  }
}

class _Translator extends TranslationService {
  int recognized = 0, translated = 0;
  Completer<void>? gate;
  @override
  Future<String> recognizePhoto(
    String path, {
    required String sourceLanguage,
  }) async {
    recognized++;
    return 'Xin chào';
  }

  @override
  Future<String> translate(
    String text, {
    required String sourceLanguage,
    required String targetLanguage,
  }) async {
    translated++;
    await gate?.future;
    return 'Hello';
  }
}

Future<void> flushFiles(WidgetTester tester) async {
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 30)),
  );
  await tester.pump();
}

http.Response reply(Object data, [int status = 200]) => http.Response(
  jsonEncode(data),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

void main() {
  late CameraPlatform previous;
  late _Camera camera;
  late _Translator translator;
  late SessionController session;
  final posts = <Map<String, dynamic>>[];
  final history = <Map<String, dynamic>>[];
  setUp(() {
    previous = CameraPlatform.instance;
    camera = _Camera();
    CameraPlatform.instance = camera;
    translator = _Translator();
    posts.clear();
    history.clear();
    session = SessionController(
      api: ApiClient(
        baseUrl: 'https://api.example.com',
        transport: MockClient((request) async {
          if (request.method == 'POST') {
            final body = jsonDecode(request.body) as Map<String, dynamic>;
            posts.add(body);
            if (posts.length == 1) {
              return reply({
                'error': {
                  'code': 'BUSY',
                  'message': 'Chưa lưu được. Hãy thử lại.',
                },
              }, 503);
            }
            return reply({
              'data': {
                ...body,
                'id': 'saved-camera-result',
                'createdAt': '2026-10-29T14:00:00Z',
              },
            }, 201);
          }
          return reply({'data': history});
        }),
      ),
    );
  });
  tearDown(() {
    CameraPlatform.instance = previous;
    session.dispose();
    session.api.close();
  });

  Future<void> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(600, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: session,
        child: MaterialApp(
          theme: appTheme(),
          home: LiveCameraScreen(
            sourceLanguage: 'vi',
            targetLanguage: 'en',
            translationService: translator,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  testWidgets(
    'camera samples one frame at a time and skips unchanged translation',
    (tester) async {
      translator.gate = Completer<void>();
      await open(tester);
      await tester.pump(const Duration(seconds: 5));
      expect(translator.recognized, 1);
      expect(translator.translated, 1);
      translator.gate!.complete();
      await tester.pump();
      await flushFiles(tester);
      await tester.pump(const Duration(milliseconds: 1500));
      await flushFiles(tester);
      expect(translator.recognized, 2);
      expect(translator.translated, 1);
      expect(find.text('Hello'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await flushFiles(tester);
    },
  );

  testWidgets('backgrounding releases camera and stops further frame capture', (
    tester,
  ) async {
    await open(tester);
    await flushFiles(tester);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    await flushFiles(tester);
    final before = camera.captures;
    await tester.pump(const Duration(seconds: 5));
    expect(camera.captures, before);
    expect(camera.calls, contains('dispose1'));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    await tester.pump();
    expect(
      camera.calls.indexOf('dispose1'),
      lessThan(camera.calls.indexOf('create2')),
    );
    await tester.pumpWidget(const SizedBox());
    await flushFiles(tester);
  });

  testWidgets(
    'retry saving frozen result reuses request id and sends text only',
    (tester) async {
      await open(tester);
      await flushFiles(tester);
      final save = find.byKey(const ValueKey('save-camera-translation'));
      await tester.ensureVisible(save);
      await tester.tap(save);
      await tester.pumpAndSettle();
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(posts, hasLength(2));
      expect(posts[0], posts[1]);
      expect(
        posts[0].keys,
        unorderedEquals([
          'clientRequestId',
          'sourceLanguage',
          'targetLanguage',
          'originalText',
          'translatedText',
        ]),
      );
      expect(posts[0]['originalText'], 'Xin chào');
      expect(posts[0]['translatedText'], 'Hello');
      expect(
        posts[0]['clientRequestId'],
        matches(
          RegExp(
            r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
          ),
        ),
      );
      expect(find.text('Đã lưu'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await flushFiles(tester);
    },
  );

  testWidgets('completed OCR removes the temporary camera image', (
    tester,
  ) async {
    final directory = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('live-camera-test-'),
    ))!;
    camera.photoPath = '${directory.path}/frame.jpg';
    await tester.runAsync(
      () => File(camera.photoPath!).writeAsBytes([1, 2, 3]),
    );
    await open(tester);
    await flushFiles(tester);
    expect(
      await tester.runAsync(() => File(camera.photoPath!).exists()),
      isFalse,
    );
    await tester.pumpWidget(const SizedBox());
    await flushFiles(tester);
    await tester.runAsync(() => directory.delete());
  });

  testWidgets(
    'saved history result is opened without saving or uploading a frame',
    (tester) async {
      history.add({
        'id': 'private-history-id',
        'sourceLanguage': 'en',
        'targetLanguage': 'vi',
        'originalText': 'Turn off the machine',
        'translatedText': 'Tắt máy',
        'createdAt': '2026-10-29T14:00:00Z',
      });
      await open(tester);
      await flushFiles(tester);
      await tester.tap(find.byTooltip('Bản dịch đã lưu'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Turn off the machine'));
      await tester.pumpAndSettle();
      expect(find.text('Tắt máy'), findsOneWidget);
      expect(find.text('private-history-id'), findsNothing);
      expect(find.text('Tạo bàn giao'), findsOneWidget);
      expect(posts, isEmpty);
      await tester.pumpWidget(const SizedBox());
      await flushFiles(tester);
    },
  );
}
