import 'package:google_mlkit_translation/google_mlkit_translation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import '../../core/api_client.dart';

const translationLanguages = {
  'vi': 'Tiếng Việt',
  'en': 'Tiếng Anh',
  'zh': 'Tiếng Trung',
};

class TranslationService {
  final _manager = OnDeviceTranslatorModelManager();
  final Map<String, OnDeviceTranslator> _translators = {};
  final Map<String, Future<void>> _downloads = {};
  final Set<Future<String>> _active = {};
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
  }) async {
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
      return result.text;
    } finally {
      await recognizer.close();
    }
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
    for (final translator in _translators.values) {
      await translator.close();
    }
    _translators.clear();
  }
}
