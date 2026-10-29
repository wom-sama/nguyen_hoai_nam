# Kết quả bản bàn giao — Nguyễn Hoài Nam

MSSV **2380601398**, **nhóm 8**, app chấm công nhân viên. Project/pubspec/thư mục: **nguyen_hoai_nam**. Tên hiển thị Android: **Nguyễn Hoài Nam**. Flutter là framework lập trình di động; backend Node.js/PostgreSQL.

API công khai: **https://nguyen-hoai-nam-2380601398-api.onrender.com/v1**. Health HTTPS đã trả **200** trong lượt kiểm tra cuối. Render Free có thể cần khởi động lại khi lâu không dùng; app không mặc định dùng localhost.

## File sử dụng

- **NGUYEN_HOAI_NAM_2380601398.apk**: bản cài release của Nam, Android 7 trở lên, gồm ARM32/ARM64/x86_64. Chữ ký APK v2 đã xác minh. Hai bản sao outputs và E:\DuAnQuanLyCongNo được đối chiếu SHA-256. Đã cài trên giả lập Android 11, mở hướng dẫn lần đầu và đăng nhập. Bản cuối bao gồm sửa vòng đời camera.
- **SOURCE_CA_NHAN_NGUYEN_HOAI_NAM_2380601398.zip**: source cá nhân Nam, mở thư mục nguyen_hoai_nam bằng Android Studio, Pub get rồi Run. Không phát frontend này để cả nhóm đổi tên và nộp lại.
- **API_CHO_AI_NHOM_8.zip** và **GUI_CHO_AI_CUA_NHOM_8.md**: gửi các bạn/AI của nhóm để làm frontend Flutter riêng. Có URL, đăng ký/OTP/admin duyệt, quyền và hợp đồng API/Postman; không chứa mật khẩu hay frontend.
- **BAN_GIAO_BACKEND_HN_2380601398_2026-10-29.zip**: gói vận hành backend AES-256, có khóa thật theo phạm vi chủ hệ thống cho phép. Mã mở ZIP nằm ở tệp riêng đã bàn giao; chỉ gửi người vận hành được phép. Không đưa BI_MAT vào frontend hoặc Git công khai.

## Bằng chứng kiểm thử

- **Backend 96/96**, PostgreSQL thật **9/9** kiểm chứng bàn giao và **12/12** CRUD/lịch sử; schema thử đã được dọn. API production đã kiểm đăng ký/OTP/phê duyệt, phân ca, chấm vào/ra, trùng công, đơn điều chỉnh, báo cáo và bàn giao có phiên bản.
- **Flutter toàn bộ 87/87**, analyzer **No issues found (8,1 giây)** sau sửa camera. Ba kiểm thử camera kiểm riêng cấp quyền/resume, thứ tự dispose trước tạo mới và dọn controller lỗi.
- Native Android đã kiểm đăng nhập mật khẩu + OTP email thật và trang theo vai; ba thông báo FCM nghiệp vụ cùng điều hướng; chấm vào/ra bằng vị trí MOCK; chia sẻ vị trí hết hạn/ngừng cập nhật khi rời màn hình; OCR và sáu chiều dịch Việt–Anh–Trung.
- Backend đăng ký khuôn mặt nhân tạo và đăng nhập khớp + OTP thật đã đạt. APK cuối đã được thu hồi rồi cấp lại quyền camera để kiểm thử: preview hiển thị ngay lần cấp quyền đầu tiên, không cần Retry. Camera preview đã hiển thị cảnh giả lập; không dùng ảnh tổng hợp làm bằng chứng chống giả mạo hoặc thử người thật.
- Giao diện kem–hồng, dấu HN riêng, hướng dẫn lần đầu có bỏ qua/xem lại, chữ được rút gọn và watermark chuyển động có dừng theo vòng đời/reduced motion.

## Phạm vi còn cần đối chiếu trên thiết bị

Nhận giọng nói production dùng Zipformer Việt và Paraformer Anh/Trung. Hai câu kiểm tra trên Windows cải thiện lỗi toàn câu rõ, nhưng **gate từ khóa vẫn 0/2**, English numeral smoke còn lỗi; đã xác minh nạp hai family và thu/dừng micro trên Android, còn thiếu kiểm độ chính xác chuỗi micro→VAD→nhận giọng→dịch bằng giọng người thật. Đọc **ASR_ROUTING_RESULT.md**; người dùng phải sửa bản chép lời trước khi dùng dữ kiện quan trọng. Không ghi nhận dạng chính xác tuyệt đối.

Chưa có bằng chứng từng thành viên tự cài/chạy, camera/vi trí vật lý trên điện thoại thật, tile map sau sửa giữ trạng thái hoặc thông báo màn hình khóa. Các thử vị trí được ghi rõ MOCK. Giáo trình CMP177 được người dùng xác nhận theo danh mục HUTECH; chưa truy cập được toàn văn giáo trình và tài liệu thực hành bài 6, nên không tuyên bố đã đọc đủ toàn văn.

Tính năng bổ sung: **bàn giao kiểm chứng dữ kiện**. Chọn 1–3 mã thiết bị/số lượng/hạn xử lý có trong cả bản gốc và bản dịch; người nhận nhập lại, server xác nhận theo phiên bản; sửa phiếu hủy xác nhận cũ và giữ lịch sử. Có khảo sát đối chiếu giới hạn trong KHAC_BIET_TINH_NANG.md, không khẳng định đã khảo sát mọi ứng dụng trên thị trường.

Ba điều phải giữ khi nộp: **tên project cá nhân, Flutter, API public trên Internet**. Frontend mỗi bạn phải khác nhau theo đề. Hạn đề: 23:59 ngày 29/10/2026; người dùng yêu cầu bàn giao trước 20:00. Đã đọc form nộp bài theo yêu cầu chỉ đọc. Buổi Sáng thứ 6 đã xác nhận; frontend GitHub riêng được chủ tài khoản cho phép đăng. Còn thiếu video YouTube; tạo APK không đồng nghĩa đã nộp bài.



