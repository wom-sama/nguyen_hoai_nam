# Native speech language — kết quả hiện tại

## Lần chạy lại PID 8283: 1/3 test chức năng pass

Ngày 29/10/2026, Android Studio Flutter Run cùng entrypoint `integration_test/native_speech_language_test.dart`, PID **8283**, Android 11/API 30 x86_64, 2 processors. Dart test bắt đầu **16:23:04.893**, kết thúc **16:23:10.352** với `Some tests failed`: **1/3 test chức năng pass**. Counter `+3 -2` của runner tính thêm setup/teardown, không phải ba test chức năng pass.

**Mic native pass**: nhận **3.200 byte PCM**, **1 frame không rỗng**; thời gian từ yêu cầu start đến stop **1.933 ms**, dưới giới hạn 3 giây; `streamClosed=true`, `isRecordingAfterStop=false`. Config yêu cầu PCM16 mono 16 kHz. Test chỉ đếm độ dài/frame, không lưu âm thanh hoặc log amplitude/nội dung mic. Đây là bằng chứng vận chuyển PCM và stop/release, không chứng minh âm thanh có lời nói hay chuỗi mic → VAD → Whisper → dịch liên tục. Log có warning AudioRecord phục hồi recorder, nhưng những kiểm tra PCM/stop nói trên đều pass.

Hai test Việt/Trung **chưa chạy đến Whisper**. Engine `com.google.android.tts` trả danh sách có 11 voice đúng `vi-VN` và 9 voice đúng `zh-CN`, nhưng không có voice usable đáp ứng điều kiện installed của fixture generator. Bản harness này đã ưu tiên local và cho phép Google Android network voice; cả hai vẫn dừng tại chọn voice, trước synthesis/WAV/ASR. Vì vậy chưa có transcript hay bằng chứng độ chính xác ASR Việt/Trung từ lần chạy này; không xem đây là Whisper nhận dạng sai.

Không thấy OOM/fatal trong snapshot PID 8283 đã đọc. Kết thúc phase ở bằng chứng trên; không hạ assertion, không chạy lại thêm hay đổi production. Nếu cần mở rộng sau, phải thay đổi availability của fixture thật rồi mới chạy lại có giá trị.

## Lịch sử PID 8003: 0/3

Ngày 29/10/2026, Android Studio Flutter Run, entrypoint `integration_test/native_speech_language_test.dart`, PID **8003**, Android 11/API 30 x86_64, 2 processors. Snapshot logcat chỉ đọc cho thấy Dart test bắt đầu **16:07:31.417**, kết thúc **16:08:23.564** với `Some tests failed`: **0/3 test chức năng pass**. Không thấy OOM/fatal trong snapshot đã đọc.

- **Mic**: chưa có kết quả PCM. `hasPermission()` chưa hoàn thành trong hạn 45 giây; record 7.1.2 giữ semaphore cho native request này. Cleanup `stop`/`dispose` xếp sau request còn chờ; timeout dispose tại dòng 122 của harness cũ che lỗi permission ban đầu. Root cấp quyền qua UI lúc 16:09:35, sau khi bộ test kết thúc; quyền có thể được dùng cho lần chạy lại nhưng không biến lần cũ thành pass.
- **Việt**: `No installed offline vi-VN TTS voice`, có 11 voice đúng locale trong danh sách nhưng chưa đáp ứng điều kiện local/installed cũ. Dừng trước tạo WAV và trước Whisper, nên chưa có kết quả ASR Việt.
- **Trung**: `No installed offline zh-CN TTS voice`, có 9 voice đúng locale nhưng chưa đáp ứng điều kiện local/installed cũ. Dừng trước tạo WAV và trước Whisper, nên chưa có kết quả ASR Trung.

Sau chẩn đoán, root cho phép sửa **harness** để giữ/rethrow lỗi mic chính và ghi lỗi cleanup phụ; lỗi cleanup độc lập vẫn fail. Root cũng cho phép TTS platform dùng Google Android network voice đúng locale cho hai câu gốc không nhạy cảm, ưu tiên local, ghi rõ cờ network/voice/engine. Đây là thay điều kiện nguồn fixture, **không đổi keyword ASR, không bỏ lỗi và không sửa production engine**. Nếu engine không synthesize được WAV qua API đang hỗ trợ, test vẫn fail; lựa chọn tiếp theo là cài voice data qua Android settings.

Kết quả native của bản harness cập nhật đã được ghi ở phần PID 8283 phía trên. Cách chạy và giới hạn nằm trong [recipe](NATIVE_SPEECH_LANGUAGE_VERIFICATION.md). Không dùng việc cấp quyền muộn hoặc thay điều kiện fixture để ghi lại lần PID 8003 thành pass.
