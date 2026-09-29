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

## Lesson 5+6 — Production image cho FastAPI backend

File: [lesson5-6/Dockerfile](lesson5-6/Dockerfile), [lesson5-6/main.py](lesson5-6/main.py), [lesson5-6/healthcheck.py](lesson5-6/healthcheck.py), [lesson5-6/pyproject.toml](lesson5-6/pyproject.toml), [lesson5-6/poetry.lock](lesson5-6/poetry.lock)

| Yêu cầu | Cách làm |
|---------|----------|
| Python 3.14 | `FROM python:3.14-slim` (cả 2 stage) |
| Cài poetry | `RUN pip install --no-cache-dir poetry` (chỉ ở stage `builder`) |
| Cài FastAPI bằng poetry | Local: `poetry add --lock fastapi uvicorn` → trong image: `poetry install --only main --no-root` |
| API hello world | `@app.get("/")` trả `{"message": "Hello World"}` |

Điểm "production":

- **Multi-stage**: stage `builder` có poetry, stage cuối chỉ copy `.venv` → image không chứa poetry.
- **`poetry.lock`** commit cùng code → build lúc nào cũng ra đúng version thư viện.
- **Copy `pyproject.toml` + `poetry.lock` trước `main.py`** → sửa code không phải cài lại thư viện (cache layer).
- **Chạy bằng user `app`** (non-root).
- `package-mode = false` vì đây là app, không phải thư viện để publish.
- **Healthcheck**: endpoint `GET /health` + `HEALTHCHECK` trong Dockerfile. Script `healthcheck.py` dùng `urllib` có sẵn trong Python nên không cần cài thêm `curl`; request lỗi hoặc trả về non-2xx sẽ làm lần kiểm tra thất bại.
- **Nhiều worker**: uvicorn tự đọc biến `WEB_CONCURRENCY` làm số worker → `ENV WEB_CONCURRENCY=2`, đổi lúc chạy: `docker run -e WEB_CONCURRENCY=4 ...`.

> Lên Kubernetes: K8s bỏ qua `HEALTHCHECK` của Docker → khai báo `livenessProbe`/`readinessProbe` trỏ vào `/health`. Thường để `WEB_CONCURRENCY=1` và scale bằng số `replicas`.

Giải thích các biến `ENV` trong Dockerfile:

| Biến | Stage | Tác dụng |
|------|-------|----------|
| `POETRY_VIRTUALENVS_IN_PROJECT=true` | builder | Poetry tạo venv ở `/app/.venv` thay vì `~/.cache/pypoetry/virtualenvs/<tên>-<hash>-py3.14` → đường dẫn cố định để `COPY --from=builder /app/.venv` sang stage 2. |
| `POETRY_NO_INTERACTION=1` | builder | Tương đương flag `-n`: poetry không hỏi gì. Lúc `docker build` không có bàn phím để trả lời → nếu poetry hỏi thì build bị treo/lỗi. |
| `PATH="/app/.venv/bin:$PATH"` | runtime | Đưa `.venv/bin` lên đầu `PATH` → gõ `uvicorn`, `python` là dùng bản trong venv, không cần `source .venv/bin/activate` hay `poetry run` (stage cuối cũng không có poetry). |
| `PYTHONDONTWRITEBYTECODE=1` | runtime | Python không ghi file `.pyc` / thư mục `__pycache__`. Container chạy bằng user `app`, không có quyền ghi vào `/app` → tránh lỗi/rác, file system gọn. |
| `PYTHONUNBUFFERED=1` | runtime | Tắt buffer stdout/stderr → log hiện ngay trong `docker logs`. Không có biến này log có thể bị giữ trong buffer, container crash là mất log. |
| `WEB_CONCURRENCY=2` | runtime | uvicorn đọc biến này làm số worker (= `--workers 2`). Ghi đè lúc chạy: `docker run -e WEB_CONCURRENCY=4 ...`. |

Build & chạy:

```bash
docker build -t lesson5-6 lesson5-6/
docker run -d --rm --name l56 -p 8000:8000 lesson5-6
curl localhost:8000/
curl localhost:8000/health
```

Output:

```
$ curl localhost:8000/
{"message":"Hello World"}

$ curl localhost:8000/health
{"status":"ok"}

$ docker exec l56 sh -c 'whoami; python -V; which poetry || echo no-poetry'
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
