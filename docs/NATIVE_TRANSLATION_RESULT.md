# Kết quả kiểm tra native chức năng f — 29/10/2026

Android Studio đã chạy Flutter Run entrypoint `integration_test/native_translation_test.dart`, với `INTEGRATION_TEST_SHOULD_REPORT_RESULTS_TO_NATIVE=false`. Đọc logcat chỉ đọc của PID **7572** trên `emulator-5554`: bắt đầu test **15:25:43**, kết thúc **15:27:13**, dòng cuối `All tests passed!` lúc **15:27:13.911**. Có **4/4 test chức năng pass**; bộ đếm `+6` của runner tính thêm setup và teardown, không phải sáu test chức năng.

Môi trường báo cáo: Android 11/API 30, `sdk_gphone_x86_64-userdebug`, 2 bộ xử lý. Đây là một lần chạy debug trên giả lập; không phải số đo điện thoại thật hay cam kết tốc độ.

| Kiểm tra native thật | Kết quả nhận được | Thời gian lần chạy |
| --- | --- | ---: |
| ML Kit Latin OCR | `SHIFT NAM 2380601398` | 3.677 ms |
| ML Kit Chinese OCR | `员工考勤` | 2.569 ms |
| Anh → Việt | `Hello` → `Xin chào` | 12.506 ms |
| Việt → Anh | `Xin chào` → `Hi` | 105 ms |
| Anh → Trung | `Hello` → `你好` | 9.213 ms |
| Trung → Anh | `你好` → `Hello` | 142 ms |
| Việt → Trung | `Xin chào` → `您好` | 187 ms |
| Trung → Việt | `你好` → `Xin chào` | 345 ms |

Hai chiều dịch đầu tiên theo từng gói ngôn ngữ gồm việc chuẩn bị/tải model chưa có cache. Không so sánh trực tiếp các số đó với những chiều chạy sau đã có model.

Whisper tiny int8 thực thi qua sherpa-onnx FFI trong Dart isolate, sử dụng model/config production và WAV chính thức 16 kHz dài **8,308 giây**. Chuẩn bị/tải và kiểm hash model: **58.844 ms**; tạo recognizer: **581 ms**; decode: **354 ms**. Transcript nguyên văn: **`0101 902101803`**. Fixture SHA-256: `dcfea5712c43a43ba7ae8083afb39d36993e5a69c46e88b68aaa72b65cb615bb`.

**Đây là bằng chứng native FFI/model có chạy và trả transcript, không phải bằng chứng ASR chính xác hoàn toàn.** Test chỉ kiểm tra output không rỗng và có chữ số tương ứng; transcript thực tế còn thiếu/sai chữ số so với nội dung mẫu. Không đổi assertion để biến một lỗi thành pass. Lần chạy này cũng chưa chứng minh ASR Việt/Trung, thu mic liên tục, VAD, queue/pause, ảnh camera vật lý hoặc chất lượng trên máy thật.

Snapshot `dumpsys meminfo 7572` sau test: **TOTAL PSS 359.905 KB** (khoảng 351 MiB), **TOTAL RSS 437.640 KB** (khoảng 427 MiB). Đây là bộ nhớ tại thời điểm chụp sau test, **không phải peak** và không phải baseline app chấm công đang sử dụng bình thường.

Log lần chạy có cảnh báo Google Play Services **found 201817023**, trong khi thành phần FCM yêu cầu **261200000** (`SERVICE_VERSION_UPDATE_REQUIRED`). Đây là cảnh báo môi trường cần theo dõi, chưa đủ kết luận FCM thất bại: trước đó root đã có Google chấp nhận direct self-FID probe lúc **14:41** và foreground banner native thật lúc **14:46** trên cùng SDK 17.0.1/AVD, với [ảnh bằng chứng](../../android-fcm-foreground-received.jpg). App main sau lần test này **chưa được kiểm tra lại FCM** tại thời điểm ghi kết quả; không suy diễn kết quả test OCR/dịch/ASR thành kết quả push.

Nguồn fixture, license, cách chạy lại và phạm vi các test được ghi trong [recipe kiểm tra native](NATIVE_TRANSLATION_VERIFICATION.md). Không có mật khẩu, token phiên, FID hay dữ liệu nhân viên trong tài liệu này.
