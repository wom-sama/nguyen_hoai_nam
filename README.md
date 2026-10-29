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

Android applicationId giữ com.example.nguyen_hoai_nam_2380601398 để khớp Firebase; project/pubspec vẫn là tên cá nhân nguyen_hoai_nam. Bản APK release đã cài thử Android11, xác minh chữ kýv2, minSDK24,target36,ARM32/ARM64/x86_64.

## Chức năng

- Đăng ký email, xác minh và admin duyệt; đăng nhập mật khẩu + OTP, refresh phiên, đăng xuất.
- Admin/quản lý/nhân viên với trang và quyền server tương ứng; giới hạn chi nhánh.
- CRUD nhân viên, chi nhánh, ca và đơn điều chỉnh; phân ca linh hoạt/qua đêm, chấm vào/ra theo giờ server và vị trí, chặn trùng, giữ giờ gốc và lịch sử, bảng công tháng chưa tính lương.
- Dịch camera trực tiếp: đọc ImageStream NV21 trong bộ nhớ, từng khung có giới hạn tần suất; chỉ gửi văn bản khi bấm Lưu. Lịch sử riêng có thể mở lại để sao chép/bàn giao. Backend hiện deploy74c5f34;5tests mới,12checks PostgreSQL và10checks API thật đạt. ImageStream đã mở được preview cảnh NOTICE sau thử lại trên Android11; chưa xác minh toàn luồng OCR–Lưu–lịch sử ở native. Không coi widget tests là toàn luồng camera native.
- a: đối chiếu khuôn mặt trên server rồi OTP; b: chia sẻ vị trí có hạn; f: OCR/dịch ảnh và nhận giọng liên tục Việt–Anh–Trung.
- Bàn giao kiểm chứng1–3 dữ kiện trong cả bản gốc/dịch, nhập lại đúng phiên bản, server tạo xác nhận; sửa phiếu hủy xác nhận cũ và giữ audit.
- FCM phân ca/duyệt đơn/bàn giao; kem–hồng, dấuHN, guide lần đầu, watermark chuyển động có dừng theo vòng đời/reduced motion.

## Kiểm thử

**97/97 Flutter tests**, wholeanalyzer **No issues found14,1s**. Backend **98/98**; PostgreSQL thật **9/9** kiểm chứng bàn giao và **12/12** CRUD/lịch sử. API production và các schema thử được phân biệt trong báo cáo.

Native: đăng nhập OTP thật/trang nhân viên; chấm vào/ra bằng GPS MOCK; chia sẻ vị trí dừng cập nhật khi rời;3FCM nghiệp vụ foreground+điều hướng; OCR Latin/Trung và6chiều dịch. APK cuối đã kiểm camera preview ngay lần cấp quyền đầu, micro cũng thu âm ngay sau cấp quyền đầu, nạp familyViệt vàAnh/Trung rồi dừng sạch. Nhãn Việt/Anh/Trung hiển thị trọn trên màn hình nhỏ.

**Giới hạn:** chưa có bằng chứng mọi thành viên tự cài, thiết bịGPS/khuôn mặt vật lý hoặc notification màn hình khóa. Face-positive+OTP được kiểm ở API bằng chân dung nhân tạo được phép; preview không thay toàn bộ luồng face-positive UI. Nhận giọng trên2câuWindows cải thiện nhưng gate từ khóa0/2; Android mới xác minh nạp model/micro, chưa benchmark độ chính xác lời nói toàn chuỗi. Người dùng cần kiểm/sửa transcript và dữ kiện quan trọng. Chưa đọc được toàn vănCMP177/bài thực hành6; không tuyên bố đã xác minh mọi giới hạn giáo trình hoặc tính độc quyền toàn thị trường.

Chi tiết: [kết quả cuối](docs/KET_QUA_CUOI.md),[đối chiếu đề](docs/DOI_CHIEU_DE_BAI.md),[runtime giọng nói](docs/NATIVE_ASR_RUNTIME_RESULT.md),[kết quả mô hình](docs/ASR_ROUTING_RESULT.md),[hướng dẫn chạy/nộp](docs/HUONG_DAN_NOP_VA_CHAY.md).

## Bàn giao và nộp bài

Source frontend này dành Nam nộp. Nhóm dùng gói API_CHO_AI_NHOM_8.zip để làm frontend riêng; không đổi màu/đổi tên rồi nộp lại source này. ZIP vận hành backend mã hóa chứa khóa thật theo phạm vi chủ tài khoản cho phép, giữ tách biệt khỏi frontend/repository công khai.

Biểu mẫu yêu cầu từng cá nhân có link GitHub frontend, backend, YouTube demo, API và file hovaten.txt tối đa1MB ghi chức năng+điểm tự chấm. Buổi học Sáng thứ 6 đã xác nhận; còn cần video YouTube trước khi tự gửi; công cụ chỉ đọc biểu mẫu, chưa nhập hoặc nộp bài. Hạn thầy:23:59ngày29/10/2026.

## Chi nhánh demo TP.HCM

API và form quản trị nhận bán kính20–200.000m. Migration006 giữ nguyên bán kính cũ, chỉ nâng giới hạn;98backendtests và8kiểm tra PostgreSQL thật đạt. Chi nhánh **DEMO TP.HCM — Vùng200km** đã tạo, tâm10.7769/106.7009, bán kính200.000m. Vùng tròn có phủ địa phương lân cận, không phải ranh giới hành chính. Cần gán nhân viên và tạo ca ở chi nhánh này trước khi chấm; vẫn kiểm GPS/độ chính xác/thời hạn ca. Không tự chuyển nhân viên hay sửa ca cũ.
