"""Authenticated, profile-scoped projection mounted by Hermes' plugin router.

No private filesystem endpoint is exposed: every read first proves the parent
session exists in the selected profile and resolves an explicit run relationship.
"""
import importlib.util
import json
import os
import re
import sqlite3
from datetime import datetime
from contextlib import closing
from pathlib import Path

from fastapi import APIRouter, HTTPException
from hermes_constants import get_hermes_home

spec = importlib.util.spec_from_file_location('conduit_delegation_projection', '/opt/data/bin/conduit_delegation.py')
projection = importlib.util.module_from_spec(spec)
spec.loader.exec_module(projection)
router = APIRouter()


def scope(session_id):
    if not session_id or len(session_id) > 256:
        raise HTTPException(400, 'Invalid session')
    home = Path(get_hermes_home()).resolve()
    rows = projection.messages(home, session_id)
    # An empty but real session is valid; inspect its existence separately.
    import sqlite3
    try:
        with closing(sqlite3.connect((home/'state.db').as_uri()+'?mode=ro', uri=True)) as conn:
            exists = conn.execute('SELECT 1 FROM sessions WHERE id=?', (session_id,)).fetchone()
    except sqlite3.Error:
        exists = False
    if not exists:
        raise HTTPException(404, 'Parent session unavailable')
    profile = home.name if home.parent.name == 'profiles' else 'default'
    return home, profile, rows


def receipts(session_id, profile):
    base = Path('/opt/data/specialist-handoffs')
    if not base.exists():
        return []
    found = []
    for path in sorted(base.glob('specialist-*.json'), key=lambda p: p.stat().st_mtime, reverse=True)[:512]:
        try:
            if path.stat().st_size > 32768:
                continue
            row = json.loads(path.read_text())
            if row.get('parent_session_id') != session_id or row.get('parent_profile') != profile:
                continue
            if row.get('status') == 'running' and not Path('/proc/'+str(int(row.get('worker_pid', 0)))).exists():
                # The wrapper died before finalizing, e.g. the parent turn was stopped.
                row = {**row, 'status': 'interrupted', 'status_summary': 'Stopped before it finished'}
            if not row.get('child_session_id'):
                child = child_session_for(row)
                if child:
                    row = {**row, 'child_session_id': child}
            found.append(row)
        except (OSError, ValueError, TypeError):
            continue
    return found


PROFILE_NAME = re.compile(r'[a-z0-9][a-z0-9_-]{0,63}')


def child_session_for(row):
    """The wrapper learns the child's session id only when the CLI exits. Until then, or when it was
    stopped, find the specialist's own session that started with this task."""
    profile, goal, started = row.get('child_profile'), (row.get('goal') or '').strip(), row.get('started_at')
    if not isinstance(profile, str) or profile == 'default' or not PROFILE_NAME.fullmatch(profile) or not goal or not started:
        return None
    try:
        t0 = datetime.fromisoformat(started).timestamp()
        db = Path('/opt/data/profiles') / profile / 'state.db'
        with closing(sqlite3.connect(db.as_uri()+'?mode=ro', uri=True, timeout=2)) as conn:
            for (sid,) in conn.execute('SELECT id FROM sessions WHERE started_at BETWEEN ? AND ? '
                                       'ORDER BY started_at LIMIT 8', (t0 - 5, t0 + 120)):
                first = conn.execute("SELECT content FROM messages WHERE session_id=? AND role='user' "
                                     'ORDER BY id LIMIT 1', (sid,)).fetchone()
                if first and isinstance(first[0], str) and first[0].strip().startswith(goal[:60]):
                    return sid
    except (ValueError, sqlite3.Error):
        return None
    return None


def routed_profile(args, child, parent_profile):
    """A profile-routed delegate_task child lives in that profile's store, not the parent's."""
    tasks = args.get('tasks') if isinstance(args.get('tasks'), list) else []
    index = child.get('task_index')
    chosen = child.get('profile')
    if not chosen and isinstance(index, int) and 0 <= index < len(tasks) and isinstance(tasks[index], dict):
        chosen = tasks[index].get('profile')
    if not chosen and not tasks:
        chosen = args.get('profile')
    return chosen if isinstance(chosen, str) and PROFILE_NAME.fullmatch(chosen) else parent_profile


def child_in_parent_store(home, session_id, goal, taken):
    """The native child's own session: linked to this parent and started with this goal."""
    goal = (goal or '').strip()
    if not goal:
        return None
    try:
        with closing(sqlite3.connect((home/'state.db').as_uri()+'?mode=ro', uri=True, timeout=2)) as conn:
            for (sid,) in conn.execute('SELECT id FROM sessions WHERE parent_session_id=? ORDER BY started_at LIMIT 64',
                                       (session_id,)):
                if sid in taken:
                    continue
                first = conn.execute("SELECT content FROM messages WHERE session_id=? AND role='user' "
                                     'ORDER BY id LIMIT 1', (sid,)).fetchone()
                if first and isinstance(first[0], str) and first[0].strip().startswith(goal[:60]):
                    return sid
    except sqlite3.Error:
        return None
    return None


def object_from(content):
    try:
        result = json.loads(content or '{}')
        return result if isinstance(result, dict) else {}
    except (TypeError, ValueError):
        return {}


def call_origins(rows):
    calls = {}
    results = {}
    for row in rows:
        if row['role'] == 'tool' and row.get('tool_call_id'):
            results[row['tool_call_id']] = object_from(row.get('content'))
        try:
            tool_calls = json.loads(row.get('tool_calls') or '[]')
        except (TypeError, ValueError):
            tool_calls = []
        if not isinstance(tool_calls, list):
            continue
        for call in tool_calls:
            if not isinstance(call, dict) or not call.get('id'):
                continue
            function = call.get('function') or {}
            calls[call['id']] = (row, function.get('name') or '', object_from(function.get('arguments')))
    return calls, results


def nested_workers(value):
    if isinstance(value, dict):
        if value.get('subagent_id'):
            yield value
        else:
            for item in value.values():
                yield from nested_workers(item)
    elif isinstance(value, list):
        for item in value[:64]:
            yield from nested_workers(item)


@router.get('/workers')
def workers(session_id: str):
    home, profile, rows = scope(session_id)
    found = receipts(session_id, profile)
    calls, results = call_origins(rows)
    for call_id, (row, name, args) in calls.items():
        if name != 'delegate_task':
            continue
        result = results.get(call_id) or {}
        children = list(nested_workers(result))
        unit_id = result.get('delegation_id')
        ids = result.get('subagent_ids')
        if unit_id and isinstance(ids, list):
            import sqlite3
            with closing(sqlite3.connect((home/'state.db').as_uri()+'?mode=ro', uri=True)) as conn:
                conn.row_factory=sqlite3.Row
                saved = conn.execute('SELECT * FROM async_delegations WHERE delegation_id=? '
                    'AND (parent_session_id=? OR origin_session_id=?)', (unit_id,session_id,session_id)).fetchone()
            if saved:
                saved=dict(saved)
                actual=object_from(saved.get('result_json'))
                completed=actual.get('results') or []
                goals=result.get('goals') or []
                for index, subagent_id in enumerate(ids[:64]):
                    child=next((r for r in completed if isinstance(r,dict) and r.get('task_index')==index),{})
                    children.append({
                        'subagent_id':subagent_id, 'task_index':index,
                        'status':child.get('status') or saved['state'],
                        'goal':goals[index] if index<len(goals) else '',
                        'summary':projection.safe(child.get('summary')),
                        'duration_seconds':child.get('duration_seconds'),
                        'started_at':projection.stamp(saved['dispatched_at']),
                        'updated_at':projection.stamp(saved['updated_at']),
                    })
        taken = set()
        for child in children:
            # Only authoritative result records with an explicit status.
            if not child.get('status'):
                continue
            routed = routed_profile(args, child, profile)
            child_session = child.get('child_session_id') or child_in_parent_store(home, session_id, child.get('goal'), taken)
            if child_session:
                taken.add(child_session)
            found.append({
                'delegation_id': child['subagent_id'], 'subagent_id': child['subagent_id'],
                'worker_kind': 'native', 'parent_session_id': session_id,
                # Transcript reads go to the store that holds the child session (the parent's);
                # the name shows which profile it ran as.
                'parent_profile': profile, 'child_profile': profile, 'name': routed,
                **({'child_session_id': child_session} if child_session else {}),
                'parent_message_id': row.get('message_uid') or str(row['id']),
                'source_tool_call_id': call_id,
                **{k: child[k] for k in ['child_session_id', 'goal', 'status', 'summary', 'duration_seconds', 'task_index', 'started_at', 'updated_at'] if k in child},
            })
    # Kanban remains the status authority. A task needs BOTH its stored parent
    # session and an exact task id from that session's creation tool result.
    try:
        from hermes_cli import kanban_db as kb
        from hermes_cli import kanban_db_connect as kbc
        with closing(kbc.connect()) as conn:
            tasks = conn.execute('SELECT * FROM tasks WHERE session_id=? ORDER BY created_at DESC LIMIT 64', (session_id,)).fetchall()
            for raw in tasks:
                task = dict(raw)
                origin = None
                for call_id, (row, name, args) in calls.items():
                    if 'kanban' not in name or 'create' not in name:
                        continue
                    result = results.get(call_id) or {}
                    created = result.get('task') if isinstance(result.get('task'), dict) else result
                    if created.get('id') == task['id'] or created.get('task_id') == task['id']:
                        origin = row, call_id
                        break
                if origin is None:
                    continue
                row, call_id = origin
                found.append(kanban_worker(kb, conn, task, session_id, profile, row, call_id))
            # Work Hermes itself reported back into this chat (the Kanban wake, or the initiative engine's
            # delivered output) names its exact task id; it anchors on the chat's reply to that report.
            for row, ids in projection.returned_tasks(rows, engine_run_resolver(home, session_id)):
                for task_id in ids:
                    raw = conn.execute('SELECT * FROM tasks WHERE id=?', (task_id,)).fetchone()
                    # Only Hermes's own objective work; an id merely mentioned in a tool listing is not delegation.
                    if raw and (dict(raw).get('idempotency_key') or '').startswith('initiative:'):
                        found.append(kanban_worker(kb, conn, dict(raw), session_id, profile, row, None,
                                                   anchor='@'+(row.get('message_uid') or str(row['id']))))
    except (ImportError, OSError, __import__('sqlite3').Error):
        pass
    return {'workers': found[:64], 'projection_version': 2}


TASK_ID = re.compile(r'(?<![\w-])(t_[0-9a-f]{8})(?![\w-])')


def engine_run_resolver(home, session_id):
    """Map a delivered initiative-engine message to the Kanban tasks its own cron run touched.

    Exact chain, no text matching: the chat's admission for that message carries identity
    ``bot:<delivery id>``; cron derives that id from (home, job, execution id), so recomputing it per
    engine execution names the run; the run's cron session (that execution's time window) holds the
    tool results that created or collected each task."""
    import hashlib
    try:
        jobs = json.loads((home/'cron'/'jobs.json').read_text())
        jobs = jobs.get('jobs', jobs) if isinstance(jobs, dict) else jobs
        job = next(j['id'] for j in jobs if j.get('name') == 'initiative-engine')
        with closing(sqlite3.connect((home/'cron'/'executions.db').as_uri()+'?mode=ro', uri=True, timeout=2)) as conn:
            runs = conn.execute('SELECT id,started_at,finished_at FROM executions WHERE job_id=? AND started_at IS NOT NULL '
                                'ORDER BY started_at DESC LIMIT 500', (job,)).fetchall()
        base = str(home.resolve())
        by_key = {hashlib.sha256(json.dumps([base, job, str(eid), base], ensure_ascii=False, separators=(',', ':'))
                                 .encode()).hexdigest(): (start, end) for eid, start, end in runs}
        with closing(sqlite3.connect((home/'state.db').as_uri()+'?mode=ro', uri=True, timeout=2)) as conn:
            admitted = {}
            for (payload,) in conn.execute('SELECT payload_json FROM session_admissions WHERE target_session_id=? '
                                           'ORDER BY seq DESC LIMIT 400', (session_id,)):
                p = object_from(payload)
                identity = (p.get('local_automation_v1') or {}).get('identity') or ''
                if identity.startswith('bot:') and isinstance(p.get('text'), str):
                    admitted[p['text']] = identity[4:]
    except (OSError, ValueError, StopIteration, KeyError, TypeError, sqlite3.Error):
        return None
    state_db = (home/'state.db').as_uri()+'?mode=ro'

    def resolve(row):
        window = by_key.get(admitted.get(row.get('content'), ''))
        if not window:
            return []
        try:
            start = datetime.fromisoformat(window[0]).timestamp()
            end = datetime.fromisoformat(window[1]).timestamp() if window[1] else start + 1800
            with closing(sqlite3.connect(state_db, uri=True, timeout=2)) as conn:
                run = conn.execute("SELECT id FROM sessions WHERE source='cron' AND title LIKE 'initiative-engine%' "
                                   "AND started_at BETWEEN ? AND ? ORDER BY started_at LIMIT 1", (start - 5, end)).fetchone()
                if not run:
                    return []
                ids = []
                for (content,) in conn.execute("SELECT content FROM messages WHERE session_id=? AND role='tool'", (run[0],)):
                    ids.extend(TASK_ID.findall(content or ''))
            return list(dict.fromkeys(ids))
        except (ValueError, TypeError, sqlite3.Error):
            return []
    return resolve


def kanban_child_session(profile, task_id, started):
    """The worker's own Kanban session when the run did not report it: in the worker profile's store,
    a kanban-source session that started with this run and whose messages name this exact task."""
    if not isinstance(profile, str) or not PROFILE_NAME.fullmatch(profile) or not started:
        return None
    db = Path('/opt/data/state.db') if profile == 'default' else Path('/opt/data/profiles') / profile / 'state.db'
    try:
        with closing(sqlite3.connect(db.as_uri()+'?mode=ro', uri=True, timeout=2)) as wconn:
            for (sid,) in wconn.execute("SELECT id FROM sessions WHERE source='kanban' AND started_at BETWEEN ? AND ? "
                                        'ORDER BY started_at LIMIT 8', (started - 5, started + 120)):
                if wconn.execute("SELECT 1 FROM messages WHERE session_id=? AND role='user' AND instr(content, ?) > 0 LIMIT 1",
                                 (sid, task_id)).fetchone():
                    return sid
    except sqlite3.Error:
        return None
    return None


def kanban_worker(kb, conn, task, session_id, profile, row, call_id, anchor=''):
    run = kb.latest_run(conn, task['id'])
    status = {'triage': 'queued', 'scheduled': 'queued', 'review': 'waiting',
              'todo': 'queued', 'ready': 'queued', 'running': 'running', 'in_progress': 'running',
              'done': 'completed', 'blocked': 'waiting', 'cancelled': 'interrupted', 'archived': 'unknown'}.get(task['status'], 'unknown')
    meta = (run.metadata or {}) if run else {}
    return {
        'delegation_id': 'kanban:'+task['id']+':'+str(run.id if run else 'queued')+anchor,
        'worker_kind': 'kanban', 'task_id': task['id'], 'run_id': str(run.id) if run else None,
        'board_slug': kb.get_current_board(),
        'parent_session_id': session_id, 'parent_profile': profile,
        'parent_message_id': row.get('message_uid') or str(row['id']),
        **({'source_tool_call_id': call_id} if call_id else {}),
        'child_profile': run.profile if run else task.get('assignee'),
        'child_session_id': meta.get('session_id') or (kanban_child_session(run.profile, task['id'], run.started_at) if run else None),
        'name': task.get('assignee'),
        'goal': projection.safe(task.get('title'), 400), 'status': status,
        'started_at': projection.stamp(run.started_at) if run else None,
        'updated_at': projection.stamp((run.ended_at or run.started_at) if run else task.get('created_at')),
        'summary': projection.safe(run.summary if run else task.get('result')),
        'status_summary': projection.safe(run.error if run else task.get('last_failure_error'), 220),
    }


@router.get('/artifact/{delegation_id}/{index}')
def artifact(delegation_id: str, index: int, session_id: str):
    _, profile, _ = scope(session_id)
    row = next((r for r in receipts(session_id, profile) if r.get('delegation_id') == delegation_id), None)
    artifacts = row.get('artifacts') or [] if row else []
    if index < 0 or index >= len(artifacts):
        raise HTTPException(404, 'Artifact unavailable')
    path = Path(artifacts[index]).resolve()
    if not path.is_relative_to(Path('/opt/data/specialist-handoffs').resolve()) or not path.is_file():
        raise HTTPException(404, 'Artifact unavailable')
    text = path.read_text()[:65536].split('## stderr (tail)')[0]
    return {'name': path.name, 'text': projection.safe(text, 65536)}
