import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nguyen_hoai_nam/core/api_client.dart';
import 'package:nguyen_hoai_nam/features/translation/translation_service.dart';

class _Translator extends TranslationService {
  final calls = <String>[];
  @override
  Future<String> translate(
    String text, {
    required String sourceLanguage,
    required String targetLanguage,
  }) async {
    calls.add('$sourceLanguage/$targetLanguage/$text');
    return '$targetLanguage:$text';
  }
}

OcrPage page(Rect bounds, {String text = 'Hello'}) => OcrPage(
  text: text,
  regions: [OcrRegion(text: text, bounds: bounds)],
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('photo OCR receives precisely the displayed bitmap pixels with no file path', () async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawRect(
      const Rect.fromLTWH(0, 0, 1, 1),
      Paint()..color = const Color(0xFFFF0000),
    );
    canvas.drawRect(
      const Rect.fromLTWH(1, 0, 1, 1),
      Paint()..color = const Color(0xFF00FF00),
    );
    final picture = recorder.endRecording();
    final bitmap = await picture.toImage(2, 1);
    picture.dispose();
    final calls = <MethodCall>[];
    const channel = MethodChannel('google_mlkit_text_recognizer');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          if (call.method == 'vision#closeTextRecognizer') return null;
          return {
            'text': 'Hello',
            'blocks': [
              {
                'text': 'Hello',
                'rect': {'left': 0, 'top': 0, 'right': 2, 'bottom': 1},
                'points': [
                  {'x': 0, 'y': 0},
                  {'x': 2, 'y': 0},
                  {'x': 2, 'y': 1},
                  {'x': 0, 'y': 1},
                ],
                'recognizedLanguages': ['en'],
                'lines': [],
              },
            ],
          };
        });
    final service = TranslationService();
    try {
      final recognized = await service.recognizeBitmap(
        bitmap,
        sourceLanguage: 'en',
      );
      final image = (calls.first.arguments as Map)['imageData'] as Map;
      expect(image['type'], 'bitmap');
      expect(image['path'], isNull);
      expect(image['rotation'], 0);
      expect(image['bitmapData'], [255, 0, 0, 255, 0, 255, 0, 255]);
      expect(recognized.regions.single.bounds, const Rect.fromLTWH(0, 0, 2, 1));
      expect(calls.last.method, 'vision#closeTextRecognizer');
    } finally {
      bitmap.dispose();
      await service.dispose();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    }
  });

  test(
    'unchanged text reuses translation but keeps new OCR coordinates',
    () async {
      final translator = _Translator();
      final first = await translator.translatePage(
        page(const Rect.fromLTWH(10, 20, 100, 40)),
        sourceLanguage: 'en',
        targetLanguage: 'vi',
      );
      final moved = await translator.translatePage(
        page(const Rect.fromLTWH(80, 90, 100, 40)),
        sourceLanguage: 'en',
        targetLanguage: 'vi',
      );
      expect(translator.calls, hasLength(1));
      expect(first.regions.single.bounds.left, 10);
      expect(moved.regions.single.bounds.left, 80);
      expect(moved.translatedText, 'vi:Hello');
      await translator.dispose();
    },
  );

  test(
    'an empty spatial OCR result never reuses earlier translated labels',
    () async {
      final translator = _Translator();
      await expectLater(
        translator.translatePage(
          OcrPage(text: '', regions: const []),
          sourceLanguage: 'en',
          targetLanguage: 'vi',
        ),
        throwsA(
          isA<ApiException>().having(
            (error) => error.code,
            'code',
            'OCR_EMPTY',
          ),
        ),
      );
      expect(translator.calls, isEmpty);
      await translator.dispose();
    },
  );

  test(
    'cache evicts older entries and clears when the language pair changes',
    () async {
      final translator = _Translator();
      for (var index = 0; index < 70; index++) {
        await translator.translatePage(
          page(const Rect.fromLTWH(0, 0, 50, 20), text: 'Text $index'),
          sourceLanguage: 'en',
          targetLanguage: 'vi',
        );
      }
      await translator.translatePage(
        page(const Rect.fromLTWH(0, 0, 50, 20), text: 'Text 0'),
        sourceLanguage: 'en',
        targetLanguage: 'vi',
      );
      expect(translator.calls, hasLength(71));
      await translator.translatePage(
        page(const Rect.fromLTWH(0, 0, 50, 20), text: 'Text 0'),
        sourceLanguage: 'en',
        targetLanguage: 'zh',
      );
      await translator.translatePage(
        page(const Rect.fromLTWH(0, 0, 50, 20), text: 'Text 0'),
        sourceLanguage: 'en',
        targetLanguage: 'vi',
      );
      expect(translator.calls, hasLength(73));
      await translator.dispose();
    },
  );
}
