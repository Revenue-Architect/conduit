"""Builds popups.html: one mockup per pattern in POPUPS-PLAN.md.

Reuses build_morph.py's card helpers and mockup.html's screens as backgrounds.
"""
import importlib.util
import sys

folder = sys.argv[1]
spec = importlib.util.spec_from_file_location("bm", f"{folder}/build_morph.py")
bm = importlib.util.module_from_spec(spec)
sys.argv = [sys.argv[0], folder]
spec.loader.exec_module(bm)  # also rebuilds morph.html (harmless)

I, head, behind = bm.I, bm.head, bm.behind
KEEP = ('<span class="go">Review</span>', '<span class="go">Review</span>')


def step(done, text, now=False):
    if now:
        return f'<div class="pstep now"><span class="pdot"></span>{text}</div>'
    mark = I["chk"] if done else '<span class="pring"></span>'
    return f'<div class="pstep{" done" if done else ""}">{mark}<span>{text}</span></div>'


plan_resting = f'''<div class="mcard" data-float style="bottom:16px">
  {head("Plan · 5 steps")}
  <div class="ppad">
    {step(True, "Found Firebase timing out after 31.2 s")}
    {step(True, "Read the last 40 log lines")}
    {step(True, "Restarted the push relay")}
    {step(False, "Sending a test alert to your S25", now=True)}
    {step(False, "Watch alerts for 5 minutes, then resend the 3 missed")}
  </div>
</div>'''

plan_raised = f'''<div class="mcard tall" data-float style="bottom:16px; top:52px">
  {head("Plan · 5 steps")}
  <div class="ppad">
    {step(True, "Found Firebase timing out after 31.2 s")}
    <div class="pnote">push-relay health said degraded; Firebase token refresh took 31.2 s.</div>
    {step(True, "Read the last 40 log lines")}
    <div class="pnote">Three refresh timeouts since 7:31; no crash.</div>
    {step(True, "Restarted the push relay")}
    <div class="pnote">Back in 2 s; health ok, Firebase 0.4 s.</div>
    {step(False, "Sending a test alert to your S25", now=True)}
    <div class="pnote">Queued 7:43, waiting for the phone to confirm.</div>
    {step(False, "Watch alerts for 5 minutes, then resend the 3 missed")}
  </div>
  <div class="mnote" style="padding-top:10px">Drag down to rest the card; drag up for the details.</div>
</div>'''


def choice(title, sub, sel=False):
    tail = f'<span class="chk">{I["chk"]}</span>' if sel else ""
    return f'<div class="opt{" sel" if sel else ""}"><div class="t"><b>{title}</b><span>{sub}</span></div>{tail}</div>'


select_card = f'''<div class="mcard" data-float style="bottom:16px">
  {head("Alerts from Chief")}
  {choice("Everything", "Each finished run and every question")}
  {choice("Only what needs me", "Approvals, questions and failures", sel=True)}
  {choice("Nothing", "Chief still works; you read it in Today")}
  <div class="mnote" style="padding-top:8px">Picking folds the card back into the row, which shows your choice.</div>
</div>'''

form_card = f'''<div class="mcard" data-float style="bottom:16px">
  {head("Fill in the prompt")}
  <div class="mnote" style="padding:0 22px 10px">Client follow-up · 2 blanks</div>
  <div class="fld focus"><label>Client</label><div>Maple &amp; Pine<span class="caret"></span></div></div>
  <div class="fld"><label>When we spoke</label><div class="ph">e.g. last Tuesday</div></div>
  <div class="mbtns"><span class="mbtn">Cancel</span><span class="mbtn pri">Use prompt</span></div>
</div>'''

must_answer = '''<div class="mcard" data-float style="bottom:16px; padding-top:20px">
  <div class="mh" style="padding-left:22px"><b>Unpair this phone?</b></div>
  <p class="mp">Push alerts stop until you pair again. Your chats and approvals stay on Hermes.</p>
  <div class="mbtns"><span class="mbtn">Keep paired</span><span class="mbtn danger">Unpair</span></div>
  <div class="mnote" style="padding-top:8px; text-align:center">Must answer: no close button, and tapping outside does nothing.</div>
</div>'''

error_card = f'''<div class="mcard" data-float style="bottom:16px">
  {head("Couldn't reach Hermes")}
  <p class="mp">The Umbrel didn't answer in 15 seconds. Your message is saved and will send when it's back.</p>
  <div class="kv" style="margin-top:14px"><div><span>Server</span><b>umbrel.local</b></div><div><span>Last seen</span><b>7:12</b></div></div>
  <div class="mbtns"><span class="mbtn">Close</span><span class="mbtn pri">Retry</span></div>
</div>'''


def mrow(icon, text, danger=False):
    return f'<div class="opt menurow{" danger" if danger else ""}"><span class="micon">{icon}</span><div class="t"><b>{text}</b></div></div>'


ICON = {
    "edit": '<svg class="i" viewBox="0 0 24 24"><path d="M4 20h4L19 9l-4-4L4 16z"/></svg>',
    "move": '<svg class="i" viewBox="0 0 24 24"><path d="M3 7a2 2 0 0 1 2-2h4l2 2h8a2 2 0 0 1 2 2v8a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z"/></svg>',
    "history": '<svg class="i" viewBox="0 0 24 24"><circle cx="12" cy="12" r="8.5"/><path d="M12 7.5V12l3 2"/></svg>',
    "trash": '<svg class="i" viewBox="0 0 24 24"><path d="M5 7h14M10 7V5h4v2M7 7l1 13h8l1-13"/></svg>',
}
menu_card = f'''<div class="mcard" data-float style="bottom:16px; padding-top:10px">
  {mrow(ICON["edit"], "Rename")}
  {mrow(ICON["move"], "Move to…")}
  {mrow(ICON["history"], "Version history")}
  <div class="sep"></div>
  {mrow(ICON["trash"], "Delete page", danger=True)}
</div>'''

screens = [
    ("pf1-hermes-sheet-resting", "03-chat-chief", plan_resting),
    ("pf2-hermes-sheet-raised", "03-chat-chief", plan_raised),
    ("pc-select-card", "05-chats", select_card),
    ("pb-form-card", "03-chat-chief", form_card),
    ("pa1-must-answer", "05-chats", must_answer),
    ("pa2-error-card", "03-chat-chief", error_card),
    ("pd-row-menu", "05-chats", menu_card),
]
HIDE = {"03-chat-chief": ('<div class="chip" data-float>', '<div class="chip" data-float>'),
        "05-chats": ('<span class="act">', '<span class="act">')}

out = []
for slug, base, card in screens:
    cls, attrs, inner = behind(base, HIDE[base])
    out.append(f'''<section class="{cls}" data-name="{slug}"{attrs}>
  <div class="under" data-behind>
{inner}
  </div>
  <div class="scrim" data-float></div>
  {card}
</section>
''')

extra = """
  .mcard.tall { display: flex; flex-direction: column; }
  .ppad { padding: 0 22px; }
  .pstep { display: flex; align-items: center; gap: 10px; padding: 7px 0; font: 400 15px/1.35 "Geist"; color: var(--ink-2); }
  .pstep svg { width: 16px; height: 16px; stroke-width: 2.4; color: var(--ink-3); flex: none; }
  .pstep.now { color: var(--ink); font-weight: 600; }
  .pdot { width: 9px; height: 9px; margin: 0 3.5px; border-radius: 50%; background: var(--live); flex: none; }
  .pring { width: 9px; height: 9px; margin: 0 3.5px; border-radius: 50%; border: 1.5px solid var(--ink-3); flex: none; }
  .pnote { margin: -2px 0 6px 26px; font: 400 13px/1.4 "Geist"; color: var(--ink-3); }
  .mbtn.danger { background: var(--neg); color: #fff; }
  .menurow { min-height: 52px; }
  .menurow .micon { width: 22px; color: var(--ink-2); display: grid; place-items: center; }
  .menurow .micon svg { width: 20px; height: 20px; }
  .menurow.danger .t b, .menurow.danger .micon { color: var(--neg); }
  .kv { display: grid; grid-template-columns: 1fr 1fr; gap: 14px 12px; margin: 16px 22px 0; padding-top: 14px; border-top: 1px solid var(--rule); }
  .kv span { display: block; font: 400 12px/1.3 "Geist"; color: var(--ink-2); }
  .kv b { display: block; margin-top: 3px; font: 500 15px/1.3 "Geist"; }
"""

morph = open(f"{folder}/morph.html", encoding="utf-8").read()
mock = open(f"{folder}/mockup.html", encoding="utf-8").read()
import re
css = re.search(r"<style>(.*?)</style>", morph, re.S).group(1)
status_js = re.search(r"(<script>\s*// One UI status bar.*?</script>)", mock, re.S).group(1)
symbols = re.search(r'(<svg width="0" height="0".*?</svg>)', mock, re.S).group(1)
html = f"""<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>Conduit, remaining pop-ups as cards</title>
<link rel="preconnect" href="https://fonts.googleapis.com">
<link href="https://fonts.googleapis.com/css2?family=Geist:wght@400..800&display=swap" rel="stylesheet">
<link rel="stylesheet" href="file:///C:/Users/Kamran/.claude/skills/app-designer/assets/device.css">
<link rel="stylesheet" href="../app-design-2026-10-24/android.css">
<style>{css}{extra}</style>
</head>
<body>
{symbols}
{"".join(out)}
<script src="file:///C:/Users/Kamran/.claude/skills/app-designer/assets/device.js"></script>
{status_js}
</body>
</html>
"""
open(f"{folder}/popups.html", "w", encoding="utf-8", newline="\n").write(html)
print("popups ok")
