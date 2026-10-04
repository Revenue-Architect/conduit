"""Spaces REST API, mounted by the Hermes dashboard at ``/api/plugins/spaces/``.

Behind the dashboard's existing authentication; no token of its own. The
dashboard imports this file on its own (not as part of the plugin package),
so the shared store is loaded from the plugin directory by path.

Errors are ``{"error": <code>, "message": ..., ...}`` with a stable code;
a stale write is always ``409 {"error": "revision_conflict", "current_revision": n}``.
"""


import importlib.util
import sys
from pathlib import Path
from typing import Any, Callable, Dict, Optional

from fastapi import APIRouter, Query, Request
from fastapi.responses import JSONResponse
from pydantic import BaseModel, ConfigDict, Field

_STORE_MODULE = "hermes_spaces_store"


def _load_store_module():
    module = sys.modules.get(_STORE_MODULE)
    if module is not None:
        return module
    path = Path(__file__).resolve().parents[1] / "spaces_store.py"
    spec = importlib.util.spec_from_file_location(_STORE_MODULE, path)
    if spec is None or spec.loader is None:
        raise ImportError(f"cannot load {path}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[_STORE_MODULE] = module
    spec.loader.exec_module(module)
    return module


_store_mod = _load_store_module()
SpacesError = _store_mod.SpacesError
UNSET = _store_mod.UNSET
store = _store_mod.SpacesStore()

router = APIRouter()

# Request bodies are bounded before they reach the store: Pydantic rejects
# oversized fields, and the store re-validates everything regardless.
_CONTENT_LIMIT = _store_mod.CONTENT_MAX + 1000


class _Body(BaseModel):
    model_config = ConfigDict(extra="forbid")


class SpaceCreate(_Body):
    name: str = Field(max_length=200)
    icon: Optional[str] = Field(default=None, max_length=64)


class SpaceUpdate(_Body):
    name: Optional[str] = Field(default=None, max_length=200)
    icon: Optional[str] = Field(default=None, max_length=64)


class PageCreate(_Body):
    title: str = Field(max_length=400)
    content: str = Field(default="", max_length=_CONTENT_LIMIT)
    parent_id: Optional[str] = Field(default=None, max_length=64)
    source_session_id: Optional[str] = Field(default=None, max_length=200)


class PageUpdate(_Body):
    expected_revision: int
    title: Optional[str] = Field(default=None, max_length=400)
    content: Optional[str] = Field(default=None, max_length=_CONTENT_LIMIT)
    parent_id: Optional[str] = Field(default=None, max_length=64)


class ChatBind(_Body):
    profile: str = Field(max_length=64)
    session_id: str = Field(max_length=200)


def _respond(action: Callable[[], Any], status: int = 200) -> JSONResponse:
    try:
        return JSONResponse(action(), status_code=status)
    except SpacesError as error:
        return JSONResponse(error.as_dict(), status_code=error.status)


@router.get("/health")
def health() -> JSONResponse:
    return _respond(store.health)


# -- spaces -------------------------------------------------------------------


@router.get("/spaces")
def list_spaces() -> JSONResponse:
    return _respond(lambda: {"spaces": store.list_spaces()})


@router.post("/spaces")
def create_space(body: SpaceCreate) -> JSONResponse:
    return _respond(lambda: {"space": store.create_space(body.name, body.icon)}, status=201)


@router.get("/spaces/{space_id}")
def get_space(space_id: str) -> JSONResponse:
    return _respond(lambda: {"space": store.get_space(space_id)})


@router.patch("/spaces/{space_id}")
def update_space(space_id: str, body: SpaceUpdate) -> JSONResponse:
    fields = body.model_fields_set
    return _respond(
        lambda: {
            "space": store.update_space(
                space_id,
                name=body.name if "name" in fields else UNSET,
                icon=body.icon if "icon" in fields else UNSET,
            )
        }
    )


@router.delete("/spaces/{space_id}")
def delete_space(space_id: str, cascade: bool = Query(False)) -> JSONResponse:
    def run() -> Dict[str, Any]:
        store.delete_space(space_id, cascade=cascade)
        return {"ok": True}

    return _respond(run)


# -- pages --------------------------------------------------------------------


@router.get("/spaces/{space_id}/pages")
def list_pages(
    space_id: str,
    q: Optional[str] = Query(None, max_length=200),
    parent_id: Optional[str] = Query(None, max_length=64),
    sort: str = Query("updated", pattern="^(updated|name)$"),
) -> JSONResponse:
    # ``parent_id=root`` lists top-level Pages; omitted lists every Page.
    parent: Any = UNSET
    if parent_id == "root":
        parent = None
    elif parent_id:
        parent = parent_id
    return _respond(
        lambda: {"pages": store.list_pages(space_id, query=q, parent_id=parent, sort=sort)}
    )


@router.post("/spaces/{space_id}/pages")
def create_page(space_id: str, body: PageCreate) -> JSONResponse:
    return _respond(
        lambda: {
            "page": store.create_page(
                space_id,
                title=body.title,
                content=body.content,
                parent_id=body.parent_id or None,
                source_session_id=body.source_session_id,
            )
        },
        status=201,
    )


@router.get("/pages/{page_id}")
def get_page(page_id: str) -> JSONResponse:
    return _respond(lambda: {"page": store.get_page(page_id)})


@router.patch("/pages/{page_id}")
def update_page(page_id: str, body: PageUpdate) -> JSONResponse:
    fields = body.model_fields_set
    return _respond(
        lambda: {
            "page": store.update_page(
                page_id,
                expected_revision=body.expected_revision,
                title=body.title if "title" in fields and body.title is not None else UNSET,
                content=body.content if "content" in fields and body.content is not None else UNSET,
                parent_id=(body.parent_id or None) if "parent_id" in fields else UNSET,
            )
        }
    )


@router.delete("/pages/{page_id}")
def delete_page(page_id: str) -> JSONResponse:
    def run() -> Dict[str, Any]:
        store.delete_page(page_id)
        return {"ok": True}

    return _respond(run)


# -- page chats ---------------------------------------------------------------


@router.get("/pages/{page_id}/chats")
def list_chats(page_id: str) -> JSONResponse:
    return _respond(lambda: {"chats": store.list_chats(page_id)})


@router.get("/pages/{page_id}/chat")
def get_chat(page_id: str, profile: str = Query(..., max_length=64)) -> JSONResponse:
    return _respond(lambda: {"chat": store.get_chat(page_id, profile)})


@router.put("/pages/{page_id}/chat")
def bind_chat(page_id: str, body: ChatBind) -> JSONResponse:
    return _respond(lambda: {"chat": store.bind_chat(page_id, body.profile, body.session_id)})


@router.delete("/pages/{page_id}/chat")
def unbind_chat(page_id: str, profile: str = Query(..., max_length=64)) -> JSONResponse:
    def run() -> Dict[str, Any]:
        store.unbind_chat(page_id, profile)
        return {"ok": True}

    return _respond(run)


@router.get("/sessions/{session_id}/page")
def page_for_session(session_id: str) -> JSONResponse:
    """Which Page a conversation belongs to, if any (for a chat header)."""

    def run() -> Dict[str, Any]:
        chat = store.chat_for_session(session_id)
        if chat is None:
            return {"chat": None, "page": None}
        page = store.get_page(chat["page_id"])
        page.pop("content", None)
        return {"chat": chat, "page": page}

    return _respond(run)
