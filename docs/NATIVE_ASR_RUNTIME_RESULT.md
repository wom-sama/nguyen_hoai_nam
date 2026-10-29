# Kiểm tra runtime giọng nói trên Android

Thiết bị: giả lập Android 11 HN_Final_API30, APK release nguyen_hoai_nam.

- Zipformer tiếng Việt: tải/kiểm hash, nạp model, mở micro PCM và dừng sạch đã quan sát trên app.
- Paraformer Anh/Trung: đã chuyển từ family Việt, nạp model, chọn nguồn Anh và mở/dừng micro trên app.
- Bản cuối đã thu hồi quyền RECORD_AUDIO rồi thử lại: cấp quyền lần đầu và phiên thu âm tiếp tục ngay, không cần bấm lại.
- Nhãn chọn ngôn ngữ hiển thị Việt / Anh / Trung; menu và nhãn hỗ trợ tiếp cận giữ tên đầy đủ.
- PSS đo một thời điểm sau dừng phiên Việt: 255800 KiB, khoảng250 MiB. Đây không phải peak RAM hoặc benchmark so sánh.

Phạm vi này xác nhận nạp model và vòng đời micro trên Android, KHÔNG thay kết quả độ chính xác FLEURS/giọng người thật. Hai câu FLEURS mới được suy luận trên Windows; gate từ khóa vẫn0/2. Xem ASR_ROUTING_RESULT.md và JSON báo cáo nguyên văn.

82 kiểm thử Flutter đạt; analyzer toàn bộ sạch27,1s. Build release đã thành công khi chạy riêng sau test/analyze. Không chạy Flutter pub get/test/analyze song song build release do tệp plugin tự sinh dùng chung.
