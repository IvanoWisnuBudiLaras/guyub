"""Firestore Emulator security tests (no project data or credentials required).

Run with:
  firebase emulators:exec --project demo-guyub-rules --only auth,firestore \
    "python3 tool/firestore_rules_tests/test_firestore_rules.py"
"""
from __future__ import annotations

import json
import unittest
from urllib.error import HTTPError, URLError
from urllib.parse import quote
from urllib.request import Request, urlopen

PROJECT_ID = "demo-guyub-rules"
AUTH_BASE = "http://127.0.0.1:9099/identitytoolkit.googleapis.com/v1"
FIRESTORE_BASE = (
    f"http://127.0.0.1:8080/v1/projects/{PROJECT_ID}/databases/(default)/documents"
)


def request(method: str, url: str, *, token: str | None = None, body=None):
    headers = {"Content-Type": "application/json"}
    if token is not None:
        headers["Authorization"] = f"Bearer {token}"
    data = None if body is None else json.dumps(body).encode("utf-8")
    req = Request(url, data=data, headers=headers, method=method)
    try:
        with urlopen(req, timeout=5) as response:
            raw = response.read()
            return response.status, json.loads(raw) if raw else {}
    except HTTPError as error:
        with error:
            raw = error.read()
        return error.code, json.loads(raw) if raw else {}
    except URLError as error:
        raise RuntimeError(
            "Firebase Auth/Firestore emulators are not reachable; run this test "
            "through firebase emulators:exec."
        ) from error


_user_counter = 0


def create_user(*, anonymous: bool = False) -> dict:
    global _user_counter
    _user_counter += 1
    body = {"returnSecureToken": True}
    if not anonymous:
        body.update({
            "email": f"operator-{_user_counter}@example.invalid",
            "password": "test-password-123",
        })
    status, result = request(
        "POST", f"{AUTH_BASE}/accounts:signUp?key=fake-api-key", body=body
    )
    if status != 200:
        raise AssertionError(f"Auth emulator sign-up failed: {status} {result}")
    return result


def document_url(collection: str, document_id: str) -> str:
    return f"{FIRESTORE_BASE}/{collection}/{quote(document_id, safe='')}"


def seed_operator(
    uid: str,
    *,
    rt_id: str = "rt-01",
    role: str = "KETUA_RT_RW",
    active: bool = True,
) -> None:
    status, result = request(
        "PATCH",
        document_url("operators", uid),
        token="owner",
        body={
            "fields": {
                "rtId": {"stringValue": rt_id},
                "role": {"stringValue": role},
                "active": {"booleanValue": active},
            }
        },
    )
    if status != 200:
        raise AssertionError(f"Admin emulator seed failed: {status} {result}")


class FirestoreRulesTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.operator = create_user()
        cls.other_operator = create_user()
        cls.resident = create_user(anonymous=True)
        cls.inactive_operator = create_user()
        cls.invalid_role_operator = create_user()
        seed_operator(cls.operator["localId"], rt_id="rt-01")
        seed_operator(cls.other_operator["localId"], rt_id="rt-02")
        seed_operator(cls.resident["localId"], rt_id="rt-01")
        seed_operator(cls.inactive_operator["localId"], active=False)
        seed_operator(cls.invalid_role_operator["localId"], role="RESIDENT")

    def test_password_operator_can_read_own_membership_only(self):
        status, body = request(
            "GET",
            document_url("operators", self.operator["localId"]),
            token=self.operator["idToken"],
        )
        self.assertEqual(status, 200, body)
        self.assertEqual(body["fields"]["rtId"]["stringValue"], "rt-01")

        status, _ = request(
            "GET",
            document_url("operators", self.other_operator["localId"]),
            token=self.operator["idToken"],
        )
        self.assertEqual(status, 403)

    def test_anonymous_and_unauthenticated_users_cannot_read_operator_records(self):
        status, _ = request(
            "GET",
            document_url("operators", self.resident["localId"]),
            token=self.resident["idToken"],
        )
        self.assertEqual(status, 403)
        status, _ = request(
            "GET", document_url("operators", self.operator["localId"])
        )
        self.assertEqual(status, 403)

    def test_inactive_and_unsupported_roles_cannot_read_membership(self):
        for account in (self.inactive_operator, self.invalid_role_operator):
            status, _ = request(
                "GET",
                document_url("operators", account["localId"]),
                token=account["idToken"],
            )
            self.assertEqual(status, 403)

    def test_clients_cannot_list_or_change_operator_membership(self):
        status, _ = request(
            "GET", f"{FIRESTORE_BASE}/operators", token=self.operator["idToken"]
        )
        self.assertEqual(status, 403)
        status, _ = request(
            "PATCH",
            document_url("operators", self.operator["localId"]),
            token=self.operator["idToken"],
            body={"fields": {"rtId": {"stringValue": "rt-02"}}},
        )
        self.assertEqual(status, 403)

    def test_task_catalog_campaigns_and_audit_are_callable_only(self):
        body = {
            "fields": {
                "rtId": {"stringValue": "rt-01"},
                "status": {"stringValue": "ACTIVE"},
                "coreInstruction": {"stringValue": "untrusted client content"},
            }
        }
        for token in (self.operator["idToken"], self.resident["idToken"]):
            for collection in ("task_templates", "task_campaigns", "task_audit_events"):
                url = document_url(collection, "task-1")
                read_status, _ = request("GET", url, token=token)
                write_status, _ = request("PATCH", url, token=token, body=body)
                self.assertEqual(read_status, 403, collection)
                self.assertEqual(write_status, 403, collection)


if __name__ == "__main__":
    unittest.main(verbosity=2)
