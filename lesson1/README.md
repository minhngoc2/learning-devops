# Bài 1 — Các lệnh Linux cơ bản

Tạo thư mục, tạo và chỉnh sửa tệp văn bản bằng các lệnh Linux cơ bản.

[Về trang tổng quan](../README.md)

> [!NOTE]
> Năm lệnh dùng trong bài: `mkdir`, `cd`, `touch`, `nano`, `cat`.

## Thực hành

```bash
mkdir -p ~/devops/lesson1     # tạo thư mục (kể cả thư mục cha)
cd ~/devops/lesson1           # di chuyển vào thư mục
touch hello_world.txt         # tạo tệp rỗng
nano hello_world.txt          # chỉnh sửa
cat hello_world.txt           # hiển thị nội dung
```

> [!TIP]
> Trong Nano: lưu bằng `Ctrl+O` → `Enter`, thoát bằng `Ctrl+X`.

## Kết quả

```console
$ cat hello_world.txt
Hello, World!
This is my first DevOps lesson.
Learning Linux basic commands: mkdir, cd, touch, nano, cat.
```

Tệp mẫu: [hello_world.txt](hello_world.txt)
