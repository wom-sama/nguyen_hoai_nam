# Luồng tài khoản và cài đặt 1.1.0

Giữ nguyên project `nguyen_hoai_nam`, applicationId, chứng thư ký, Firebase và API đã nộp. Backend: `https://nguyen-hoai-nam-2380601398-api.onrender.com/v1`.

## Sử dụng

1. Đăng ký bằng email cá nhân, xác nhận OTP và chờ admin duyệt/gán chi nhánh.
2. Đăng nhập bằng tên đăng nhập + mật khẩu + OTP gửi đúng email của tài khoản. Phiên đang hợp lệ được khôi phục, không hỏi lại OTP khi mở chức năng.
3. Nếu chưa có phương thức sinh trắc, đăng ký ít nhất khuôn mặt hoặc vân tay trước khi vào nghiệp vụ. Vân tay cần máy có cảm biến và vân tay đã đăng ký trong Android; đăng ký liên kết trong vòng 15 phút sau mật khẩu + OTP.
4. Lần sau: khuôn mặt đã đăng ký dùng trên các thiết bị; vân tay dùng trên thiết bị đã liên kết. Hai phương thức cấp phiên trực tiếp, không gửi OTP. Khóa vân tay bị vô hiệu khi dữ liệu sinh trắc Android thay đổi thì đăng nhập mật khẩu + OTP và liên kết lại.
5. Tài khoản → Cài đặt và hồ sơ: sửa tên, điện thoại, địa chỉ, avatar; đổi cỡ chữ 80–160%, màu chữ, màu chủ đạo, ảnh nền. Bấm Lưu để đồng bộ lên backend. `/me` chỉ báo phiên bản; ảnh tải lại khi phiên bản thay đổi.
6. Đổi email: OTP riêng gửi email cũ và email mới, nhập đúng cả hai trong 10 phút. Sau đó một admin khác duyệt trong 24 giờ; chủ yêu cầu không tự duyệt. Sau khi duyệt, các phiên và liên kết vân tay cũ bị thu hồi; đăng nhập lại bằng email nhận OTP mới. Không sửa email trực tiếp qua CRUD nhân viên.

## Hợp đồng cho frontend riêng của nhóm

Mọi đường dẫn dưới đây nối sau `/v1`. API bảo vệ dùng `Authorization: Bearer <accessToken>` của chính người đang đăng nhập. Khóa server không đưa vào frontend.

| API | Dữ liệu / kết quả |
|---|---|
| POST `/auth/face-login` | `{username,imageBase64}` → `{accessToken,refreshToken,user}`; không còn challenge OTP |
| GET `/fingerprint/status?deviceId=<UUID>` | Đăng nhập trước; trả `registered,device,canEnroll,username` |
| POST `/fingerprint/enroll` | Phiên mật khẩu+OTP mới ≤15 phút; `{deviceId,publicKey,deviceName}`; public key PEM SPKI RSA 2048–4096/P-256 |
| POST `/auth/fingerprint/challenge` | `{username,deviceId}` → `challengeId,payload,expiresAt` (2 phút) |
| POST `/auth/fingerprint/verify` | `{username,deviceId,challengeId,signature}`; ký nguyên UTF-8 payload bằng SHA-256, chữ ký base64 → phiên trực tiếp |
| DELETE `/fingerprint/devices/:id` | Chỉ gỡ thiết bị thuộc tài khoản đang đăng nhập |
| GET `/me/profile` | Hồ sơ + `appearance` + `profileVersion` |
| PATCH `/me/profile` | Chỉ `fullName,phone,address,avatarBase64`; avatar PNG/JPEG base64 ≤300 KiB |
| PATCH `/me/appearance` | `fontScale,textColor,primaryColor,backgroundBase64`; màu `#RRGGBB`, ảnh ≤650 KiB; trả hồ sơ đã lưu |
| POST `/me/email-change` | `{newEmail}` → `requestId,maskedOldEmail,maskedNewEmail,status,expiresAt,retryAfterSeconds` |
| POST `/me/email-change/:id/verify` | `{oldCode,newCode}` → `pending_approval`; sai mã HTTP422, không tự retry bằng refresh token |
| GET `/me/email-change` | Yêu cầu gần nhất của người đăng nhập |
| GET `/email-change-requests` | Admin xem danh sách chờ duyệt |
| POST `/email-change-requests/:id/review` | Admin khác: `{decision:'approved'}` hoặc `'rejected'` |

Backend migrations 008/009 bổ sung hồ sơ, yêu cầu đổi email, khóa công khai thiết bị và nonce. Không đổi các migration cũ hay khóa vận hành. Các frontend nhóm đang dùng face-login theo hợp đồng cũ cần chuyển sang nhận phiên trực tiếp.

## Giới hạn xác thực

Khuôn mặt là so khớp ảnh 2D YuNet/SFace, chưa có liveness/chống ảnh giả. Android giữ khóa riêng; server xác minh chữ ký, không nhận ảnh vân tay. Android BiometricPrompt có thể chọn phương thức sinh trắc mạnh khác trên máy đa cảm biến; không cho PIN thay bằng chứng sinh trắc. Khả năng phần cứng không được suy ra từ unit test hoặc chữ ký mô phỏng; trạng thái kiểm thử APK thực tế ghi riêng trong báo cáo bàn giao.
