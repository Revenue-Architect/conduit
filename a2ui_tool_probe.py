import sqlite3,json
c=sqlite3.connect('file:/opt/data/state.db?mode=ro',uri=True)
for i,t in c.execute("select id,tool_calls from messages where session_id='20261008_155631_66fb9f' and tool_calls is not null"):
 if 'a2ui_check' in t:print('VALIDATOR_CALL',i)
