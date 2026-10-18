# Learning DevOps

Ghi chép và bài thực hành về Linux, Bash, Docker, AWS và triển khai ứng dụng bằng Terraform.

## Bài học

| Bài | Chủ đề |
|-----|--------|
| [Bài 1](lesson1/README.md) | Các lệnh Linux cơ bản |
| [Bài 3](lesson3/README.md) | Bash script kiểm tra dịch vụ |
| [Bài 4](lesson4/README.md) | Docker image cho ứng dụng Python |
| [Bài 5–6](lesson5-6/README.md) | Docker image cho FastAPI theo hướng production |
| [Bài 8](lesson8/README.md) | Thiết kế mạng nội bộ VPC trên AWS |
| [Bài 10–11](lesson10-11/README.md) | Go API + RDS trên ECS Fargate bằng Terraform |

## Bài 10–11: Triển khai trên AWS

Go API đã chạy trên ECS Fargate, kết nối RDS PostgreSQL và kiểm tra tạo/đọc todo thành công. Terraform gồm bootstrap, môi trường dev và các module cần thiết.

- [Kết quả và sơ đồ kiến trúc](lesson10-11/README.md#architecture)
- [Ảnh kiểm chứng API và ECS](lesson10-11/README.md#evidence)
- [Chạy local và triển khai AWS](lesson10-11/quickstart.md)
