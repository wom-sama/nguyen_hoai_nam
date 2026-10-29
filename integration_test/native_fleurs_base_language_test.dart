import 'package:nguyen_hoai_nam/features/translation/speech_models.dart';

import 'native_fleurs_language_test.dart' show runNativeFleursLanguageTests;

/// Candidate only. Production still uses tiny until a native improvement is
/// demonstrated on the exact same predefined clips and keyword assertions.
void main() => runNativeFleursLanguageTests(
  modelPrefix: 'base',
  modelAssets: baseCandidateAssets,
  cacheName: 'whisper-base-int8-v1',
  preparationTimeout: const Duration(minutes: 3),
);

// Official sherpa Whisper multilingual base export, pinned HF revision.
// ONNX SHA-256 values are upstream LFS object ids; token digest verified locally.
// Total download 160,609,290 bytes, MIT Whisper weights; sherpa Apache-2.0.
const baseCandidateAssets = <SpeechModelAsset>[
  SpeechModelAsset(
    fileName: 'base-encoder.int8.onnx',
    url: 'https://huggingface.co/csukuangfj/sherpa-onnx-whisper-base/resolve/bb53ee204431c90d314c1cc08d28d23e5b7927cc/base-encoder.int8.onnx?download=true',
    bytes: 29120534,
    sha256: '0b8fb1304b6109976038efff5ace81720e00386f3ff6b54ee8c75291ca0a1e11',
  ),
  SpeechModelAsset(
    fileName: 'base-decoder.int8.onnx',
    url: 'https://huggingface.co/csukuangfj/sherpa-onnx-whisper-base/resolve/bb53ee204431c90d314c1cc08d28d23e5b7927cc/base-decoder.int8.onnx',
    bytes: 130672026,
    sha256: '9759d217388a01b3a4c7c15533201067b48ae819c4daafc8624e64b9409dc02d',
  ),
  SpeechModelAsset(
    fileName: 'base-tokens.txt',
    url: 'https://huggingface.co/csukuangfj/sherpa-onnx-whisper-base/resolve/bb53ee204431c90d314c1cc08d28d23e5b7927cc/base-tokens.txt',
    bytes: 816730,
    sha256: 'b34b360dbb493e781e479794586d661700670d65564001f23024971d1f2fa126',
  ),
];
