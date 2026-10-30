# Nguyễn Hoài Nam — App chấm công nhân viên

MSSV **2380601398** · **Nhóm8** · **Sáng thứ 6** · Flutter project **nguyen_hoai_nam** · Android hiển thị **Nguyễn Hoài Nam**.

Frontend cá nhân: **https://github.com/wom-sama/nguyen_hoai_nam**.

API HTTPS: **https://nguyen-hoai-nam-2380601398-api.onrender.com/v1**. Backend công khai: https://github.com/wom-sama/nguyen-hoai-nam-2380601398-api . Không dùng localhost trong bản nộp.

## Chạy bằng Android Studio

1. Mở đúng thư mục nguyen_hoai_nam có pubspec.yaml, chọn Flutter SDK và Pub get.
2. Chọn Android giả lập/điện thoại có Internet, mở lib/main.dart rồi Run.
3. Đăng ký email cá nhân, nhận OTP thật và chờ admin duyệt; đăng nhập bằng username + mật khẩu + OTP email.
4. Cho phép camera/micro/vị trí khi dùng chức năng. Model nhận giọng tải lần đầu khoảng35MB cho Việt hoặc83MB cho Anh/Trung; gói dịch ML Kit tải riêng.
5. Build APK bằng menu Build > Flutter > Build APK. Chạy test/analyze/pub get kết thúc trước khi build; SDK hiện tại có race trên tệp plugin tự sinh nếu chạy song song. Không sửa tay GeneratedPluginRegistrant.java.

Android applicationId giữ com.example.nguyen_hoai_nam_2380601398 để khớp Firebase; project/pubspec vẫn là tên cá nhân nguyen_hoai_nam. Bản APK release trước đợt sửa sau hạn nộp đã cài thử Android11. APK **1.0.1+2** là mốc 139 tests, đã build qua Android Studio (281,2 giây), chữ ký v2 trùng bản đã nộp, minSDK24, target36, ARM32/ARM64/x86_64. Bản **1.0.2+3** đã build qua Android Studio (163,6 giây), chữ ký v2 trùng bản đã nộp; 149/149 tests đạt và analyzer sạch (9,4 giây). Kiểm tra native cuối còn được ghi riêng trong KIEM_TRA_APK.json.

## Chức năng

- Đăng ký email, xác minh và admin duyệt; đăng nhập mật khẩu + OTP, refresh phiên, đăng xuất.
- Admin/quản lý/nhân viên với trang và quyền server tương ứng; giới hạn chi nhánh.
- CRUD nhân viên, chi nhánh, ca và đơn điều chỉnh; phân ca linh hoạt/qua đêm, chấm vào/ra theo giờ server và vị trí, chặn trùng, giữ giờ gốc và lịch sử, bảng công tháng chưa tính lương.
- Dịch camera trực tiếp: đọc ImageStream NV21 trong bộ nhớ, từng khung có giới hạn tần suất; chỉ gửi văn bản khi bấm Lưu. Lịch sử riêng có thể mở lại để sao chép/bàn giao. Mốc kiểm chứng camera có5tests mới,12checks PostgreSQL và10checks API thật đạt. Native release 1.0.2+3 đã đổi cảnh NOTICE có nhãn theo vùng rồi về TV xóa nhãn trong cùng phiên camera; chưa xác minh toàn luồng OCR–Lưu–lịch sử ở native.
- a: đối chiếu khuôn mặt trên server rồi OTP; b: chia sẻ vị trí có hạn; f: OCR/dịch ảnh và nhận giọng liên tục Việt–Anh–Trung.
- Bàn giao kiểm chứng1–3 dữ kiện trong cả bản gốc/dịch, nhập lại đúng phiên bản, server tạo xác nhận; sửa phiếu hủy xác nhận cũ và giữ audit.
- FCM phân ca/duyệt đơn/bàn giao và cập nhật hồ sơ của chính tài khoản; kem–hồng, dấuHN, guide lần đầu, watermark chuyển động có dừng theo vòng đời/reduced motion.

## Sửa luồng tài khoản và quản lý sau hạn nộp — 30/10/2026

Backend bản **8ec** đã Live, giữ nguyên URL API, khóa cấu hình và tên project/package. Khi admin lưu nhân viên với email không đổi, phiên đăng nhập, thiết bị thông báo và OTP đang chờ được giữ lại. Đổi email thật, mật khẩu hoặc khóa tài khoản vẫn thu hồi phiên/thiết bị/OTP; email mới phải được xác minh lại. Đổi vai trò hoặc chi nhánh riêng không buộc nhập OTP lại. Phiên hợp lệ được khôi phục/refresh, không tự lặp luồng OTP khi quay lại ứng dụng.

Ứng dụng đã bổ sung đọc `/me` mỗi 10 giây khi ở foreground và khi nhận FCM `profile_updated` đúng người nhận. Đổi tài khoản/vai trò/trạng thái/chi nhánh làm cập nhật trang tương ứng và hủy cache tài nguyên theo phạm vi cũ; backend vẫn kiểm quyền hiện tại trên mỗi request. 10 giây là chu kỳ polling, không phải SLA.

Danh sách phân ca chỉ chọn người active, đã xác minh email và thuộc đúng chi nhánh. Admin vẫn nhìn thấy người chưa gán chi nhánh trong quản lý nhân viên để gán trước; không bỏ giới hạn chi nhánh hoặc tự đưa người chưa đủ điều kiện vào ca. Lỗi Home giữ ca cũ đã được sửa ở nguồn và có 10 widget tests hồi quy; bản APK 1.0.2+3 đã chứa sửa này; kiểm tra native cuối được ghi riêng.

QA native sau hạn nộp đã đăng ký và xác minh OTP đúng email alias kiểm thử. Trong cùng phiên, giao diện nhận duyệt tài khoản/nâng quản lý/hạ về nhân viên lần lượt trong **≤9,079/8,989/9,529 giây**, tính từ lúc API đọc lại thay đổi đến thời điểm quan sát; khi hạ vai, route quản lý đang mở được tháo. Đây là cận trên của từng lần quan sát, không phải SLA hay phân vị độ trễ. PATCH giữ nguyên email + đọc lại mất 348 ms; sau access token hết hạn, cold restart đã khôi phục phiên không cần OTP mới.

Native APK 1.0.2+3 cài đè giữ phiên; admin đăng nhập OTP thật vào đúng trang quản trị. Form hiển thị đủ ba vai; đã lưu chi nhánh của tài khoản QA sang DEMO TP.HCM và trả về chi nhánh thử, đọc lại API đúng cả hai lần. Màn phân ca hiện đúng QA đủ điều kiện và tên kèm @username; không thay dữ liệu tài khoản nhóm.

Năm mẫu API `/me` riêng đạt 70–248 ms, trung bình 109 ms; chỉ là round-trip API, không thay thời gian cập nhật native ở trên. Native cũng đã thấy ảnh tĩnh Anh→Việt có nhãn dịch theo vùng, còn hạn chế chất lượng dịch. **Live OCR đã đạt đổi cảnh/xóa nhãn trong cùng phiên** trên giả lập sau khi bật Enable Animations, dùng CameraX/NV21 nguyên bản; các thử Camera2/YUV420 đã hoàn nguyên. Timestamp tiến lên nhưng cảnh báo trùng vẫn còn, chưa đo FPS hoặc thử thiết bị thật. **Face-positive qua camera UI vẫn chưa xác minh.** Xem [hướng dẫn và bằng chứng camera giả lập](docs/THU_CAMERA_TREN_GIA_LAP.md); các báo cáo API ở `KIEM_THU_SAU_NOP_API.json` và `DO_TRE_API_HO_SO.json` chỉ thay dữ liệu QA gắn nhãn, không sửa tài khoản nhóm thật.

## Kiểm thử

Nguồn cuối APK 1.0.2+3: **149/149 Flutter tests đạt (11 giây)**, gồm 10 widget tests sửa Home giữ ca cũ; analyzer **No issues found (9,4 giây)**. Baseline 1.0.1+2 giữ mốc **139/139 tests (40 giây)** và analyzer **No issues found (4,7 giây)**. Backend **109/109 tests**; **6/6** kiểm tra migration 007 trên PostgreSQL thật đạt, schema tạm đã dọn. Các mốc trước gồm PostgreSQL thật **9/9** kiểm chứng bàn giao và **12/12** CRUD/lịch sử. Kiểm thử tự động, API production và native được phân biệt.

Native đã ghi nhận ở các bản trước: đăng nhập OTP thật/trang nhân viên; chấm vào/ra bằng GPS MOCK; chia sẻ vị trí dừng cập nhật khi rời;3FCM nghiệp vụ foreground+điều hướng; OCR Latin/Trung và6chiều dịch. APK trước đã kiểm camera preview ngay lần cấp quyền đầu, micro cũng thu âm ngay sau cấp quyền đầu, nạp familyViệt vàAnh/Trung rồi dừng sạch. Nhãn Việt/Anh/Trung hiển thị trọn trên màn hình nhỏ. Các bằng chứng cũ được giữ riêng, không dùng để kết luận toàn bộ bản 1.0.2+3 đã đạt native.

**Giới hạn:** chưa có bằng chứng mọi thành viên tự cài, thiết bịGPS/khuôn mặt vật lý hoặc notification màn hình khóa. Face-positive+OTP được kiểm ở API bằng chân dung nhân tạo được phép; preview không thay toàn bộ luồng face-positive UI. Nhận giọng trên2câuWindows cải thiện nhưng gate từ khóa0/2; Android mới xác minh nạp model/micro, chưa benchmark độ chính xác lời nói toàn chuỗi. Người dùng cần kiểm/sửa transcript và dữ kiện quan trọng. Chưa đọc được toàn vănCMP177/bài thực hành6; không tuyên bố đã xác minh mọi giới hạn giáo trình hoặc tính độc quyền toàn thị trường.

Chi tiết: [kết quả cuối](docs/KET_QUA_CUOI.md),[đối chiếu đề](docs/DOI_CHIEU_DE_BAI.md),[runtime giọng nói](docs/NATIVE_ASR_RUNTIME_RESULT.md),[kết quả mô hình](docs/ASR_ROUTING_RESULT.md),[hướng dẫn chạy/nộp](docs/HUONG_DAN_NOP_VA_CHAY.md).

## Bàn giao và nộp bài

Source frontend này dành Nam nộp. Nhóm dùng gói API_CHO_AI_NHOM_8.zip để làm frontend riêng; không đổi màu/đổi tên rồi nộp lại source này. ZIP vận hành backend mã hóa chứa khóa thật theo phạm vi chủ tài khoản cho phép, giữ tách biệt khỏi frontend/repository công khai.

Biểu mẫu yêu cầu từng cá nhân có link GitHub frontend, backend, YouTube demo, API và file hovaten.txt tối đa1MB ghi chức năng+điểm tự chấm. Buổi học Sáng thứ 6 đã xác nhận; còn cần video YouTube trước khi tự gửi; công cụ chỉ đọc biểu mẫu, chưa nhập hoặc nộp bài. Hạn thầy:23:59ngày29/10/2026.

## Chi nhánh demo TP.HCM

API và form quản trị nhận bán kính20–200.000m. Migration006 giữ nguyên bán kính cũ, chỉ nâng giới hạn; tại mốc triển khai này98backendtests và8kiểm tra PostgreSQL thật đạt. Chi nhánh **DEMO TP.HCM — Vùng200km** đã tạo, tâm10.7769/106.7009, bán kính200.000m. Vùng tròn có phủ địa phương lân cận, không phải ranh giới hành chính. Cần gán nhân viên và tạo ca ở chi nhánh này trước khi chấm; vẫn kiểm GPS/độ chính xác/thời hạn ca. Không tự chuyển nhân viên hay sửa ca cũ.
