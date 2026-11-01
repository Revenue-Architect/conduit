import pathlib,json,re
s=pathlib.Path('/tmp/a2ui-message-7631.txt').read_text();block=re.search(r'```a2ui\n(.*?)\n```',s,re.S).group(1)
for line in block.splitlines():
 d=json.loads(line)
 for c in d.get('updateComponents',{}).get('components',[]):
  if c.get('component')=='InfoRow':print(c['id'],len(c.get('detail','')), 'OVER_LIMIT' if len(c.get('detail',''))>160 else 'OK')
