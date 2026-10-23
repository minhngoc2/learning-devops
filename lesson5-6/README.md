# Bài 5–6 — Docker image cho FastAPI theo hướng production

API FastAPI đóng gói bằng multi-stage Docker build: Poetry khóa dependency, container chạy non-root và có health check.

[Về trang tổng quan](../README.md)

> [!NOTE]
> Tệp: [Dockerfile](Dockerfile), [main.py](main.py), [healthcheck.py](healthcheck.py), [pyproject.toml](pyproject.toml), [poetry.lock](poetry.lock).

- **[Quickstart](quickstart.md)**: build, chạy, kiểm tra container, dọn dẹp (kèm kết quả mẫu)

## Yêu cầu

| Yêu cầu | Cách đáp ứng |
|---|---|
| Python 3.14 | `FROM python:3.14-slim` ở cả hai stage |
| Poetry | `pip install --no-cache-dir poetry`, chỉ ở stage `builder` |
| FastAPI + Uvicorn | `poetry add --lock fastapi uvicorn`, cài bằng `poetry install --only main --no-root` |
| API hello world | `GET /` trả `{"message": "Hello World"}` |

## Các điểm hướng đến production

- **Multi-stage build:** Poetry chỉ có trong stage `builder`; runtime image chỉ nhận `.venv`.
- **Dependency lock:** commit `poetry.lock` để cố định phiên bản dependency.
- **Build cache:** copy `pyproject.toml` và `poetry.lock` trước source code, nên sửa code không cài lại dependency.
- **Non-root user:** ứng dụng chạy bằng user `app`.
- **Non-package mode:** `package-mode = false`, vì project chỉ quản lý dependency, không publish package.
- **Health check:** endpoint `GET /health` và chỉ thị `HEALTHCHECK`. `healthcheck.py` dùng `urllib` có sẵn, nên không cần cài `curl`.
- **Nhiều worker:** Uvicorn đọc `WEB_CONCURRENCY=2` và chạy hai worker; có thể ghi đè khi chạy container.

> [!TIP]
> Trên Kubernetes, khai báo `livenessProbe` và `readinessProbe` trỏ tới `/health`. Thường mỗi container chạy một worker và Kubernetes scale bằng số `replicas`.

## Các biến `ENV`

| Stage | Biến | Tác dụng |
|---|---|---|
| Builder | `POETRY_VIRTUALENVS_IN_PROJECT=true` | Tạo virtualenv tại `/app/.venv` để copy sang stage cuối |
| Builder | `POETRY_NO_INTERACTION=1` | Không hỏi nhập liệu khi build |
| Runtime | `PATH="/app/.venv/bin:$PATH"` | Dùng `python`, `uvicorn` trong virtualenv mà không cần activate hay `poetry run` |
| Runtime | `PYTHONDONTWRITEBYTECODE=1` | Không tạo `.pyc` và `__pycache__` |
| Runtime | `PYTHONUNBUFFERED=1` | Ghi log ngay ra stdout/stderr để xem bằng `docker logs` |
| Runtime | `WEB_CONCURRENCY=2` | Số Uvicorn worker; có thể ghi đè |

## Kết quả

| Kiểm tra | Kết quả |
|---|---|
| `GET /` | `{"message":"Hello World"}` |
| `GET /health` | `{"status":"ok"}` |

> [!TIP]
> Lệnh đầy đủ và kết quả mẫu nằm trong [quickstart](quickstart.md).
