import 'package:flutter_test/flutter_test.dart';
import 'package:nguyen_hoai_nam/features/translation/speech_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('an idle engine can be observed and disposed without opening a microphone', () async {
    // There is deliberately no fake recorder or native method handler here.
    // Construction/idle disposal must not require any platform microphone API.
    final engine = ContinuousSpeechEngine();
    final initial = await engine.states.first;
    expect(initial.phase, 'idle');
    expect(initial.queuedSegments, 0);
    await expectLater(engine.dispose(), completes);
    await expectLater(engine.dispose(), completes);
  });

  test(
    'rejects unsupported source languages before loading native resources',
    () async {
      final engine = ContinuousSpeechEngine();
      await expectLater(
        engine.start(languageCode: 'not-supported'),
        throwsA(isA<SpeechEngineException>()),
      );
      await engine.dispose();
    },
  );
}
