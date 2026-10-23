"""Authenticated, profile-scoped projection mounted by Hermes' plugin router.

No private filesystem endpoint is exposed: every read first proves the parent
session exists in the selected profile and resolves an explicit run relationship.
"""
import importlib.util
import json
import os
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
                row = {**row, 'status': 'unknown', 'status_summary': 'Worker status unavailable'}
            found.append(row)
        except (OSError, ValueError, TypeError):
            continue
    return found


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
        for child in children:
            # Only authoritative result records with an explicit status.
            if not child.get('status'):
                continue
            found.append({
                'delegation_id': child['subagent_id'], 'subagent_id': child['subagent_id'],
                'worker_kind': 'native', 'parent_session_id': session_id,
                'parent_profile': profile, 'child_profile': profile,
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
                run = kb.latest_run(conn, task['id'])
                state = task['status']
                status = {'triage': 'queued', 'scheduled': 'queued', 'review': 'waiting',
                          'todo': 'queued', 'ready': 'queued', 'running': 'running', 'in_progress': 'running',
                          'done': 'completed', 'blocked': 'waiting', 'cancelled': 'interrupted', 'archived': 'unknown'}.get(state, 'unknown')
                meta = (run.metadata or {}) if run else {}
                found.append({
                    'delegation_id': 'kanban:'+task['id']+':'+str(run.id if run else 'queued'),
                    'worker_kind': 'kanban', 'task_id': task['id'], 'run_id': str(run.id) if run else None,
                    'board_slug': kb.get_current_board(),
                    'parent_session_id': session_id, 'parent_profile': profile,
                    'parent_message_id': row.get('message_uid') or str(row['id']), 'source_tool_call_id': call_id,
                    'child_profile': run.profile if run else task.get('assignee'),
                    'child_session_id': meta.get('session_id'), 'name': task.get('assignee'),
                    'goal': projection.safe(task.get('title'), 400), 'status': status,
                    'started_at': projection.stamp(run.started_at) if run else None,
                    'updated_at': projection.stamp((run.ended_at or run.started_at) if run else task.get('created_at')),
                    'summary': projection.safe(run.summary if run else task.get('result')),
                    'status_summary': projection.safe(run.error if run else task.get('last_failure_error'), 220),
                })
    except (ImportError, OSError, __import__('sqlite3').Error):
        pass
    return {'workers': found[:64], 'projection_version': 2}


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
