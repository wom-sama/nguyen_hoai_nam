import 'dart:ui';

import 'package:google_mlkit_translation/google_mlkit_translation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import '../../core/api_client.dart';

const translationLanguages = {
  'vi': 'Tiếng Việt',
  'en': 'Tiếng Anh',
  'zh': 'Tiếng Trung',
};

/// Coordinates are in ML Kit's upright image space, before preview fitting.
class OcrRegion {
  const OcrRegion({
    required this.text,
    required this.bounds,
    this.corners = const [],
  });
  final String text;
  final Rect bounds;
  final List<Offset> corners;
}

class OcrPage {
  OcrPage({required this.text, required Iterable<OcrRegion> regions})
    : regions = List.unmodifiable(regions);
  final String text;
  final List<OcrRegion> regions;
}

class TranslatedOcrRegion {
  const TranslatedOcrRegion({
    required this.originalText,
    required this.translatedText,
    required this.bounds,
    this.corners = const [],
  });
  final String originalText, translatedText;
  final Rect bounds;
  final List<Offset> corners;
}

class OcrTranslation {
  OcrTranslation({
    required this.originalText,
    required Iterable<TranslatedOcrRegion> regions,
  }) : regions = List.unmodifiable(regions);
  final String originalText;
  final List<TranslatedOcrRegion> regions;
  String get translatedText =>
      regions.map((region) => region.translatedText).join('\n\n');
}

class TranslationService {
  final _manager = OnDeviceTranslatorModelManager();
  final Map<String, OnDeviceTranslator> _translators = {};
  final Map<String, Future<void>> _downloads = {};
  final Set<Future<String>> _active = {};
  final Set<Future<OcrPage>> _ocrActive = {};
  final _regionCache = <String, String>{};
  String? _regionCachePair;
  bool _disposed = false;
  TranslateLanguage _language(String code) => switch (code) {
    'vi' => TranslateLanguage.vietnamese,
    'en' => TranslateLanguage.english,
    'zh' => TranslateLanguage.chinese,
    _ => throw const ApiException(
      'LANGUAGE_NOT_SUPPORTED',
      'Chọn tiếng Việt, Anh hoặc Trung.',
    ),
  };
  Future<void> preparePair({
    required String sourceLanguage,
    required String targetLanguage,
  }) async {
    _language(sourceLanguage);
    _language(targetLanguage);
    for (final code in {sourceLanguage, targetLanguage}) {
      if (code == 'en') continue;
      await (_downloads[code] ??= _download(code));
    }
  }

  Future<void> _download(String code) async {
    try {
      if (!await _manager.isModelDownloaded(code)) {
        final ok = await _manager.downloadModel(code, isWifiRequired: false);
        if (!ok) {
          throw const ApiException(
            'TRANSLATION_MODEL',
            'Chưa tải được gói ngôn ngữ. Hãy kiểm tra mạng và thử lại.',
          );
        }
      }
    } catch (e) {
      _downloads.remove(code);
      rethrow;
    }
  }

  Future<String> translate(
    String text, {
    required String sourceLanguage,
    required String targetLanguage,
  }) {
    if (_disposed) {
      return Future.error(
        const ApiException('TRANSLATOR_CLOSED', 'Phiên dịch đã đóng.'),
      );
    }
    late final Future<String> task;
    task = _translate(
      text,
      sourceLanguage,
      targetLanguage,
    ).whenComplete(() => _active.remove(task));
    _active.add(task);
    return task;
  }

  Future<String> _translate(String text, String source, String target) async {
    if (text.trim().isEmpty) {
      throw const ApiException(
        'EMPTY_TEXT',
        'Nhập hoặc nhận dạng nội dung trước khi dịch.',
      );
    }
    if (source == target) return text;
    await preparePair(sourceLanguage: source, targetLanguage: target);
    if (_disposed) {
      throw const ApiException('TRANSLATOR_CLOSED', 'Phiên dịch đã đóng.');
    }
    final key = '$source-$target';
    final translator = _translators.putIfAbsent(
      key,
      () => OnDeviceTranslator(
        sourceLanguage: _language(source),
        targetLanguage: _language(target),
      ),
    );
    return translator.translateText(text);
  }

  Future<String> recognizePhoto(
    String path, {
    required String sourceLanguage,
  }) => recognizeFrame(
    InputImage.fromFilePath(path),
    sourceLanguage: sourceLanguage,
  );

  Future<String> recognizeFrame(
    InputImage image, {
    required String sourceLanguage,
  }) async => (await recognizePage(image, sourceLanguage: sourceLanguage)).text;

  /// OCR reads the exact upright pixels displayed by RawImage, so EXIF handling
  /// cannot differ between a gallery file decoder and ML Kit's file decoder.
  Future<OcrPage> recognizeBitmap(
    Image bitmap, {
    required String sourceLanguage,
  }) async {
    final data = await bitmap.toByteData(format: ImageByteFormat.rawRgba);
    if (data == null) {
      throw const ApiException(
        'PHOTO_DECODE',
        'Chưa đọc được ảnh. Hãy chọn ảnh khác.',
      );
    }
    return recognizePage(
      InputImage.fromBitmap(
        bitmap: data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        width: bitmap.width,
        height: bitmap.height,
      ),
      sourceLanguage: sourceLanguage,
    );
  }

  Future<OcrPage> recognizePage(
    InputImage image, {
    required String sourceLanguage,
  }) {
    late final Future<OcrPage> task;
    task = _recognizePage(
      image,
      sourceLanguage,
    ).whenComplete(() => _ocrActive.remove(task));
    _ocrActive.add(task);
    return task;
  }

  Future<OcrPage> _recognizePage(
    InputImage image,
    String sourceLanguage,
  ) async {
    if (_disposed) {
      throw const ApiException('TRANSLATOR_CLOSED', 'Phiên dịch đã đóng.');
    }
    final recognizer = TextRecognizer(
      script: sourceLanguage == 'zh'
          ? TextRecognitionScript.chinese
          : TextRecognitionScript.latin,
    );
    try {
      final result = await recognizer.processImage(image);
      if (result.text.trim().isEmpty) {
        throw const ApiException(
          'OCR_EMPTY',
          'Chưa đọc được chữ trong ảnh. Thử ảnh rõ nét và đủ sáng hơn.',
        );
      }
      final regions = result.blocks
          .where((block) => block.text.trim().isNotEmpty)
          .map(
            (block) => OcrRegion(
              text: block.text.trim(),
              bounds: block.boundingBox,
              corners: List.unmodifiable(
                block.cornerPoints.map(
                  (point) => Offset(point.x.toDouble(), point.y.toDouble()),
                ),
              ),
            ),
          )
          .toList(growable: false);
      if (regions.isEmpty ||
          regions.any(
            (region) => !region.bounds.isFinite || region.bounds.isEmpty,
          )) {
        throw const ApiException(
          'OCR_LAYOUT',
          'Chưa xác định được vùng chữ. Hãy chọn ảnh rõ nét hơn.',
        );
      }
      return OcrPage(text: result.text.trim(), regions: regions);
    } finally {
      await recognizer.close();
    }
  }

  Future<OcrTranslation> translatePage(
    OcrPage page, {
    required String sourceLanguage,
    required String targetLanguage,
  }) async {
    if (page.text.trim().isEmpty || page.regions.isEmpty) {
      throw const ApiException('OCR_EMPTY', 'Chưa đọc được chữ trong ảnh.');
    }
    if (page.text.length > 10000 || page.regions.length > 128) {
      throw const ApiException(
        'OCR_TOO_LONG',
        'Ảnh có quá nhiều chữ. Hãy chụp một vùng nhỏ hơn.',
      );
    }
    final pair = '$sourceLanguage-$targetLanguage';
    if (_regionCachePair != pair) {
      _regionCachePair = pair;
      _regionCache.clear();
    }
    final regions = <TranslatedOcrRegion>[];
    for (final region in page.regions) {
      var translated = _regionCache.remove(region.text);
      translated ??= (await translate(
        region.text,
        sourceLanguage: sourceLanguage,
        targetLanguage: targetLanguage,
      )).trim();
      if (translated.isEmpty) {
        throw const ApiException(
          'TRANSLATION_EMPTY',
          'Chưa dịch được vùng chữ này. Hãy thử lại.',
        );
      }
      if (_regionCachePair == pair) {
        _regionCache[region.text] = translated;
        while (_regionCache.length > 64) {
          _regionCache.remove(_regionCache.keys.first);
        }
      }
      regions.add(
        TranslatedOcrRegion(
          originalText: region.text,
          translatedText: translated,
          bounds: region.bounds,
          corners: region.corners,
        ),
      );
    }
    return OcrTranslation(originalText: page.text, regions: regions);
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    // Callers receive operation failures; disposal only waits for their native work to drain.
    await Future.wait(
      _active.toList().map(
        (future) =>
            future.then<void>((_) {}, onError: (Object e, StackTrace s) {}),
      ),
    );
    await Future.wait(
      _ocrActive.toList().map(
        (future) =>
            future.then<void>((_) {}, onError: (Object e, StackTrace s) {}),
      ),
    );
    for (final translator in _translators.values) {
      await translator.close();
    }
    _translators.clear();
    _regionCache.clear();
  }
}
