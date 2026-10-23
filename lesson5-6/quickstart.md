# Quickstart: FastAPI trong Docker

Chạy mọi lệnh từ thư mục gốc của repository. Cần Docker.

## 1. Build và chạy

```bash
docker build -t lesson5-6 lesson5-6/
docker run -d --rm --name l56 -p 8000:8000 lesson5-6
```

## 2. Gọi API

```bash
curl --fail http://localhost:8000/
curl --fail http://localhost:8000/health
```

<details>
<summary>Kết quả mẫu</summary>

```console
$ curl --fail http://localhost:8000/
{"message":"Hello World"}

$ curl --fail http://localhost:8000/health
{"status":"ok"}
```

</details>

## 3. Kiểm tra container

```bash
docker exec l56 sh -c 'whoami; python -V; command -v poetry || echo no-poetry'
docker ps --filter name=l56 --format '{{.Status}}'
docker logs l56 | grep 'Started server'
```

Kỳ vọng: user là `app`, không có Poetry trong runtime image (`no-poetry`), trạng thái `(healthy)` sau khoảng 5–30 giây, và log có `Started server` cho mỗi worker.

> [!NOTE]
> Ngay sau khi chạy, trạng thái có thể là `(health: starting)`. `HEALTHCHECK` chờ `--start-period=5s`, sau đó kiểm tra mỗi 30 giây.

## 4. Dừng và dọn dẹp

```bash
docker stop l56
docker image rm lesson5-6
```

`--rm` khi chạy nên container tự xóa sau khi dừng.
