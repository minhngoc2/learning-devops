# Learning DevOps

Ghi chép và bài thực hành trong quá trình học Linux, Bash, Docker và triển khai ứng dụng.

## Bài 1 — Các lệnh Linux cơ bản

Thực hành:

- Tạo thư mục: `mkdir -p ~/devops/lesson1`.
- Di chuyển vào thư mục: `cd ~/devops/lesson1`.
- Tạo tệp: `touch hello_world.txt`.
- Chỉnh sửa bằng Nano: `nano hello_world.txt` (lưu: `Ctrl+O` → `Enter`, thoát: `Ctrl+X`).
- Hiển thị nội dung: `cat hello_world.txt`.

Kết quả:

```console
$ cat hello_world.txt
Hello, World!
This is my first DevOps lesson.
Learning Linux basic commands: mkdir, cd, touch, nano, cat.
```

Tệp mẫu: [hello_world.txt](lesson1/hello_world.txt)

## Bài 3 — Bash script kiểm tra dịch vụ

Script: [health_check.sh](lesson3/health_check.sh)

- Khai báo hai dịch vụ: `services=("nginx" "ssh")`.
- Dùng vòng lặp và `systemctl is-active --quiet "$svc"` để kiểm tra trạng thái.
- Dùng `if/else` và mã màu ANSI để phân biệt dịch vụ đang chạy hoặc đã dừng.

`systemctl is-active --quiet` không in kết quả; exit code `0` nghĩa là dịch vụ đang chạy, các giá trị khác `0` nghĩa là dịch vụ không hoạt động.

Chạy:

```bash
chmod +x lesson3/health_check.sh
./lesson3/health_check.sh
```

Kết quả khi Nginx đã dừng:

```console
$ ./lesson3/health_check.sh
[ALERT] nginx is DOWN!     # màu đỏ
[OK] ssh is running        # [OK] màu xanh
```

> Trên RHEL/CentOS, dịch vụ SSH có tên `sshd`; hãy thay `ssh` trong mảng `services`.

## Bài 4 — Docker image cho ứng dụng Python

Tệp: [Dockerfile](lesson4/Dockerfile), [main.py](lesson4/main.py)

- Dùng image `python:3.14-slim`.
- Đặt thư mục làm việc thành `/app`.
- Cài Poetry bằng `pip install --no-cache-dir poetry`.
- Copy `main.py` vào image.
- Chạy ứng dụng bằng `CMD ["python", "main.py"]`.

`--no-cache-dir` ngăn pip lưu cache trong layer, giúp image gọn hơn.

Build và chạy:

```bash
docker build -t lesson4 lesson4/
docker run --rm lesson4
```

Kết quả:

```console
$ docker run --rm lesson4
hello world

$ docker run --rm lesson4 sh -c 'pwd; python -V; poetry --version'
/app
Python 3.14.7
Poetry (version 2.4.3)
```

## Bài 5–6 — Docker image cho FastAPI theo hướng production

Tệp:

- [Dockerfile](lesson5-6/Dockerfile)
- [main.py](lesson5-6/main.py)
- [healthcheck.py](lesson5-6/healthcheck.py)
- [pyproject.toml](lesson5-6/pyproject.toml)
- [poetry.lock](lesson5-6/poetry.lock)

Yêu cầu:

- **Python 3.14**: `FROM python:3.14-slim` ở cả hai stage.
- **Poetry**: `RUN pip install --no-cache-dir poetry` chỉ ở stage `builder`.
- **FastAPI và Uvicorn**: thêm các dependency bằng `poetry add --lock fastapi uvicorn`, sau đó cài trong image bằng `poetry install --only main --no-root`.
- **API hello world**: `@app.get("/")` trả `{"message": "Hello World"}`.

Các điểm hướng đến production:

- **Multi-stage build**: Poetry chỉ tồn tại trong stage `builder`; runtime image chỉ nhận `.venv`.
- **Dependency lock**: commit `poetry.lock` cùng source code để cố định phiên bản các Python dependency.
- **Tận dụng build cache**: copy `pyproject.toml` và `poetry.lock` trước source code để không cài lại dependency khi chỉ thay đổi code.
- **Non-root user**: chạy ứng dụng bằng user `app`.
- **Non-package mode**: `package-mode = false` vì project này chỉ cần quản lý dependency, không build package để publish.
- **Health check**: endpoint `GET /health` và chỉ thị `HEALTHCHECK`. Script `healthcheck.py` dùng `urllib` có sẵn trong Python nên không cần cài thêm `curl`.
- **Nhiều worker**: Uvicorn đọc `WEB_CONCURRENCY=2` và khởi chạy hai worker; có thể ghi đè khi chạy container.

> Trên Kubernetes, hãy khai báo `livenessProbe` và `readinessProbe` trỏ tới `/health`. Thông thường mỗi container chạy một worker và Kubernetes scale bằng số `replicas`.

Giải thích các biến `ENV` trong Dockerfile:

### Builder

| Biến | Tác dụng |
|------|----------|
| `POETRY_VIRTUALENVS_IN_PROJECT=true` | Tạo virtual environment tại `/app/.venv` để copy sang stage `runtime`. |
| `POETRY_NO_INTERACTION=1` | Không yêu cầu nhập dữ liệu trong quá trình build. |

### Runtime

| Biến | Tác dụng |
|------|----------|
| `PATH="/app/.venv/bin:$PATH"` | Dùng `python` và `uvicorn` trong virtual environment mà không cần activate hoặc chạy `poetry run`. |
| `PYTHONDONTWRITEBYTECODE=1` | Không tạo file `.pyc` và thư mục `__pycache__` trong container. |
| `PYTHONUNBUFFERED=1` | Ghi log ngay ra stdout/stderr để xem bằng `docker logs`. |
| `WEB_CONCURRENCY=2` | Chạy hai Uvicorn worker; có thể ghi đè khi chạy container. |

Build và chạy:

```bash
docker build -t lesson5-6 lesson5-6/
docker run -d --rm --name l56 -p 8000:8000 lesson5-6
curl --fail http://localhost:8000/
curl --fail http://localhost:8000/health
```

Kết quả:

```console
$ curl --fail http://localhost:8000/
{"message":"Hello World"}

$ curl --fail http://localhost:8000/health
{"status":"ok"}

$ docker exec l56 sh -c 'whoami; python -V; command -v poetry || echo no-poetry'
app
Python 3.14.7
no-poetry

$ docker ps --filter name=l56 --format '{{.Status}}'
Up 8 seconds (healthy)

$ docker logs l56 | grep 'Started server'
INFO:     Started server process [9]
INFO:     Started server process [8]
```

Dừng và dọn dẹp:

```bash
docker stop l56
docker image rm lesson5-6
```

Container được chạy với `--rm` nên `docker stop` cũng tự động xóa container; lệnh thứ hai xóa image đã build trên máy.
