import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';

/// Whisper weights are MIT-licensed; the sherpa runtime is Apache-2.0.
/// Sources: k2-fsa/sherpa-onnx documentation and its linked HF exports.
/// Whisper files are pinned to HF commit 65176e2deb88badc814a94058666cadccc29b61c.
/// ONNX hashes are HF LFS SHA-256 oids; VAD hash is GitHub asset 271935959's
/// published SHA-256 digest. Token hash was computed over that pinned file.
const speechModelAssets = <SpeechModelAsset>[
  SpeechModelAsset(
    fileName: 'tiny-encoder.int8.onnx',
    url: 'https://huggingface.co/csukuangfj/sherpa-onnx-whisper-tiny/resolve/65176e2deb88badc814a94058666cadccc29b61c/tiny-encoder.int8.onnx',
    bytes: 12937772,
    sha256: 'd24fb083ae3b1041fc24e97971d60e280c9342201fbb67b0ab428a8b4a51a434',
  ),
  SpeechModelAsset(
    fileName: 'tiny-decoder.int8.onnx',
    url: 'https://huggingface.co/csukuangfj/sherpa-onnx-whisper-tiny/resolve/65176e2deb88badc814a94058666cadccc29b61c/tiny-decoder.int8.onnx',
    bytes: 89855401,
    sha256: 'd2fece8dd42771f1df975c6c0445770d0c292bf7547c2cae04a6c0cc57540925',
  ),
  SpeechModelAsset(
    fileName: 'tiny-tokens.txt',
    url: 'https://huggingface.co/csukuangfj/sherpa-onnx-whisper-tiny/resolve/65176e2deb88badc814a94058666cadccc29b61c/tiny-tokens.txt',
    bytes: 816730,
    sha256: 'b34b360dbb493e781e479794586d661700670d65564001f23024971d1f2fa126',
  ),
  SpeechModelAsset(
    fileName: 'silero_vad.onnx',
    url: 'https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/silero_vad.onnx',
    bytes: 643854,
    sha256: '9e2449e1087496d8d4caba907f23e0bd3f78d91fa552479bb9c23ac09cbb1fd6',
  ),
];

/// The legacy Whisper manifest above is retained for reproducible baselines.
/// Production chooses only one language family and its VAD at a time.
class SpeechModelSet {
  const SpeechModelSet({required this.cacheName, required this.assets});
  final String cacheName;
  final List<SpeechModelAsset> assets;
  int get downloadBytes => assets.fold(0, (sum, asset) => sum + asset.bytes);
}

const _vadAsset = SpeechModelAsset(
  fileName: 'silero_vad.onnx',
  url: 'https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/silero_vad.onnx',
  bytes: 643854,
  sha256: '9e2449e1087496d8d4caba907f23e0bd3f78d91fa552479bb9c23ac09cbb1fd6',
);

// VI weights: hynt Zipformer-30M-RNNT-6000h, CC-BY-NC-ND-4.0.
// Unmodified ONNX export by Fangjun Kuang; attribution in ASR_ROUTING_RESULT.md.
const vietnameseSpeechModelSet = SpeechModelSet(
  cacheName: 'zipformer-vi-30m-int8-v1',
  assets: [
    SpeechModelAsset(
      fileName: 'encoder.int8.onnx',
      url: 'https://huggingface.co/csukuangfj2/sherpa-onnx-zipformer-vi-30M-int8-2026-02-09/resolve/83e140db6d23fbb8480fd5fb868f74ab80e7092c/encoder.int8.onnx?download=true',
      bytes: 27699063,
      sha256:
          '8ef5286dd427eb108055c2ddc1982aa31e544706072d5ea228729292dacade68',
    ),
    SpeechModelAsset(
      fileName: 'decoder.onnx',
      url: 'https://huggingface.co/csukuangfj2/sherpa-onnx-zipformer-vi-30M-int8-2026-02-09/resolve/83e140db6d23fbb8480fd5fb868f74ab80e7092c/decoder.onnx?download=true',
      bytes: 5165084,
      sha256:
          'cf2aa385b82c9d5d40cd29c3188af52d0249b3b78f0d4b7eb84ad502d50c7e7f',
    ),
    SpeechModelAsset(
      fileName: 'joiner.int8.onnx',
      url: 'https://huggingface.co/csukuangfj2/sherpa-onnx-zipformer-vi-30M-int8-2026-02-09/resolve/83e140db6d23fbb8480fd5fb868f74ab80e7092c/joiner.int8.onnx?download=true',
      bytes: 1033417,
      sha256:
          '7311d2e17b810ecea515d79c71cc4668af8759256a06fa01d27047772320c821',
    ),
    SpeechModelAsset(
      fileName: 'tokens.txt',
      url: 'https://huggingface.co/csukuangfj2/sherpa-onnx-zipformer-vi-30M-int8-2026-02-09/resolve/83e140db6d23fbb8480fd5fb868f74ab80e7092c/tokens.txt',
      bytes: 23238,
      sha256:
          'ca8171f8bbd516c050b627582f2125c8f5f1f6ed967ab41b0fa9aae2cf61b492',
    ),
    _vadAsset,
  ],
);

// EN/ZH: Alibaba DAMO Academy/FunASR Paraformer, Apache-2.0 upstream.
const englishChineseSpeechModelSet = SpeechModelSet(
  cacheName: 'paraformer-en-zh-small-int8-v1',
  assets: [
    SpeechModelAsset(
      fileName: 'model.int8.onnx',
      url: 'https://huggingface.co/csukuangfj/sherpa-onnx-paraformer-zh-small-2024-03-09/resolve/63ddc3cd0f2810b68289a7b3876e62ef5d53d6df/model.int8.onnx?download=true',
      bytes: 81828675,
      sha256:
          '3ef6c19369b912f7caf3cef8e545c5ccd1a33d9d7ec792a46668dc41c4b229ec',
    ),
    SpeechModelAsset(
      fileName: 'tokens.txt',
      url: 'https://huggingface.co/csukuangfj/sherpa-onnx-paraformer-zh-small-2024-03-09/resolve/63ddc3cd0f2810b68289a7b3876e62ef5d53d6df/tokens.txt',
      bytes: 75352,
      sha256:
          '4b2d964e18b9cf139b473003b6698fb2ed9a2a5ec55b93daa677b28f578897aa',
    ),
    _vadAsset,
  ],
);

SpeechModelSet speechModelSetForLanguage(String languageCode) =>
    switch (languageCode) {
      'vi' => vietnameseSpeechModelSet,
      'en' || 'zh' => englishChineseSpeechModelSet,
      _ => throw ArgumentError.value(
        languageCode,
        'languageCode',
        'Unsupported speech language',
      ),
    };

class SpeechModelAsset {
  const SpeechModelAsset({
    required this.fileName,
    required this.url,
    required this.bytes,
    required this.sha256,
  });
  final String fileName;
  final String url;
  final int bytes;
  final String sha256;
}

class SpeechModelDownloadException implements Exception {
  const SpeechModelDownloadException(this.message, [this.cause]);
  final String message;
  final Object? cause;
  @override
  String toString() => message;
}

class SpeechDownloadCancelled implements Exception {
  const SpeechDownloadCancelled();
  @override
  String toString() => 'Đã hủy tải bộ nhận giọng nói.';
}

class SpeechModelStore {
  SpeechModelStore({
    required this.directory,
    List<SpeechModelAsset> assets = speechModelAssets,
  }) : assets = List.unmodifiable(assets) {
    for (final asset in assets) {
      if (!RegExp(r'^[a-zA-Z0-9][a-zA-Z0-9._-]*$').hasMatch(asset.fileName) ||
          asset.bytes <= 0 ||
          !RegExp(r'^[a-f0-9]{64}$').hasMatch(asset.sha256)) {
        throw ArgumentError('Invalid speech model manifest.');
      }
    }
  }

  final Directory directory;
  final List<SpeechModelAsset> assets;
  HttpClient? _http;
  bool _cancelled = false;

  void cancel() {
    _cancelled = true;
    _http?.close(force: true);
  }

  Future<Directory> prepare({void Function(double)? onProgress}) async {
    _checkCancellation();
    await directory.create(recursive: true);
    final totalBytes = assets.fold<int>(0, (sum, asset) => sum + asset.bytes);
    var completedBytes = 0;
    final progressClock = Stopwatch()..start();
    var lastProgressMs = -120;
    final deadline = DateTime.now().add(const Duration(minutes: 15));

    void report(int bytes, {bool force = false}) {
      if (force || progressClock.elapsedMilliseconds - lastProgressMs >= 120) {
        lastProgressMs = progressClock.elapsedMilliseconds;
        onProgress?.call(
          totalBytes == 0 ? 1 : (bytes / totalBytes).clamp(0.0, 1.0),
        );
      }
    }

    try {
      for (final asset in assets) {
        _checkCancellation();
        final target = File('${directory.path}/${asset.fileName}');
        if (await _matches(target, asset)) {
          completedBytes += asset.bytes;
          report(completedBytes, force: true);
          continue;
        }
        _checkCancellation();
        final partial = File('${target.path}.part');
        RandomAccessFile? output;
        try {
          final client = _http ??= HttpClient()
            ..connectionTimeout = const Duration(seconds: 20)
            ..idleTimeout = const Duration(seconds: 20);
          final request = await client
              .getUrl(Uri.parse(asset.url))
              .timeout(const Duration(seconds: 25));
          request.followRedirects = true;
          request.maxRedirects = 8;
          final response = await request.close().timeout(
            const Duration(seconds: 40),
          );
          if (response.statusCode != HttpStatus.ok) {
            throw SpeechModelDownloadException(
              'Chưa tải được gói giọng nói. Hãy thử lại khi mạng ổn định.',
              '${asset.fileName}: HTTP ${response.statusCode}',
            );
          }
          if (response.contentLength > asset.bytes) {
            throw SpeechModelDownloadException(
              'Gói giọng nói tải về chưa hợp lệ. Hãy thử tải lại.',
              '${asset.fileName}: content length exceeds verified size',
            );
          }
          output = await partial.open(mode: FileMode.write);
          var received = 0;
          await for (final chunk in response.timeout(
            const Duration(seconds: 40),
          )) {
            _checkCancellation();
            if (DateTime.now().isAfter(deadline)) {
              throw const SpeechModelDownloadException(
                'Tải bộ giọng nói quá lâu. Hãy kiểm tra mạng rồi thử lại.',
              );
            }
            received += chunk.length;
            if (received > asset.bytes) {
              throw SpeechModelDownloadException(
                'Gói giọng nói tải về chưa hợp lệ. Hãy thử tải lại.',
                '${asset.fileName}: received bytes exceed verified size',
              );
            }
            await output.writeFrom(chunk);
            report(completedBytes + received);
          }
          await output.flush();
          await output.close();
          output = null;
          _checkCancellation();
          if (!await _matches(partial, asset)) {
            throw SpeechModelDownloadException(
              'Gói giọng nói chưa tải đầy đủ hoặc bị lỗi. Hãy tải lại trước khi thu âm.',
              '${asset.fileName}: size or checksum mismatch',
            );
          }
          _checkCancellation();
          if (await target.exists()) await target.delete();
          await partial.rename(target.path);
          completedBytes += asset.bytes;
          report(completedBytes, force: true);
        } catch (error) {
          if (output != null) await output.close();
          if (await partial.exists()) await partial.delete();
          if (_cancelled) throw const SpeechDownloadCancelled();
          if (error is SpeechModelDownloadException) rethrow;
          throw SpeechModelDownloadException(
            'Không tải được gói giọng nói. Kiểm tra kết nối và dung lượng trống rồi thử lại.',
            error,
          );
        }
      }
      _checkCancellation();
      report(totalBytes, force: true);
      return directory;
    } finally {
      _http?.close(force: true);
      _http = null;
    }
  }

  void _checkCancellation() {
    if (_cancelled) throw const SpeechDownloadCancelled();
  }

  Future<bool> _matches(File file, SpeechModelAsset asset) async {
    if (!await file.exists() || await file.length() != asset.bytes) {
      return false;
    }
    final filePath = file.path;
    final expected = asset.sha256;
    return Isolate.run(() async {
      final digest = await sha256.bind(File(filePath).openRead()).first;
      return digest.toString() == expected;
    });
  }
}
