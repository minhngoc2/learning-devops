"""Unit tests with a fake table: no AWS, no boto3. Run: python3 -m unittest discover -s app -v"""

import json
import unittest
from decimal import Decimal

import handler

USERS = [
    {"id": "u001", "name": "An Nguyen", "email": "an@example.com", "age": Decimal("29")},
    {"id": "u002", "name": "Binh Tran", "email": "binh@example.com", "age": Decimal("34")},
    {"id": "u003", "name": "Chi Le", "email": "chi@example.com", "score": Decimal("4.5")},
]


class FakeTable:
    """Mimics the boto3 Table calls the handler uses: scan (with paging) and get_item."""

    def __init__(self, items, fail=False):
        self.items = sorted(items, key=lambda i: i["id"])
        self.fail = fail
        self.scans = []

    def scan(self, Limit, ExclusiveStartKey=None):
        if self.fail:
            raise RuntimeError("AccessDeniedException")
        self.scans.append({"Limit": Limit, "ExclusiveStartKey": ExclusiveStartKey})
        rest = [i for i in self.items if ExclusiveStartKey is None or i["id"] > ExclusiveStartKey["id"]]
        page = rest[:Limit]
        out = {"Items": page, "Count": len(page)}
        if len(rest) > Limit:
            out["LastEvaluatedKey"] = {"id": page[-1]["id"]}
        return out

    def get_item(self, Key):
        if self.fail:
            raise RuntimeError("AccessDeniedException")
        item = next((i for i in self.items if i["id"] == Key["id"]), None)
        return {} if item is None else {"Item": item}


def call(route, query=None, path=None):
    event = {"routeKey": route, "requestContext": {"requestId": "test"}}
    if query is not None:
        event["queryStringParameters"] = query
    if path is not None:
        event["pathParameters"] = path
    resp = handler.lambda_handler(event, None)
    return resp["statusCode"], json.loads(resp["body"]), resp


class HandlerTest(unittest.TestCase):
    def setUp(self):
        self.table = FakeTable(USERS)
        handler._table = self.table

    def test_health(self):
        status, body, resp = call("GET /health")
        self.assertEqual((status, body), (200, {"status": "ok"}))
        self.assertEqual(resp["headers"]["Content-Type"], "application/json")

    def test_list_users(self):
        status, body, _ = call("GET /users")
        self.assertEqual(status, 200)
        self.assertEqual(body["count"], 3)
        self.assertEqual([u["id"] for u in body["users"]], ["u001", "u002", "u003"])
        self.assertNotIn("next", body)
        self.assertEqual(self.table.scans[0]["Limit"], handler.DEFAULT_LIMIT)

    def test_numbers_become_json_numbers(self):
        _, body, _ = call("GET /users")
        self.assertEqual(body["users"][0]["age"], 29)
        self.assertEqual(body["users"][2]["score"], 4.5)

    def test_pagination_walks_every_user_once(self):
        seen, cursor = [], None
        for _ in range(5):
            query = {"limit": "2"} | ({"next": cursor} if cursor else {})
            status, body, _ = call("GET /users", query=query)
            self.assertEqual(status, 200)
            seen += [u["id"] for u in body["users"]]
            cursor = body.get("next")
            self.assertNotIn("=", cursor or "")
            if cursor is None:
                break
        self.assertEqual(seen, ["u001", "u002", "u003"])

    def test_bad_limit(self):
        for raw in ["0", "101", "abc", "-1"]:
            with self.subTest(limit=raw):
                status, body, _ = call("GET /users", query={"limit": raw})
                self.assertEqual(status, 400)
                self.assertIn("limit", body["error"])

    def test_bad_cursor(self):
        for raw in ["not-base64!", "bnVsbA", "eyJ4IjoxfQ"]:  # garbage, null, {"x":1}
            with self.subTest(next=raw):
                status, body, _ = call("GET /users", query={"next": raw})
                self.assertEqual((status, body), (400, {"error": "next is not a valid cursor"}))

    def test_get_user(self):
        status, body, _ = call("GET /users/{id}", path={"id": "u002"})
        self.assertEqual(status, 200)
        self.assertEqual(body["name"], "Binh Tran")

    def test_get_missing_user(self):
        status, body, _ = call("GET /users/{id}", path={"id": "nobody"})
        self.assertEqual((status, body), (404, {"error": "user not found"}))

    def test_unknown_route(self):
        status, body, _ = call("DELETE /users/{id}", path={"id": "u001"})
        self.assertEqual((status, body), (404, {"error": "route not found"}))

    def test_aws_error_is_500_without_details(self):
        handler._table = FakeTable(USERS, fail=True)
        with self.assertLogs(level="ERROR"):
            status, body, _ = call("GET /users")
        self.assertEqual((status, body), (500, {"error": "internal error"}))


if __name__ == "__main__":
    unittest.main()
