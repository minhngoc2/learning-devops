# Bài 8 — Thiết kế mạng nội bộ VPC

Thiết kế mạng AWS cho hai microservice (order, payment) của hai team riêng biệt, chạy trong nội địa Nhật Bản.

[Về trang tổng quan](../README.md)

> [!NOTE]
> Bài thiết kế, không có lệnh để chạy. Có hai phương án: **chung một VPC** (phương án 1) và **mỗi team một VPC/account** nối bằng PrivateLink ([phương án 2](#phương-án-2--mỗi-team-một-vpc-và-một-aws-account)).

Tệp:

- **Bản v2 (đã review & sửa):** [aws_vpc_payment_v2.excalidraw](aws_vpc_payment_v2.excalidraw), [aws_vpc_payment_v2.png](aws_vpc_payment_v2.png), [aws_vpc_payment.html](aws_vpc_payment.html) (ma trận kết nối + sequence một request thanh toán)
- Bản gốc: [aws_vpc_payment.excalidraw](aws_vpc_payment.excalidraw), [aws_vpc_payment.png](aws_vpc_payment.png)

## Đề bài

Công ty có 2 team hoàn toàn riêng biệt đang triển khai 2 microservice cho 1 hệ thống chung (main system):

- 2 service: order service, payment service.
- Mỗi service dùng 1 database riêng.
- Mỗi service có thể code bằng ngôn ngữ khác nhau.
- Hệ thống được sử dụng trong nội địa Nhật Bản.

Yêu cầu: vẽ sơ đồ mạng nội bộ (VPC, route table, subnet, NAT, NACL, ...), chỉ ra các thông số, region, AZ.

## Sơ đồ

![Sơ đồ VPC v2](aws_vpc_payment_v2.png)

Bản v2 gồm 6 phần: (1) topology theo từng AZ, (2) đường đi của một request thanh toán, (3) route table, (4) security group + stateful vs stateless, (5) NACL đầy đủ, (6) review bản gốc.

### Những gì đã sửa so với bản gốc

> [!IMPORTANT]
> **NACL là stateless** nhưng bản gốc thiếu rule cho traffic trả về (ephemeral `1024-65535`), nên reply từ DB, từ payment và từ PSP qua NAT sẽ bị drop. Đã bổ sung (xem [bảng NACL](#nacl-mỗi-tầng-subnet-một-nacl)).

- Vùng payment bị ghi nhầm "Team A - Order domain" và subnet `order-app`/`order-db` → **Team B**, `payment-app-*` / `payment-db-*`.
- Chưa vẽ AZ → tách 2 cột `ap-northeast-1a` / `1c`; mỗi subnet, NAT, route table, vai trò RDS (primary/standby) thể hiện theo AZ.
- Thiếu mũi tên ALB → service (listener rule) và order → payment `:8443` → đã bổ sung, đánh số luồng ①–⑦.
- Chỉ có 1 icon NAT dù ghi "1 per AZ" → `nat-1a`, `nat-1c`.
- Lỗi chính tả "Pyament"; route table / NACL / SG không có trong PNG.

> [!TIP]
> Mở [aws_vpc_payment.excalidraw](aws_vpc_payment.excalidraw) bằng [excalidraw.com](https://excalidraw.com) hoặc extension Excalidraw trong VS Code để chỉnh sửa.

## Thông số

| Thành phần | Giá trị |
|---|---|
| Region | `ap-northeast-1` (Tokyo) — dữ liệu nằm trong Nhật Bản |
| AZ | `ap-northeast-1a`, `ap-northeast-1c` |
| VPC | `10.0.0.0/16` |
| Public subnet (ALB, NAT) | 1a `10.0.0.0/24`, 1c `10.0.1.0/24` |
| order-app (private) | 1a `10.0.10.0/24`, 1c `10.0.11.0/24` — Order Service (Go) |
| order-db (isolated) | 1a `10.0.30.0/24`, 1c `10.0.31.0/24` — RDS Multi-AZ `:5432` |
| payment-app (private) | 1a `10.0.20.0/24`, 1c `10.0.21.0/24` — Payment Service (Node.js) |
| payment-db (isolated) | 1a `10.0.40.0/24`, 1c `10.0.41.0/24` — RDS Multi-AZ `:3306` |
| NAT Gateway | 1 NAT mỗi AZ, có Elastic IP |
| WAF | Gắn vào ALB, geo-match chỉ cho phép JP |

### Route table

| Route table | Route |
|---|---|
| `rtb-public` | `0.0.0.0/0` → IGW |
| `rtb-app-1a` / `rtb-app-1c` | `0.0.0.0/0` → NAT cùng AZ |
| `rtb-db` | Chỉ `local`, không ra internet |
| Tất cả | `10.0.0.0/16` → `local` |

### NACL (mỗi tầng subnet một NACL)

NACL không theo dõi kết nối, nên mỗi chiều đi **và** chiều về đều phải có rule. Ký hiệu `/23` = cặp subnet 1a + 1c (vd. `10.0.10.0/23` = order-app 1a + 1c).

| NACL | Inbound | Outbound |
|---|---|---|
| `nacl-public` | 443 ← `0.0.0.0/0`; **1024-65535 ← `0.0.0.0/0`**; 443 ← `10.0.20.0/23` (payment → NAT) | 1024-65535 → `0.0.0.0/0`; 8080 → `10.0.10.0/23`; 8443 → `10.0.20.0/23`; 443 → `0.0.0.0/0` |
| `nacl-order` | 8080 ← `10.0.0.0/23`; **1024-65535 ← `10.0.20.0/23`, `10.0.30.0/23`** | 1024-65535 → `10.0.0.0/23`; 8443 → `10.0.20.0/23`; 5432 → `10.0.30.0/23` |
| `nacl-payment` | 8443 ← `10.0.0.0/23`, `10.0.10.0/23`; **1024-65535 ← `0.0.0.0/0`** | 1024-65535 → `10.0.0.0/23`, `10.0.10.0/23`; 3306 → `10.0.40.0/23`; 443 → `0.0.0.0/0` |
| `nacl-order-db` | 5432 ← `10.0.10.0/23` | **1024-65535 → `10.0.10.0/23`** |
| `nacl-payment-db` | 3306 ← `10.0.20.0/23` | **1024-65535 → `10.0.20.0/23`** |

Chữ đậm = rule trả về bị thiếu ở bản gốc.

### Security group

- `sg-alb`: 443 từ `0.0.0.0/0`.
- `sg-order` (`:8080`), `sg-payment` (`:8443`): cổng app chỉ từ `sg-alb`; `sg-payment` nhận thêm `8443` từ `sg-order`. (Cổng app `8080`/`8443` là giả định của bản v2.)
- `sg-order-db`, `sg-payment-db`: cổng DB chỉ từ SG app của team mình.

Payment Service gọi cổng thanh toán bên ngoài (PayPal, Stripe) qua NAT → IGW.

### Nên cân nhắc thêm

> [!TIP]
> - VPC endpoint (S3, ECR, Secrets Manager, CloudWatch) để traffic tới AWS API không đi qua NAT — rẻ hơn và private.
> - Hai team "hoàn toàn riêng biệt" → mỗi team một AWS account + VPC, nối bằng PrivateLink / Transit Gateway là ranh giới cô lập mạnh hơn so với chia subnet trong cùng một VPC.

## Phương án 2 — mỗi team một VPC (và một AWS account)

Tệp: [aws_two_vpc.excalidraw](aws_two_vpc.excalidraw), [aws_two_vpc.png](aws_two_vpc.png), [aws_two_vpc.html](aws_two_vpc.html)

![Sơ đồ 2 VPC](aws_two_vpc.png)

Cùng yêu cầu như trên; khác biệt duy nhất: Team A thay đổi mạng (CIDR, subnet, route table, NACL, SG…) không thể ảnh hưởng VPC của Team B.

| Thành phần | VPC-order (Team A) | VPC-payment (Team B) |
|---|---|---|
| CIDR | `10.10.0.0/16` | `10.20.0.0/16` |
| Public subnet | `10.10.0.0/24`, `10.10.1.0/24` — ALB-A | `10.20.0.0/24`, `10.20.1.0/24` — ALB-B, NAT-1a/1c |
| App subnet | `10.10.10.0/24`, `10.10.11.0/24` — Order (Go) `:8080` + vpce ENI | `10.20.20.0/24`, `10.20.21.0/24` — Payment (Node.js) `:8443` + NLB nội bộ |
| DB subnet | `10.10.30.0/24`, `10.10.31.0/24` — RDS `:5432` | `10.20.40.0/24`, `10.20.41.0/24` — RDS `:3306` |
| Internet egress | Không có NAT (dùng VPC endpoint S3/ECR/Logs) | NAT mỗi AZ → Stripe/PayPal |
| Domain | `order.example.jp` → ALB-A + WAF | `pay.example.jp` → ALB-B + WAF |

- **Kết nối order → payment bằng AWS PrivateLink**: Team B công bố endpoint service (sau NLB nội bộ, cổng `8443`) và chỉ cho phép principal của account A; Team A tạo interface endpoint trong app subnet của mình (`payments.internal`).
- **Không có route nào giữa hai VPC** (không peering, không Transit Gateway) → CIDR có thể trùng, route table hai bên độc lập, chỉ một chiều, chỉ một cổng.
- Payment chỉ thấy IP của NLB, không bao giờ thấy `10.10.x.x` → NACL/SG của Team B không phụ thuộc CIDR của Team A.
- "Hợp đồng" chung giữa hai team chỉ gồm: tên endpoint service, cổng `8443`, account được phép, API.
- Peering/TGW vẫn hợp lệ, nhưng bắt buộc CIDR không trùng và sửa route ở cả hai phía — xem phần 4 của sơ đồ.
