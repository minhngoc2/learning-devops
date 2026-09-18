# learning-devops

## Lesson 1 — Basic Linux commands

| Step | Command |
|------|---------|
| Tạo thư mục `~/devops/lesson1` | `mkdir -p ~/devops/lesson1` |
| Di chuyển vào thư mục | `cd ~/devops/lesson1` |
| Tạo file `hello_world.txt` | `touch hello_world.txt` |
| Mở file bằng nano, viết nội dung | `nano hello_world.txt` (lưu: `Ctrl+O` → `Enter`, thoát: `Ctrl+X`) |
| Hiển thị nội dung file | `cat hello_world.txt` |

Output:

```
$ cat hello_world.txt
Hello, World!
This is my first DevOps lesson.
Learning Linux basic commands: mkdir, cd, touch, nano, cat.
```

File mẫu: [lesson1/hello_world.txt](lesson1/hello_world.txt)

## Lesson 3 — Bash script: Health check

Script: [lesson3/health_check.sh](lesson3/health_check.sh)

| Yêu cầu | Cách làm |
|---------|----------|
| Khai báo mảng 2 dịch vụ | `services=("nginx" "ssh")` |
| Vòng lặp kiểm tra trạng thái | `for svc in "${services[@]}"; do ... done` + `systemctl is-active --quiet "$svc"` |
| Dịch vụ chết → cảnh báo đỏ | `if/else` + mã màu ANSI `\033[0;31m` với `echo -e` |

`systemctl is-active --quiet` không in gì, chỉ trả exit code: `0` = active, khác `0` = không chạy.

Chạy:

```bash
chmod +x lesson3/health_check.sh
./lesson3/health_check.sh
```

Output (ví dụ nginx đã dừng):

```
$ ./lesson3/health_check.sh
[ALERT] nginx is DOWN!     # màu đỏ
[OK] ssh is running        # [OK] màu xanh
```

> Trên RHEL/CentOS dịch vụ SSH tên là `sshd`, sửa trong mảng `services`.

## Lesson 4 — Docker image cho Python

File: [lesson4/Dockerfile](lesson4/Dockerfile), [lesson4/main.py](lesson4/main.py)

| Yêu cầu | Chỉ thị Dockerfile |
|---------|--------------------|
| Môi trường Python 3.14 | `FROM python:3.14-slim` |
| Thư mục làm việc `/app` | `WORKDIR /app` |
| Cài `poetry` bằng pip | `RUN pip install --no-cache-dir poetry` |
| Có sẵn `main.py` trong image | `COPY main.py .` |
| `docker run` chạy `main.py` | `CMD ["python", "main.py"]` |

`--no-cache-dir` để pip không giữ cache trong layer → image nhỏ hơn.

Build & chạy:

```bash
docker build -t lesson4 lesson4/
docker run --rm lesson4
```

Output:

```
$ docker run --rm lesson4
hello world

$ docker run --rm lesson4 sh -c 'pwd; python -V; poetry --version'
/app
Python 3.14.7
Poetry (version 2.4.3)
```
