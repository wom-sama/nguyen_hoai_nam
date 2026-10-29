import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nguyen_hoai_nam/features/translation/speech_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.llfbandit.record/messages');
  test('permission dialog lifecycle bounce never starts capture or cancels the grant', () async {
    final permission = Completer<bool>(), requested = Completer<void>();
    final calls = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call.method);
          if (call.method == 'hasPermission') {
            expect((call.arguments as Map)['request'], isTrue);
            if (!requested.isCompleted) requested.complete();
            return permission.future;
          }
          if (call.method == 'create' || call.method == 'dispose') return null;
          throw StateError('Permission flow must not invoke ${call.method}');
        });
    final engine = ContinuousSpeechEngine();
    try {
      final grant = engine.requestMicrophonePermission();
      await requested.future;
      engine.setForeground(false);
      await engine
          .stop(); // Same idle stop triggered by the OS permission dialog.
      permission.complete(true);
      expect(await grant, isTrue);
      expect((await engine.states.first).phase, 'idle');
      expect(calls.where((method) => method == 'create').length, 1);
      expect(calls.where((method) => method.contains('start')), isEmpty);
      await expectLater(
        engine.start(languageCode: 'vi'),
        throwsA(isA<SpeechEngineException>()),
      );
      engine.setForeground(true);
    } finally {
      await engine.dispose();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    }
  });
}
