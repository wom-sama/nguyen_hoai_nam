# Kết quả backend và tích hợp đã kiểm — 29/10/2026
## Bản kiểm tra cuối sau đổi ASR
### APK release đã cài thử

Đã có fileAPK **217908988byte**, xác minh **v2signaturePASS bằng apksigner37**; aapt2 xác nhận labelNguyễnHoàiNam,minSDK24,target36,3ABIs. Bản cuối đã build thành công, cài thử Android11 và mở Guide/Auth; camera preview đạt ngay lần cấp quyền đầu sau sửa vòng đời. NativeAndroidASRrouting mới vẫn chưa xác minh đầy đủ. Không coi signatureverified là toàn bộ appđãready.


FlutterWHOLE **82/82PASS**(work/flutter-tests-final-release.log); WHOLEanalyze **No issues found,27.1s**(work/flutter-analyze-final.log). Các mốc69/74/scopedanalyze trong nhật ký dưới là lịch sử, không phải kết quả cuối. ProductionASRsource hiện chọn **ZipformerVI/ParaformerEN–ZH**; Windows paired có cải thiện khách quan nhưng **keywordgateTiny/Base vẫn0/2, khôngpass**, và routingmới **chưa được chứng minh nativeAndroid**. Xem ASR_ROUTING_RESULT.md;19targetedtests là source/lifecycle, không19nativeASRtests. APKcuối đã cài thử và kiểm preview camera sau cấp quyền đầu; xem KET_QUA_CUOI.md.


Tài liệu chốt phần backend, không tự chấm điểm và không coi kiểm thử server là đã kiểm mọi thao tác UI/phần cứng. Giờ trong tài liệu là Asia/Bangkok(UTC+7). Bản xuất không chứa bí mật nằm ở [KIEM_THU_API_THAT_HN.json](../../KIEM_THU_API_THAT_HN.json).

## Bản nguồn và địa chỉ

- Flutter project/pubspec: **nguyen_hoai_nam**, Nguyễn Hoài Nam, MSSV2380601398, nhóm8.
- Thư mục source đã đổi thành **outputs/nguyen_hoai_nam** lúc17:27; prefix source archive là nguyen_hoai_nam.
- Android namespace/applicationId vẫn **com.example.nguyen_hoai_nam_2380601398**; cấu hình Firebase tương ứng được giữ nguyên. Đổi tên Flutter project không có nghĩa đổi Firebase app ID.
- Backend commit **263421e0db595cd72f3df472f2c7e8b20f89b691**; metadata LF được thêm trên feature commit c5c0a1e. Cả4migration giữ nguyên byte/checksum; checkout Windows core.autocrlf=true đã được kiểm.
- [API HTTPS thật](https://nguyen-hoai-nam-2380601398-api.onrender.com): Render build16:26:47, Live16:27:12; health200 được xác nhận16:38. App không dùng localhost để nộp.
- Hợp đồng **50route** và Postman **63request**; đây là số route/template, không phải tuyên bố tất cả đã chạy production.

## Các lớp kiểm chứng, tách riêng

| Lớp | Kết quả thật | Giới hạn |
|---|---|---|
| Full regression backend FINAL | **91/91 đạt**,0fail/0skip; log work/backend-tests-final.log | Có pg-mem, fixture ONNX thật, adapter/provider test; không tự coi tất cả là request production |
| PostgreSQL thật — critical facts | **9/9 checks đạt** qua TLS, JSONB, migration1–4lặp, wrong-answer unchanged, server proof/version, amend/audit, stale và hai worker/latest author event | Schema thử riêng đã xóa; mailer/FCM provider giả trong testapp, không gửi thật |
| PostgreSQL thật — CRUD/history | **12/12 checks đạt** lúc17:19:50–17:20:10: CRUD4nhóm, lastadmin/branch/history guards, softdelete+revoke, crossbranch, raw/audit/correction guards | DELETE chỉ trong schema thử có prefix/ownership xác minh; không xóa fixture production |
| Production API có nhãn | EmailOTP thật, phân quyền, ca/công/đơn/report, critical facts, face+OTP và shareTTL như phần dưới | Tọa độ MOCK/ảnh tổng hợp được người dùng cho phép, không giả thành người thật/thiết bị GPS thật |
| Native Android | Admin/employee đăng nhập và dashboard; ba loại business FCM có banner + màn được mở; OCR/dịch/mic như phần dưới | Không thay chứng cứ cả nhóm tự cài, APK release, camera/GPS vật lý hoặc thông báo nền |

Các schema test thật không có fallback sang public. Cleanup đã kiểm prefix, owner và xác nhận namespace không còn. Không cộng9/12checks hoặc các lượt chạy lại vào91test regression.

## Luồng production đã hoàn tất

Dữ liệu **KIỂM THỬ HN/MOCK** được người dùng cho phép giữ lại; không phải công nhân viên thật, không tính lương. Credential chỉ lưu ở nơi riêng; không ghi email/password/OTP/token/FID/embedding trong báo cáo.

1. Đăng ký hai alias Gmail của chủ hệ thống; verify OTP thật lúc15:59. Admin gán manager/employee active, cùng branch.
2. Tạo ca employee; check-in201, chấm vào trùng409 ALREADY_CHECKED_IN, check-out200. Giờ do server ghi; tọa độ fixture10.8,106.7 là giả lập.
3. Employee gửi correction201; manager duyệt200 lúc16:50:58–59. Giờ effective đổi nhưng recorded timestamps gốc còn nguyên; không tự duyệt đơn của mình.
4. Reports employee và manager đều200, có đúng dòng ca thử; không suy diễn thành payroll.
5. Tạo ca manager và draft bàn giao3fact; tác giả phải sở hữu ca.
6. Publish200 lúc17:14:59–17:15:00; wronganswer422 FACT_ANSWER_MISMATCH lúc17:15:12, items/version/proof/revisions không đổi.
7. Đáp án đúng200 lúc17:15:14, server proof đúng recipient và version. Author amendment200 lúc17:15:14–15, trở lại submitted, allitemsopen/proofnull; revision giữ proof cũ. Native mở phiếu hiện tại **version4** lúc17:20.
8. Share vị trí MOCK201 với TTL1phút, employee và manager đúng branch GET200 thấy share; sau hạn cả hai GET200 không còn thấy. Không cập nhật liên tục, không DELETE production.
9. Ảnh chân dung **tổng hợp** được cho phép: model local xác nhận1face; API face-enroll201 lúc17:00:39–43, status enrolled=true. Face-login200 chỉ trả challenge, chưa token; OTP thật verify200 và protected/me200 lúc17:03:02–03. Phiên face mới lưu riêng, không ghi đè phiên CLI/native.

API xác minh facts chỉ kiểm literal/canonical token trong cả hai text và câu trả lời đúng phiên bản; không đánh giá ngữ nghĩa toàn bản dịch hay chứng nhận con người hiểu. Nhập đáp án tự động trong fixture là kiểm server, không phải bằng chứng thao tác nhập tay trên UI.

## Ba loại thông báo nghiệp vụ trên Android

Người kiểm thử đã quan sát banner thật và mở dữ liệu được phép bằng tài khoản employee. Nội dung khóa màn hình luôn chung: “Sổ ca HN / Bạn có cập nhật mới. Mở ứng dụng để xem”.

| Sự kiện | Bằng chứng |
|---|---|
| Duyệt correction,16:51–16:52 | [Banner](../../android-fcm-correction-approved.png) → [Đơn đã duyệt và giờ điều chỉnh](../../android-correction-approved-details.png) |
| Phân ca mới,16:54 | [Banner](../../android-fcm-shift-assigned.png) → [Màn ca được phân](../../android-assigned-shift-from-fcm.png) |
| Gửi/sửa bàn giao,17:20 | [Banner](../../android-fcm-handover-published.png) → [Nhận(1),phiếu version4](../../android-handover-from-fcm.png) |

Đây là business events qua outbox, khác direct self-device provider probe14:41/foreground14:46. Chưa tuyên bố giao ở background/lockscreen, mọi thiết bị hoặc mọi tình huống offline. FCM là bổ sung, không thay OTP hoặc ba chức năng a,b,f.

## Native GPS, chia sẻ và UI mới

Native Android đã chấm vào **17:41:38** và chấm ra **17:44:19** qua Flutter UI→HTTPS Render→PostgreSQL. KIEM_THU_CHAM_CONG_ANDROID.json xác nhận một attendance record, source=device, đủ hai giờ, thứ tự đúng, accuracy hữu hạn và khớp branchMOCK. Đây là luồng native thật với **tọa độ giả lập**, không phải chứng cứ di chuyển GPS vật lý. Xem [vào](../../android-native-gps-checkin.png),[ra](../../android-native-gps-checkout.png) và [evidence](../../KIEM_THU_CHAM_CONG_ANDROID.json).

Native đã bật share15phút lúc17:46, rời màn hình17:51. KIEM_THU_CHIA_SE_ANDROID.json kiểm148287ms không có cập nhật sau khi rời, deadline không bị kéo dài và tọa độMOCK khớp. **Chưa quan sát native15phút hết hạn** ở lần ghi này; APIcaseTTL1phút trước đó đã hết hạn đúng. Không nhập nhằng hai bằng chứng. Sourcefix giữ opt-in/map ổn định, expiry chính xác và không chồng GET có5test mới; **tile native saufix chưa được quan sát**.

Hướng dẫn native3bước, bỏ qua/hoàn tất và Home mới đã được quan sát: [guide](../../android-guide-first-run.png),[Home](../../android-home-polished.png). FlutterWHOLE **82/82PASS**; WHOLEanalyzer **No issues found,27.1s** sau đổiASR. Kết quả69/69/fullanalyzeclean17:30 là mốc trước đó, không tự chuyển thành74/fullanalyze.

## Native OCR, dịch và speech: ghi đúng kết quả

- [Native translation](NATIVE_TRANSLATION_RESULT.md): **4/4 test chức năng**, OCR Latin/Trung và **6/6 chiều dịch** Việt–Anh–Trung đã chạy trên Android. Whisper FFI/model đã chạy với WAV tiếng Anh; transcript còn sai/thiếu chữ số, không có bảo đảm độ chính xác.
- [Native speech bổ sung](NATIVE_SPEECH_LANGUAGE_RESULT.md), harnessTTS trước đây: **1/3 test chức năng đạt**. Phần mic nhận3200byte PCM/1frame, stream đóng và recorder dừng đúng; đây là capture/transport/release.
- Hai test Việt/Trung bị chặn ở nguồn fixture TTS trước synthesis/WAV/Whisper. **Không gọi đó là engine pass hoặc Whisper nhận dạng sai.** Không hạ assertion hay đổi kết quả cũ.
- Các phép thửTiny/Base trên hai fixtureFLEURS **0/2keywordgate, khôngpass**. Không lấy kết quảTTS cũ làm kết quảFLEURS. Productionrouting mớiZipformerVI/ParaformerENZH được chọn theo cải thiệnWindows; nativeAndroidroutingmới chưa chứng minh. Chưa chứng minh chuỗi lời nói thật mic→VAD→Whisper→dịch liên tục hoàn chỉnh; cameraUI và di chuyểnGPS vật lý còn chờ. NativeGPSmock→Render đã đạt như phần trên; OCRfixture không thay ảnh chụp camera.

## Phần còn cần làm trước khẳng định toàn sản phẩm đã đạt

FlutterWHOLE78/78đã đạt, WHOLEanalyzerNoissues12.8s; APKbuildthứhai còn đang chạy, chưa xác nhận bảnAPKcuối. UI/package đang được chốt; nếu đổi tiếp phải kiểm lại theo bản cuối. APKfile/signature đã có; chưa chứng minh cài/vận hành bảnAPK này, cả nhóm tự chạy, cameraUI/physicalGPS, nativeASRroutingmới hoặc notification nền. Nhận diện mặt2D không có chứng nhận liveness/chống ảnh in; OTP email vẫn bắt buộc.

Render Free có cold start, quota Gmail/model và hạn database **28/11/2026**; cần sao lưu/restore theo hướng dẫn. Không hứa realtime vô hạn/mọi thiết bị mượt chỉ từ các lần kiểm.

Public source không chứa .env hoặc private keys. ZIP vận hành AES-256 có BI_MAT là gói riêng do người dùng cho phép; mật khẩu ZIP chuyển tách. Frontend mỗi thành viên phải riêng, project tên cá nhân/package riêng/Firebase config khớp; backend handoff ZIP không chứa source frontend.



