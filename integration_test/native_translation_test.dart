import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

import 'package:nguyen_hoai_nam/features/translation/speech_models.dart';
import 'package:nguyen_hoai_nam/features/translation/translation_service.dart';

/// Run this entrypoint on Android from an Android Studio Flutter Run config.
/// These tests intentionally use real native ML Kit and sherpa-onnx plugins.
/// No HTTP/native inference is mocked, and main.dart/auth is never modified.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final evidence = <String, Object?>{};
  binding.reportData = evidence;

  setUpAll(() {
    expect(
      Platform.isAndroid,
      isTrue,
      reason: 'Run on an Android device, not the host test runner.',
    );
    evidence['platform'] = Platform.operatingSystem;
    evidence['osVersion'] = Platform.operatingSystemVersion;
    evidence['processors'] = Platform.numberOfProcessors;
    evidence['scope'] = 'Real native OCR, translation and file ASR; not microphone/camera/VAD end-to-end.';
  });

  tearDownAll(() {
    // Android Studio Run console keeps this evidence even without a driver.
    debugPrint('NATIVE_VERIFICATION_REPORT: $evidence');
  });

  testWidgets('real Latin OCR reads original employee-shift fixture', (
    tester,
  ) async {
    final directory = await getTemporaryDirectory();
    final image = await _originalTextImage(
      directory,
      'latin',
      'SHIFT NAM 2380601398',
    );
    final service = TranslationService();
    try {
      final watch = Stopwatch()..start();
      final actual = await service.recognizePhoto(
        image.path,
        sourceLanguage: 'en',
      );
      final normalized = actual.toUpperCase().replaceAll(RegExp(r'\s+'), '');
      evidence['ocrLatin'] = {
        'text': actual,
        'milliseconds': watch.elapsedMilliseconds,
      };
      expect(normalized, contains('SHIFT'));
      expect(normalized, contains('2380601398'));
    } finally {
      await service.dispose();
      if (await image.exists()) await image.delete();
    }
  }, timeout: const Timeout(Duration(minutes: 2)));

  testWidgets('real Chinese OCR reads original employee-attendance fixture', (
    tester,
  ) async {
    final directory = await getTemporaryDirectory();
    final image = await _originalTextImage(directory, 'chinese', '员工考勤');
    final service = TranslationService();
    try {
      final watch = Stopwatch()..start();
      final actual = await service.recognizePhoto(
        image.path,
        sourceLanguage: 'zh',
      );
      evidence['ocrChinese'] = {
        'text': actual,
        'milliseconds': watch.elapsedMilliseconds,
      };
      expect(actual.replaceAll(RegExp(r'\s+'), ''), contains('员工考勤'));
    } finally {
      await service.dispose();
      if (await image.exists()) await image.delete();
    }
  }, timeout: const Timeout(Duration(minutes: 2)));

  testWidgets('real on-device translation covers all six VI EN ZH directions', (
    tester,
  ) async {
    final service = TranslationService();
    final pairs =
        <({String source, String target, String input, List<String> accepted})>[
          (source: 'en', target: 'vi', input: 'Hello', accepted: ['chào']),
          (
            source: 'vi',
            target: 'en',
            input: 'Xin chào',
            accepted: ['hello', 'hi', 'greetings'],
          ),
          (source: 'en', target: 'zh', input: 'Hello', accepted: ['你好', '您好']),
          (
            source: 'zh',
            target: 'en',
            input: '你好',
            accepted: ['hello', 'hi', 'greetings'],
          ),
          (
            source: 'vi',
            target: 'zh',
            input: 'Xin chào',
            accepted: ['你好', '您好'],
          ),
          (source: 'zh', target: 'vi', input: '你好', accepted: ['chào']),
        ];
    final results = <String, Object?>{};
    evidence['translation'] = results;
    try {
      // Model download failures are failures, never treated as a skipped pass.
      for (final pair in pairs) {
        final watch = Stopwatch()..start();
        final actual = await service.translate(
          pair.input,
          sourceLanguage: pair.source,
          targetLanguage: pair.target,
        );
        results['${pair.source}-${pair.target}'] = {
          'input': pair.input,
          'text': actual,
          'milliseconds': watch.elapsedMilliseconds,
        };
        final normalized = actual.toLowerCase().replaceAll(RegExp(r'\s+'), '');
        expect(
          pair.accepted.any(normalized.contains),
          isTrue,
          reason:
              '${pair.source}->${pair.target}: expected a greeting, got "$actual".',
        );
        expect(
          actual.trim().toLowerCase(),
          isNot(pair.input.toLowerCase()),
          reason: 'A source-text fallback does not prove native translation.',
        );
      }
    } finally {
      await service.dispose();
    }
  }, timeout: const Timeout(Duration(minutes: 5)));

  testWidgets('real Whisper tiny int8 FFI transcribes a pinned official WAV', (
    tester,
  ) async {
    final support = await getApplicationSupportDirectory();
    final directory = Directory(
      '${support.path}/speech-models/whisper-tiny-int8-v1',
    );
    final store = SpeechModelStore(directory: directory);
    final downloadWatch = Stopwatch()..start();
    var lastPercent = -10;
    try {
      await store
          .prepare(
            onProgress: (progress) {
              final percent = (progress * 100).floor();
              if (percent >= lastPercent + 10 || percent == 100) {
                lastPercent = percent;
                debugPrint('NATIVE_ASR_MODELS: $percent%');
              }
            },
          )
          .timeout(
            const Duration(minutes: 4),
            onTimeout: () {
              store.cancel();
              throw TimeoutException(
                'Verified ASR model preparation exceeded four minutes.',
              );
            },
          );
      evidence['asrModelPreparationMs'] = downloadWatch.elapsedMilliseconds;
      final temporary = await getTemporaryDirectory();
      final audio = await _downloadOfficialAudio(temporary);
      try {
        // Same model files, Whisper config, task, language and thread policy as
        // speech_workers.dart; only the microphone transport is bypassed.
        final result = await _runAsrIsolate(directory.path, audio.path);
        evidence['asr'] = result;
        final text = (result['text']! as String).toLowerCase();
        expect(
          text.length,
          greaterThan(5),
          reason: 'Empty/native-load-only output is not an ASR pass.',
        );
        expect(
          RegExp(r'zero|0').hasMatch(text),
          isTrue,
          reason:
              'The official spoken-digit fixture contains repeated zeros: "$text".',
        );
        expect(
          RegExp(r'one|1').hasMatch(text),
          isTrue,
          reason: 'The official spoken-digit fixture contains ones: "$text".',
        );
      } finally {
        if (await audio.exists()) await audio.delete();
      }
    } finally {
      store.cancel();
    }
  }, timeout: const Timeout(Duration(minutes: 7)));
}

/// Original short text, drawn to PNG by the real device renderer. No third-party
/// image or recognizer callback provides the expected string to ML Kit.
Future<File> _originalTextImage(
  Directory directory,
  String name,
  String text,
) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawRect(
    const ui.Rect.fromLTWH(0, 0, 1400, 240),
    ui.Paint()..color = const ui.Color(0xffffffff),
  );
  final paragraph =
      (ui.ParagraphBuilder(
              ui.ParagraphStyle(
                textDirection: ui.TextDirection.ltr,
                fontSize: 80,
                fontFamily: 'sans-serif',
              ),
            )
            ..pushStyle(ui.TextStyle(color: const ui.Color(0xff000000)))
            ..addText(text))
          .build()
        ..layout(const ui.ParagraphConstraints(width: 1280));
  canvas.drawParagraph(paragraph, const ui.Offset(60, 60));
  final picture = recorder.endRecording();
  final image = await picture.toImage(1400, 240);
  try {
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    if (png == null) {
      throw StateError('Device failed to render the OCR fixture.');
    }
    return await File('${directory.path}/native_ocr_$name.png').writeAsBytes(
      png.buffer.asUint8List(png.offsetInBytes, png.lengthInBytes),
      flush: true,
    );
  } finally {
    image.dispose();
    picture.dispose();
    paragraph.dispose();
  }
}

// Official Vosk example audio, repository Apache-2.0 license. Its old directory
// name does not mean that Python is used: this test reads PCM through sherpa FFI.
// File pinned to its last modifying commit; size and digest verified separately.
const _audioUrl =
    'https://raw.githubusercontent.com/alphacep/vosk-api/78e66149f8ac56a64aa64306c1e8fc132c4eb154/python/example/test.wav';
const _audioBytes = 265914;
const _audioSha256 =
    'dcfea5712c43a43ba7ae8083afb39d36993e5a69c46e88b68aaa72b65cb615bb';

Future<File> _downloadOfficialAudio(Directory directory) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 20);
  final file = File('${directory.path}/native_asr_official.wav');
  try {
    final request = await client
        .getUrl(Uri.parse(_audioUrl))
        .timeout(const Duration(seconds: 25));
    final response = await request.close().timeout(const Duration(seconds: 25));
    if (response.statusCode != HttpStatus.ok ||
        response.contentLength > _audioBytes) {
      throw StateError(
        'Official audio HTTP ${response.statusCode}, size ${response.contentLength}.',
      );
    }
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in response.timeout(const Duration(seconds: 20))) {
      bytes.add(chunk);
      if (bytes.length > _audioBytes) {
        throw StateError('Official audio exceeded its pinned size.');
      }
    }
    final contents = bytes.takeBytes();
    if (contents.length != _audioBytes ||
        sha256.convert(contents).toString() != _audioSha256) {
      throw StateError('Official audio size/SHA-256 mismatch.');
    }
    return await file.writeAsBytes(contents, flush: true);
  } finally {
    client.close(force: true);
  }
}

// Isolate closure scope contains only two sendable strings, not the model store,
// HTTP client, test binding or other surrounding test-widget state.
Future<Map<String, Object>> _runAsrIsolate(
  String directory,
  String audioPath,
) => Isolate.run(() => _decodeOfficialWave(directory, audioPath));

Future<Map<String, Object>> _decodeOfficialWave(
  String directory,
  String audioPath,
) async {
  await sherpa.initBindingsAsync();
  final wave = sherpa.readWave(audioPath);
  if (wave.sampleRate != 16000 ||
      wave.samples.length < 16000 ||
      wave.samples.length > 16000 * 12) {
    throw StateError(
      'Expected a short mono 16 kHz WAV, got ${wave.sampleRate} Hz / ${wave.samples.length} samples.',
    );
  }
  final watch = Stopwatch()..start();
  final recognizer = sherpa.OfflineRecognizer(
    sherpa.OfflineRecognizerConfig(
      model: sherpa.OfflineModelConfig(
        whisper: sherpa.OfflineWhisperModelConfig(
          encoder: '$directory/tiny-encoder.int8.onnx',
          decoder: '$directory/tiny-decoder.int8.onnx',
          language: 'en',
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
      stream.acceptWaveform(samples: wave.samples, sampleRate: wave.sampleRate);
      watch.reset();
      recognizer.decode(stream);
      return {
        'text': recognizer.getResult(stream).text,
        'modelLoadMs': loadMs,
        'decodeMs': watch.elapsedMilliseconds,
        'sampleRate': wave.sampleRate,
        'audioSeconds': wave.samples.length / wave.sampleRate,
        'language': 'en',
        'model': 'whisper-tiny-int8',
        'fixtureSha256': _audioSha256,
      };
    } finally {
      stream.free();
    }
  } finally {
    recognizer.free();
  }
}
