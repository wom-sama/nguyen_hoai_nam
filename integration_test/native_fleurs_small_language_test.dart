import 'package:nguyen_hoai_nam/features/translation/speech_models.dart';

import 'native_fleurs_language_test.dart' show runNativeFleursLanguageTests;

/// Candidate only; exact same human fixtures, keywords and native pipeline.
/// No host weight download or production model change is required by this entry.
void main() => runNativeFleursLanguageTests(
  modelPrefix: 'small',
  modelAssets: smallCandidateAssets,
  cacheName: 'whisper-small-int8-v1',
  preparationTimeout: const Duration(minutes: 5),
);

// Official multilingual small export. SHA-256 values for ONNX are upstream
// LFS digests. Tokens share the verified base/tiny Git blob and SHA-256.
// Total 375,485,327 bytes. Whisper weights MIT; sherpa runtime Apache-2.0.
const smallCandidateAssets = <SpeechModelAsset>[
  SpeechModelAsset(
    fileName: 'small-encoder.int8.onnx',
    url: 'https://huggingface.co/csukuangfj/sherpa-onnx-whisper-small/resolve/8f3c18b358db4d1f2fc1eae49d75cd20989e4309/small-encoder.int8.onnx?download=true',
    bytes: 112442483,
    sha256: '4cbe7b22fa9026b843b60a68640c747de05bafb1a11b57edc0e66c232d9f33a9',
  ),
  SpeechModelAsset(
    fileName: 'small-decoder.int8.onnx',
    url: 'https://huggingface.co/csukuangfj/sherpa-onnx-whisper-small/resolve/8f3c18b358db4d1f2fc1eae49d75cd20989e4309/small-decoder.int8.onnx?download=true',
    bytes: 262226114,
    sha256: 'acad50b5c782696e91b55914cc5ab4f756f1532f76e22aa6fc615f39fb69a8ee',
  ),
  SpeechModelAsset(
    fileName: 'small-tokens.txt',
    url: 'https://huggingface.co/csukuangfj/sherpa-onnx-whisper-small/resolve/8f3c18b358db4d1f2fc1eae49d75cd20989e4309/small-tokens.txt?download=true',
    bytes: 816730,
    sha256: 'b34b360dbb493e781e479794586d661700670d65564001f23024971d1f2fa126',
  ),
];
