# Nhận dạng theo ngôn ngữ — kết quả và phạm vi

Production chọn **Zipformer-30M tiếng Việt** khi nguồn là `vi`; **Paraformer nhỏ Anh/Trung** khi nguồn `en` hoặc `zh`. Chỉ một family recognizer được nạp tại một thời điểm; chuyển family đóng worker/native handles cũ trước khi nạp gói mới. EN↔ZH dùng cùng model. Mỗi family có cache/hash riêng và Silero VAD: lần đầu khoảng **35 MB VI** hoặc **83 MB EN/ZH**, chưa tính gói dịch ML Kit. Download pin HTTPS/SHA-256, ghi atomic, cancel/stop/drain và queue giới hạn giữ nguyên.

## Bằng chứng chọn model

Các phép thử Windows native Sherpa FFI dùng **đúng hai WAV FLEURS đã pin**, waveform/hash/reference/keyword không đổi, native readWave trùng host. **Test keyword vẫn 0/2**: không gọi đây là pass. Zipformer trả `HƯ` thay `HƯƠU`; Paraformer trả `克隆` thay tên riêng `科隆`. Raw transcript nằm trong [report routing](WINDOWS_FLEURS_ROUTED_REPORT.json).

Implementation được chọn dựa trên cải thiện lỗi toàn câu, không hạ assertion keyword. [Số đo paired](ASR_PAIRED_FIXTURE_METRICS.json) dùng Levenshtein: NFC, lowercase, bỏ punctuation; Việt tách từ theo whitespace; Trung so ký tự và chuẩn hóa Simplified/Traditional hợp lệ bằng Windows NLS. Đây là **phân tích sau phép thử trên hai câu**, không phải benchmark tổng quát hay pass gate ban đầu.

| Model/platform | VI WER (34 từ) | ZH CER (35 ký tự) |
| --- | ---: | ---: |
| Tiny / Android | 22 lỗi · 64,71% | 27 lỗi · 77,14% |
| Base FP32 / Windows | 14 lỗi · 41,18% | 7 lỗi · 20,00% |
| Zipformer VI + Paraformer EN/ZH / Windows | **1 lỗi · 2,94%** | **5 lỗi · 14,29%** |

Base FP32→routing là so sánh trên cùng Windows runtime; Tiny Android khác nền tảng nên không dùng bảng để cô lập nguyên nhân hoặc cam kết tốc độ Android. Windows load/decode: VI 7.639/874 ms; ZH 1.483/328 ms. Một lần chạy chưa đo peak RAM, mic→VAD→ASR→dịch end-to-end, hay hiệu năng điện thoại thật. **Đã kiểm nạp hai family và thu/dừng micro native Android; chưa kiểm độ chính xác toàn chuỗi bằng giọng người thật.** Xem NATIVE_ASR_RUNTIME_RESULT.md.

English correctness smoke dùng lại WAV Vosk chính thức đã pin trong phép thử trước (8,308 giây, 132.928 mẫu/16 kHz). Paraformer Windows trả `one zero zero zero one i know two one o zero one eighth zero three`; load 21.043 ms/decode 759 ms trong lần chạy host đang tải. Chuỗi đầu `10001` đúng, nhưng kiểm tra cả chuỗi cuối `01803` **fail** vì output khác (`eighth`/`o`); không đổi cách normalize sau khi thấy kết quả để tạo pass. [Report English nguyên văn](WINDOWS_PARAFORMER_ENGLISH_REPORT.json). Chưa có cam kết chép đúng toàn bộ số tiếng Anh.

Kiểm tra source sau routing: scoped Dart analyzer **No issues found**; **19/19 targeted tests pass** (routing/lifecycle/buffer/hash-store/history UI). Các test này không được gọi là 19 phép thử ASR native hoặc Android runtime proof.

Không tự sửa chữ, thêm keyword prompt hay thay nội dung gốc. Kết quả có thể sai tên riêng, số lượng/giờ và từ gần âm; người dùng phải đối chiếu và sửa bản gốc/bản dịch trong form bàn giao trước khi gửi hoặc xác nhận công việc quan trọng. Giao diện nhập chữ và form bàn giao vẫn chỉnh sửa được.

## Nguồn và license model

**VI:** *Zipformer-30M-RNNT-6000h — hynt*. [Upstream](https://huggingface.co/hynt/Zipformer-30M-RNNT-6000h) khai báo **CC BY-NC-ND 4.0** (card pin `ad6f873b5f5b6ed083821253a88d81afed2505c4`), không phải Apache/MIT. Dùng cho sản phẩm môn học phi thương mại; file ONNX tải nguyên trạng. ONNX export/package: Fangjun Kuang / sherpa-onnx, [repo](https://huggingface.co/csukuangfj2/sherpa-onnx-zipformer-vi-30M-int8-2026-02-09), pin `83e140db6d23fbb8480fd5fb868f74ab80e7092c`. Không gộp license runtime vào license weights.

**EN/ZH:** Paraformer — Alibaba DAMO Academy / FunASR. [Checkpoint upstream](https://modelscope.cn/models/iic/speech_paraformer_asr_nat-zh-cn-16k-common-vocab8358-tensorflow1/summary) khai báo **Apache License 2.0**. [ONNX quantization](https://www.modelscope.cn/models/crazyant/speech_paraformer_asr_nat-zh-cn-16k-common-vocab8358-onnx/summary): crazyant; package sherpa: Fangjun Kuang. [Repo export](https://huggingface.co/csukuangfj/sherpa-onnx-paraformer-zh-small-2024-03-09), pin `63ddc3cd0f2810b68289a7b3876e62ef5d53d6df`. README export xác định chuỗi nguồn; không có license riêng của repo export để suy diễn khác upstream.

Runtime sherpa-onnx Apache-2.0; audio FLEURS CC BY 4.0 theo [provenance fixture](NATIVE_FLEURS_PROVENANCE.md). Danh sách file/bytes/pin/SHA đầy đủ trong `lib/features/translation/speech_models.dart`; tổng hai model không gồm VAD là 115.824.829 byte. Host đã kiểm toàn bộ model và token đã tải với SHA chính thức trước inference. Cấu hình native: FeatureConfig 16 kHz/80 bins; VI transducer encoder/decoder/joiner, EN/ZH paraformer single model; auto-detect model type, CPU một thread, greedy search.

