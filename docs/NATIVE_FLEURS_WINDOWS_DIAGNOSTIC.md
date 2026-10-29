# Windows native diagnostic — not Android verification

Ngày 29/10/2026, do AVD bị offline/I/O và AVD mới chưa boot được, root cho phép một chương trình **Dart console thuần** dùng package sherpa-onnx 2.0.1/Windows DLL có sẵn. Không dùng Flutter UI, Python, Gradle, tài khoản hay dữ liệu nhân viên. **Không coi kết quả Windows là Android proof**, không thay kết quả native Android đã lưu.

## Native readWave

Hai WAV FLEURS gốc được đọc qua **sherpa.readWave native thật trên Windows**, không chỉ parse bằng .NET. Số mẫu và sample rate đúng, peak/RMS trùng chính xác với phép đọc host trước đó, nonfinite=0:

| Clip | Samples / Hz | Peak | RMS |
| --- | --- | ---: | ---: |
| Việt | 239040 / 16000 | 0.16962206363677979 | 0.0295126662238795 |
| Mandarin | 119040 / 16000 | 0.3634607791900635 | 0.03476302286781156 |

[Report native WAV](WINDOWS_FLEURS_WAVE_REPORT.json). Không thấy lỗi gain/scaling hoặc float32 WAV trên Windows; không chuyển PCM16 hay sửa waveform. Điều này chưa xác nhận riêng binary native reader Android.

## Runtime Windows và Small

Lần tạo recognizer đầu tiên crash trước inference: C API yêu cầu ONNX API28 nhưng Windows nạp `C:\Windows\System32\onnxruntime.dll` 1.17.x/API17. Package có DLL **1.28.2**; preload bằng đường dẫn đầy đủ tới DLL package trong **script test Windows** đã khắc phục. Không sửa Windows system DLL, pubcache hoặc app Android. Lần decode thực tế báo sherpa native **2.0.1**, ONNX Runtime **1.28.2**.

Đã tải đủ Small int8 chính thức **375.485.327 byte** vào `work/native-verification/whisper-small-int8`, xác minh size/SHA-256 theo [manifest candidate](NATIVE_FLEURS_SMALL_VERIFICATION.md). Cùng hai clip/hash/keyword/NFC đã chốt, **Windows Small đạt 0/2 kiểm tra keyword**. Đây là kết quả sau khi sửa Windows DLL-loading, không phải lỗi tải/runtime.

| Clip | Load | Decode | Thiếu keyword |
| --- | ---: | ---: | --- |
| Việt | 2330 ms | 5692 ms | `động vật`, `hươu cao cổ` |
| Mandarin | 1534 ms | 3604 ms | `哺乳动物`, `科隆群岛` |

Raw Việt:

> Một số loài đậm vật như voi và hỗ cầu cổ, thường hay lại gặn xe và chỉ phải các nhộn cổ bình thường. Chúng ta cũng sẽ quan sát một cách dễ dàng.

Raw Mandarin:

> 因为远离大陆,铺乳动物无法长度发射而来使得巨龟成为客栋群造主要的食

[Report Windows Small nguyên văn đã lọc](WINDOWS_FLEURS_SMALL_REPORT.json). Output có cải thiện ở một số phần so với Tiny Android nhưng không đạt tiêu chí đã chốt; không suy diễn khác nền tảng thành benchmark cải thiện chắc chắn. Không giảm threshold, đổi keyword hoặc chọn lại clip để đạt pass. Không có bằng chứng Android Small/RAM/latency từ lần chạy này; production chưa được đổi bởi diagnostic này. Artifact/audio vẫn theo attribution/license trong [FLEURS provenance](NATIVE_FLEURS_PROVENANCE.md).

## So sánh kiểm soát Base FP32

Root duyệt kiểm tra bỏ quantization bằng **Base FP32**, revision `bb53ee204431c90d314c1cc08d28d23e5b7927cc`. Tải/kiểm hash đủ 292.452.882 byte (encoder 95.087.154, decoder 196.548.998, tokens 816.730). Encoder SHA-256 `5a6b87cb313993f6c9fefec9e7027556f6cb30becddf49655bee36c50ecc12d7`; decoder `8a12c3f6ad65bb5b86d7e6eccc302378f20f9fb2df6cb10747c62895da7ac194`; tokens giữ digest đã xác minh trong manifest Base. Không đổi clip/waveform/keyword/normalization hoặc production.

Kết quả Windows khoảng **19:02**: **0/2 keyword checks**. Native WAV vẫn trùng host. VI load 1693 ms/decode 1998 ms; ZH load 773 ms/decode 1348 ms. Việt vẫn thiếu cả `động vật`/`hươu cao cổ`. Trung trả `因為遠離大陸鋪乳動物無法長度發射而來使得巨龜成為克洞群島主要的失草動物`, vẫn đọc sai `哺乳` và `科隆` dù đã xử lý dạng Traditional hợp lệ của keyword.

[Raw Base FP32 report](WINDOWS_FLEURS_BASE_FP32_REPORT.json) giữ nguyên cả transcript Việt, bao gồm ký tự khác hệ chữ nếu native decoder trả về. Bỏ int8 **chưa giải quyết** tiêu chí chất lượng trên hai câu này, nên không có căn cứ đổi production sang Base FP32 chỉ từ phép thử này. Đây tiếp tục là Windows diagnostic, không phải Android result.
