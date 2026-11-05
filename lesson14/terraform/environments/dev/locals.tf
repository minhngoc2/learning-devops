locals {
  name = "${var.project}-dev"

  default_tags = {
    Project     = var.project
    Environment = "dev"
    ManagedBy   = "terraform"
  }

  services = toset(["user", "product", "cart", "order", "payment", "notification"])

  # Every image and log group: the six services plus the one-off db-init task.
  all_task_names = setunion(local.services, ["db-init"])

  # Path routing and listener priority on the internal ALB; notification is a worker and has no route.
  web_services = {
    user    = { path_pattern = "/api/users*", priority = 10 }
    product = { path_pattern = "/api/products*", priority = 20 }
    cart    = { path_pattern = "/api/cart*", priority = 30 }
    order   = { path_pattern = "/api/orders*", priority = 40 }
    payment = { path_pattern = "/api/payments*", priority = 50 }
  }

  # Services with their own PostgreSQL role and schema (cart uses DynamoDB, notification no store).
  db_services = toset(["user", "product", "order", "payment"])
  db_schemas = {
    user    = "users"
    product = "products"
    order   = "orders"
    payment = "payments"
  }

  public_routes = [
    "POST /api/users/register",
    "POST /api/users/login",
    "GET /api/products",
    "GET /api/products/{id}",
  ]
  protected_routes = [
    "GET /api/users/me",
    "POST /api/products",
    "GET /api/cart",
    "PUT /api/cart/items/{productId}",
    "DELETE /api/cart",
    "POST /api/orders",
    "GET /api/orders",
    "GET /api/orders/{id}",
    "GET /api/payments/{orderId}",
  ]
}
