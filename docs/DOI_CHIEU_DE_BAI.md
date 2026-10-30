# Đối chiếu đề kiểm tra — Nguyễn Hoài Nam

MSSV **2380601398** · **Nhóm 8** · **Sáng thứ 6** · App chấm công nhân viên. Bản bàn giao ngày 29/10/2026; bổ sung sửa luồng tài khoản/quản lý sau hạn nộp ngày 30/10/2026.

## Đối chiếu chức năng

Bản 1.1.0 cập nhật luồng sinh trắc, hồ sơ và email theo [hợp đồng hiện tại](CAP_NHAT_1.1.0.md). Khuôn mặt/vân tay cấp phiên trực tiếp không OTP; chỉ đăng ký và đăng nhập mật khẩu dùng OTP, ngoài bước xác nhận đổi email được yêu cầu riêng. Các quan sát native 1.0.x bên dưới được giữ như lịch sử, chưa phải bằng chứng cho APK mới.

| Mục đề | Đã hiện thực và kiểm tra | Giới hạn bằng chứng |
|---|---|---|
| 1. Đăng ký | Email → OTP thật → nhân viên chờ duyệt → admin duyệt. QA native sau hạn nộp đã đăng ký và xác minh OTP đúng alias kiểm thử. Chọn nhánh email theo đề. | Một tài khoản QA được kiểm, chưa đại diện việc từng thành viên tự đăng ký/chạy. |
| 2. Đăng nhập | Username + mật khẩu + OTP email; refresh rotation và logout. Email cũ không thu hồi phiên, email thật/mật khẩu/khóa vẫn thu hồi. Native đã khôi phục phiên qua cold restart sau access expiry mà không cần OTP mới. | Chưa kiểm mọi tình huống phiên trên mọi thiết bị. |
| 3. Phân quyền | Trang theo vai và server kiểm quyền hiện tại. `/me` foreground 10 giây + FCM hồ sơ đúng tài khoản; đổi phạm vi hủy cache. Native cùng phiên đã thấy duyệt/nâng quản lý/hạ nhân viên; hạ vai tháo route quản lý đang mở. | Cận trên từng lần quan sát ≤9,079/8,989/9,529 giây, không phải SLA; chưa kiểm mọi thiết bị hoặc mọi luồng. |
| 4. CRUD — 4,5đ | Nhân viên, chi nhánh, ca, đơn điều chỉnh. Có kiểm quyền, lịch sử, bảo vệ admin cuối, giữ giờ chấm gốc. Ca qua đêm, chặn trùng và bảng công tháng. Phân ca chỉ cho người active, email verified, cùng chi nhánh; admin vẫn thấy người chưa gán chi nhánh để gán trước. | 12 kiểm tra CRUD/lịch sử trên PostgreSQL thật; native 1.0.2+3 đã lưu/đọc lại hai lần đổi chi nhánh QA và thấy đúng QA đủ điều kiện phân ca. Home có 10 widget tests hồi quy; chưa thao tác mọi nút CRUD hoặc lưu phân ca mới trên Android. |
| 5a. Khuôn mặt | Server YuNet/SFace → khớp → phiên trực tiếp, không OTP từ 1.1.0. Kiểm thử API chạy mô hình thật với ảnh cùng/khác người. | Chưa chạy trọn luồng face-positive từ camera UI của APK mới; chưa thử người thật/chống giả mạo. |
| 5b. Vị trí | Chấm vào/ra từ UI → HTTPS → PostgreSQL; chia sẻ có thời hạn, dừng cập nhật khi rời. API kiểm phạm vi quyền và hết hạn. | Tọa độ MOCK của giả lập; chưa kiểm di chuyển GPS vật lý. Tile map sau sửa giữ trạng thái chưa quan sát lại. |
| 5f. Dịch | OCR Latin/Trung và sáu chiều dịch trên Android đã kiểm ở mốc trước. Sau hạn nộp đã thấy ảnh tĩnh Anh→Việt với nhãn theo vùng; live 1.0.2+3 đã nhận NOTICE rồi về TV xóa nhãn trong cùng phiên. Giọng có micro/VAD, Zipformer Việt, Paraformer Anh/Trung; hai family nạp/thu/dừng trên Android. | Live kiểm trên giả lập có Enable Animations, chưa đo FPS/thử thiết bị thật; dịch còn hạn chế chất lượng. Giọng người thật→nhận dạng→dịch chưa kiểm chính xác toàn chuỗi; gate từ khóa hai fixture Windows 0/2 giữ nguyên. |
| 6. Tính năng đề xuất — 1đ | Bàn giao kiểm chứng 1–3 dữ kiện có trong gốc/dịch; người nhận nhập lại; server xác nhận theo phiên bản. Sửa phiếu hủy xác nhận cũ, giữ lịch sử. Production đã kiểm sai/đúng/sửa; 9 kiểm tra PostgreSQL đạt. | Đối chiếu dữ kiện không chứng nhận hiểu toàn bộ ngữ nghĩa; khảo sát đối chứng có giới hạn, không tuyên bố độc quyền toàn thị trường. |
| 7. Giao diện/cả nhóm — 1đ | Kem–hồng, dấu HN, bố cục sổ ca riêng; bỏ chữ thừa, guide lần đầu, watermark chuyển động/reduced motion. APK release đã cài và đăng nhập Android 11. | Chưa xác nhận mọi thành viên tự cài/chạy. Backend có thể dùng chung; frontend mỗi người phải riêng. |

## Bổ sung camera trực tiếp

Đã thêm preview camera, tự động lấy khung có giới hạn tần suất, OCR/dịch trên thiết bị, tạm dừng/tiếp tục và lịch sử lưu riêng qua API.5widget tests kiểm không chồng khung, dừng khi xuống nền, xóa ảnh tạm, UUID thử lưu lại và mở lịch sử. Tại mốc camera, backend96tests,12checks PostgreSQL camera và10checks production đạt; source1eadc04đãLive ở mốc đó.

Release **1.0.2+3 CameraX/NV21 nguyên bản** đã kiểm live trong cùng phiên trên Android 11 VirtualScene sau bật Enable Animations: TV → Walk14s → NOTICE xuất hiện nhãn theo vùng; Reset position → TV xóa nhãn cũ, không mở lại camera. Bước `live-continuous-confirmed` ghi lúc 21:59:30 UTC; xem [hướng dẫn/bằng chứng](THU_CAMERA_TREN_GIA_LAP.md). Các thử Camera2/YUV420 đã hoàn nguyên. Timestamp tiến lên nhưng cảnh báo trùng vẫn còn; không suy ra FPS, thiết bị thật hoặc liveness. Native lưu/lịch sử và face-positive camera UI vẫn cần bằng chứng riêng.

## Sửa tài khoản/quản lý sau hạn nộp

Backend **8ec đã Live**; giữ nguyên public URL, khóa cấu hình, tên project và package. Migration007 bổ sung version hồ sơ và sự kiện `profile_updated` gửi đúng UUID chủ tài khoản, nội dung notification vẫn chung. Email không đổi trong PATCH nhân viên giữ phiên/thiết bị/OTP đang chờ; email thực sự thay đổi, mật khẩu hoặc khóa tài khoản vẫn thu hồi. Chỉ đổi vai trò/chi nhánh không ép OTP lại. Kiểm thử ba tài khoản/email riêng đã kiểm đúng recipient qua đăng ký, duyệt, đăng nhập và gửi lại OTP.

Flutter đã bổ sung đồng bộ `/me` mỗi 10 giây khi foreground và khi có FCM hồ sơ, khôi phục/refresh phiên hợp lệ, cập nhật trang và hủy cache khi tài khoản/vai trò/trạng thái/chi nhánh đổi. Native QA cùng phiên đã thấy duyệt tài khoản/nâng quản lý/hạ nhân viên trong cận trên lần lượt **9,079/8,989/9,529 giây** từ API đọc lại đến lúc quan sát; khi hạ vai, route quản lý đang mở được tháo. Đây không phải SLA. PATCH giữ email cũ + đọc lại mất 348 ms; cold restart sau access token hết hạn đã khôi phục phiên không yêu cầu OTP mới.

`DO_TRE_API_HO_SO.json` ghi năm round-trip API `/me` 70–248 ms, trung bình 109 ms; không phải thời gian cập nhật UI. `KIEM_THU_SAU_NOP_API.json` ghi native signup/OTP đúng alias QA và các quan sát sau đó, chỉ thay dữ liệu gắn nhãn kiểm thử. Native ảnh tĩnh Anh→Việt có nhãn theo vùng nhưng chất lượng dịch còn hạn chế. Bằng chứng live đổi cảnh/xóa nhãn được ghi riêng ở trên; **face-positive camera UI vẫn chưa xác minh**.

Danh sách phân ca giữ active + verified + cùng chi nhánh; admin vẫn thấy người chưa gán chi nhánh để gán trước. Lỗi Home giữ ca cũ đã sửa và có 10 widget tests hồi quy. APK **1.0.2+3 đã build/cài đè**, khôi phục phiên không OTP mới. Native admin đã mở form đủ ba vai, lưu tài khoản QA sang DEMO TP.HCM rồi trả về chi nhánh thử; cả hai lần đều đọc lại API đúng giá trị. Màn chỉnh ca hiện đúng tài khoản QA đủ điều kiện sau khi gán chi nhánh. Các bước này không sửa tài khoản nhóm hay ca của người khác.

## Kết quả cuối

- Nguồn cuối APK 1.0.2+3: **149/149 Flutter tests đạt (11 giây)**, gồm 10 widget tests Home giữ ca cũ; analyzer **No issues found (9,4 giây)**. Android Studio build 163,6 giây exit0; APK cài đè thành công và giữ chứng chỉ ký đã nộp. Native kiểm toàn bộ camera/quét mặt vẫn được ghi riêng theo bằng chứng, không suy từ kết quả build/tests. Baseline 1.0.1+2 giữ mốc139/139 tests 40 giây/analyzer 4,7 giây.
- **109/109 backend tests**; **6/6** kiểm tra migration 007 trên PostgreSQL thật đạt. Các mốc trước gồm **9/9** kiểm chứng bàn giao và **12/12** CRUD/lịch sử trên PostgreSQL thật; schema thử đã dọn. Không gộp những số này thành kiểm thử native bản mới.
- Baseline APK **1.0.1+2**: **xem dung lượng/chữ ký/SHA trong KIEM_TRA_APK.json**, build Android Studio 281,2 giây, chữ ký v2 trùng bản đã nộp, không debuggable; minSDK24, target36, ARM32/ARM64/x86_64. Giữ nguyên chứng chỉ/bằng chứng lịch sử; bản 1.0.2+3 đã build/bàn giao, bằng chứng native được tách theo từng chức năng.
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
