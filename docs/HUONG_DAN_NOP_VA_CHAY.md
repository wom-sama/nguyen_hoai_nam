# Chạy và nộp bài — Nguyễn Hoài Nam

MSSV **2380601398** · **Nhóm 8** · **Sáng thứ 6** · App chấm công nhân viên.

## Mở bằng Android Studio

1. Clone frontend **https://github.com/wom-sama/nguyen_hoai_nam** hoặc giải nén source cá nhân. Mở đúng thư mục có **pubspec.yaml**, không mở riêng android/.
2. Chọn Flutter SDK, thực hiện Pub get. Chọn Android có Internet/Google Play services, mở **lib/main.dart**, Run.
3. App dùng **https://nguyen-hoai-nam-2380601398-api.onrender.com/v1**. Health: **GET /v1/health**. Không đưa database/JWT/OTP/relay/service-account keys vào app.
4. Đăng ký email riêng → OTP → chờ admin duyệt. Gửi admin username để duyệt, không gửi mật khẩu/OTP. Sau đó đăng nhập username + mật khẩu + OTP email.
5. Cấp camera/vị trí/micro/thông báo khi cần. Tải giọng lần đầu khoảng35MB cho Việt hoặc83MB cho Anh/Trung; ML Kit có model dịch riêng. Chờ tải xong rồi sử dụng.

Project là **nguyen_hoai_nam**, tên hiển thị **Nguyễn Hoài Nam**. Android applicationId giữ **com.example.nguyen_hoai_nam_2380601398** để khớp Firebase. SDK hiện tại đã build/cài Android11, minSDK24, target36.

## Kiểm tra và build

Chạy **lần lượt**, chờ mỗi lệnh xong trước lệnh tiếp theo:

```sh
flutter pub get
flutter test
flutter analyze
```

Sau đó dùng **Build → Flutter → Build APK** trong Android Studio. Không chạy pub get/test/analyze đồng thời với release build vì có race tệp plugin tự sinh của SDK hiện tại; không sửa tay GeneratedPluginRegistrant.java. APK thường ở build/app/outputs/flutter-apk/app-release.apk. Cài và mở thử trước khi gửi.

Bản bàn giao cuối: **87/87 Flutter**, analyzer sạch **8,1s**; backend **96/96**, PostgreSQL **9+12** kiểm tra. APK release đã cài và đăng nhập bằng OTP thật; camera/micro đạt lần cấp quyền đầu. Xem [kết quả và giới hạn](KET_QUA_CUOI.md), [đối chiếu đề](DOI_CHIEU_DE_BAI.md).

## Gửi đúng gói

- **SOURCE_CA_NHAN_NGUYEN_HOAI_NAM_2380601398.zip**: source cá nhân Nam, không dùng cho cả nhóm nộp cùng frontend.
- **API_CHO_AI_NHOM_8.zip**: API/Postman/prompt để các bạn viết frontend Flutter riêng. Không cần server keys hoặc mật khẩu Google để gọi API.
- **BAN_GIAO_BACKEND_HN_2380601398_2026-10-29.zip**: vận hành backend AES-256 có khóa thật theo quyền chủ tài khoản. Chuyển mật khẩu ZIP riêng; không đưa BI_MAT vào Git/APK/public.
- Thành viên đổi Android package phải đăng ký Firebase app/config khớp package riêng. Backend GitHub/API được dùng chung theo đề.

Render Free có cold start: chờ health trở lại trước khi thử. Khi chấm công bị lỗi mạng mơ hồ, đọc lại ca/công để biết server đã ghi hay chưa; không bấm tạo liên tục. Database Free hiện tại hết hạn28/11/2026: [sao lưu/khôi phục](SAO_LUU_DATABASE.md).

## Những mục cần nộp

- Frontend: **https://github.com/wom-sama/nguyen_hoai_nam**.
- Backend: **https://github.com/wom-sama/nguyen-hoai-nam-2380601398-api**.
- API mở kiểm tra: **https://nguyen-hoai-nam-2380601398-api.onrender.com/v1/health**; base frontend là **/v1**.
- YouTube demo: **chưa có link**. Dùng KICH_BAN_VIDEO_NGUYEN_HOAI_NAM.txt để nói gọn, quay đúng chức năng, không lộ mật khẩu/OTP/keys.
- **hovaten.txt** dưới1MB ghi chức năng và điểm dự kiến **8,5/10**. Nhóm8, buổi **Sáng thứ6**, MSSV2380601398, Nguyễn Hoài Nam.

Form đã đọc: **https://docs.google.com/forms/d/e/1FAIpQLSdJ5OOQjod8qE2Rzs-dVd-L6eHXTsRHvPLGYS6_L59-FXWsCg/viewform?usp=header**. Công cụ không điền, chọn, tải tệp hoặc bấm Gửi theo yêu cầu chỉ đọc. Cá nhân tự nộp trước **23:59 ngày29/10/2026**; có APK chưa đồng nghĩa đã nộp.
