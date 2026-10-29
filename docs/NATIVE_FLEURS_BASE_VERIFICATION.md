# Candidate Whisper base int8 — native comparison

Android Studio Flutter Run entrypoint: `integration_test/native_fleurs_base_language_test.dart`. Same additional run args: `--dart-define=INTEGRATION_TEST_SHOULD_REPORT_RESULTS_TO_NATIVE=false` and the verified debug renderer fallback. Report: **`NATIVE_FLEURS_BASE_LANGUAGE_REPORT:`**. Progress: `NATIVE_FLEURS_MODEL_CACHE whisper-base-int8-v1`.

This candidate reuses `runNativeFleursLanguageTests` from the earlier test. It changes only model file prefix/assets/cache and preparation timeout; both original FLEURS clips, hashes, references, two keyword checks, case/NFC/legitimate Simplified–Traditional normalization, `transcribe`, explicit `vi`/`zh`, and native decode pipeline stay the same. Tiny's observed 0/2 result remains in [the original result](NATIVE_FLEURS_RESULT.md). Production engine/default models/UI remain unchanged until native evidence justifies adoption.

Base downloads to a **separate** app-support cache `speech-models/whisper-base-int8-v1`; Tiny's cache is preserved. Existing `SpeechModelStore` verifies pinned byte counts/SHA-256 and atomically publishes files. Base requires **160,609,290 bytes** total (about 160.6 MB decimal), downloaded once. Model preparation is bounded to 3 minutes, native decode to 45 seconds; errors/timeouts remain failures. Audio fixtures are embedded in test-only Dart; no TTS/audio network/backend/auth or production assets/dependencies are added.

## Official pinned assets

Exporter: [sherpa-onnx Whisper base repository](https://huggingface.co/csukuangfj/sherpa-onnx-whisper-base), revision **bb53ee204431c90d314c1cc08d28d23e5b7927cc**. ONNX digests are the repository's published LFS SHA-256 object identifiers. **All three downloaded files were checked against the byte counts and digests below on the host**, in `work/native-verification/whisper-base-int8`; this is artifact verification, not native ASR evidence. Encoder URL uses the official resolver's `download=true` option after the host's initial normal resolver transfer stalled; bytes/hash are unchanged. [Whisper weights/code are MIT](https://github.com/openai/whisper#license); sherpa runtime is Apache-2.0.

| File | Bytes | SHA-256 |
| --- | ---: | --- |
| [base-encoder.int8.onnx](https://huggingface.co/csukuangfj/sherpa-onnx-whisper-base/resolve/bb53ee204431c90d314c1cc08d28d23e5b7927cc/base-encoder.int8.onnx?download=true) | 29,120,534 | `0b8fb1304b6109976038efff5ace81720e00386f3ff6b54ee8c75291ca0a1e11` |
| [base-decoder.int8.onnx](https://huggingface.co/csukuangfj/sherpa-onnx-whisper-base/resolve/bb53ee204431c90d314c1cc08d28d23e5b7927cc/base-decoder.int8.onnx) | 130,672,026 | `9759d217388a01b3a4c7c15533201067b48ae819c4daafc8624e64b9409dc02d` |
| [base-tokens.txt](https://huggingface.co/csukuangfj/sherpa-onnx-whisper-base/resolve/bb53ee204431c90d314c1cc08d28d23e5b7927cc/base-tokens.txt) | 816,730 | `b34b360dbb493e781e479794586d661700670d65564001f23024971d1f2fa126` |

## Diagnosis before comparison

Public fixture headers and sample statistics are consistent with normalized mono 16 kHz float32 PCM: VI peak 0.16962/RMS 0.02951/mean 0.0000152; ZH peak 0.36346/RMS 0.03476/mean −0.0000186; no NaN/Inf. sherpa's native WAV reader explicitly supports format 3 float32. The production microphone conversion is little-endian PCM16 divided by 32768, as expected. Both worker and native fixture test specify multilingual Whisper `tiny` (not `tiny.en`), correct pinned multilingual tokens, task `transcribe`, and language `vi`/`zh`. Configuration follows the [official sherpa Dart example](https://github.com/k2-fsa/sherpa-onnx/blob/master/dart-api-examples/non-streaming-asr/bin/whisper.dart).

No sample-rate/scaling/task/language/token mismatch was evidenced in this bounded review. Tiny capacity and quantization sensitivity remain plausible hypotheses, not proven root cause; exact-clip Base comparison tests whether the larger multilingual candidate improves the actual failing behavior. [Whisper documents size/accuracy tradeoffs and language variation](https://github.com/openai/whisper#available-models-and-languages). Base has 74M parameters versus Tiny 39M; upstream Small int8 totals 375,485,327 bytes, above this task's 350 MB candidate-download cap, so Small was not downloaded. Do not claim Base quality or latency before Android results.
