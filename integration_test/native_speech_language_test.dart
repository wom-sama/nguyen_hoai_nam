import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

import 'package:nguyen_hoai_nam/features/translation/speech_models.dart';

/// Independent native checks. Synthesized fixture audio is never played aloud;
/// microphone bytes are counted and discarded, never logged or persisted.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final evidence = <String, Object?>{};
  binding.reportData = evidence;

  setUpAll(() {
    expect(
      Platform.isAndroid,
      isTrue,
      reason: 'Select an Android target in Android Studio.',
    );
    evidence['platform'] = Platform.operatingSystemVersion;
    evidence['processors'] = Platform.numberOfProcessors;
    evidence['scope'] = 'Separate real microphone PCM transport and VI/ZH synthetic-fixture ASR; not microphone-to-VAD-to-translation end-to-end.';
  });
  tearDownAll(() => debugPrint('NATIVE_SPEECH_LANGUAGE_REPORT: $evidence'));

  testWidgets(
    'real microphone supplies PCM frames and stops within three seconds',
    (tester) async {
      final recorder = AudioRecorder();
      StreamSubscription<Uint8List>? subscription;
      var bytes = 0, chunks = 0;
      Object? streamError;
      final closed = Completer<void>();
      final captureWatch = Stopwatch();
      Object? primaryFailure;
      final micResult = <String, Object?>{
        'requestedSampleRate': 16000,
        'requestedChannels': 1,
        'privacy': 'No sample values, amplitude, transcript or audio file captured by this mic test.',
      };
      evidence['microphone'] = micResult;
      try {
        // The owner approves the expected Android mic dialog through the UI.
        final allowed = await recorder.hasPermission().timeout(
          const Duration(seconds: 45),
        );
        expect(
          allowed,
          isTrue,
          reason:
              'Microphone permission was denied; no PCM verification occurred.',
        );
        expect(
          await recorder.isEncoderSupported(AudioEncoder.pcm16bits),
          isTrue,
        );
        captureWatch.start();
        final stream = await recorder
            .startStream(
              const RecordConfig(
                encoder: AudioEncoder.pcm16bits,
                sampleRate: 16000,
                numChannels: 1,
                streamBufferSize: 3200,
              ),
            )
            .timeout(const Duration(milliseconds: 1000));
        subscription = stream.listen(
          (frame) {
            if (frame.isNotEmpty) {
              bytes += frame.length;
              chunks++;
            }
          },
          onError: (Object error) {
            streamError = error;
            if (!closed.isCompleted) closed.complete();
          },
          onDone: () {
            if (!closed.isCompleted) closed.complete();
          },
        );
        await Future<void>.delayed(const Duration(milliseconds: 750));
        await recorder.stop().timeout(const Duration(milliseconds: 1000));
        captureWatch.stop();
        await closed.future.timeout(const Duration(milliseconds: 500));
        micResult.addAll({
          'pcmBytes': bytes,
          'nonEmptyChunks': chunks,
          'startThroughStopMs': captureWatch.elapsedMilliseconds,
          'requestedSampleRate': 16000,
          'requestedChannels': 1,
          'streamClosed': closed.isCompleted,
          'isRecordingAfterStop': await recorder.isRecording(),
          'privacy': 'No sample values, amplitude, transcript or audio file captured by this mic test.',
        });
        expect(
          streamError,
          isNull,
          reason: 'Native PCM stream reported an error.',
        );
        expect(
          bytes,
          greaterThan(0),
          reason: 'No nonempty native microphone frame reached Dart.',
        );
        expect(chunks, greaterThan(0));
        expect(
          bytes.isEven,
          isTrue,
          reason: 'PCM16 stream ended with an incomplete sample.',
        );
        expect(captureWatch.elapsedMilliseconds, lessThanOrEqualTo(3000));
        expect(await recorder.isRecording(), isFalse);
      } catch (error) {
        primaryFailure = error;
        micResult['failure'] = error.toString();
        rethrow;
      } finally {
        // A failing assertion/timeout must still release the real microphone.
        // Permission requests retain record's semaphore until Android responds;
        // bounded cleanup failures must not replace that original failure.
        Object? cleanupFailure;
        StackTrace? cleanupStack;
        final cleanupErrors = <String>[];
        try {
          await recorder.stop().timeout(const Duration(seconds: 2));
        } catch (error, stack) {
          cleanupFailure = error;
          cleanupStack = stack;
          cleanupErrors.add('stop: $error');
        }
        try {
          await subscription?.cancel();
        } catch (error, stack) {
          cleanupFailure ??= error;
          cleanupStack ??= stack;
          cleanupErrors.add('subscription: $error');
        }
        try {
          await recorder.dispose().timeout(const Duration(seconds: 2));
        } catch (error, stack) {
          cleanupFailure ??= error;
          cleanupStack ??= stack;
          cleanupErrors.add('dispose: $error');
        }
        micResult['pcmBytes'] = bytes;
        micResult['nonEmptyChunks'] = chunks;
        if (cleanupErrors.isNotEmpty) {
          micResult['cleanupFailures'] = cleanupErrors;
        }
        if (primaryFailure == null && cleanupFailure != null) {
          micResult['failure'] = cleanupFailure.toString();
          Error.throwWithStackTrace(cleanupFailure, cleanupStack!);
        }
      }
    },
    timeout: const Timeout(Duration(seconds: 55)),
  );

  const fixtures = [
    (language: 'vi', locale: 'vi-VN', text: 'Xin chào. Tôi đi làm hôm nay.'),
    (language: 'zh', locale: 'zh-CN', text: '你好，我今天来上班。'),
  ];
  for (final fixture in fixtures) {
    testWidgets(
      'real platform ${fixture.language} TTS fixture is decoded by Whisper ${fixture.language}',
      (tester) async {
        final tts = FlutterTts();
        File? audio;
        final result = <String, Object?>{
          'input': fixture.text,
          'locale': fixture.locale,
        };
        evidence[fixture.language] = result;
        try {
          final support = await getApplicationSupportDirectory();
          final directory = Directory(
            '${support.path}/speech-models/whisper-tiny-int8-v1',
          );
          final store = SpeechModelStore(directory: directory);
          try {
            await store.prepare().timeout(
              const Duration(seconds: 60),
              onTimeout: () {
                store.cancel();
                throw TimeoutException(
                  'Model preparation exceeded 60 seconds. Run the earlier native translation test to fill the verified cache first.',
                );
              },
            );
          } finally {
            store.cancel();
          }
          final engine = await tts.getDefaultEngine;
          result['engine'] = engine;
          final voice = await _selectPlatformVoice(
            tts,
            fixture.locale,
            engine: engine?.toString(),
          );
          result['voice'] = voice;
          result['fixtureGenerator'] = voice['network_required'] == '1'
              ? 'Google Android network TTS; original nonsensitive fixture sentence only'
              : 'Android local TTS';
          result['asrInference'] =
              'Whisper tiny int8 on device through native FFI';
          final configured = await tts.setLanguage(fixture.locale);
          expect(
            configured,
            1,
            reason: 'TTS engine rejected ${fixture.locale}.',
          );
          expect(
            await tts.setVoice({
              'name': voice['name']!,
              'locale': voice['locale']!,
            }),
            1,
          );
          await tts.setSpeechRate(.45);
          await tts.awaitSynthCompletion(true);
          final temporary = await getTemporaryDirectory();
          audio = File(
            '${temporary.path}/native_fixture_${fixture.language}.wav',
          );
          final errors = Completer<Object>();
          tts.setErrorHandler((message) {
            if (!errors.isCompleted) errors.complete(message);
          });
          final watch = Stopwatch()..start();
          final synthesized = await Future.any<dynamic>([
            tts.synthesizeToFile(fixture.text, audio.path, true),
            errors.future.then<dynamic>(
              (error) =>
                  throw StateError('Native TTS synthesis failed: $error'),
            ),
          ]).timeout(const Duration(seconds: 30));
          result['synthesisMs'] = watch.elapsedMilliseconds;
          expect(
            synthesized,
            1,
            reason: 'TTS did not signal completed file synthesis.',
          );
          expect(await audio.exists(), isTrue);
          final length = await audio.length();
          result['wavBytes'] = length;
          expect(length, inInclusiveRange(1000, 2000000));
          final decoded = await _decodeInIsolate(
            directory.path,
            audio.path,
            fixture.language,
          ).timeout(const Duration(seconds: 15));
          result.addAll(decoded);
          final actual = decoded['text']! as String;
          expect(
            actual.trim(),
            isNotEmpty,
            reason: 'Native ${fixture.language} ASR returned no transcript.',
          );
          if (fixture.language == 'vi') {
            final normalized = _foldVietnamese(actual);
            expect(
              normalized,
              contains('chao'),
              reason:
                  'Expected greeting keyword from the VI fixture, got "$actual".',
            );
            expect(
              normalized,
              contains('lam'),
              reason:
                  'Expected work keyword from the VI fixture, got "$actual".',
            );
          } else {
            expect(
              actual.replaceAll(RegExp(r'\s+'), ''),
              contains('你好'),
              reason:
                  'Expected greeting keyword from the ZH fixture, got "$actual".',
            );
            expect(
              actual.contains('上班') || actual.contains('工作'),
              isTrue,
              reason:
                  'Expected work keyword from the ZH fixture, got "$actual".',
            );
          }
        } catch (error) {
          result['failure'] = error.toString();
          rethrow;
        } finally {
          try {
            await tts.stop().timeout(const Duration(seconds: 2));
          } finally {
            if (audio != null && await audio.exists()) await audio.delete();
          }
        }
      },
      timeout: const Timeout(Duration(seconds: 100)),
    );
  }
}

Future<Map<String, String>> _selectPlatformVoice(
  FlutterTts tts,
  String locale, {
  required String? engine,
}) async {
  final raw = await tts.getVoices;
  if (raw is! List) {
    throw StateError('TTS engine did not provide a voice list.');
  }
  final prefix = locale.toLowerCase();
  final matching = raw
      .whereType<Map>()
      .map(
        (voice) => voice.map(
          (key, value) => MapEntry(key.toString(), value.toString()),
        ),
      )
      .where((voice) => (voice['locale'] ?? '').toLowerCase() == prefix)
      .toList();
  final installed = matching
      .where(
        (voice) =>
            (voice['network_required'] == '0' ||
                (voice['network_required'] == '1' &&
                    engine == 'com.google.android.tts')) &&
            !(voice['features'] ?? '').toLowerCase().contains('notinstalled') &&
            (voice['name'] ?? '').isNotEmpty,
      )
      .toList();
  if (installed.isEmpty) {
    throw StateError(
      'No usable installed $locale voice from this Android TTS engine. Matching voices: ${matching.length}. Local is preferred; Google Android network voices are permitted only for the original nonsensitive fixture. Install voice data through Android settings if neither is available.',
    );
  }
  installed.sort((a, b) {
    final network = a['network_required']!.compareTo(b['network_required']!);
    return network == 0 ? a['name']!.compareTo(b['name']!) : network;
  });
  return {
    'name': installed.first['name']!,
    'locale': installed.first['locale']!,
    'network_required': installed.first['network_required']!,
  };
}

String _foldVietnamese(String text) {
  const groups = {
    'a': 'àáạảãâầấậẩẫăằắặẳẵ',
    'e': 'èéẹẻẽêềếệểễ',
    'i': 'ìíịỉĩ',
    'o': 'òóọỏõôồốộổỗơờớợởỡ',
    'u': 'ùúụủũưừứựửữ',
    'y': 'ỳýỵỷỹ',
    'd': 'đ',
  };
  var folded = text.toLowerCase();
  for (final entry in groups.entries) {
    for (final character in entry.value.split('')) {
      folded = folded.replaceAll(character, entry.key);
    }
  }
  return folded;
}

// This separate closure scope captures only sendable strings.
Future<Map<String, Object>> _decodeInIsolate(
  String directory,
  String audioPath,
  String language,
) => Isolate.run(() => _decodeWave(directory, audioPath, language));

Future<Map<String, Object>> _decodeWave(
  String directory,
  String audioPath,
  String language,
) async {
  await sherpa.initBindingsAsync();
  final wave = sherpa.readWave(audioPath);
  if (wave.sampleRate < 8000 ||
      wave.sampleRate > 48000 ||
      wave.samples.length < wave.sampleRate ~/ 2 ||
      wave.samples.length > wave.sampleRate * 12) {
    throw StateError(
      'TTS did not produce a readable short mono WAV: ${wave.sampleRate} Hz, ${wave.samples.length} samples.',
    );
  }
  final watch = Stopwatch()..start();
  final recognizer = sherpa.OfflineRecognizer(
    sherpa.OfflineRecognizerConfig(
      model: sherpa.OfflineModelConfig(
        whisper: sherpa.OfflineWhisperModelConfig(
          encoder: '$directory/tiny-encoder.int8.onnx',
          decoder: '$directory/tiny-decoder.int8.onnx',
          language: language,
          task: 'transcribe',
        ),
        tokens: '$directory/tiny-tokens.txt',
        modelType: 'whisper',
        numThreads: Platform.numberOfProcessors >= 4 ? 2 : 1,
        debug: false,
      ),
    ),
  );
  final loadMs = watch.elapsedMilliseconds;
  try {
    final stream = recognizer.createStream();
    try {
      // sherpa native OfflineStream resamples the actual WAV rate to Whisper's
      // 16 kHz when necessary; never mislabel 22.05/24 kHz audio as 16 kHz.
      stream.acceptWaveform(samples: wave.samples, sampleRate: wave.sampleRate);
      watch.reset();
      recognizer.decode(stream);
      return {
        'text': recognizer.getResult(stream).text,
        'modelLoadMs': loadMs,
        'decodeMs': watch.elapsedMilliseconds,
        'sourceSampleRate': wave.sampleRate,
        'audioSeconds': wave.samples.length / wave.sampleRate,
        'language': language,
        'model': 'whisper-tiny-int8',
      };
    } finally {
      stream.free();
    }
  } finally {
    recognizer.free();
  }
}
