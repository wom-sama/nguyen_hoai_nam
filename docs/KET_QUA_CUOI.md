# Bản bàn giao Nguyễn Hoài Nam

MSSV2380601398 · Nhóm8 · Sáng thứ6 · Project Flutter **nguyen_hoai_nam**, Android hiển thị **Nguyễn Hoài Nam**. Backend Node/PostgreSQL.

Frontend: https://github.com/wom-sama/nguyen_hoai_nam . Backend: https://github.com/wom-sama/nguyen-hoai-nam-2380601398-api . API production: https://nguyen-hoai-nam-2380601398-api.onrender.com/v1 . Backend sửa sau nộp 8ecdbbc đã Live trên chính URL này. Không đổi khóa, Firebase, applicationId hoặc chứng chỉ ký đã nộp.

## Đã kiểm

- Nguồn sau sửa: **149/149 Flutter tests**, analyzer toàn bộ **No issues found (9,4s)**. Có hồi quy phiên đăng nhập, phản hồi phân quyền, danh sách nhân viên theo chi nhánh, dữ liệu ca đang tải, camera/ảnh và quét mặt tự động. Kiểm thử mock không thay thế kiểm trên thiết bị.
- Backend **109/109 tests** và **6 kiểm tra PostgreSQL thật cho migration 007** đạt. Các kết quả lịch sử trước đó gồm 9 kiểm chứng bàn giao, 12 CRUD/lịch sử, 12 camera và 10 checks camera qua HTTPS; không cộng dồn thành số ca kiểm thử hiện tại.
- Native cùng một phiên: duyệt nhân viên, đổi thành quản lý, hạ về nhân viên đã hiện lần lượt trong tối đa 9,079 / 8,989 / 9,529 giây kể từ readback API; hạ quyền đóng cả route quản lý đang mở. Đây là cận trên thời gian quan sát, không phải cam kết độ trễ. Cold restart sau khi access token hết hạn vẫn khôi phục phiên mà không cần OTP mới sau PATCH cùng email.
- Native ảnh EN→VI đã thấy bản dịch theo vùng trên ảnh. Live CameraX/NV21 nguyên bản 1.0.2+3 đã kiểm TV → Walk14s → NOTICE có nhãn dịch → Reset position → TV xóa nhãn cũ trong cùng phiên, sau bật Enable Animations của VirtualScene. Có từ dịch sai/ngắn không đủ ngữ cảnh; chưa kiểm mọi cặp ngôn ngữ, xoay ảnh hoặc thiết bị thật.
- Native 1.0.2+3 cài đè giữ phiên không OTP mới. Admin đăng nhập OTP thật; form hiển thị đủ ba vai. Lưu QA sang DEMO TP.HCM rồi trả về chi nhánh thử, cả hai lần API đọc lại đúng giá trị. Màn phân ca hiện đúng QA đủ điều kiện với @username. Không thay tài khoản nhóm hoặc ca người khác.
- Native trước đợt đổi stream: mật khẩu+OTP thật/admin và nhân viên; GPSMOCK chấm vào/ra; chia sẻ có hạn/dừng khi rời;3FCM foreground và điều hướng; OCRLatin/Trung và6chiều dịch; hai family giọng nạp/thu/dừng được.
- UI kem–hồng, dấuHN, guide lần đầu, watermark có reduced motion; màn đăng nhập/tài khoản đã bỏ cấu hình URL máy chủ và chữ kỹ thuật không cần thiết.

## Camera bản cuối

JPEG still capture của CameraX trên giả lập từng treo ở takePicture. Source thay bằng **ImageStream/NV21**. Camera dịch xử lý một khung mỗi lần, nghỉ 1,4s sau xử lý, bỏ khung khi bận và dừng khi rời. Bản dịch nằm trên vùng chữ của camera hoặc ảnh. Quét mặt dùng ML Kit tìm đúng một khuôn mặt đủ lớn, gần chính diện và giữ ổn định ít nhất 3 khung/700ms; tự chọn khung đạt để mã hóa PNG trong bộ nhớ. Bộ dò cục bộ không chứng minh danh tính hay chống giả mạo; server vẫn so SFace và yêu cầu OTP cho lần đăng nhập mới.

Chỉ bấm Lưu bản dịch mới gửi văn bản gốc/dịch lên API; lịch sử riêng chỉ chủ tài khoản đọc/xóa, kể cả khi người khác là admin. Bản lưu có thể mở lại để soạn bàn giao, nhưng không tự xác nhận dữ kiện bàn giao.

APK 1.0.1+2 đã build/cài qua Android Studio, giữ nguyên chứng chỉ bản đã nộp và dùng cho các bằng chứng native trên. Bản 1.0.2+3 đã build thành công qua Android Studio trong 163,6 giây, bổ sung sửa Home giữ ca cũ, tắt tự sửa tên/email và chỉnh bố cục ảnh/quét mặt; chữ ký vẫn trùng bản đã nộp. Xem KIEM_TRA_APK.json bên cạnh gói bàn giao để xác định phiên bản thực sự đã xuất và trạng thái cài/kiểm tra.

## Giới hạn cần giữ đúng khi trình bày

Face-positive+OTP đã kiểmAPI bằng ảnh nhân tạo được phép; chưa coi preview là toàn luồng đăng nhập mặtUI hoặc chống giả mạo2D. Giọng có sai và chưa benchmark toàn chuỗi giọng người thật; không biến gate từ khóa0/2cũ thành đạt. GPS dùngMOCK, chưa có điện thoại vật lý/cả nhóm tự cài, tilemap saufix và FCMmàn hình khóa chưa kiểm.

Tính năng đề xuất là **bàn giao kiểm chứng1–3dữ kiện gốc/dịch theo phiên bản**, nhập lại mới xác nhận, sửa hủy proof cũ/giữ audit. Khảo sát đối chứng có giới hạn, không tuyên bố độc quyền toàn thị trường. CMP177 đã được Nam xác nhận theo danh mục, chưa đọc được toàn văn/bài6.

Ba điều bắt buộc: project tên cá nhân, Flutter, API Internet. Mỗi người phải có frontend riêng. Nam đã báo nộp bài; tài liệu/điểm dự kiến trong bản đã nộp được giữ ở bản sao lịch sử, không coi là kết quả kiểm chứng mới. Form vẫn chỉ đọc, không tự điền/gửi lại. Database Free có mốc hết hạn 28/11/2026 ghi nhận lúc tạo; xem SAO_LUU_DATABASE.md và kiểm tra dashboard khi vận hành.

## Chi nhánh demo TP.HCM

API và form quản trị nhận bán kính20–200.000m. Migration006 giữ nguyên bán kính cũ, chỉ nâng giới hạn;98backendtests và8kiểm tra PostgreSQL thật đạt. Chi nhánh **DEMO TP.HCM — Vùng200km** đã tạo, tâm10.7769/106.7009, bán kính200.000m. Vùng tròn có phủ địa phương lân cận, không phải ranh giới hành chính. Cần gán nhân viên và tạo ca ở chi nhánh này trước khi chấm; vẫn kiểm GPS/độ chính xác/thời hạn ca. Không tự chuyển nhân viên hay sửa ca cũ.
