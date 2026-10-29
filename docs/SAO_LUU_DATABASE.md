# Hướng dẫn sao lưu database

## Sao lưu database trước ngày 28/11/2026

Database Render Free đang dùng được ghi nhận hết hạn **28/11/2026**. Đây là hạn của database hiện tại, không phải cam kết dịch vụ được tự gia hạn. Cần sao lưu và thử khôi phục sớm, nên hoàn tất trước **26/11/2026**; không đợi ngày hết hạn. Tài liệu chỉ hướng dẫn, chưa tạo bản backup hoặc thao tác cloud.

1. Người quản lý database lấy thông tin **External** connection từ Render. Trên máy được phép quản trị, dùng PostgreSQL client 17 hoặc mới hơn; cấu hình host, port, database, user và xác minh TLS theo [hướng dẫn kết nối Render](https://render.com/docs/postgresql-creating-connecting). Nếu client yêu cầu CA, cấu hình nguồn CA tin cậy; không tắt kiểm tra chứng chỉ để vượt lỗi.
2. Đặt các thông tin kết nối bằng cấu hình libpq cục bộ (`PGHOST`, `PGPORT`, `PGDATABASE`, `PGUSER`, cấu hình TLS phù hợp). Không chèn URI chứa mật khẩu vào lệnh/chat/README. Các lệnh dưới yêu cầu nhập mật khẩu khi chạy và dùng placeholder tên file; chưa được thực thi trong tài liệu này.

```sh
pg_dump --format=custom --no-owner --no-acl --password --file "so-ca-hn-backup-2026-11-20.dump"
pg_restore --list "so-ca-hn-backup-2026-11-20.dump"
```

3. Kiểm tra lệnh dump kết thúc thành công, file có dung lượng hợp lý và danh mục restore đọc được. Giữ tối thiểu hai bản sao ở nơi riêng do nhóm kiểm soát; backup chứa dữ liệu tài khoản và nghiệp vụ, nên không đưa vào Git, APK hoặc thư mục chia sẻ công khai. Ghi ngày tạo và phiên bản PostgreSQL/client bên cạnh bản sao.
4. **Thử khôi phục vào database mới dành riêng cho thử nghiệm.** Đổi cấu hình kết nối sang đích thử, kiểm tra lại host và database trước khi chạy. Không dùng `--clean` hoặc trỏ vào database đang phục vụ app.

```sh
pg_restore --exit-on-error --no-owner --no-acl --password --dbname "ten_database_thu_moi" "so-ca-hn-backup-2026-11-20.dump"
```

5. Đối chiếu số bản ghi và quan hệ chính, thử `/v1/health`, đăng nhập/OTP và một thao tác CRUD qua backend nối database thử. `pg_restore --list` chỉ đọc mục lục, chưa chứng minh backup khôi phục được. Chỉ coi bản sao sử dụng được sau khi đã restore và kiểm tra.
6. Nếu cần duy trì app sau hạn Free, chuẩn bị database thay thế hoặc gói được chủ tài khoản lựa chọn trước ngày hết hạn. Sau khi restore và xác minh, cập nhật `DATABASE_URL` trong secret environment của backend; chỉ đổi URL API trên app nếu địa chỉ API cũng thay đổi. Chưa thực hiện chuyển dịch vụ, mua gói hoặc gia hạn trong bước lập tài liệu.

File dump không thay thế các bí mật môi trường, mã nguồn, cấu hình relay và Firebase. Lưu riêng các cấu hình cần khôi phục trong nơi quản lý bí mật của nhóm; không đưa `.env`, khóa service account, JWT/OTP secret hoặc mật khẩu database vào gói bài nộp.


