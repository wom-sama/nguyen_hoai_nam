# Kiểm tra camera trên Android Emulator

Máy dùng kiểm thử là HN_Final_API30, Android 11, camera sau VirtualScene. Ảnh và video thử là dữ liệu nhân tạo, không dùng webcam hoặc khuôn mặt của người khác.

## Tùy chọn cần kiểm tra

Mở dấu ba chấm của giả lập → Camera → Virtual scene images → bật **Enable Animations**. Giữ ảnh Wall đã chọn và kích thước ảnh. Tùy chọn này thuộc nguồn camera ảo của Emulator, không phải hiệu ứng nền của app.

Trong lần chẩn đoán ngày 30/10/2026, khi tùy chọn tắt, HN giữ khung đầu dù cảnh ảo đã đổi. Đổi sang YUV420 và thử provider Camera2 đều không giải quyết được; toàn bộ các thay đổi thử đã được hoàn nguyên. Bản release **1.0.2+3 CameraX/NV21 nguyên bản** được kiểm lại sau khi bật Enable Animations.

## Kết quả đã quan sát

Trong **cùng một phiên camera**, đi từ TV → Walk14s → NOTICE đã xuất hiện nhãn OCR/dịch theo vùng. Sau Reset position → TV, nhãn cũ được xóa. Không đóng hoặc mở lại camera giữa hai cảnh. Helper `post_submission_qa.mjs`, bước `live-continuous-confirmed`, ghi nhận kết quả lúc **21:59:30 UTC**.

Bằng chứng: [NOTICE có nhãn theo vùng](evidence/native-live-continuous-1-notice.png) và [trở về TV, nhãn cũ đã xóa](evidence/native-live-continuous-2-clear.png).

Timestamp đã tiến lên nhưng log vẫn còn cảnh báo timestamp/khung trùng. Kết quả này xác nhận đổi cảnh và xóa nhãn liên tục trên giả lập đã nêu; không phải số đo FPS, kiểm thiết bị thật hoặc chứng minh liveness/chống giả mạo. **Face-positive từ camera UI vẫn chưa xác minh.** Lưu kết quả/lịch sử và các tình huống khác cần được đối chiếu bằng chứng riêng.

## Cách kiểm đúng

1. Mở Dịch → chọn ngôn ngữ → Dịch trực tiếp qua camera.
2. Hướng tới chữ, rồi chuyển sang vùng không có chữ và quay lại chữ trong **cùng một phiên**. Preview và nhãn phải đổi theo cảnh; nhãn cũ phải được xóa khi không còn chữ.
3. Chạm nhãn để đọc đầy đủ bản gốc/bản dịch. App chủ động tạm dừng camera khi mở phần chi tiết; chọn tiếp tục để quét lại.
4. Thử hủy, mở lại và đưa app xuống nền. Không coi việc mở lại mới thấy ảnh mới là realtime liên tục.

Một khung OCR thành công, kiểm thử mock hoặc camera preview mở được không thay thế các bước trên. Thiết bị Android thật cần được kiểm riêng trước khi dùng cho nghiệp vụ thực tế.

## Căn ảnh thử khuôn mặt

Ảnh nhân tạo đã được đăng ký qua API bằng mật khẩu và OTP đúng email của tài khoản QA riêng. Native nhận ra mặt nhưng hiện còn báo đưa gần hơn; toàn luồng tự quét → server → OTP → dashboard chưa được đánh dấu đạt. Giữ nguyên điều kiện kích thước/chính diện/ổn định; không giảm ngưỡng để lấy kết quả kiểm thử.

Với camera VirtualScene, bấm vào preview của cửa sổ giả lập chính, giữ Alt riêng rồi giữ W khoảng nửa giây để tiến gần, thả W rồi Alt. Các ô Move trong Device Pose dùng inch và có phạm vi nhỏ; không nhập tọa độ mét của macro vào đó vì có thể làm cảnh nhảy sai vị trí. Đây là hướng dẫn cho người kiểm thử, không phải thao tác người dùng app phải thực hiện trên điện thoại thật.
