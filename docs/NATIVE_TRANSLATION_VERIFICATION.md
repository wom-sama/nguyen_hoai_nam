# Kiểm tra native chức năng f bằng Android Studio

Entrypoint: `integration_test/native_translation_test.dart`. Đây là chương trình kiểm thử tách biệt, không thêm đường đăng nhập, API hay giao diện chẩn đoán vào ứng dụng nộp bài.

1. Mở project Flutter hiện có trong Android Studio; chọn giả lập Android hoặc máy Android thật có mạng và đủ bộ nhớ. Đóng app đang thu mic trước khi chạy.
2. **Run → Edit Configurations → + → Flutter**. Tên tùy chọn: `Native translation verification`. Dart entrypoint: đường dẫn đầy đủ đến `integration_test/native_translation_test.dart` trong project này.
3. Trong **Additional run args**, thêm `--dart-define=INTEGRATION_TEST_SHOULD_REPORT_RESULTS_TO_NATIVE=false`. Giữ các đối số renderer debug mà máy này đã xác minh nếu cần. Không cần `API_BASE_URL`, tài khoản hay backend. Chọn thiết bị Android, rồi **Run** cấu hình đó.
4. Đọc cửa sổ **Run**: bốn test phải pass; lưu dòng `NATIVE_VERIFICATION_REPORT:` cùng model download, log lỗi và tên/API/RAM thiết bị. Mỗi phép đo là thời gian của lần chạy hiện tại, không phải cam kết hiệu năng. File test có timeout riêng; lỗi mạng/model/OCR/FFI làm test fail, không chuyển thành skip/pass.
5. Dừng cấu hình test rồi chạy lại cấu hình app `lib/main.dart` trước khi demo sản phẩm. Gói mô hình đã kiểm SHA-256 nằm trong cùng app support directory để app có thể dùng lại. Ảnh OCR và WAV tạm được xóa sau test. Test không xóa model dịch đã tải.

## Phạm vi chứng minh

- ML Kit Latin OCR đọc ảnh PNG dựng từ câu gốc `SHIFT NAM 2380601398`; Chinese OCR đọc `员工考勤`. Chữ vẽ đen trên trắng bằng renderer thật của Android/Flutter; không truyền chuỗi đáp án vào recognizer. Không có ảnh bên thứ ba.
- `TranslationService` thật dịch lời chào ở cả sáu chiều Việt/Anh/Trung. Kiểm tra ý nghĩa cơ bản với các cách chào hợp lệ, đồng thời bác bỏ việc trả nguyên văn đầu vào. Gói VI/ZH được tải qua ML Kit khi chưa có cache; không giả lập model hay native method channel.
- Whisper tiny int8 chạy qua **sherpa-onnx FFI thật trong Dart isolate**, dùng đúng model manifest, đường cache, config Whisper, `transcribe`, số luồng như worker production. WAV tiếng Anh là mẫu chữ số chính thức của Vosk, 265.914 byte, khoảng 8,3 giây, pinned commit và SHA-256 trong test. Test kiểm tra output có chữ số tương ứng, ghi nguyên transcript/load/decode time để người kiểm tra đánh giá.
- **Chưa chứng minh**: luồng camera/mic vật lý, cắt câu VAD, thu liên tục/queue/pause trên thiết bị, độ chính xác ASR tiếng Việt/Trung, hay độ trễ trên điện thoại thật. Cần demo riêng những phần này; không lấy test ASR tiếng Anh làm bằng chứng cho cả ba ngôn ngữ.

## Nguồn và quyền sử dụng fixture

- Chữ/ảnh OCR được viết và dựng riêng cho project, không chứa dữ liệu nhân viên.
- WAV tải trực tiếp từ [repository Vosk chính thức, commit đã pin](https://github.com/alphacep/vosk-api/blob/78e66149f8ac56a64aa64306c1e8fc132c4eb154/python/example/test.wav). Repository công bố [Apache License 2.0](https://github.com/alphacep/vosk-api/blob/master/COPYING); [hướng dẫn chính thức](https://alphacephei.com/vosk/install) dùng chính `test.wav` làm ví dụ PCM 16 kHz. Chỉ dùng tệp âm thanh; không cài/chạy Vosk hoặc Python. WAV không đóng gói vào asset/source giao diện; được tải vào thư mục tạm khi test chạy.
- Model Whisper/sherpa giữ nguyên manifest/hash và nguồn trong `speech_models.dart`; không suy diễn license model thành license âm thanh.
- [Flutter integration testing](https://docs.flutter.dev/testing/integration-tests), [ML Kit text recognition](https://developers.google.com/ml-kit/vision/text-recognition/v2/android), [ML Kit on-device translation](https://developers.google.com/ml-kit/language/translation/android).

Đã chạy native qua Android Studio ngày 29/10/2026, PID 7572: **4/4 test chức năng pass** lúc 15:27:13. [Kết quả thực tế và giới hạn](NATIVE_TRANSLATION_RESULT.md) ghi transcript, thời gian và snapshot bộ nhớ; đặc biệt transcript ASR còn thiếu/sai chữ số. Analyzer/host widget tests riêng lẻ không chứng minh native pass. Khi chạy lại, phải lưu kết quả mới thay vì suy diễn từ lần chạy trước.
