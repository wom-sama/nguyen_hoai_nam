# Đối chiếu đề kiểm tra — Nguyễn Hoài Nam

MSSV **2380601398** · **Nhóm 8** · **Sáng thứ 6** · App chấm công nhân viên. Cập nhật bản bàn giao ngày 29/10/2026.

## Đối chiếu chức năng

| Mục đề | Đã hiện thực và kiểm tra | Giới hạn bằng chứng |
|---|---|---|
| 1. Đăng ký | Email → OTP thật → nhân viên chờ duyệt → admin duyệt. Chọn nhánh email theo đề. | Chưa quay đầy đủ thao tác đăng ký mới trên Android cho từng thành viên. |
| 2. Đăng nhập | Username + mật khẩu + OTP email; refresh rotation và logout. Admin/nhân viên đã đăng nhập native bằng OTP thật. | Chưa kiểm mọi tình huống phiên trên mọi thiết bị. |
| 3. Phân quyền | Admin/quản lý/nhân viên; trang theo vai, server kiểm vai/trạng thái/chi nhánh. | Native đã quan sát admin/nhân viên; vai quản lý đã kiểm API. |
| 4. CRUD — 4,5đ | Nhân viên, chi nhánh, ca, đơn điều chỉnh. Có kiểm quyền, lịch sử, bảo vệ admin cuối, giữ giờ chấm gốc. Ca qua đêm, chặn trùng và bảng công tháng. | 12 kiểm tra CRUD/lịch sử trên PostgreSQL thật; không gọi đây là đã thao tác mọi nút CRUD trên Android. |
| 5a. Khuôn mặt | Server YuNet/SFace → khớp → OTP thật → phiên đăng nhập. Mẫu nhân tạo được phép đã chạy production thành công. Camera preview của APK cuối đạt ngay lần cấp quyền đầu. | Chưa chạy trọn luồng face-positive từ camera UI; chưa thử người thật/chống giả mạo. |
| 5b. Vị trí | Chấm vào/ra từ UI → HTTPS → PostgreSQL; chia sẻ có thời hạn, dừng cập nhật khi rời. API kiểm phạm vi quyền và hết hạn. | Tọa độ MOCK của giả lập; chưa kiểm di chuyển GPS vật lý. Tile map sau sửa giữ trạng thái chưa quan sát lại. |
| 5f. Dịch | OCR Latin/Trung và sáu chiều dịch Việt–Anh–Trung trên Android đạt. Giọng liên tục có micro/VAD, Zipformer Việt, Paraformer Anh/Trung; hai family nạp/thu/dừng trên Android. | Chưa xác minh độ chính xác toàn chuỗi giọng người thật → nhận dạng → dịch. Hai fixture Windows còn lỗi tên riêng, gate từ khóa vẫn 0/2; giữ nguyên kết quả này. |
| 6. Tính năng đề xuất — 1đ | Bàn giao kiểm chứng 1–3 dữ kiện có trong gốc/dịch; người nhận nhập lại; server xác nhận theo phiên bản. Sửa phiếu hủy xác nhận cũ, giữ lịch sử. Production đã kiểm sai/đúng/sửa; 9 kiểm tra PostgreSQL đạt. | Đối chiếu dữ kiện không chứng nhận hiểu toàn bộ ngữ nghĩa; khảo sát đối chứng có giới hạn, không tuyên bố độc quyền toàn thị trường. |
| 7. Giao diện/cả nhóm — 1đ | Kem–hồng, dấu HN, bố cục sổ ca riêng; bỏ chữ thừa, guide lần đầu, watermark chuyển động/reduced motion. APK release đã cài và đăng nhập Android 11. | Chưa xác nhận mọi thành viên tự cài/chạy. Backend có thể dùng chung; frontend mỗi người phải riêng. |

## Bổ sung camera trực tiếp

Đã thêm preview camera, tự động lấy khung có giới hạn tần suất, OCR/dịch trên thiết bị, tạm dừng/tiếp tục và lịch sử lưu riêng qua API.5widget tests kiểm không chồng khung, dừng khi xuống nền, xóa ảnh tạm, UUID thử lưu lại và mở lịch sử. Backend mới96tests,12checks PostgreSQL camera và10checks production đạt; source1eadc04đãLive. Native camera nhận chữ/dịch/lưu qua APK mới còn đang kiểm.

## Kết quả cuối

- **97/97 Flutter tests**, analyzer toàn bộ **No issues found (7,4 giây)**, sau sửa micro/camera và nhãn ngôn ngữ.
- **96/96 backend tests**; **9/9** kiểm chứng bàn giao và **12/12** CRUD/lịch sử trên PostgreSQL thật, schema thử đã dọn.
- APK release **xem dung lượng/chữ ký/SHA trong KIEM_TRA_APK.json**, chữ ký v2 hợp lệ, không debuggable; minSDK24, target36, ARM32/ARM64/x86_64. Đã cài thử và đăng nhập bằng OTP thật.
- Ba thông báo FCM nghiệp vụ foreground và điều hướng đã quan sát. Chưa kiểm màn hình khóa/background trên điện thoại thật.
- Camera và micro hoạt động ngay lần cấp quyền đầu. Native ASR đã chứng minh nạp/thu/dừng; điều này không thay bằng chứng độ chính xác nhận lời nói.

Nguồn chi tiết: [kết quả cuối](KET_QUA_CUOI.md), [backend](BACKEND_FINAL_RESULT.md), [dịch native](NATIVE_TRANSLATION_RESULT.md), [ASR native](NATIVE_ASR_RUNTIME_RESULT.md), [đối chứng tính mới](KHAC_BIET_TINH_NANG.md). Các báo cáo thử model cũ được giữ làm lịch sử; không chuyển kết quả không đạt thành đạt.

## Ràng buộc có thể bị 0đ/rớt

- Project/pubspec/thư mục **nguyen_hoai_nam**, tên Android **Nguyễn Hoài Nam**. Giữ applicationId **com.example.nguyen_hoai_nam_2380601398** để khớp Firebase đã đăng ký.
- Mobile dùng **Flutter/Dart**, backend Node/PostgreSQL; không dùng Python viết app.
- API **https://nguyen-hoai-nam-2380601398-api.onrender.com/v1**; cấu hình nộp không dùng localhost/10.0.2.2/IP LAN.
- Frontend cá nhân: **https://github.com/wom-sama/nguyen_hoai_nam**. Không phát source để nhóm đổi màu/đổi tên nộp lại. Backend dùng chung: **https://github.com/wom-sama/nguyen-hoai-nam-2380601398-api**.
- CMP177 bản 2024 đã được Nam xác nhận; chưa truy cập được toàn văn giáo trình/bài thực hành 6, nên không tuyên bố đã đọc hoặc xác minh toàn bộ nội dung đó.
- Từng cá nhân phải nộp theo form, hạn **23:59 ngày 29/10/2026**. Form chỉ được đọc; công cụ chưa điền/tải tệp/gửi.

## Tự chấm dự kiến: 8,5/10

CRUD **4,5/4,5**; a/b/f **2,5/3,5**; tính năng đề xuất **0,75/1**; giao diện/khả năng chạy **0,75/1**. Chưa nhận trọn phần nâng cao do giới hạn native face/độ chính xác giọng nói; dự phòng đánh giá tính mới và việc cả nhóm cài chạy. Giảng viên quyết định điểm cuối.

Database Free hiện tại hết hạn **28/11/2026**; đọc [hướng dẫn sao lưu](SAO_LUU_DATABASE.md). Chưa tạo dump/restore trong phạm vi tài liệu này.
