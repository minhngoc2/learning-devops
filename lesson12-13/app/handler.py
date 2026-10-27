"""Users API for AWS Lambda behind an API Gateway HTTP API (payload format 2.0), backed by DynamoDB.

API Gateway fills event["routeKey"] from the matched route ("GET /users", "GET /users/{id}"),
so the handler routes on it and never parses raw paths.
"""

import base64
import binascii
import json
import logging
import os
from decimal import Decimal

logger = logging.getLogger()
logger.setLevel(os.environ.get("LOG_LEVEL", "INFO"))

# Init phase: runs once per execution environment (cold start), then reused by warm invocations.
TABLE_NAME = os.environ.get("TABLE_NAME", "")
DEFAULT_LIMIT = 20
MAX_LIMIT = 100

_table = None


def table():
    """DynamoDB Table resource, created once per execution environment. Tests replace _table with a fake."""
    global _table
    if _table is None:
        import boto3  # bundled in the Lambda Python runtime; imported lazily so unit tests need no AWS SDK

        _table = boto3.resource("dynamodb").Table(TABLE_NAME)
    return _table


def lambda_handler(event, context):
    route = event.get("routeKey", "")
    request_id = event.get("requestContext", {}).get("requestId", "-")
    logger.info("request", extra={"route": route, "request_id": request_id})

    try:
        if route == "GET /health":
            return reply(200, {"status": "ok"})
        if route == "GET /users":
            return list_users(event.get("queryStringParameters") or {})
        if route == "GET /users/{id}":
            return get_user((event.get("pathParameters") or {}).get("id", ""))
        return reply(404, {"error": "route not found"})
    except BadRequest as e:
        return reply(400, {"error": str(e)})
    except Exception:  # an AWS error or a bug: log the trace, never leak it to the client
        logger.exception("unhandled error", extra={"route": route, "request_id": request_id})
        return reply(500, {"error": "internal error"})


class BadRequest(Exception):
    pass


def list_users(query):
    limit = parse_limit(query.get("limit"))
    kwargs = {"Limit": limit}
    if query.get("next"):
        kwargs["ExclusiveStartKey"] = decode_cursor(query["next"])

    # Scan reads the whole table page by page: fine for a small users table, use Query on a key for large ones.
    page = table().scan(**kwargs)
    body = {"users": page.get("Items", []), "count": page.get("Count", 0)}
    if "LastEvaluatedKey" in page:  # more items exist: hand the client an opaque cursor for the next page
        body["next"] = encode_cursor(page["LastEvaluatedKey"])
    return reply(200, body)


def get_user(user_id):
    if not user_id:
        raise BadRequest("id is required")
    item = table().get_item(Key={"id": user_id}).get("Item")
    if item is None:
        return reply(404, {"error": "user not found"})
    return reply(200, item)


def parse_limit(raw):
    if raw is None:
        return DEFAULT_LIMIT
    try:
        limit = int(raw)
    except ValueError:
        raise BadRequest(f"limit must be an integer between 1 and {MAX_LIMIT}") from None
    if not 1 <= limit <= MAX_LIMIT:
        raise BadRequest(f"limit must be an integer between 1 and {MAX_LIMIT}")
    return limit


def encode_cursor(key):
    # URL-safe base64 without "=" padding, so the cursor can go into a query string as-is.
    return base64.urlsafe_b64encode(json.dumps(key, default=to_json).encode()).decode().rstrip("=")


def decode_cursor(cursor):
    try:
        key = json.loads(base64.urlsafe_b64decode(cursor + "=" * (-len(cursor) % 4)))
    except (binascii.Error, ValueError, UnicodeDecodeError):
        raise BadRequest("next is not a valid cursor") from None
    if not isinstance(key, dict) or set(key) != {"id"} or not isinstance(key["id"], str):
        raise BadRequest("next is not a valid cursor")
    return key


def to_json(value):
    # DynamoDB returns every number as Decimal; JSON has no Decimal type.
    if isinstance(value, Decimal):
        return int(value) if value == value.to_integral_value() else float(value)
    raise TypeError(f"{type(value).__name__} is not JSON serializable")


def reply(status, body):
    return {
        "statusCode": status,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps(body, default=to_json, separators=(",", ":")),
    }
