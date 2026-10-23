# Bài 4 — Docker image cho ứng dụng Python

Đóng gói một script Python đơn giản thành Docker image và chạy nó.

[Về trang tổng quan](../README.md) · Tệp: [Dockerfile](Dockerfile), [main.py](main.py)

## Dockerfile

- Dùng image `python:3.14-slim`.
- Đặt thư mục làm việc thành `/app`.
- Cài Poetry bằng `pip install --no-cache-dir poetry`.
- Copy `main.py` vào image và chạy bằng `CMD ["python", "main.py"]`.

> [!TIP]
> `--no-cache-dir` ngăn pip lưu cache trong layer, giúp image gọn hơn.

> [!NOTE]
> Ở bài này Poetry chỉ được cài vào image; việc dùng Poetry để quản lý dependency được thực hành ở [Bài 5–6](../lesson5-6/README.md).

## Build và chạy

Từ thư mục gốc của repository:

```bash
docker build -t lesson4 lesson4/
docker run --rm lesson4
```

## Kết quả

```console
$ docker run --rm lesson4
hello world
```
