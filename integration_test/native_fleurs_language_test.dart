import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

import 'package:nguyen_hoai_nam/features/translation/speech_models.dart';

import 'native_fleurs_fixtures.dart';

void main() => runNativeFleursLanguageTests();

/// Shared native harness; the base entry changes only the pinned model variant.
/// Fixture bytes, references, keywords and normalization stay identical.
void runNativeFleursLanguageTests({
  String modelPrefix = 'tiny',
  List<SpeechModelAsset> modelAssets = speechModelAssets,
  String cacheName = 'whisper-tiny-int8-v1',
  Duration preparationTimeout = const Duration(seconds: 60),
}) {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final evidence = <String, Object?>{};
  binding.reportData = evidence;
  Future<Directory>? models;

  setUpAll(() {
    expect(
      Platform.isAndroid,
      isTrue,
      reason: 'Run this entrypoint on Android from Android Studio.',
    );
    evidence['platform'] = Platform.operatingSystemVersion;
    evidence['processors'] = Platform.numberOfProcessors;
    evidence['modelVariant'] = 'whisper-$modelPrefix-int8';
    evidence['scope'] = 'Real on-device VI/ZH Whisper FFI using pinned human FLEURS speech; not microphone/VAD/translation end-to-end or general accuracy benchmark.';
    expect(_normalize('đo\u0323\u0302ng va\u0323\u0302t', 'vi'), 'độngvật');
    expect(
      _normalize('hu\u031bo\u031bu cao co\u0302\u0309', 'vi'),
      'hươucaocổ',
    );
    expect(_normalize('哺乳動物 科隆群島', 'zh'), '哺乳动物科隆群岛');
  });
  tearDownAll(
    () => debugPrint(
      '${modelPrefix == 'tiny' ? 'NATIVE_FLEURS_LANGUAGE_REPORT' : 'NATIVE_FLEURS_${modelPrefix.toUpperCase()}_LANGUAGE_REPORT'}: $evidence',
    ),
  );

  for (final fixture in nativeFleursFixtures) {
    testWidgets(
      'real Whisper $modelPrefix ${fixture.language} decodes pinned FLEURS human speech',
      (tester) async {
        final result = <String, Object?>{
          'dataset': 'google/fleurs',
          'config': fixture.config,
          'fixture': fixture.fileName,
          'reference': fixture.reference,
          'requiredKeywords': fixture.keywords,
          'fixtureSha256': fixture.sha256,
          'license': 'CC-BY-4.0',
        };
        evidence[fixture.language] = result;
        File? temporaryFile;
        try {
          // All bytes are test-only constants. No new assets or dependencies are
          // added to the production app, and no TTS voice or audio network is used.
          final bytes = base64Decode(fixture.base64Audio);
          expect(bytes.length, fixture.bytes);
          expect(sha256.convert(bytes).toString(), fixture.sha256);
          final temporary = await getTemporaryDirectory();
          temporaryFile = await File(
            '${temporary.path}/fleurs_${fixture.fileName}',
          ).writeAsBytes(bytes, flush: true);
          final directory = await (models ??= _prepareModels(
            modelAssets,
            cacheName,
            preparationTimeout,
          ));
          final decoded = await _decodeInIsolate(
            directory.path,
            temporaryFile.path,
            fixture.language,
            modelPrefix,
          ).timeout(const Duration(seconds: 45));
          result.addAll(decoded);
          expect(
            decoded['waveValidationFailure'],
            isNull,
            reason: 'Native WAV amplitude does not match the pinned host fixture; inference was not attempted.',
          );
          expect(decoded['samples'], fixture.samples);
          expect(decoded['sampleRate'], 16000);
          expect(decoded['audioSeconds'] as double, lessThan(15));
          final text = decoded['text']! as String;
          expect(
            text.trim(),
            isNotEmpty,
            reason:
                'Native ASR returned an empty ${fixture.language} transcript.',
          );
          final normalized = _normalize(text, fixture.language);
          for (final keyword in fixture.keywords) {
            expect(
              normalized,
              contains(_normalize(keyword, fixture.language)),
              reason:
                  'Missing official-reference keyword "$keyword". Actual raw transcript: "$text".',
            );
          }
          result['keywordChecksPassed'] = true;
        } catch (error) {
          result['failure'] = error.toString();
          rethrow;
        } finally {
          if (temporaryFile != null && await temporaryFile.exists()) {
            await temporaryFile.delete();
          }
        }
      },
      timeout: Timeout(preparationTimeout + const Duration(seconds: 60)),
    );
  }
}

Future<Directory> _prepareModels(
  List<SpeechModelAsset> assets,
  String cacheName,
  Duration timeout,
) async {
  final support = await getApplicationSupportDirectory();
  final directory = Directory('${support.path}/speech-models/$cacheName');
  final store = SpeechModelStore(directory: directory, assets: assets);
  var lastPercent = -10;
  try {
    return await store
        .prepare(
          onProgress: (progress) {
            final percent = (progress * 100).floor();
            if (percent >= lastPercent + 10 || percent == 100) {
              lastPercent = percent;
              debugPrint('NATIVE_FLEURS_MODEL_CACHE $cacheName: $percent%');
            }
          },
        )
        .timeout(
          timeout,
          onTimeout: () {
            store.cancel();
            throw TimeoutException(
              'Verified $cacheName model preparation exceeded ${timeout.inSeconds}s.',
            );
          },
        );
  } finally {
    store.cancel();
  }
}

// A dedicated closure scope captures only sendable strings.
Future<Map<String, Object>> _decodeInIsolate(
  String directory,
  String path,
  String language,
  String modelPrefix,
) => Isolate.run(() => _decodeWave(directory, path, language, modelPrefix));

Future<Map<String, Object>> _decodeWave(
  String directory,
  String path,
  String language,
  String modelPrefix,
) async {
  await sherpa.initBindingsAsync();
  // sherpa's real native WAV reader supports the original mono float32 format.
  final wave = sherpa.readWave(path);
  if (wave.sampleRate != 16000 ||
      wave.samples.isEmpty ||
      wave.samples.length >= 16000 * 15) {
    throw StateError(
      'Pinned fixture is not readable mono 16kHz speech under 15s.',
    );
  }
  var peak = 0.0, minimum = 0.0, maximum = 0.0, sum = 0.0, squares = 0.0;
  var nonfinite = 0;
  for (final sample in wave.samples) {
    if (!sample.isFinite) {
      nonfinite++;
      continue;
    }
    peak = math.max(peak, sample.abs());
    minimum = math.min(minimum, sample);
    maximum = math.max(maximum, sample);
    sum += sample;
    squares += sample * sample;
  }
  final rms = math.sqrt(squares / wave.samples.length);
  final (expectedPeak, expectedRms) = language == 'vi'
      ? (0.16962206363677979, 0.0295126662238795)
      : (0.3634607791900635, 0.03476302286781156);
  final metadata = <String, Object>{
    'samples': wave.samples.length,
    'sampleRate': wave.sampleRate,
    'audioSeconds': wave.samples.length / wave.sampleRate,
    'language': language,
    'model': 'whisper-$modelPrefix-int8',
    'nativeWaveStatistics': <String, Object>{
      'peak': peak,
      'rms': rms,
      'minimum': minimum,
      'maximum': maximum,
      'mean': sum / wave.samples.length,
      'nonfinite': nonfinite,
      'referencePeak': expectedPeak,
      'referenceRms': expectedRms,
      'peakTolerance': 0.002,
      'rmsTolerance': 0.001,
    },
  };
  // Validate actual deployed native float-WAV reading BEFORE model creation or
  // inference. Do not compensate an unexpected gain or change fixture samples.
  if (nonfinite != 0 ||
      (peak - expectedPeak).abs() > 0.002 ||
      (rms - expectedRms).abs() > 0.001) {
    return {
      ...metadata,
      'waveValidationFailure': 'Native float32 waveform statistics differ from the unchanged original fixture; decode not attempted.',
    };
  }
  final watch = Stopwatch()..start();
  final recognizer = sherpa.OfflineRecognizer(
    sherpa.OfflineRecognizerConfig(
      model: sherpa.OfflineModelConfig(
        whisper: sherpa.OfflineWhisperModelConfig(
          encoder: '$directory/$modelPrefix-encoder.int8.onnx',
          decoder: '$directory/$modelPrefix-decoder.int8.onnx',
          language: language,
          task: 'transcribe',
        ),
        tokens: '$directory/$modelPrefix-tokens.txt',
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
      stream.acceptWaveform(samples: wave.samples, sampleRate: wave.sampleRate);
      watch.reset();
      recognizer.decode(stream);
      return {
        ...metadata,
        'text': recognizer.getResult(stream).text,
        'modelLoadMs': loadMs,
        'decodeMs': watch.elapsedMilliseconds,
      };
    } finally {
      stream.free();
    }
  } finally {
    recognizer.free();
  }
}

/// Canonical composition for the Vietnamese vowel alphabet used in the two
/// keyword checks. This handles NFC/NFD equivalents without removing accents or
/// accepting different words. Han keywords only map the two documented
/// simplified/traditional characters 動/动 and 島/岛; punctuation/space is ignored.
String _normalize(String input, String language) {
  var text = input.toLowerCase();
  if (language == 'zh') {
    return text
        .replaceAll('動', '动')
        .replaceAll('島', '岛')
        .replaceAll(RegExp(r'[\s，。,.、！!？?；;：:]'), '');
  }
  const vowels = <String, String>{
    'a': 'aàáảãạ',
    'ă': 'ăằắẳẵặ',
    'â': 'âầấẩẫậ',
    'e': 'eèéẻẽẹ',
    'ê': 'êềếểễệ',
    'i': 'iìíỉĩị',
    'o': 'oòóỏõọ',
    'ô': 'ôồốổỗộ',
    'ơ': 'ơờớởỡợ',
    'u': 'uùúủũụ',
    'ư': 'ưừứửữự',
    'y': 'yỳýỷỹỵ',
  };
  const tones = ['', '\u0300', '\u0301', '\u0309', '\u0303', '\u0323'];
  const shapes = {
    'ă': 'a\u0306',
    'â': 'a\u0302',
    'ê': 'e\u0302',
    'ô': 'o\u0302',
    'ơ': 'o\u031b',
    'ư': 'u\u031b',
  };
  final decomposed = StringBuffer();
  for (final character in text.split('')) {
    var found = false;
    for (final entry in vowels.entries) {
      final index = entry.value.indexOf(character);
      if (index >= 0) {
        decomposed.write('${shapes[entry.key] ?? entry.key}${tones[index]}');
        found = true;
        break;
      }
    }
    if (!found) decomposed.write(character);
  }
  text = decomposed.toString().replaceAllMapped(
    RegExp(r'([aeiouy])([\u0300\u0301\u0309\u0303\u0323\u0302\u0306\u031b]+)'),
    (match) {
      var base = match[1]!;
      final marks = match[2]!;
      if (marks.contains('\u0302')) {
        base = const {'a': 'â', 'e': 'ê', 'o': 'ô'}[base] ?? base;
      } else if (marks.contains('\u0306') && base == 'a') {
        base = 'ă';
      } else if (marks.contains('\u031b')) {
        base = const {'o': 'ơ', 'u': 'ư'}[base] ?? base;
      }
      var tone = 0;
      for (var i = 1; i < tones.length; i++) {
        if (marks.contains(tones[i])) tone = i;
      }
      return vowels[base]![tone];
    },
  );
  return text.replaceAll(RegExp(r'[\s，。,.、！!？?；;：:]'), '');
}
