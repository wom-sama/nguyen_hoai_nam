# Small multilingual int8 candidate

Android Studio Flutter Run entrypoint: `integration_test/native_fleurs_small_language_test.dart`; same args `--dart-define=INTEGRATION_TEST_SHOULD_REPORT_RESULTS_TO_NATIVE=false` and verified renderer fallback. Output marker **NATIVE_FLEURS_SMALL_LANGUAGE_REPORT**; `modelVariant=whisper-small-int8`. No TTS/mic/auth/backend needed. Only the official model asset list/prefix/cache/preparation timeout changes; the same two FLEURS clips, hashes, two required keywords and normalization remain fixed.

Cache is separate: `speech-models/whisper-small-int8-v1`. Existing model store downloads/verifies SHA-256 atomically on device. Preparation timeout 5 minutes, decode timeout 45 seconds; download/memory/native/keyword errors remain failures. Stop through Android Studio if the delivery deadline requires it; a stopped/incomplete run is not a pass. **No host Small weights were downloaded; metadata hashes are upstream evidence, and full-byte verification happens on device. Production remains unchanged.**

Before model creation/decode, the shared harness computes **actual deployed sherpa.readWave** peak/RMS/min/max/mean/nonfinite count. It requires finite samples, peak within 0.002 and RMS within 0.001 of the unchanged host originals: VI peak 0.1696220636/RMS 0.0295126662; ZH peak 0.3634607792/RMS 0.0347630229. Values are returned in `nativeWaveStatistics`. Mismatch fails with `waveValidationFailure` and does **not** run inference or adjust gain. This distinguishes a deployed float32 WAV-reading/scaling defect from a model-language keyword failure. Existing Tiny/Base raw results predate this added amplitude diagnostic and are not retroactively claimed to have passed it.

Official [sherpa Whisper small](https://huggingface.co/csukuangfj/sherpa-onnx-whisper-small), pinned revision **8f3c18b358db4d1f2fc1eae49d75cd20989e4309**. [Whisper weights MIT](https://github.com/openai/whisper#license); sherpa runtime Apache-2.0. [Official sherpa instructions](https://k2-fsa.github.io/sherpa/onnx/pretrained_models/whisper/tiny.en.html) explicitly allow replacing tiny.en with small; the same Whisper FFI configuration supports the architecture.

| Asset | Bytes | SHA-256 |
| --- | ---: | --- |
| [small-encoder.int8.onnx](https://huggingface.co/csukuangfj/sherpa-onnx-whisper-small/resolve/8f3c18b358db4d1f2fc1eae49d75cd20989e4309/small-encoder.int8.onnx?download=true) | 112,442,483 | `4cbe7b22fa9026b843b60a68640c747de05bafb1a11b57edc0e66c232d9f33a9` |
| [small-decoder.int8.onnx](https://huggingface.co/csukuangfj/sherpa-onnx-whisper-small/resolve/8f3c18b358db4d1f2fc1eae49d75cd20989e4309/small-decoder.int8.onnx?download=true) | 262,226,114 | `acad50b5c782696e91b55914cc5ab4f756f1532f76e22aa6fc615f39fb69a8ee` |
| [small-tokens.txt](https://huggingface.co/csukuangfj/sherpa-onnx-whisper-small/resolve/8f3c18b358db4d1f2fc1eae49d75cd20989e4309/small-tokens.txt?download=true) | 816,730 | `b34b360dbb493e781e479794586d661700670d65564001f23024971d1f2fa126` |

Total **375,485,327 bytes** (~375.5 MB decimal / 358.1 MiB), within root's revised 450 MB cap. ONNX hashes are published LFS object ids. Token Git blob `a4edf0b719c10d28cd83f8c294449f99ff5d5dc0` matches the already byte-verified Base/Tiny token file; its known SHA-256 is retained.

## Memory/time boundaries

Small has 244M parameters versus Base 74M/Tiny 39M. [Whisper's published ~2GB VRAM figure](https://github.com/openai/whisper#available-models-and-languages) describes a different runtime/precision and is **not** Android CPU-int8 RAM evidence. On a 1536 MB AVD, budget at least the 375 MB model representation plus ONNX Runtime graphs/intermediates, attention/KV buffers, Flutter/native app and Android system; peak may be materially larger than file size. No measured Small peak RAM on this AVD exists yet, so fit/performance is not guaranteed. Native OOM/low-memory/device-offline must be recorded distinctly from a genuine keyword failure; no memory success is inferred from analyzer or metadata.

To recover host space, exactly the three owned Base model files were removed from `work/native-verification/whisper-base-int8` after keeping `verified_manifest.json`, freeing 160,609,290 bytes. No AVD, app source/cache or other artifacts were removed. This does not remove the Base app-support cache on Android.
