import sqlite3,json,re,pathlib
c=sqlite3.connect('file:/opt/data/state.db?mode=ro',uri=True);c.row_factory=sqlite3.Row
for sid in ('20261008_155631_66fb9f','20261008_115615_5f4e52'):
 print('SESSION',sid)
 for r in c.execute("select id,role,content from messages where session_id=? and role in ('user','assistant') order by id",(sid,)):
  text=r['content'] or ''
  if r['role']=='user':print('USER',r['id'],text[:700])
  if r['role']=='assistant' and ('a2ui' in text or 'createSurface' in text):
   print('A2UI_MESSAGE',r['id'],'chars',len(text),'fences',re.findall(r'```([^\n]*)',text));print(text[:1000])
   pathlib.Path('/tmp/a2ui-message-'+str(r['id'])+'.txt').write_text(text)
