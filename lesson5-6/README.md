# Bài 5–6 — Docker image cho FastAPI theo hướng production

[Về trang tổng quan](../README.md)

## Cấu trúc

- [`lesson5-6/`](./)
  - [`Dockerfile`](Dockerfile)
  - [`main.py`](main.py)
  - [`healthcheck.py`](healthcheck.py)
  - [`pyproject.toml`](pyproject.toml)
  - [`poetry.lock`](poetry.lock)

## Yêu cầu

- **Python 3.14**: `FROM python:3.14-slim` ở cả hai stage.
- **Poetry**: `RUN pip install --no-cache-dir poetry` chỉ ở stage `builder`.
- **FastAPI và Uvicorn**: thêm các dependency bằng `poetry add --lock fastapi uvicorn`, sau đó cài trong image bằng `poetry install --only main --no-root`.
- **API hello world**: `@app.get("/")` trả `{"message": "Hello World"}`.

## Các điểm hướng đến production

- **Multi-stage build**: Poetry chỉ tồn tại trong stage `builder`; runtime image chỉ nhận `.venv`.
- **Dependency lock**: commit `poetry.lock` cùng source code để cố định phiên bản các Python dependency.
- **Tận dụng build cache**: copy `pyproject.toml` và `poetry.lock` trước source code để không cài lại dependency khi chỉ thay đổi code.
- **Non-root user**: chạy ứng dụng bằng user `app`.
- **Non-package mode**: `package-mode = false` vì project này chỉ cần quản lý dependency, không build package để publish.
- **Health check**: endpoint `GET /health` và chỉ thị `HEALTHCHECK`. Script `healthcheck.py` dùng `urllib` có sẵn trong Python nên không cần cài thêm `curl`.
- **Nhiều worker**: Uvicorn đọc `WEB_CONCURRENCY=2` và khởi chạy hai worker; có thể ghi đè khi chạy container.

> Trên Kubernetes, hãy khai báo `livenessProbe` và `readinessProbe` trỏ tới `/health`. Thông thường mỗi container chạy một worker và Kubernetes scale bằng số `replicas`.

## Các biến `ENV`

### Builder

| Biến | Tác dụng |
|------|----------|
| `POETRY_VIRTUALENVS_IN_PROJECT=true` | Tạo virtual environment tại `/app/.venv` để copy sang stage cuối. |
| `POETRY_NO_INTERACTION=1` | Không yêu cầu nhập dữ liệu trong quá trình build. |

### Runtime

| Biến | Tác dụng |
|------|----------|
| `PATH="/app/.venv/bin:$PATH"` | Dùng `python` và `uvicorn` trong virtual environment mà không cần activate hoặc chạy `poetry run`. |
| `PYTHONDONTWRITEBYTECODE=1` | Không tạo file `.pyc` và thư mục `__pycache__` trong container. |
| `PYTHONUNBUFFERED=1` | Ghi log ngay ra stdout/stderr để xem bằng `docker logs`. |
| `WEB_CONCURRENCY=2` | Chạy hai Uvicorn worker; có thể ghi đè khi chạy container. |

## Build và chạy

Từ thư mục gốc của repository:

```bash
docker build -t lesson5-6 lesson5-6/
docker run -d --rm --name l56 -p 8000:8000 lesson5-6
curl --fail http://localhost:8000/
curl --fail http://localhost:8000/health
```

## Kết quả

```console
$ curl --fail http://localhost:8000/
{"message":"Hello World"}

$ curl --fail http://localhost:8000/health
{"status":"ok"}
```

## Kiểm tra container

```bash
docker exec l56 sh -c 'whoami; python -V; command -v poetry || echo no-poetry'
docker ps --filter name=l56 --format '{{.Status}}'
docker logs l56 | grep 'Started server'
```

## Dừng và dọn dẹp

```bash
docker stop l56
docker image rm lesson5-6
```
