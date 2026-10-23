# Bài 3 — Bash script kiểm tra dịch vụ

Script Bash kiểm tra `nginx` và `ssh` có đang chạy không, và tô màu kết quả.

[Về trang tổng quan](../README.md) · Script: [health_check.sh](health_check.sh)

> [!NOTE]
> Bài này cần chạy trên Linux sử dụng systemd.

## Cách hoạt động

- Khai báo hai dịch vụ: `services=("nginx" "ssh")`.
- Lặp qua từng dịch vụ và kiểm tra bằng `systemctl is-active --quiet "$svc"`.
- Dùng `if/else` và mã màu ANSI: đỏ khi dịch vụ dừng, xanh khi đang chạy.

`systemctl is-active --quiet` không in gì; exit code `0` nghĩa là dịch vụ đang chạy, khác `0` nghĩa là không hoạt động.

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

> [!TIP]
> Trên RHEL/CentOS, dịch vụ SSH có tên `sshd`; hãy thay `ssh` trong mảng `services`.
