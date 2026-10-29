# Khác biệt của bàn giao ca — phạm vi hiện tại đã triển khai

## Tính năng hiện tại, không còn là đề xuất chờ duyệt

Người dùng đã chấp thuận mở rộng critical facts ngày29/10/2026. Source đã hiện thực Flutter payload/UI và Node/PostgreSQL; feature commit c5c0a1e đã triển khai, bản bàn giao263421e chỉ bổ sung metadata LF, không đổi4SQL. Không tiếp tục mô tả nhánh này là“chưa được duyệt/chưa triển khai/chưa test”.

Mỗi bàn giao hoàn chỉnh có1–3facts equipment/quantity/deadline. Bản nháp có0–3facts typed-valid; khi gửi/finalack, value canonical phải xuất hiện đầy đủ trong **cả originalText và translatedText**. Recipient đúng/currentversion nhập lại exactfactset mới được hoàn tất; mọi items phải understood. Server tự tạo proof người/thời điểm/version; không tin proof/cờ thành công từclient. Author sửa submitted hoặc acknowledged sẽ mở submitted, allitemsopen/proofnull và giữ proof cũ trong revisionaudit. Không downgrade active→draft để bypass.

Quantity khôngunit/thousandsseparator, chuẩn hóa decimal có quy tắc; equipment giữ khác biệt_/-; deadline strict HH:mm hoặc YYYY-MM-DD HH:mm và ngày thật. So sánh toàntoken ngăn12khớp112/EQ12/12.5. Đây là literal/canonical matching, **không AI kiểm toàn nghĩa bản dịch hoặc chứng nhận mức hiểu**. Người nhận có thể chép literal; fixture tự nhập đúng chỉ kiểm quy tắc server.

Đã kiểm: fullbackendFINAL91/91, realPGcriticalfacts9/9/schema dọn, productionpublish200→wrong422atomic→ackproof200→amendreset200/audit; native từbusinessFCM mở đúngNhận(1)/phiếuversion4. Flutterwhole74/74đã đạt sau5map/privacytests;5file scopedanalyzerclean, wholeanalyzer sau thay đổi cuối còn chờ. Chưa biến các test ấy thành bằng chứng mọi người tự nhập UI/cả nhóm chạy hoặc giảng viên cho điểm. Xem [kết quả](BACKEND_FINAL_RESULT.md) và [đối chiếu đề](DOI_CHIEU_DE_BAI.md).

Source: [model/payload](../lib/features/handovers/handover_models.dart), [composer](../lib/features/handovers/handover_composer.dart), [detail](../lib/features/handovers/handover_detail.dart), [API](../backend/src/resources.js), [serverfacts](../backend/src/critical-facts.js), [hợp đồng](../backend/docs/HANDOVER_CRITICAL_FACTS.md).

## Cách diễn giải tính mới

Đề dành1điểm cho“Tính năng mới mà các app hiện tại tương ứng chưa có(tự đề xuất)”. Dịch/checklist/xác nhận đã đọc hoặc quiz riêng lẻ đều có overlap ở khảo sát bên dưới. Nhánh hiện tại kết hợp **anchors dữ kiện gốc–dịch + câu trả lời nhập lại + version/proof/audit gắn bàn giao ca**; đây là điểm khác biệt cụ thể để trình bày và demo, không phải khẳng định app đầu tiên/duy nhất trên toàn thị trường.

Khảo sát3app là nguồn so sánh có phạm vi, không kiểm mọi gói thương mại/tích hợp tùy biến. Chưa có xác nhận của giảng viên về điểm tính mới. Không tự liên hệ bên thứ ba hoặc gửi source khi chưa được phép.

## Khảo sát trước khi mở rộng — giữ nguyên nguồn đã đọc

Block sau là kết quả khảo sát ban đầu, được giữ để thấy overlap và lý do không dừng ở“bàn giao song ngữ+checkbox”. Không browse lại hoặc suy đoán sản phẩm đối chứng thiếu chức năng chỉ vì tài liệu không mô tả.

## Sự kiện xác thực từ nguồn chính thức

Ngày trong bảng là ngày được chính bài viết hiển thị, nếu có. Các trang không hiện ngày rõ được ghi như vậy; ngày đọc chung là 29/10/2026. Nội dung được diễn giải, không sao chép giao diện, template hay source của sản phẩm.

| Sản phẩm | Nội dung đã kiểm chứng | Nguồn trực tiếp và ngày bài viết | Giới hạn kết luận |
|---|---|---|---|
| **Connecteam** | Updates có dịch sang ngôn ngữ thiết bị của nhân viên. | [Updates: Automatic Translation](https://help.connecteam.com/en/articles/7900512-updates-automatic-translation), **13/05/2025**. | Xác nhận dịch nội dung Updates; không tự suy thành quy trình bàn giao có kiểm tra dữ kiện trọng yếu. |
| **Connecteam** | Pop-up có nút xác nhận đã đọc/hiểu; admin theo dõi ai xác nhận và nhắc người còn thiếu. | [Pop Up Updates](https://help.connecteam.com/en/articles/6510543-pop-up-updates), **23/06/2024**. | Đây là xác nhận của người đọc; không phải bằng chứng hệ thống đã đo đúng mức hiểu nội dung. |
| **Connecteam** | Forms có checklist; người dùng có thể hoàn thành form gắn với ca và sửa submission khi admin cho phép. | [Starting Guide to Forms](https://help.connecteam.com/en/articles/4225197-starting-guide-to-forms), **23/08/2026**; [Forms (for Users)](https://help.connecteam.com/en/articles/5827096-forms-for-users), **23/12/2025**. | Form và khả năng sửa không chứng minh cơ chế version/thu hồi xác nhận giống app này; cũng không chứng minh Connecteam thiếu cơ chế đó. |
| **Connecteam** | Quiz hỗ trợ trắc nghiệm, điểm đạt, theo dõi kết quả từng câu; tài liệu nêu mỗi câu chọn một đáp án đúng. | [Starting Guide to Quizzes](https://help.connecteam.com/en/articles/6451819-starting-guide-to-quizzes), **10/09/2024**. | Thêm quiz đơn thuần cũng đã có overlap; không đủ để gọi là điểm mới. |
| **Deputy** | News Feed hỗ trợ yêu cầu người nhận xác nhận, hiển thị danh sách đã/chưa xác nhận và phân quyền xem danh sách đó. | [Reading News Feed posts FAQs](https://help.deputy.com/hc/en-au/articles/4689377622159-Reading-News-Feed-posts-FAQs), **không thấy ngày công bố rõ trong nội dung đã đọc**. | Xác nhận đã đọc không đồng nghĩa kiểm tra đúng dữ kiện của bản dịch. |
| **Deputy** | Bài viết chính thức hướng dẫn tổ chức thông tin bàn giao và xác nhận ca có thể gắn ghi chú/task list; ngữ cảnh được nhìn thấy khi xem ca. | [How To Improve Communication With Your Hospitality Staff](https://www.deputy.com/au/blog/6-easy-ways-to-improve-communication-with-your-staff), **14/05/2026**. | Phần hướng dẫn bàn giao là tư vấn quy trình; không coi mọi gợi ý trong bài là một chức năng chuyên biệt đã kiểm thử trực tiếp trong Deputy. |
| **Jibble** | Mobile có cấu hình ngôn ngữ giao diện cho từng người dùng. | [Configuring language settings on Jibble’s mobile app](https://www.jibble.io/help/configuring-language-settings-mobile), **không thấy ngày công bố rõ trong nội dung đã đọc**. | Bản địa hóa giao diện khác với dịch nội dung bàn giao. Không suy rằng Jibble có dịch nội dung từ bằng chứng này. |
| **Jibble** | Nhận diện khuôn mặt hỗ trợ ghi nhận giờ trên thiết bị cá nhân/kiosk. | [How facial recognition works](https://www.jibble.io/help/how-facial-recognition-works), **không thấy ngày công bố rõ trong nội dung đã đọc**. | Dùng làm đối chứng đúng nhóm app chấm công; nguồn này không cung cấp bằng chứng về bàn giao, checklist hoặc quiz. |

Khảo sát không xác minh được trong các trang đã đọc một quy trình của cả ba sản phẩm trùng hoàn toàn cơ chế version bàn giao đang có. **Không tìm thấy trong tài liệu đã đọc không đồng nghĩa sản phẩm không có.** Các công cụ form, automation và tích hợp tùy biến có thể mở rộng khả năng của sản phẩm; chưa kiểm thử các cấu hình ấy.

## Lịch sử đề xuất đã được giải quyết

Bản tài liệu ban đầu chỉ xét bàn giao song ngữ, xác nhận từng việc và version; khảo sát phát hiện nhiều phần đã phổ biến nên đề nghị hỏi người dùng về đối soát mã/số lượng/hạn chót. **Người dùng đã duyệt nhánh mở rộng; nó đã được triển khai và kiểm như phần đầu.** Câu hỏi xin duyệt và các dòng“chưa sửa source/chưa có test”của bản nghiên cứu cũ không còn là trạng thái hiện tại.

Phần dùng nguồn chính thức ở trên vẫn có giá trị so sánh giới hạn: không có bằng chứng độc quyền toàn thị trường, không tự chấm điểm. Các công cụ form/automation tùy biến có thể mô phỏng một phần quy trình; cần diễn giải đúng trước giảng viên.

## Phạm vi kỹ thuật đã chọn

Flutter/Dart client, HTTP/JSON, Node/PostgreSQL và quy tắc xác định; không thêmLLM/LP/cloudAI trả phí/Python hoặc SDK di động thay Flutter. Dịch/OCR/giọng nói vẫn thuộc chức năngf, không tính thành một tính năng đối chứng mới riêng. CMP1772024đã được người dùng xác nhận nhưng chưa có bằng chứng đọc toàn văn/bài6để khẳng định mọi chi tiết giáo trình.

API thực đã Live; bản cuối vẫn cần UI/release/cả nhóm và phần native còn thiếu theo báo cáo. Nghiên cứu tính mới không thay các điều kiện bắt buộc về project cá nhân, frontend riêng, Flutter và HTTPS deploy.
