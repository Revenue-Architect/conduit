"""Hermes Spaces: persistent working Pages the user and Hermes edit together.

Registers five ``spaces_*`` tools and a ``pre_llm_call`` hook that tells a
Page-bound conversation which Page it belongs to. The REST API Conduit uses
lives in ``dashboard/plugin_api.py`` and shares ``spaces_store.py``.
"""

from __future__ import annotations


def register(ctx) -> None:
    from .context_hook import make_hook
    from .spaces_store import SpacesStore
    from .tools import DESCRIPTIONS, SCHEMAS, TOOLSET, make_handlers

    store = SpacesStore()
    store.ensure_ready()
    handlers = make_handlers(store)
    for name, schema in SCHEMAS.items():
        ctx.register_tool(
            name=name,
            toolset=TOOLSET,
            schema=schema,
            handler=handlers[name],
            description=DESCRIPTIONS[name],
        )
    ctx.register_hook("pre_llm_call", make_hook(store))
