# Native Whisper FLEURS Việt/Trung — kết quả thực tế

Ngày **29/10/2026**, Android Studio Flutter Run entrypoint `integration_test/native_fleurs_language_test.dart`, cờ `INTEGRATION_TEST_SHOULD_REPORT_RESULTS_TO_NATIVE=false`. Lần thử 18:03 chưa chạy vì không có thiết bị kết nối; root khôi phục AVD trước lần chạy thực tế. Snapshot chỉ đọc xác minh package `com.example.nguyen_hoai_nam_2380601398`, PID **4272**, cùng marker hai test FLEURS. Test Việt bắt đầu **18:11:48.971**; bộ test kết thúc **18:11:58.801**, `Some tests failed`.

**Kết quả: 0/2 test chức năng pass.** Counter `+2 -2` bao gồm setup/teardown, không phải hai test ASR pass. Môi trường Android 11/API 30 x86_64 userdebug, 2 processors. Không chạy lại, thay clip, sửa assertion hoặc đổi model/config sau khi xem output.

Các bước decode base64, byte count/SHA-256, native WAV/sample count, sample rate 16 kHz, duration dưới 15 giây và output không rỗng đã qua trước kiểm tra keyword. Native model/FFI thực sự chạy; **transcript không đạt keyword từ reference**. Hai test dừng tại keyword đầu tiên không có; các assertion tiếp theo không được coi là đã pass. Đây là lỗi nhận dạng nội dung thực tế trong phép thử, không còn là thiếu voice TTS hoặc không truy cập được fixture.

| Fixture | Audio | Native model load | Decode | Keyword đầu tiên không đạt |
| --- | ---: | ---: | ---: | --- |
| Việt `vi_vn-10056093347220194289.wav` | 14,94 giây / 239.040 mẫu | 963 ms | 2.286 ms | `động vật` |
| Mandarin `cmn_hans_cn-10149760684641961155.wav` | 7,44 giây / 119.040 mẫu | 476 ms | 941 ms | `哺乳动物` |

Transcript **Việt nguyên văn**:

> Mọc sâu, lại đam vọc như vô vô hô khó khó thường, đây là dàng xe và chỉ với két nụm cổ bình thường. Chúng ta cũng xe. Quên xe, mọc két đi dàng.

Transcript **Mandarin nguyên văn**:

> 因为原理大陆普通通我反正是20%的聚规程会可能去连主要的食堂的我

Không dùng output trên làm bằng chứng độ chính xác ASR Việt/Trung. Hai câu không đại diện mọi người dùng hoặc một benchmark WER/CER hoàn chỉnh; tuy vậy kết quả này cho thấy không thể tuyên bố chất lượng nhận dạng tốt trên hai fixture đã chốt. Không suy diễn thời gian debug của AVD thành cam kết điện thoại thật. Test này cũng không kiểm tra mic → VAD → ASR → dịch liên tục.

[Snapshot log đã lọc](NATIVE_FLEURS_RAW_REPORT.txt) chỉ giữ marker, lỗi test và dữ liệu fixture công khai; không chứa auth/token/FID hoặc log API khác. Android log chia/cắt một số dòng report dài; bản này ghi các trường transcript/thời gian có trong snapshot, không tuyên bố là một JSON nguyên vẹn. Không có lần đọc/poll lặp lại sau snapshot kết thúc.

Audio/reference vẫn theo Google FLEURS, Conneau et al. (2022), **CC BY 4.0**. [Provenance, nguồn pin, hash, attribution và cách chạy](NATIVE_FLEURS_PROVENANCE.md) giữ nguyên; source và tiêu chí không đổi trong lượt ghi kết quả.
