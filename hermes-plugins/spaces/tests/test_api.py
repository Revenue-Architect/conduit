from __future__ import annotations

import importlib.util
import unittest

from _support import PLUGIN_DIR, isolate_default_db

try:
    from fastapi import FastAPI
    from fastapi.testclient import TestClient
except ImportError:  # pragma: no cover - only inside the Hermes venv
    FastAPI = None


def load_api():
    isolate_default_db()
    import sys

    sys.modules.pop("hermes_spaces_store", None)
    spec = importlib.util.spec_from_file_location(
        "spaces_plugin_api_under_test", PLUGIN_DIR / "dashboard" / "plugin_api.py"
    )
    module = importlib.util.module_from_spec(spec)
    # As the dashboard does: registered before running, so Pydantic can
    # resolve the module's annotations.
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


@unittest.skipIf(FastAPI is None, "FastAPI is only available inside the Hermes venv")
class ApiTests(unittest.TestCase):
    def setUp(self) -> None:
        api = load_api()
        app = FastAPI()
        app.include_router(api.router, prefix="/api/plugins/spaces")
        self.client = TestClient(app)
        self.base = "/api/plugins/spaces"

    def test_health(self) -> None:
        response = self.client.get(f"{self.base}/health")
        self.assertEqual(response.json(), {"ok": True, "schema_version": 1})

    def test_full_page_flow_and_stable_conflict_contract(self) -> None:
        space = self.client.post(f"{self.base}/spaces", json={"name": "Test"})
        self.assertEqual(space.status_code, 201)
        space_id = space.json()["space"]["id"]
        page = self.client.post(
            f"{self.base}/spaces/{space_id}/pages", json={"title": "Hello", "content": "This is a test."}
        ).json()["page"]
        page_id = page["id"]
        listed = self.client.get(f"{self.base}/spaces/{space_id}/pages").json()["pages"]
        self.assertEqual(listed[0]["excerpt"], "This is a test.")
        self.assertNotIn("content", listed[0])
        ok = self.client.patch(
            f"{self.base}/pages/{page_id}", json={"content": "Two", "expected_revision": 1}
        )
        self.assertEqual(ok.json()["page"]["revision"], 2)
        stale = self.client.patch(
            f"{self.base}/pages/{page_id}", json={"content": "stale", "expected_revision": 1}
        )
        self.assertEqual(stale.status_code, 409)
        self.assertEqual(
            stale.json(),
            {
                "error": "revision_conflict",
                "message": "The page changed since this draft was loaded.",
                "current_revision": 2,
            },
        )
        self.assertEqual(self.client.delete(f"{self.base}/spaces/{space_id}").status_code, 409)
        self.assertEqual(
            self.client.delete(f"{self.base}/spaces/{space_id}?cascade=true").status_code, 200
        )

    def test_patch_requires_revision_and_rejects_unknown_fields(self) -> None:
        space_id = self.client.post(f"{self.base}/spaces", json={"name": "X"}).json()["space"]["id"]
        page_id = self.client.post(
            f"{self.base}/spaces/{space_id}/pages", json={"title": "T"}
        ).json()["page"]["id"]
        self.assertEqual(
            self.client.patch(f"{self.base}/pages/{page_id}", json={"content": "x"}).status_code, 422
        )
        self.assertEqual(
            self.client.patch(
                f"{self.base}/pages/{page_id}", json={"expected_revision": 1, "revision": 9}
            ).status_code,
            422,
        )
        too_big = "x" * 101_001
        self.assertEqual(
            self.client.patch(
                f"{self.base}/pages/{page_id}", json={"expected_revision": 1, "content": too_big}
            ).status_code,
            422,
        )

    def test_malformed_ids_and_missing_pages(self) -> None:
        self.assertEqual(self.client.get(f"{self.base}/pages/not-a-uuid").status_code, 404)
        self.assertEqual(
            self.client.get(f"{self.base}/pages/00000000-0000-4000-8000-000000000000").status_code,
            404,
        )

    def test_chat_binding_and_session_lookup(self) -> None:
        space_id = self.client.post(f"{self.base}/spaces", json={"name": "C"}).json()["space"]["id"]
        page_id = self.client.post(
            f"{self.base}/spaces/{space_id}/pages", json={"title": "T", "content": "secret body"}
        ).json()["page"]["id"]
        self.assertIsNone(self.client.get(f"{self.base}/pages/{page_id}/chat?profile=kai").json()["chat"])
        bound = self.client.put(
            f"{self.base}/pages/{page_id}/chat", json={"profile": "kai", "session_id": "s-1"}
        ).json()["chat"]
        self.assertEqual(bound["session_id"], "s-1")
        chats = self.client.get(f"{self.base}/pages/{page_id}/chats").json()["chats"]
        self.assertEqual([chat["profile"] for chat in chats], ["kai"])
        lookup = self.client.get(f"{self.base}/sessions/s-1/page").json()
        self.assertEqual(lookup["page"]["id"], page_id)
        self.assertNotIn("content", lookup["page"])
        self.client.delete(f"{self.base}/pages/{page_id}/chat?profile=kai")
        self.assertIsNone(self.client.get(f"{self.base}/sessions/s-1/page").json()["page"])


if __name__ == "__main__":
    unittest.main()
