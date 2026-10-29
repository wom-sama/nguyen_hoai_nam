import 'package:flutter_test/flutter_test.dart';
import 'package:nguyen_hoai_nam/features/translation/speech_engine.dart';
import 'package:nguyen_hoai_nam/features/translation/speech_models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('Vietnamese and English-Chinese use distinct cache families', () {
    final vi = speechModelSetForLanguage('vi');
    final en = speechModelSetForLanguage('en');
    expect(identical(en, speechModelSetForLanguage('zh')), isTrue);
    expect(vi.cacheName, isNot(en.cacheName));
    expect(
      vi.assets.any((asset) => asset.fileName == 'model.int8.onnx'),
      isFalse,
    );
    expect(
      en.assets.any((asset) => asset.fileName == 'encoder.int8.onnx'),
      isFalse,
    );
  });
  test('first use downloads only the selected family plus its VAD', () {
    expect(speechModelSetForLanguage('vi').downloadBytes, 34564656);
    expect(speechModelSetForLanguage('en').downloadBytes, 82547881);
    for (final code in ['vi', 'en', 'zh']) {
      final assets = speechModelSetForLanguage(code).assets;
      expect(
        assets.where((asset) => asset.fileName == 'silero_vad.onnx').length,
        1,
      );
      expect(
        assets.map((asset) => asset.fileName).toSet().length,
        assets.length,
      );
      expect(
        assets.every((asset) => Uri.parse(asset.url).scheme == 'https'),
        isTrue,
      );
    }
  });
  test('unsupported language cannot select arbitrary model files', () {
    expect(() => speechModelSetForLanguage('../en'), throwsArgumentError);
  });
  test(
    'unsupported prepare fails before model or microphone resources',
    () async {
      final engine = ContinuousSpeechEngine();
      await expectLater(
        engine.prepare(languageCode: 'xx'),
        throwsA(isA<SpeechEngineException>()),
      );
      expect((await engine.states.first).phase, 'idle');
      await engine.dispose();
    },
  );
}
