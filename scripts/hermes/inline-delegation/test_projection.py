import base64
import importlib.util
import json
import os
import sqlite3
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

import conduit_delegation as projection


class ProjectionTests(unittest.TestCase):
    def test_public_text_removes_reasoning_and_credentials(self):
        self.assertEqual(projection.safe('A<think>private</think>B token=abcdef123456'), 'AB [redacted]')

    def test_origin_uses_hook_ids_without_history_guessing(self):
        origin = {'parent_session_id': 'real-parent', 'source_tool_call_id': 'actual-call', 'parent_profile': 'architect'}
        encoded = base64.urlsafe_b64encode(json.dumps(origin).encode()).decode()
        with patch.dict(os.environ, {'CONDUIT_DELEGATION_ORIGIN': encoded}):
            self.assertEqual(projection.origin_for('/tmp/task'), origin)

    def test_fallback_refuses_ambiguous_task_arguments(self):
        with tempfile.TemporaryDirectory() as root:
            db = sqlite3.connect(Path(root)/'state.db')
            db.executescript('CREATE TABLE sessions(id TEXT); CREATE TABLE messages(id INT,message_uid TEXT,role TEXT,content TEXT,tool_calls TEXT,tool_call_id TEXT,timestamp REAL,session_id TEXT); INSERT INTO sessions VALUES("parent");')
            for i in range(2):
                calls = json.dumps([{'id': f'call-{i}', 'function': {'name': 'terminal', 'arguments': json.dumps({'command': '/opt/data/bin/ask-specialist kai --task-file /tmp/unique'})}}])
                db.execute('INSERT INTO messages VALUES(?,?,?,?,?,?,?,?)', (i, str(i), 'assistant', '', calls, None, 1, 'parent'))
            db.commit()
            with patch.dict(os.environ, {'CONDUIT_DELEGATION_ORIGIN': '', 'HERMES_SESSION_ID': 'parent', 'HERMES_HOME': root}):
                self.assertIsNone(projection.origin_for('/tmp/unique'))
            db.close()

    def test_stream_capture_uses_reported_child_id_and_final_result_only(self):
        with tempfile.TemporaryDirectory() as root:
            receipt = projection.Receipt({'parent_session_id': 'p'}, 'kai', 'Read only', root)
            code = '''import json,sys
for x in [{'type':'tool_use','name':'read_file','input':{'secret':'hidden'}},
 {'type':'text','text':'partial'}, {'type':'result','session_id':'reported-child','text':'actual answer'}]:
 print(json.dumps(x),flush=True)
sys.stderr.write('diagnostic only')
'''
            proc = subprocess.Popen([sys.executable, '-c', code], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            out, err, timeout, alive = projection.capture(proc, 5, receipt, lambda p: False, 1024)
            self.assertEqual(out, b'actual answer')
            self.assertFalse(timeout or alive)
            data = json.loads(receipt.path.read_text())
            self.assertEqual(data['child_session_id'], 'reported-child')
            self.assertEqual(data['status_summary'], 'Running read_file')
            self.assertNotIn('hidden', receipt.path.read_text())
            proc.stdout.close(); proc.stderr.close()

    def test_existing_source_guard_is_intact(self):
        source = (Path(__file__).parent/'ask-specialist.py').read_text()
        for line in ['child_env["HERMES_SESSION_SOURCE"] = "oneshot"',
                     'child_env["HERMES_SESSION_SOURCE_EXPLICIT"] = "1"',
                     'child_env[DEPTH_ENV] = "1"']:
            self.assertIn(line, source)


if __name__ == '__main__':
    unittest.main()
