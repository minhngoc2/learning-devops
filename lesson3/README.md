# Bài 3 — Bash script kiểm tra dịch vụ

[Về trang tổng quan](../README.md)

Script: [health_check.sh](health_check.sh)

> Bài này cần chạy trên Linux sử dụng systemd.

- Khai báo hai dịch vụ: `services=("nginx" "ssh")`.
- Dùng vòng lặp và `systemctl is-active --quiet "$svc"` để kiểm tra trạng thái.
- Dùng `if/else` và mã màu ANSI để phân biệt dịch vụ đang chạy hoặc đã dừng.

`systemctl is-active --quiet` không in kết quả; exit code `0` nghĩa là dịch vụ đang chạy, các giá trị khác `0` nghĩa là dịch vụ không hoạt động.

## Chạy

Từ thư mục gốc của repository:

```bash
chmod +x lesson3/health_check.sh
./lesson3/health_check.sh
```

## Kết quả

Ví dụ khi Nginx đã dừng:

```console
$ ./lesson3/health_check.sh
[ALERT] nginx is DOWN!
[OK] ssh is running
```

Script hiển thị cảnh báo bằng màu đỏ và trạng thái hoạt động bằng màu xanh.

> Trên RHEL/CentOS, dịch vụ SSH có tên `sshd`; hãy thay `ssh` trong mảng `services`.
