# Bản bàn giao Nguyễn Hoài Nam

MSSV2380601398 · Nhóm8 · Sáng thứ6 · Project Flutter **nguyen_hoai_nam**, Android hiển thị **Nguyễn Hoài Nam**. Backend Node/PostgreSQL.

Frontend: https://github.com/wom-sama/nguyen_hoai_nam . Backend: https://github.com/wom-sama/nguyen-hoai-nam-2380601398-api . API production: https://nguyen-hoai-nam-2380601398-api.onrender.com/v1 . Runtime API camera1eadc04đãLive và kiểm HTTPS thật.

## Đã kiểm

- **97/97 Flutter tests**, analyzer toàn bộ **No issues found (7,4s)**. Có kiểm cả ba vai, admin thêm chi nhánh/manager chỉ đọc, vòng đời camera,7trường hợp NV21/stride/xoay và mã hóa PNG giữ pixel/chiều ảnh.
- **96/96 backend tests**; PostgreSQL thật9kiểm chứng bàn giao +12CRUD/lịch sử +12camera; schema thử đã dọn. Camera production thêm10checks lưu/đọc/chống trùng/phân quyền/xóa bản ghi thử qua HTTPS.
- Native trước đợt đổi stream: mật khẩu+OTP thật/admin và nhân viên; GPSMOCK chấm vào/ra; chia sẻ có hạn/dừng khi rời;3FCM foreground và điều hướng; OCRLatin/Trung và6chiều dịch; hai family giọng nạp/thu/dừng được.
- UI kem–hồng, dấuHN, guide lần đầu, watermark có reduced motion; màn đăng nhập/tài khoản đã bỏ cấu hình URL máy chủ và chữ kỹ thuật không cần thiết.

## Camera bản cuối

JPEGstillcapture củaCameraX trên giả lập đã treo ở takePicture. Source cuối thay bằng **ImageStream/NV21**, không dùng takePicture cho dịch trực tiếp hoặc chụp khuôn mặt. Camera dịch xử lý một khung mỗi lần, nghỉ1,4s sau xử lý, bỏ khung khi bận, dừng camera khi rời. Ảnh khuôn mặt chọn từ luồng được chuyểnPNG trong bộ nhớ và chỉ gửi khi người dùng bấm chụp. Không tạo tệpảnh tạm cho hai luồng này.

Chỉ bấm Lưu bản dịch mới gửi văn bản gốc/dịch lên API; lịch sử riêng chỉ chủ tài khoản đọc/xóa, kể cả khi người khác là admin. Bản lưu có thể mở lại để soạn bàn giao, nhưng không tự xác nhận dữ kiện bàn giao.

APK cuối đang build/cài để đối chiếu native; chữ ký/kích thước/hashes và trạng thái cài ở KIEM_TRA_APK.json bên cạnh gói bàn giao. Các widgettests không thay thế bằng chứng camera native.

## Giới hạn cần giữ đúng khi trình bày

Face-positive+OTP đã kiểmAPI bằng ảnh nhân tạo được phép; chưa coi preview là toàn luồng đăng nhập mặtUI hoặc chống giả mạo2D. Giọng có sai và chưa benchmark toàn chuỗi giọng người thật; không biến gate từ khóa0/2cũ thành đạt. GPS dùngMOCK, chưa có điện thoại vật lý/cả nhóm tự cài, tilemap saufix và FCMmàn hình khóa chưa kiểm.

Tính năng đề xuất là **bàn giao kiểm chứng1–3dữ kiện gốc/dịch theo phiên bản**, nhập lại mới xác nhận, sửa hủy proof cũ/giữ audit. Khảo sát đối chứng có giới hạn, không tuyên bố độc quyền toàn thị trường. CMP177 đã được Nam xác nhận theo danh mục, chưa đọc được toàn văn/bài6.

Ba điều bắt buộc: project tên cá nhân, Flutter, APIInternet. Mỗi người phải có frontend riêng. Điểm tự chấm8,5chỉ là dự kiến. Form chỉ đọc, chưa điền/gửi; Nam còn cần YouTube demo và tự nộp trước23:59ngày29/10/2026. DatabaseFree hết hạn28/11/2026; xem SAO_LUU_DATABASE.md.
