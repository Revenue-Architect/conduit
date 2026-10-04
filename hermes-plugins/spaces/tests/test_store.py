from __future__ import annotations

import threading
import unittest

from _support import module, store

S = module("spaces_store")


class StoreTests(unittest.TestCase):
    def setUp(self) -> None:
        self.store = store()

    def test_initialisation_is_idempotent_and_seeds_personal_once(self) -> None:
        self.store.ensure_ready()
        again = S.SpacesStore(path=self.store.path)
        again.ensure_ready()
        names = [space["name"] for space in again.list_spaces()]
        self.assertEqual(names, ["Personal"])
        self.assertEqual(again.health(), {"ok": True, "schema_version": 1})
        # Deleting the seed does not bring it back on the next start.
        again.delete_space(again.list_spaces()[0]["id"])
        S.SpacesStore(path=self.store.path).ensure_ready()
        self.assertEqual(S.SpacesStore(path=self.store.path).list_spaces(), [])

    def test_space_names_are_trimmed_and_unique_case_insensitively(self) -> None:
        space = self.store.create_space("  Hermes  ", "🧠")
        self.assertEqual(space["name"], "Hermes")
        with self.assertRaises(S.SpacesError) as raised:
            self.store.create_space("hermes")
        self.assertEqual(raised.exception.code, "name_taken")
        with self.assertRaises(S.SpacesError):
            self.store.create_space("   ")
        with self.assertRaises(S.SpacesError):
            self.store.create_space("x" * 81)

    def test_page_revision_increments_exactly_once_per_mutation(self) -> None:
        space = self.store.create_space("Work")
        page = self.store.create_page(space["id"], title="Hello", content="This is a test.")
        self.assertEqual(page["revision"], 1)
        updated = self.store.update_page(page["id"], expected_revision=1, content="Two")
        self.assertEqual(updated["revision"], 2)
        self.assertEqual(updated["title"], "Hello")
        renamed = self.store.update_page(page["id"], expected_revision=2, title="Hi", content="Two")
        self.assertEqual((renamed["revision"], renamed["title"]), (3, "Hi"))

    def test_stale_write_is_rejected_with_current_revision(self) -> None:
        space = self.store.create_space("Work")
        page = self.store.create_page(space["id"], title="Doc")
        self.store.update_page(page["id"], expected_revision=1, content="new")
        with self.assertRaises(S.SpacesError) as raised:
            self.store.update_page(page["id"], expected_revision=1, content="stale")
        error = raised.exception
        self.assertEqual((error.code, error.status), ("revision_conflict", 409))
        self.assertEqual(error.as_dict()["current_revision"], 2)
        self.assertEqual(self.store.get_page(page["id"])["content"], "new")

    def test_concurrent_writers_one_wins_one_conflicts(self) -> None:
        space = self.store.create_space("Race")
        page = self.store.create_page(space["id"], title="Doc")
        results: list = []
        barrier = threading.Barrier(2)

        def write(text: str) -> None:
            writer = S.SpacesStore(path=self.store.path)
            barrier.wait()
            try:
                writer.update_page(page["id"], expected_revision=1, content=text)
                results.append("ok")
            except S.SpacesError as error:
                results.append(error.code)

        threads = [threading.Thread(target=write, args=(name,)) for name in ("a", "b")]
        for thread in threads:
            thread.start()
        for thread in threads:
            thread.join()
        self.assertEqual(sorted(results), ["ok", "revision_conflict"])
        self.assertEqual(self.store.get_page(page["id"])["revision"], 2)

    def test_nested_pages_reject_cycles_and_cross_space_parents(self) -> None:
        space = self.store.create_space("Tree")
        other = self.store.create_space("Other")
        root = self.store.create_page(space["id"], title="Root")
        child = self.store.create_page(space["id"], title="Child", parent_id=root["id"])
        grandchild = self.store.create_page(space["id"], title="Grand", parent_id=child["id"])
        stranger = self.store.create_page(other["id"], title="Stranger")
        cases = [
            (root, root["id"]),  # its own parent
            (root, grandchild["id"]),  # under its own descendant
            (child, grandchild["id"]),  # under its own child
        ]
        for target, parent in cases:
            with self.assertRaises(S.SpacesError) as raised:
                self.store.update_page(target["id"], expected_revision=1, parent_id=parent)
            self.assertEqual(raised.exception.code, "invalid_parent")
        with self.assertRaises(S.SpacesError):
            self.store.create_page(space["id"], title="X", parent_id=stranger["id"])
        moved = self.store.update_page(grandchild["id"], expected_revision=1, parent_id=None)
        self.assertIsNone(moved["parent_id"])

    def test_deleting_a_page_with_subpages_is_refused(self) -> None:
        space = self.store.create_space("Tree")
        root = self.store.create_page(space["id"], title="Root")
        self.store.create_page(space["id"], title="Child", parent_id=root["id"])
        with self.assertRaises(S.SpacesError) as raised:
            self.store.delete_page(root["id"])
        self.assertEqual(raised.exception.code, "page_has_subpages")

    def test_space_delete_needs_cascade_when_it_has_pages(self) -> None:
        space = self.store.create_space("Full")
        root = self.store.create_page(space["id"], title="Root")
        self.store.create_page(space["id"], title="Child", parent_id=root["id"])
        with self.assertRaises(S.SpacesError) as raised:
            self.store.delete_space(space["id"])
        self.assertEqual(raised.exception.code, "space_not_empty")
        self.store.delete_space(space["id"], cascade=True)
        with self.assertRaises(S.SpacesError):
            self.store.get_page(root["id"])

    def test_listing_returns_excerpts_not_bodies_and_searches(self) -> None:
        space = self.store.create_space("Search")
        self.store.create_page(space["id"], title="Alpha", content="# Heading\n\nAlpha body " * 50)
        self.store.create_page(space["id"], title="Beta", content="mentions 100% of_things")
        pages = self.store.list_pages(space["id"])
        self.assertEqual(len(pages), 2)
        for page in pages:
            self.assertNotIn("content", page)
            self.assertLessEqual(len(page["excerpt"]), S.EXCERPT_LENGTH)
        self.assertEqual([p["title"] for p in self.store.list_pages(space["id"], query="100%")], ["Beta"])
        self.assertEqual([p["title"] for p in self.store.list_pages(space["id"], query="of_t")], ["Beta"])
        self.assertEqual(
            [p["title"] for p in self.store.list_pages(space["id"], sort="name")], ["Alpha", "Beta"]
        )

    def test_limits_are_enforced(self) -> None:
        space = self.store.create_space("Limits")
        with self.assertRaises(S.SpacesError):
            self.store.create_page(space["id"], title="x" * 161)
        with self.assertRaises(S.SpacesError):
            self.store.create_page(space["id"], title="Big", content="x" * 100_001)
        page = self.store.create_page(space["id"], title="Edge", content="x" * 100_000)
        self.assertEqual(len(page["content"]), 100_000)
        with self.assertRaises(S.SpacesError):
            self.store.update_page(page["id"], expected_revision="1", content="y")

    def test_malformed_ids_are_not_found(self) -> None:
        for bad in ("../etc", "", "x" * 300, "' OR 1=1 --"):
            with self.assertRaises(S.SpacesError) as raised:
                self.store.get_page(bad)
            self.assertEqual(raised.exception.status, 404)

    def test_chat_bindings_per_profile_and_unique_sessions(self) -> None:
        space = self.store.create_space("Chats")
        page = self.store.create_page(space["id"], title="Doc")
        other = self.store.create_page(space["id"], title="Other")
        self.store.bind_chat(page["id"], "kai", "sess-a")
        self.store.bind_chat(page["id"], "strong", "sess-b")
        self.assertEqual(self.store.get_chat(page["id"], "kai")["session_id"], "sess-a")
        self.assertEqual(self.store.chat_for_session("sess-b")["profile"], "strong")
        with self.assertRaises(S.SpacesError) as raised:
            self.store.bind_chat(other["id"], "kai", "sess-a")
        self.assertEqual(raised.exception.code, "session_already_bound")
        self.assertEqual(
            sorted(chat["profile"] for chat in self.store.list_chats(page["id"])), ["kai", "strong"]
        )
        self.store.bind_chat(page["id"], "kai", "sess-c")  # rebinding replaces
        self.assertIsNone(self.store.chat_for_session("sess-a"))
        self.store.delete_page(page["id"])
        self.assertIsNone(self.store.chat_for_session("sess-c"))
        self.assertIsNone(self.store.chat_for_session("../bad id"))

    def test_data_survives_a_new_store_instance(self) -> None:
        space = self.store.create_space("Persist")
        page = self.store.create_page(space["id"], title="Doc", content="kept")
        self.store.bind_chat(page["id"], "kai", "sess-x")
        reopened = S.SpacesStore(path=self.store.path)
        self.assertEqual(reopened.get_page(page["id"])["content"], "kept")
        self.assertEqual(reopened.get_chat(page["id"], "kai")["session_id"], "sess-x")


if __name__ == "__main__":
    unittest.main()
