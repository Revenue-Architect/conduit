import sqlite3,json
c=sqlite3.connect('file:/opt/data/state.db?mode=ro',uri=True)
for name,n in c.execute("select tool_name,count(*) from messages where session_id='20261008_155631_66fb9f' and role='tool' group by tool_name"):print(name,n)
for p in ('/opt/data/SOUL.md','/opt/data/skills/software-development/a2ui-mobile/SKILL.md'):
 import pathlib
 print('FILE',p)
 for i,l in enumerate(pathlib.Path(p).read_text().splitlines(),1):
  if 'a2ui_check' in l or '160' in l or 'validate' in l.lower():print(i,l[:240])
