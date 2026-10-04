"""SQLite store for Hermes Spaces: Spaces, Pages and Page-chat bindings.

Pure standard library so the agent process (tools, hook) and the dashboard
process (REST routes) share one implementation. Every operation opens its own
short-lived connection: WAL lets readers run beside a writer, and mutations
take ``BEGIN IMMEDIATE`` so a revision check and its update are one atomic
step across processes.

Page bodies are untrusted document data. Nothing here interprets them.
"""

from __future__ import annotations

import os
import re
import sqlite3
import time
import uuid
from contextlib import closing, contextmanager
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Dict, Iterator, List, Optional

SCHEMA_VERSION = 1

NAME_MAX = 80
TITLE_MAX = 160
CONTENT_MAX = 100_000
ICON_MAX = 16
EXCERPT_LENGTH = 180
LIST_LIMIT_MAX = 500
SEARCH_MAX = 200

_ID_RE = re.compile(r"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$")
_PROFILE_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_-]{0,63}$")
_SESSION_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._:-]{0,199}$")

# Sentinel: "parent_id was not part of this update" (``None`` means "move to
# the top level").
UNSET: Any = object()


class SpacesError(Exception):
    """A failure with a stable machine-readable code and HTTP status."""

    def __init__(self, code: str, message: str, status: int, **extra: Any):
        super().__init__(message)
        self.code = code
        self.message = message
        self.status = status
        self.extra = extra

    def as_dict(self) -> Dict[str, Any]:
        return {"error": self.code, "message": self.message, **self.extra}


def _invalid(message: str) -> SpacesError:
    return SpacesError("invalid_request", message, 422)


def _not_found(what: str) -> SpacesError:
    return SpacesError("not_found", f"{what} not found.", 404)


def now_ms() -> int:
    return int(time.time() * 1000)


def valid_id(value: Any) -> bool:
    return isinstance(value, str) and bool(_ID_RE.match(value))


def valid_profile(value: Any) -> bool:
    return isinstance(value, str) and bool(_PROFILE_RE.match(value))


def valid_session_id(value: Any) -> bool:
    return isinstance(value, str) and bool(_SESSION_RE.match(value))


def _require_id(value: Any, what: str) -> str:
    if not valid_id(value):
        raise _not_found(what)
    return value


def _clean_name(value: Any) -> str:
    name = value.strip() if isinstance(value, str) else ""
    if not 1 <= len(name) <= NAME_MAX:
        raise _invalid(f"Space name must be 1 to {NAME_MAX} characters.")
    return name


def _clean_icon(value: Any) -> Optional[str]:
    if value is None:
        return None
    icon = value.strip() if isinstance(value, str) else ""
    if not icon:
        return None
    if len(icon) > ICON_MAX:
        raise _invalid(f"Icon must be at most {ICON_MAX} characters.")
    return icon


def _clean_title(value: Any) -> str:
    title = value.strip() if isinstance(value, str) else ""
    if not 1 <= len(title) <= TITLE_MAX:
        raise _invalid(f"Page title must be 1 to {TITLE_MAX} characters.")
    return title


def _clean_content(value: Any) -> str:
    if value is None:
        return ""
    if not isinstance(value, str):
        raise _invalid("Page content must be Markdown text.")
    if len(value) > CONTENT_MAX:
        raise _invalid(f"Page content must be at most {CONTENT_MAX} characters.")
    return value


def excerpt(content: str) -> str:
    """A short plain-ish preview: first non-empty lines, Markdown markers
    trimmed, whitespace collapsed."""
    lines = []
    for raw in content.splitlines():
        line = raw.strip()
        if not line or line.startswith("```") or line in ("---", "***"):
            continue
        line = re.sub(r"^(#{1,6}\s+|[-*+]\s+(\[[ xX]\]\s+)?|\d+[.)]\s+|>\s*)", "", line)
        lines.append(line)
        if sum(len(item) for item in lines) >= EXCERPT_LENGTH:
            break
    text = re.sub(r"\s+", " ", " ".join(lines)).strip()
    return text if len(text) <= EXCERPT_LENGTH else text[: EXCERPT_LENGTH - 1].rstrip() + "…"


def default_db_path() -> Path:
    """``<hermes root>/spaces/spaces.db``: one store shared by every profile."""
    override = os.environ.get("HERMES_SPACES_DB", "").strip()
    if override:
        return Path(override)
    try:
        from hermes_constants import get_default_hermes_root

        root = Path(get_default_hermes_root())
    except Exception:
        root = Path(os.environ.get("HERMES_HOME") or Path.home() / ".hermes")
    return root / "spaces" / "spaces.db"


_SCHEMA = """
CREATE TABLE IF NOT EXISTS spaces (
    id          TEXT PRIMARY KEY,
    name        TEXT NOT NULL,
    icon        TEXT,
    created_at  INTEGER NOT NULL,
    updated_at  INTEGER NOT NULL
);
CREATE UNIQUE INDEX IF NOT EXISTS idx_spaces_name_nocase ON spaces(lower(name));

CREATE TABLE IF NOT EXISTS pages (
    id                  TEXT PRIMARY KEY,
    space_id            TEXT NOT NULL,
    parent_id           TEXT,
    title               TEXT NOT NULL,
    content             TEXT NOT NULL DEFAULT '',
    revision            INTEGER NOT NULL DEFAULT 1,
    source_session_id   TEXT,
    created_at          INTEGER NOT NULL,
    updated_at          INTEGER NOT NULL,
    FOREIGN KEY(space_id) REFERENCES spaces(id) ON DELETE CASCADE,
    FOREIGN KEY(parent_id) REFERENCES pages(id) ON DELETE RESTRICT
);
CREATE INDEX IF NOT EXISTS idx_pages_space ON pages(space_id);
CREATE INDEX IF NOT EXISTS idx_pages_parent ON pages(parent_id);
CREATE INDEX IF NOT EXISTS idx_pages_updated ON pages(space_id, updated_at DESC);

CREATE TABLE IF NOT EXISTS page_chats (
    page_id      TEXT NOT NULL,
    profile      TEXT NOT NULL,
    session_id   TEXT NOT NULL,
    created_at   INTEGER NOT NULL,
    updated_at   INTEGER NOT NULL,
    PRIMARY KEY(page_id, profile),
    UNIQUE(session_id),
    FOREIGN KEY(page_id) REFERENCES pages(id) ON DELETE CASCADE
);
"""


@dataclass
class SpacesStore:
    path: Path = field(default_factory=default_db_path)
    _ready: bool = field(default=False, init=False, repr=False)

    # -- connection -----------------------------------------------------------

    def _connect(self) -> sqlite3.Connection:
        conn = sqlite3.connect(str(self.path), timeout=5.0, isolation_level=None)
        conn.row_factory = sqlite3.Row
        conn.execute("PRAGMA foreign_keys = ON")
        conn.execute("PRAGMA busy_timeout = 5000")
        conn.execute("PRAGMA synchronous = NORMAL")
        return conn

    def ensure_ready(self) -> None:
        """Create the schema and seed the first Space. Idempotent; safe to
        call from several processes at once."""
        if self._ready:
            return
        self.path.parent.mkdir(parents=True, exist_ok=True)
        with closing(self._connect()) as conn:
            conn.execute("PRAGMA journal_mode = WAL")
            conn.execute("BEGIN IMMEDIATE")
            try:
                version = conn.execute("PRAGMA user_version").fetchone()[0]
                if version > SCHEMA_VERSION:
                    raise RuntimeError(
                        f"spaces.db schema {version} is newer than this plugin ({SCHEMA_VERSION})"
                    )
                for statement in filter(None, (s.strip() for s in _SCHEMA.split(";"))):
                    conn.execute(statement)
                if version < SCHEMA_VERSION:
                    conn.execute(f"PRAGMA user_version = {SCHEMA_VERSION}")
                if conn.execute("SELECT COUNT(*) FROM spaces").fetchone()[0] == 0 and version == 0:
                    stamp = now_ms()
                    conn.execute(
                        "INSERT INTO spaces(id, name, icon, created_at, updated_at) VALUES (?, ?, ?, ?, ?)",
                        (str(uuid.uuid4()), "Personal", None, stamp, stamp),
                    )
                conn.execute("COMMIT")
            except Exception:
                conn.execute("ROLLBACK")
                raise
        self._ready = True

    @contextmanager
    def _read(self) -> Iterator[sqlite3.Connection]:
        self.ensure_ready()
        with closing(self._connect()) as conn:
            yield conn

    @contextmanager
    def _write(self) -> Iterator[sqlite3.Connection]:
        self.ensure_ready()
        with closing(self._connect()) as conn:
            conn.execute("BEGIN IMMEDIATE")
            try:
                yield conn
                conn.execute("COMMIT")
            except BaseException:
                conn.execute("ROLLBACK")
                raise

    def health(self) -> Dict[str, Any]:
        with self._read() as conn:
            version = conn.execute("PRAGMA user_version").fetchone()[0]
        return {"ok": True, "schema_version": version}

    # -- spaces ---------------------------------------------------------------

    @staticmethod
    def _space(row: sqlite3.Row) -> Dict[str, Any]:
        out = {
            "id": row["id"],
            "name": row["name"],
            "icon": row["icon"],
            "created_at": row["created_at"],
            "updated_at": row["updated_at"],
        }
        if "page_count" in row.keys():
            out["page_count"] = row["page_count"]
        return out

    def list_spaces(self) -> List[Dict[str, Any]]:
        with self._read() as conn:
            rows = conn.execute(
                "SELECT s.*, (SELECT COUNT(*) FROM pages p WHERE p.space_id = s.id) AS page_count "
                "FROM spaces s ORDER BY lower(s.name)"
            ).fetchall()
        return [self._space(row) for row in rows]

    def get_space(self, space_id: str) -> Dict[str, Any]:
        _require_id(space_id, "Space")
        with self._read() as conn:
            row = conn.execute(
                "SELECT s.*, (SELECT COUNT(*) FROM pages p WHERE p.space_id = s.id) AS page_count "
                "FROM spaces s WHERE s.id = ?",
                (space_id,),
            ).fetchone()
        if row is None:
            raise _not_found("Space")
        return self._space(row)

    def _name_taken(self, conn: sqlite3.Connection, name: str, except_id: Optional[str] = None) -> bool:
        row = conn.execute(
            "SELECT id FROM spaces WHERE lower(name) = lower(?)", (name,)
        ).fetchone()
        return row is not None and row["id"] != except_id

    def create_space(self, name: Any, icon: Any = None) -> Dict[str, Any]:
        clean, clean_icon = _clean_name(name), _clean_icon(icon)
        stamp = now_ms()
        space_id = str(uuid.uuid4())
        with self._write() as conn:
            if self._name_taken(conn, clean):
                raise SpacesError("name_taken", "A Space with that name already exists.", 409)
            conn.execute(
                "INSERT INTO spaces(id, name, icon, created_at, updated_at) VALUES (?, ?, ?, ?, ?)",
                (space_id, clean, clean_icon, stamp, stamp),
            )
        return self.get_space(space_id)

    def update_space(self, space_id: str, *, name: Any = UNSET, icon: Any = UNSET) -> Dict[str, Any]:
        _require_id(space_id, "Space")
        with self._write() as conn:
            row = conn.execute("SELECT * FROM spaces WHERE id = ?", (space_id,)).fetchone()
            if row is None:
                raise _not_found("Space")
            new_name = row["name"] if name is UNSET else _clean_name(name)
            new_icon = row["icon"] if icon is UNSET else _clean_icon(icon)
            if self._name_taken(conn, new_name, except_id=space_id):
                raise SpacesError("name_taken", "A Space with that name already exists.", 409)
            conn.execute(
                "UPDATE spaces SET name = ?, icon = ?, updated_at = ? WHERE id = ?",
                (new_name, new_icon, now_ms(), space_id),
            )
        return self.get_space(space_id)

    def delete_space(self, space_id: str, *, cascade: bool = False) -> None:
        _require_id(space_id, "Space")
        with self._write() as conn:
            if conn.execute("SELECT 1 FROM spaces WHERE id = ?", (space_id,)).fetchone() is None:
                raise _not_found("Space")
            count = conn.execute(
                "SELECT COUNT(*) FROM pages WHERE space_id = ?", (space_id,)
            ).fetchone()[0]
            if count and not cascade:
                raise SpacesError(
                    "space_not_empty",
                    "This Space still has Pages. Delete them first or confirm deleting everything.",
                    409,
                    page_count=count,
                )
            if count:
                # Children reference parents with RESTRICT: clear the tree first.
                conn.execute("UPDATE pages SET parent_id = NULL WHERE space_id = ?", (space_id,))
            conn.execute("DELETE FROM spaces WHERE id = ?", (space_id,))

    # -- pages ----------------------------------------------------------------

    @staticmethod
    def _page_meta(row: sqlite3.Row) -> Dict[str, Any]:
        out = {
            "id": row["id"],
            "space_id": row["space_id"],
            "parent_id": row["parent_id"],
            "title": row["title"],
            "revision": row["revision"],
            "created_at": row["created_at"],
            "updated_at": row["updated_at"],
        }
        if "content" in row.keys():
            out["excerpt"] = excerpt(row["content"])
        if "child_count" in row.keys():
            out["child_count"] = row["child_count"]
        return out

    @staticmethod
    def _page_full(row: sqlite3.Row) -> Dict[str, Any]:
        return {
            "id": row["id"],
            "space_id": row["space_id"],
            "parent_id": row["parent_id"],
            "title": row["title"],
            "content": row["content"],
            "revision": row["revision"],
            "source_session_id": row["source_session_id"],
            "created_at": row["created_at"],
            "updated_at": row["updated_at"],
        }

    def list_pages(
        self,
        space_id: str,
        *,
        query: Optional[str] = None,
        parent_id: Any = UNSET,
        sort: str = "updated",
        limit: int = LIST_LIMIT_MAX,
    ) -> List[Dict[str, Any]]:
        _require_id(space_id, "Space")
        where, params = ["p.space_id = ?"], [space_id]
        if query is not None and query.strip():
            needle = query.strip()[:SEARCH_MAX].lower()
            escaped = needle.replace("\\", "\\\\").replace("%", "\\%").replace("_", "\\_")
            where.append(
                "(lower(p.title) LIKE ? ESCAPE '\\' OR lower(p.content) LIKE ? ESCAPE '\\')"
            )
            params += [f"%{escaped}%", f"%{escaped}%"]
        if parent_id is not UNSET:
            if parent_id is None:
                where.append("p.parent_id IS NULL")
            else:
                _require_id(parent_id, "Parent page")
                where.append("p.parent_id = ?")
                params.append(parent_id)
        order = "lower(p.title), p.updated_at DESC" if sort == "name" else "p.updated_at DESC"
        limit = max(1, min(int(limit), LIST_LIMIT_MAX))
        with self._read() as conn:
            if conn.execute("SELECT 1 FROM spaces WHERE id = ?", (space_id,)).fetchone() is None:
                raise _not_found("Space")
            rows = conn.execute(
                "SELECT p.id, p.space_id, p.parent_id, p.title, p.revision, p.created_at, p.updated_at, "
                "substr(p.content, 1, 1200) AS content, "
                "(SELECT COUNT(*) FROM pages c WHERE c.parent_id = p.id) AS child_count "
                f"FROM pages p WHERE {' AND '.join(where)} ORDER BY {order} LIMIT ?",
                (*params, limit),
            ).fetchall()
        return [self._page_meta(row) for row in rows]

    def get_page(self, page_id: str) -> Dict[str, Any]:
        _require_id(page_id, "Page")
        with self._read() as conn:
            row = conn.execute("SELECT * FROM pages WHERE id = ?", (page_id,)).fetchone()
        if row is None:
            raise _not_found("Page")
        return self._page_full(row)

    def _check_parent(
        self, conn: sqlite3.Connection, space_id: str, parent_id: Optional[str], page_id: Optional[str]
    ) -> None:
        if parent_id is None:
            return
        if not valid_id(parent_id):
            raise _invalid("Parent page is not valid.")
        if parent_id == page_id:
            raise SpacesError("invalid_parent", "A Page cannot be its own parent.", 422)
        parent = conn.execute(
            "SELECT space_id FROM pages WHERE id = ?", (parent_id,)
        ).fetchone()
        if parent is None:
            raise SpacesError("invalid_parent", "Parent page does not exist.", 422)
        if parent["space_id"] != space_id:
            raise SpacesError("invalid_parent", "Parent page belongs to another Space.", 422)
        if page_id is None:
            return
        # Walk up from the new parent: reaching the moved page means a cycle.
        cursor, seen = parent_id, set()
        while cursor is not None and cursor not in seen:
            if cursor == page_id:
                raise SpacesError(
                    "invalid_parent", "A Page cannot be moved under one of its own subpages.", 422
                )
            seen.add(cursor)
            row = conn.execute("SELECT parent_id FROM pages WHERE id = ?", (cursor,)).fetchone()
            cursor = row["parent_id"] if row else None

    def create_page(
        self,
        space_id: str,
        *,
        title: Any,
        content: Any = "",
        parent_id: Optional[str] = None,
        source_session_id: Optional[str] = None,
    ) -> Dict[str, Any]:
        _require_id(space_id, "Space")
        clean_title, clean_content = _clean_title(title), _clean_content(content)
        source = source_session_id if valid_session_id(source_session_id) else None
        page_id, stamp = str(uuid.uuid4()), now_ms()
        with self._write() as conn:
            if conn.execute("SELECT 1 FROM spaces WHERE id = ?", (space_id,)).fetchone() is None:
                raise _not_found("Space")
            self._check_parent(conn, space_id, parent_id, None)
            conn.execute(
                "INSERT INTO pages(id, space_id, parent_id, title, content, revision, "
                "source_session_id, created_at, updated_at) VALUES (?, ?, ?, ?, ?, 1, ?, ?, ?)",
                (page_id, space_id, parent_id, clean_title, clean_content, source, stamp, stamp),
            )
            conn.execute("UPDATE spaces SET updated_at = ? WHERE id = ?", (stamp, space_id))
        return self.get_page(page_id)

    def update_page(
        self,
        page_id: str,
        *,
        expected_revision: Any,
        title: Any = UNSET,
        content: Any = UNSET,
        parent_id: Any = UNSET,
    ) -> Dict[str, Any]:
        _require_id(page_id, "Page")
        if isinstance(expected_revision, bool) or not isinstance(expected_revision, int):
            raise _invalid("expected_revision is required and must be an integer.")
        new_title = UNSET if title is UNSET else _clean_title(title)
        new_content = UNSET if content is UNSET else _clean_content(content)
        with self._write() as conn:
            row = conn.execute("SELECT * FROM pages WHERE id = ?", (page_id,)).fetchone()
            if row is None:
                raise _not_found("Page")
            if row["revision"] != expected_revision:
                raise SpacesError(
                    "revision_conflict",
                    "The page changed since this draft was loaded.",
                    409,
                    current_revision=row["revision"],
                )
            if parent_id is not UNSET:
                self._check_parent(conn, row["space_id"], parent_id, page_id)
            stamp = now_ms()
            conn.execute(
                "UPDATE pages SET title = ?, content = ?, parent_id = ?, "
                "revision = revision + 1, updated_at = ? WHERE id = ?",
                (
                    row["title"] if new_title is UNSET else new_title,
                    row["content"] if new_content is UNSET else new_content,
                    row["parent_id"] if parent_id is UNSET else parent_id,
                    stamp,
                    page_id,
                ),
            )
            conn.execute("UPDATE spaces SET updated_at = ? WHERE id = ?", (stamp, row["space_id"]))
        return self.get_page(page_id)

    def delete_page(self, page_id: str) -> None:
        _require_id(page_id, "Page")
        with self._write() as conn:
            if conn.execute("SELECT 1 FROM pages WHERE id = ?", (page_id,)).fetchone() is None:
                raise _not_found("Page")
            children = conn.execute(
                "SELECT COUNT(*) FROM pages WHERE parent_id = ?", (page_id,)
            ).fetchone()[0]
            if children:
                raise SpacesError(
                    "page_has_subpages",
                    "Move or delete this Page's subpages first.",
                    409,
                    child_count=children,
                )
            conn.execute("DELETE FROM pages WHERE id = ?", (page_id,))

    # -- page chats -----------------------------------------------------------

    @staticmethod
    def _chat(row: sqlite3.Row) -> Dict[str, Any]:
        return {
            "page_id": row["page_id"],
            "profile": row["profile"],
            "session_id": row["session_id"],
            "created_at": row["created_at"],
            "updated_at": row["updated_at"],
        }

    def get_chat(self, page_id: str, profile: str) -> Optional[Dict[str, Any]]:
        _require_id(page_id, "Page")
        if not valid_profile(profile):
            raise _invalid("Profile is not valid.")
        with self._read() as conn:
            row = conn.execute(
                "SELECT * FROM page_chats WHERE page_id = ? AND profile = ?", (page_id, profile)
            ).fetchone()
        return self._chat(row) if row else None

    def list_chats(self, page_id: str) -> List[Dict[str, Any]]:
        """Every profile's conversation for one Page, most recent first."""
        _require_id(page_id, "Page")
        with self._read() as conn:
            if conn.execute("SELECT 1 FROM pages WHERE id = ?", (page_id,)).fetchone() is None:
                raise _not_found("Page")
            rows = conn.execute(
                "SELECT * FROM page_chats WHERE page_id = ? ORDER BY updated_at DESC", (page_id,)
            ).fetchall()
        return [self._chat(row) for row in rows]

    def bind_chat(self, page_id: str, profile: str, session_id: str) -> Dict[str, Any]:
        _require_id(page_id, "Page")
        if not valid_profile(profile):
            raise _invalid("Profile is not valid.")
        if not valid_session_id(session_id):
            raise _invalid("Session id is not valid.")
        stamp = now_ms()
        with self._write() as conn:
            if conn.execute("SELECT 1 FROM pages WHERE id = ?", (page_id,)).fetchone() is None:
                raise _not_found("Page")
            other = conn.execute(
                "SELECT page_id, profile FROM page_chats WHERE session_id = ?", (session_id,)
            ).fetchone()
            if other is not None and (other["page_id"], other["profile"]) != (page_id, profile):
                raise SpacesError(
                    "session_already_bound", "That conversation already belongs to another Page.", 409
                )
            conn.execute(
                "INSERT INTO page_chats(page_id, profile, session_id, created_at, updated_at) "
                "VALUES (?, ?, ?, ?, ?) ON CONFLICT(page_id, profile) DO UPDATE SET "
                "session_id = excluded.session_id, updated_at = excluded.updated_at",
                (page_id, profile, session_id, stamp, stamp),
            )
        chat = self.get_chat(page_id, profile)
        assert chat is not None
        return chat

    def unbind_chat(self, page_id: str, profile: str) -> None:
        _require_id(page_id, "Page")
        if not valid_profile(profile):
            raise _invalid("Profile is not valid.")
        with self._write() as conn:
            conn.execute(
                "DELETE FROM page_chats WHERE page_id = ? AND profile = ?", (page_id, profile)
            )

    def chat_for_session(self, session_id: Any) -> Optional[Dict[str, Any]]:
        if not valid_session_id(session_id):
            return None
        with self._read() as conn:
            row = conn.execute(
                "SELECT * FROM page_chats WHERE session_id = ?", (session_id,)
            ).fetchone()
        return self._chat(row) if row else None
