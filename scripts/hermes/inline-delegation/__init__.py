"""Carry Hermes' hook-provided origin into the existing specialist subprocess.

No tool is added and no execution or policy decision is made by this hook.
"""
import base64
import json
import shlex
from pathlib import Path


def _origin(tool_name='', args=None, session_id='', tool_call_id='', turn_id='', **_):
    if tool_name != 'terminal' or not session_id or not tool_call_id or not isinstance(args, dict):
        return None
    key = 'command' if isinstance(args.get('command'), str) else 'cmd'
    command = args.get(key)
    if not isinstance(command, str) or 'ask-specialist' not in command:
        return None
    from hermes_constants import get_hermes_home
    home = Path(get_hermes_home())
    profile = home.name if home.parent.name == 'profiles' else 'default'
    origin = {'parent_session_id': session_id, 'parent_profile': profile,
              'source_tool_call_id': tool_call_id, 'parent_turn_id': turn_id or None}
    encoded = base64.urlsafe_b64encode(json.dumps(origin).encode()).decode()
    return {'action': 'modify', 'args': {key:
        'export CONDUIT_DELEGATION_ORIGIN=' + shlex.quote(encoded) + '\n' + command}}


def register(ctx):
    ctx.register_hook('pre_tool_call', _origin)
