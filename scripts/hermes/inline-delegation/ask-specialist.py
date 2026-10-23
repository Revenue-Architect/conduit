#!/opt/hermes/.venv/bin/python3
"""ask-specialist: enforced, synchronous call from Chief to one named Hermes specialist.

Usage:
    ask-specialist <profile> --task-file <path> [--timeout 300] [--max-chars 1500]

What it enforces (the old skill only asked nicely):
  * hard allowlist of profiles (anything else is rejected, exit 2)
  * recursion guard: HERMES_SPECIALIST_DEPTH >= 1 or a specialist HERMES_HOME is refused
  * the child runs as an argument list (no shell) with a hard timeout
  * the full answer is saved to a handoff file; only a capped summary is printed, so
    Chief's context (and its Hindsight auto_retain) never sees raw specialist output
  * the task file is always consumed (deleted)

Prints exactly one JSON object on stdout. Exit codes: 0 ok, 1 error, 2 rejected, 3 timeout.
Test-only overrides (honoured only when ASK_SPECIALIST_TEST=1):
    ASK_SPECIALIST_HERMES_BIN, ASK_SPECIALIST_HANDOFF_DIR
"""
from __future__ import annotations

import argparse
import json
import os
import re
import signal
import stat
import subprocess
import sys
import time
import uuid
from datetime import datetime
from pathlib import Path

ALLOWLIST = ("kai", "hermuse", "scout", "architect", "ops")
DEFAULT_HERMES_BIN = "/opt/hermes/.venv/bin/hermes"
DEFAULT_HANDOFF_DIR = "/opt/data/specialist-handoffs"
DEPTH_ENV = "HERMES_SPECIALIST_DEPTH"
MAX_CAPTURE = 4 * 1024 * 1024  # bytes kept per stream
TRUNC_MARK = " ...[truncated; full text in artifact]"

PROTOCOL = """

---
Handoff protocol (added automatically by ask-specialist):
- Chief invoked you for this one task. Do not call ask-specialist and do not hand work to another named specialist.
- Unless the task above explicitly asks for changes, stay read-only: no edits, restarts, deletes or messages.
- End your reply with a section titled "## Final answer": the conclusion first (at most 1000 characters), then anything you could not verify.
- State which environment you actually checked (Hermes container, other containers, or the Umbrel host). Never conclude that something does not exist from one environment alone.
"""

FINAL_RE = re.compile(
    r"^[ \t]*(?:#{1,4}[ \t]*|\*\*)(final answer|summary|conclusion|handoff|result)\b[^\n]*$",
    re.IGNORECASE | re.MULTILINE,
)


def _test_mode() -> bool:
    return os.environ.get("ASK_SPECIALIST_TEST") == "1"


def resolve_bin() -> str:
    if _test_mode() and os.environ.get("ASK_SPECIALIST_HERMES_BIN"):
        return os.environ["ASK_SPECIALIST_HERMES_BIN"]
    return DEFAULT_HERMES_BIN


def emit(env: dict, code: int) -> "None":
    sys.stdout.write(json.dumps(env, ensure_ascii=False) + "\n")
    sys.stdout.flush()
    raise SystemExit(code)


def consume(path: str | None) -> None:
    """Delete the task file (regular files only; never follow a symlink target)."""
    if not path:
        return
    try:
        st = os.lstat(path)
        if stat.S_ISREG(st.st_mode) or stat.S_ISLNK(st.st_mode):
            os.unlink(path)
    except OSError:
        pass


def active_home_is_specialist() -> str | None:
    home = os.environ.get("HERMES_HOME", "").rstrip("/")
    if not home:
        return None
    p = Path(home)
    if p.parent.name == "profiles" and p.name in ALLOWLIST:
        return p.name
    return None


def pick_summary(text: str, max_chars: int) -> tuple[str, bool]:
    body = text.strip()
    matches = list(FINAL_RE.finditer(body))
    if matches:
        body = body[matches[-1].start():].strip()
    if len(body) <= max_chars:
        return body, False
    cut = max(0, max_chars - len(TRUNC_MARK))
    head = body[:cut]
    sp = head.rfind(" ")
    if sp > cut * 0.6:
        head = head[:sp]
    return head.rstrip() + TRUNC_MARK, True


def handoff_path(profile: str, session_id: str | None) -> Path:
    base = Path(os.environ["ASK_SPECIALIST_HANDOFF_DIR"] if _test_mode() and os.environ.get("ASK_SPECIALIST_HANDOFF_DIR") else DEFAULT_HANDOFF_DIR)
    try:
        from zoneinfo import ZoneInfo

        day = datetime.now(ZoneInfo("America/Toronto")).strftime("%Y-%m-%d")
    except Exception:
        day = datetime.now().strftime("%Y-%m-%d")
    d = base / day
    d.mkdir(parents=True, exist_ok=True)
    try:
        os.chmod(d, 0o700)
    except OSError:
        pass
    ident = re.sub(r"[^A-Za-z0-9_.-]", "", session_id or "") or uuid.uuid4().hex[:12]
    return d / f"{profile}-{ident}.md"


def write_artifact(path: Path, header: dict, out: str, err: str) -> None:
    lines = ["---"] + [f"{k}: {v}" for k, v in header.items()] + ["---", "", "## Specialist output", "", out.rstrip() or "(empty)", ""]
    if err.strip():
        lines += ["## stderr (tail)", "", "```", err.strip()[-2000:], "```", ""]
    tmp = path.with_suffix(".md.tmp")
    fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w", encoding="utf-8") as fh:
        fh.write("\n".join(lines))
    os.replace(tmp, path)


def pid_alive(pid: int) -> bool:
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return False
    except PermissionError:
        return True
    # a zombie still answers kill(0); treat it as gone
    try:
        with open(f"/proc/{pid}/stat") as fh:
            return fh.read().rsplit(")", 1)[1].split()[0] != "Z"
    except OSError:
        return True


def stop_child(proc: subprocess.Popen) -> bool:
    """SIGTERM the child's process group, escalate to SIGKILL. Returns True if it is STILL running."""
    for sig, wait in ((signal.SIGTERM, 8.0), (signal.SIGKILL, 3.0)):
        try:
            os.killpg(proc.pid, sig)
        except (ProcessLookupError, PermissionError):
            pass
        end = time.time() + wait
        while time.time() < end:
            if proc.poll() is not None:
                return False
            time.sleep(0.1)
    return proc.poll() is None


def main(argv: list[str]) -> None:
    started = time.time()
    ap = argparse.ArgumentParser(prog="ask-specialist", add_help=True)
    ap.add_argument("profile")
    ap.add_argument("--task-file", required=True)
    ap.add_argument("--timeout", type=int, default=300)
    ap.add_argument("--max-chars", type=int, default=1500)
    try:
        ns = ap.parse_args(argv)
    except SystemExit as exc:
        # argparse already printed usage to stderr; keep the JSON contract
        if exc.code not in (0, None):
            emit({"status": "rejected", "profile": None, "error": "bad arguments (see usage on stderr)", "duration_s": 0.0}, 2)
        raise

    profile, task_file = ns.profile, ns.task_file

    def env_out(status: str, code: int, **extra) -> None:
        d = {"status": status, "profile": profile, "duration_s": round(time.time() - started, 1)}
        d.update(extra)
        emit(d, code)

    # ---- guards (the task file is consumed even when we refuse) ----
    if profile not in ALLOWLIST:
        consume(task_file)
        env_out("rejected", 2, error=f"profile not in allowlist {list(ALLOWLIST)}")
    try:
        depth = int(os.environ.get(DEPTH_ENV, "0") or "0")
    except ValueError:
        depth = 1
    if depth >= 1:
        consume(task_file)
        env_out("rejected", 2, error=f"recursion guard: {DEPTH_ENV}={depth}; a specialist may not call another specialist")
    spec_home = active_home_is_specialist()
    if spec_home:
        consume(task_file)
        env_out("rejected", 2, error=f"recursion guard: running inside specialist profile '{spec_home}'")
    if not (1 <= ns.timeout <= 3600) or not (200 <= ns.max_chars <= 20000):
        consume(task_file)
        env_out("rejected", 2, error="--timeout must be 1..3600 and --max-chars 200..20000")

    try:
        st = os.lstat(task_file)
    except OSError as exc:
        env_out("error", 1, error=f"task file unreadable: {exc.strerror}")
    if not stat.S_ISREG(st.st_mode):
        consume(task_file)
        env_out("rejected", 2, error="task file must be a regular file (not a symlink or directory)")
    try:
        task_text = Path(task_file).read_text(encoding="utf-8")
    except (OSError, UnicodeDecodeError) as exc:
        consume(task_file)
        env_out("error", 1, error=f"task file unreadable: {exc}")
    if not task_text.strip():
        consume(task_file)
        env_out("error", 1, error="task file is empty")

    hermes_bin = resolve_bin()
    # Display-only lifecycle; the existing CLI execution, guard and result contract remain.
    from conduit_delegation import Receipt, capture, origin_for, safe
    try:
        origin = origin_for(task_file)
    except Exception:
        origin = None
    receipt = Receipt(origin, profile, task_text,
        os.environ.get("ASK_SPECIALIST_HANDOFF_DIR", DEFAULT_HANDOFF_DIR) if _test_mode() else DEFAULT_HANDOFF_DIR)

    # The child reads a private copy with the handoff protocol appended; the original is consumed now.
    child_file = f"{task_file}.child-{uuid.uuid4().hex[:8]}"
    fd = os.open(child_file, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(fd, "w", encoding="utf-8") as fh:
        fh.write(task_text.rstrip() + PROTOCOL)
    consume(task_file)

    child_env = dict(os.environ)
    # A specialist is a fresh finite CLI session, not the parent gateway/cron/kanban surface.
    # Hermes v0.22.x rejects inherited non-CLI source labels during session.create.
    child_env["HERMES_SESSION_SOURCE"] = "oneshot"
    child_env["HERMES_SESSION_SOURCE_EXPLICIT"] = "1"
    child_env[DEPTH_ENV] = "1"
    cmd = [hermes_bin, "-p", profile, "chat", "--query-file", child_file, "--oneshot", "-Q", "--format", "stream-json"]
    proc = None
    out = err = ""
    timed_out = False
    still_running = False
    try:
        try:
            proc = subprocess.Popen(
                cmd, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                env=child_env, cwd="/opt/data" if os.path.isdir("/opt/data") else None,
                start_new_session=True,
            )
        except OSError as exc:
            receipt.update(status="failed", summary="Could not start specialist")
            env_out("error", 1, error=f"could not start specialist: {exc.strerror}")
        receipt.update(status="running", worker_pid=proc.pid)
        o, e, timed_out, still_running = capture(
            proc, ns.timeout, receipt, stop_child, MAX_CAPTURE)
        out = (o or b"")[:MAX_CAPTURE].decode("utf-8", "replace")
        err = (e or b"")[:MAX_CAPTURE].decode("utf-8", "replace")
    finally:
        consume(child_file)

    m = re.search(r"session_id:\s*(\S+)", err) or re.search(r"^Session:\s+(\S+)", out, re.MULTILINE)
    session_id = m.group(1) if m else None
    rc = proc.returncode if proc is not None else None
    duration = round(time.time() - started, 1)

    if timed_out:
        status, code = "timeout", 3
    elif rc != 0:
        status, code = "error", 1
    elif not out.strip():
        status, code = "error", 1
    else:
        status, code = "ok", 0

    artifact = None
    try:
        path = handoff_path(profile, session_id)
        write_artifact(
            path,
            {"profile": profile, "session_id": session_id or "unknown", "status": status, "exit_code": rc,
             "duration_s": duration, "date": datetime.now().astimezone().isoformat(timespec="seconds")},
            out, err,
        )
        artifact = str(path)
    except OSError as exc:
        err += f"\n[ask-specialist] could not save artifact: {exc}"

    receipt.update(status={"ok": "completed", "error": "failed", "timeout": "timeout"}[status],
        child_session_id=session_id or receipt.data.get("child_session_id"),
        duration_seconds=duration, artifacts=[artifact] if artifact else [],
        summary=safe(pick_summary(out, ns.max_chars)[0] if status == "ok" else
            ("Specialist timed out" if timed_out else f"Specialist exited rc={rc}")))
    extra = {"session_id": session_id or receipt.data.get("child_session_id"), "artifact": artifact, "exit_code": rc}
    if status == "ok":
        summary, truncated = pick_summary(out, ns.max_chars)
        extra.update(summary=summary, truncated=truncated, chars_total=len(out))
    elif status == "timeout":
        extra.update(
            error=f"specialist did not finish within {ns.timeout}s; not retried",
            child_pid=proc.pid if proc else None, child_still_running=still_running,
            partial_summary=pick_summary(out, min(ns.max_chars, 600))[0] if out.strip() else "",
        )
    else:
        tail = (err.strip() or out.strip())[-500:]
        extra.update(error=f"specialist exited rc={rc}" if rc not in (0, None) else "specialist returned empty output", detail=tail)
    env_out(status, code, **extra)


if __name__ == "__main__":
    main(sys.argv[1:])
