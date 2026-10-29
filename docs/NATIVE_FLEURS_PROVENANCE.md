# Native Whisper Việt/Trung — fixture FLEURS

Entrypoint Android Studio Flutter Run: `integration_test/native_fleurs_language_test.dart`. Additional run args: `--dart-define=INTEGRATION_TEST_SHOULD_REPORT_RESULTS_TO_NATIVE=false`, cùng renderer debug fallback đã xác minh. Không tài khoản/backend/quyền mic/TTS. Model Whisper dùng cache đã kiểm hash như production; hai WAV ở helper base64 **chỉ trong integration_test**, không có asset/dependency production mới. Thời hạn mỗi test 2 phút; model cache thiếu hoặc lỗi native vẫn fail. Hai test chức năng ghi `NATIVE_FLEURS_LANGUAGE_REPORT:` kể cả thất bại. **Đã chạy native** PID 4272, kết thúc 18:11:58 ngày 29/10/2026: **0/2 test chức năng pass**, cả hai thiếu keyword từ reference. [Kết quả thực tế và transcript](NATIVE_FLEURS_RESULT.md) được giữ nguyên; không đổi clip/model/assertion để biến kết quả thành pass.

## Nguồn, attribution và license

Audio gốc không chỉnh sửa từ [Google FLEURS chính thức](https://huggingface.co/datasets/google/fleurs), revision **70bb2e84b976b7e960aa89f1c648e09c59f894dd**, phát hành theo **[CC BY 4.0](https://creativecommons.org/licenses/by/4.0/)**. Attribution: Alexis Conneau, Min Ma, Simran Khanuja, Yu Zhang, Vera Axelrod, Siddharth Dalmia, Jason Riesa, Clara Rivera và Ankur Bapna; *FLEURS: Few-shot Learning Evaluation of Universal Representations of Speech* (2022), [arXiv:2205.12446](https://arxiv.org/abs/2205.12446). Giữ attribution/license này khi phân phối helper chứa audio. Chỉ mã hóa base64 để vận chuyển fixture; không crop, resample hay sửa waveform.

Tải từ phần đầu archive bằng .NET GZip/Tar, dừng khi lấy được clip hợp lệ dưới 15 giây có transcript đối chiếu; không tải cả tập, không dùng Python. Clip được chọn **trước khi xem bất kỳ output ASR nào**, không chọn lại theo kết quả model. HF dataset viewer báo giới hạn scan Parquet; archive và TSV chính thức vẫn truy cập công khai không token.

| Fixture | Entry archive | Thời lượng | Bytes | Mẫu |
| --- | --- | ---: | ---: | ---: |
| Việt, `vi_vn` | `dev/10056093347220194289.wav` | 14,94 giây | 956.218 | 239.040 |
| Mandarin, `cmn_hans_cn` | `dev/10149760684641961155.wav` | 7,44 giây | 476.218 | 119.040 |

Cả hai WAV **mono 16 kHz IEEE float32 (format 3), 32-bit**, giữ nguyên byte. Native sherpa [wave-reader.cc](https://github.com/k2-fsa/sherpa-onnx/blob/master/sherpa-onnx/csrc/wave-reader.cc) hỗ trợ format này; test vẫn phải chạy plugin/FFI thật để xác nhận trên thiết bị.

Việt: [archive pin revision](https://huggingface.co/datasets/google/fleurs/resolve/70bb2e84b976b7e960aa89f1c648e09c59f894dd/data/vi_vn/audio/dev.tar.gz), [TSV tham chiếu](https://huggingface.co/datasets/google/fleurs/resolve/70bb2e84b976b7e960aa89f1c648e09c59f894dd/data/vi_vn/dev.tsv). SHA-256 `c32afc1cf9eb6b33753fc979edcb64426dcf677a85958ece9671ea8f78dabfe3`.

> Một số loài động vật như voi và hươu cao cổ thường hay lại gần xe và chỉ với các dụng cụ bình thường chúng ta cũng sẽ quan sát một cách dễ dàng.

Mandarin: [archive pin revision](https://huggingface.co/datasets/google/fleurs/resolve/70bb2e84b976b7e960aa89f1c648e09c59f894dd/data/cmn_hans_cn/audio/dev.tar.gz), [TSV tham chiếu](https://huggingface.co/datasets/google/fleurs/resolve/70bb2e84b976b7e960aa89f1c648e09c59f894dd/data/cmn_hans_cn/dev.tsv). SHA-256 `577a635c2261680c61dda5fecbc4f83bff6f37f453665b8d9d1a68f210f57c0a`.

> 因为远离大陆，哺乳动物无法长途跋涉而来，使得巨龟成为科隆群岛主要的食草动物。

## Kiểm tra đã chốt trước inference

Xác minh độ dài byte + SHA-256, native sample count, 16 kHz, duration dưới 15 giây, transcript không rỗng, và **cả hai keyword** từ reference: Việt `động vật` + `hươu cao cổ`; Trung `哺乳动物` + `科隆群岛`. Việt chuẩn hóa chữ thường và canonical composition của bảng nguyên âm Việt để NFC/NFD tương đương; **không bỏ dấu** hoặc đổi từ. Trung chấp nhận hai dạng hợp lệ tương ứng `哺乳動物` và `科隆群島` bằng map `動→动`, `島→岛`; bỏ khoảng trắng/dấu câu không thay nghĩa. Không thêm synonym/giảm threshold sau khi xem output.

Whisper dùng đúng encoder/decoder int8/tokens, task `transcribe`, language `vi` hoặc `zh`, CPU threads như worker production; inference qua native FFI trong isolate. Ghi raw transcript, model-load/decode latency và failure, không giả lập model hay làm dữ liệu mẫu giống đáp án. Pass keyword trên hai câu đọc không chứng minh chính xác mọi người dùng, chấm điểm WER/CER, mic/VAD liên tục hay dịch end-to-end. Test không dùng TTS, không gửi giọng người dùng hoặc dữ liệu nhân viên.
