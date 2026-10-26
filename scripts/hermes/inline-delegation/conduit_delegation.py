"""Read-only Conduit projection of existing Hermes runs and handoff artifacts.

The wrapper owns its lifecycle receipt beside its existing handoff. No scheduler,
database, notification delivery, or execution path lives here.
"""
from __future__ import annotations

import json
import base64
import os
import re
import shlex
import sqlite3
import threading
from contextlib import closing
import time
from datetime import datetime, timezone
from pathlib import Path


def safe(value, limit=1000):
    text = str(value or "")
    text = re.sub(r"(?is)<(?:think|thinking|analysis)>.*?(?:</(?:think|thinking|analysis)>|$)", "", text)
    text = re.sub(r"(?i)\b(?:sk-[\w-]{12,}|Bearer\s+[\w.=-]{12,}|(?:api[_-]?key|token|password|secret)\s*[:=]\s*\S+)", "[redacted]", text)
    return text[:limit].strip()


def stamp(value=None):
    return datetime.fromtimestamp(value or time.time(), timezone.utc).isoformat()


def messages(home, session_id):
    db = Path(home) / "state.db"
    if not db.is_file():
        return []
    with closing(sqlite3.connect(db.as_uri() + "?mode=ro", uri=True, timeout=2)) as conn:
        conn.row_factory = sqlite3.Row
        if not conn.execute("SELECT 1 FROM sessions WHERE id=?", (session_id,)).fetchone():
            return []
        return [dict(row) for row in conn.execute(
            "SELECT id,message_uid,role,content,tool_calls,tool_call_id,timestamp FROM messages "
            "WHERE session_id=? ORDER BY id DESC LIMIT 1000", (session_id,))][::-1]


KANBAN_WAKE = re.compile(r"\[kanban\] Task (t_[0-9a-f]{6,16}) ")
ENGINE_OUTPUT = '[Cronjob "initiative-engine" output'
KANBAN_TASK_ID = re.compile(r"(?<![\w-])(t_[0-9a-f]{8})(?![\w-])")


def returned_tasks(rows, resolve=None):
    """Kanban work reported back into this chat by Hermes itself, never by the owner's text.

    The native Kanban wake names exactly one task. For the initiative engine's delivered output,
    ``resolve(row)`` returns the tasks that engine run itself created or collected (its own tool
    results), plus any ids the output names. Each anchors on the chat's reply to that message, or the
    message itself while no reply exists, as (anchor_row, [task ids])."""
    found = []
    for index, row in enumerate(rows):
        text = row.get("content")
        if row.get("role") != "user" or not isinstance(text, str):
            continue
        if text.startswith("[kanban] Task "):
            match = KANBAN_WAKE.match(text)
            ids = [match.group(1)] if match else []
        elif text.startswith(ENGINE_OUTPUT):
            ids = list(dict.fromkeys([*(resolve(row) if resolve else []), *KANBAN_TASK_ID.findall(text)]))
        else:
            continue
        if not ids:
            continue
        reply = None
        for later in rows[index + 1:]:
            # Notifications queued back to back share one reply; the owner's own message ends the turn.
            later_text = str(later.get("content") or "")
            if later.get("role") == "user" and not later_text.startswith(("[kanban] Task ", ENGINE_OUTPUT)):
                break
            if later.get("role") == "assistant" and str(later.get("content") or "").strip():
                reply = later
                break
        found.append((reply or row, ids[:8]))
    return found


def origin_for(task_file):
    """Match the unique task-file argument to its recorded, ID-bearing tool call.

    Refuse ambiguity. This is an exact execution argument, never a title, bot name,
    or a guess based on the most recent chat turn.
    """
    encoded = os.environ.get('CONDUIT_DELEGATION_ORIGIN', '')
    if encoded:
        origin = json.loads(base64.urlsafe_b64decode(encoded))
        if isinstance(origin, dict) and origin.get('parent_session_id') and origin.get('source_tool_call_id'):
            return {k: str(v)[:256] for k, v in origin.items()
                    if k in ('parent_session_id', 'parent_profile', 'parent_turn_id', 'source_tool_call_id') and v}
    sid = os.environ.get("HERMES_SESSION_ID", "")
    home = Path(os.environ.get("HERMES_HOME", "/opt/data"))
    matches = []
    for row in messages(home, sid) if sid else []:
        try:
            calls = json.loads(row.get("tool_calls") or "[]")
        except (ValueError, TypeError):
            continue
        for call in calls:
            function = call.get("function") or {}
            args = function.get("arguments") or {}
            try:
                args = json.loads(args) if isinstance(args, str) else args
                command = args.get("command") or args.get("cmd") or ""
                tokens = shlex.split(command)
            except (ValueError, TypeError, AttributeError):
                continue
            if task_file in tokens and any(Path(t).name == "ask-specialist" for t in tokens):
                if call.get("id"):
                    matches.append((row, call["id"]))
    if len(matches) != 1:
        return None
    row, call_id = matches[0]
    profile = home.name if home.parent.name == "profiles" else "default"
    return {"parent_session_id": sid, "parent_profile": profile,
            "parent_message_id": row.get("message_uid") or str(row["id"]),
            "source_tool_call_id": call_id}


class Receipt:
    def __init__(self, origin, profile, goal, base):
        self.data = {**(origin or {}), "delegation_id": "specialist:" + os.urandom(16).hex(),
                     "worker_kind": "specialist", "child_profile": profile, "name": profile,
                     "goal": safe(goal, 400), "started_at": stamp(), "status": "queued"}
        # Keep an indexed lifecycle receipt in the existing handoff directory.
        self.path = Path(base) / (self.data["delegation_id"].replace(":", "-") + ".json")
        self.lock = threading.Lock()

    def update(self, **fields):
        with self.lock:
            self.data.update(fields, updated_at=stamp())
            try:
                self.path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
                tmp = self.path.with_suffix(".tmp")
                fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
                with os.fdopen(fd, "w") as out:
                    json.dump(self.data, out)
                os.replace(tmp, self.path)
            except OSError:
                pass  # Display-only failure must not change specialist execution.


def capture(proc, timeout, receipt, stop_child, max_capture):
    """Consume the CLI's supported stream-json format, retaining only public activity.

    Preserve the wrapper's single JSON stdout contract and final-answer artifact.
    Tool input/output and reasoning are never copied into the receipt.
    """
    output, errors = bytearray(), bytearray()
    result = {}

    def stdout():
        for line in iter(proc.stdout.readline, b""):
            try:
                event = json.loads(line)
            except (ValueError, TypeError):
                continue
            sid = event.get("session_id")
            if isinstance(sid, str) and sid:
                receipt.update(child_session_id=sid)
            if event.get("type") == "tool_use":
                receipt.update(status_summary="Running " + safe(event.get("name"), 64))
            if event.get("type") == "result":
                result.update(event)
            elif event.get("type") == "text" and len(output) < max_capture:
                output.extend(str(event.get("text") or "").encode()[:max_capture-len(output)])

    def stderr():
        for line in iter(proc.stderr.readline, b""):
            if len(errors) < max_capture:
                errors.extend(line[:max_capture-len(errors)])
            match = re.search(rb"session_id:\s*([A-Za-z0-9_.:-]+)", line)
            if match:
                receipt.update(child_session_id=match.group(1).decode())

    threads = [threading.Thread(target=fn, daemon=True) for fn in (stdout, stderr)]
    for thread in threads:
        thread.start()
    timed_out = False
    still_running = False
    try:
        proc.wait(timeout=timeout)
    except __import__('subprocess').TimeoutExpired:
        timed_out = True
        still_running = stop_child(proc)
    for thread in threads:
        thread.join(timeout=3)
    final = result.get("text")
    if isinstance(final, str):
        output = final.encode()[:max_capture]
    return bytes(output), bytes(errors), timed_out, still_running
