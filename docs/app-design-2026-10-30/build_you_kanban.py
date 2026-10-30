"""Builds you-kanban.html: the You tab and Kanban as a card.

The You tab takes its ideas from CoWork OS (memory you can read, what needs
your OK, the week's usage, where bots reach you) and shows only what Hermes
exposes: built-in memory files (USER.md, MEMORY.md), /api/analytics/usage,
approvals.mode / approvals.cron_mode / write_approval, gateway channels and
profiles. Kanban uses Hermes' real lanes (no due dates exist).

Reuses mockup.html's status bar and morph.html's tokens and card styles.
"""
import re
import sys

folder = sys.argv[1]
mock = open(f"{folder}/mockup.html", encoding="utf-8").read()
morph = open(f"{folder}/morph.html", encoding="utf-8").read()
css = re.search(r"<style>(.*?)</style>", morph, re.S).group(1)
status_js = re.search(r"(<script>\s*// One UI status bar.*?</script>)", mock, re.S).group(1)
symbols = re.search(r'(<svg width="0" height="0".*?</svg>)', mock, re.S).group(1)

ICON = {
    "sun": '<svg class="i" viewBox="0 0 24 24"><circle cx="12" cy="12" r="4"/><path d="M12 3v2M12 19v2M3 12h2M19 12h2M5.6 5.6l1.4 1.4M17 17l1.4 1.4M5.6 18.4 7 17M17 7l1.4-1.4"/></svg>',
    "chat": '<svg class="i" viewBox="0 0 24 24"><path d="M4 5h16v11H9l-5 4z"/></svg>',
    "you": '<svg class="i" viewBox="0 0 24 24"><circle cx="12" cy="8" r="4"/><path d="M4 21c1.5-4 4.5-6 8-6s6.5 2 8 6"/></svg>',
    "chev": '<svg class="i" viewBox="0 0 24 24"><path d="M9 6l6 6-6 6"/></svg>',
    "server": '<svg class="i" viewBox="0 0 24 24"><rect x="4" y="4" width="16" height="7" rx="2"/><rect x="4" y="13" width="16" height="7" rx="2"/><path d="M8 7.5h.01M8 16.5h.01"/></svg>',
    "phone": '<svg class="i" viewBox="0 0 24 24"><rect x="7" y="3" width="10" height="18" rx="2.5"/><path d="M11 18h2"/></svg>',
    "send": '<svg class="i" viewBox="0 0 24 24"><path d="M4 12l16-8-6 16-3-7z"/></svg>',
    "mail": '<svg class="i" viewBox="0 0 24 24"><rect x="3" y="5" width="18" height="14" rx="2"/><path d="M3 7l9 6 9-6"/></svg>',
    "shield": '<svg class="i" viewBox="0 0 24 24"><path d="M12 3l8 3v6c0 4.5-3.4 8.2-8 9-4.6-.8-8-4.5-8-9V6z"/></svg>',
    "clock": '<svg class="i" viewBox="0 0 24 24"><circle cx="12" cy="12" r="8.5"/><path d="M12 7.5V12l3 2"/></svg>',
    "book": '<svg class="i" viewBox="0 0 24 24"><path d="M5 4h10a3 3 0 0 1 3 3v13H8a3 3 0 0 1-3-3z"/><path d="M5 17a3 3 0 0 1 3-3h10"/></svg>',
    "moon": '<svg class="i" viewBox="0 0 24 24"><path d="M20 14.5A8 8 0 0 1 9.5 4a8 8 0 1 0 10.5 10.5z"/></svg>',
    "x": '<svg class="i" viewBox="0 0 24 24"><path d="M6 6l12 12M18 6 6 18"/></svg>',
}


def dock(on):
    items = [("Today", ICON["sun"], ""), ("Chats", ICON["chat"], "<em>1</em>"), ("You", ICON["you"], "")]
    links = "".join(
        f'<a{" class=\"on\"" if name == on else ""}><span class="ind">{icon}{badge}</span>{name}</a>'
        for name, icon, badge in items)
    return f'<div class="dockfade" data-float></div><nav class="dock three" data-float>{links}</nav>'


def srow(icon, title, sub, value=""):
    v = f'<span class="sv">{value}</span>' if value else ""
    return (f'<div class="srow"><span class="glyph">{icon}</span><div class="t"><b>{title}</b><span>{sub}</span></div>'
            f'{v}<span class="sc">{ICON["chev"]}</span></div>')


def face_row(face, title, sub):
    return (f'<div class="srow"><img class="face" src="assets/{face}-cut.png" alt=""><div class="t"><b>{title}</b>'
            f'<span>{sub}</span></div><span class="sc">{ICON["chev"]}</span></div>')


you = f'''<section class="screen" data-name="y01-you" data-time="7:48" data-chrome="light" data-home="dark">
  <div class="body">
    <div class="bandwrap" style="height:164px"><svg class="city" style="fill:#0F1E33"><use href="#city"/></svg><div class="pagehead over"><b>You</b><span>Kamran · Toronto</span></div></div>
    <div data-scrolls style="margin-top:-8px; flex:1; min-height:0; overflow:hidden">
      <section class="grp">
        {srow(ICON["server"], "Umbrel", "Connected · Hermes with 6 bots · 14 apps up")}
      </section>
      <section class="grp">
        <h3>What the team knows about you</h3>
        <div class="memo">
          <p>Lives in Toronto and works on Eastern time.</p>
          <p>Runs Kaizen Commerce; Maple &amp; Pine is a client.</p>
          <p>Keep emails short and sign them Kamran.</p>
        </div>
        <div class="mlink">USER.md · 14 notes · Chief added one yesterday<span class="sc">{ICON["chev"]}</span></div>
      </section>
      <section class="grp">
        <h3>What needs your OK</h3>
        {srow(ICON["shield"], "Risky commands", "Hermes asks when one looks risky", "Smart")}
        {srow(ICON["clock"], "In routines", "Risky commands are blocked, never run", "Blocked")}
        {srow(ICON["book"], "Memory and skills", "Bots ask before changing what they know", "Ask me")}
      </section>
      <section class="grp">
        <h3>This week</h3>
        <div class="usage"><b>1.2M tokens · $4.12</b><span>Chief used most · Open WebUI runs on your Umbrel, free</span>
          <div class="bars"><i style="height:40%"></i><i style="height:62%"></i><i style="height:35%"></i><i style="height:80%"></i><i style="height:55%"></i><i style="height:30%"></i><i class="today" style="height:46%"></i></div>
        </div>
      </section>
      <section class="grp">
        <h3>Where bots reach you</h3>
        {srow(ICON["phone"], "This phone", "Push alerts from all six bots", "On")}
        {srow(ICON["send"], "Telegram", "Chief and ops", "On")}
        {srow(ICON["mail"], "Email", "Daily summary at 7:30", "On")}
      </section>
      <section class="grp">
        <h3>Your bots</h3>
        {face_row("chief", "Chief", "gpt-6.1-terra · plans, email, calendar")}
        {face_row("ops", "ops", "gpt-6.1-mini · Umbrel and servers")}
      </section>
      <section class="grp">
        <h3>Look</h3>
        {srow(ICON["sun"], "Sky", "Follows Toronto's time and weather", "On")}
        {srow(ICON["moon"], "Theme", "Dark mode uses the evening sky", "System")}
      </section>
    </div>
  </div>
  {dock("You")}
</section>
'''

m = re.search(r'<section class="([^"]*)" data-name="01-today-morning"([^>]*)>\n(.*?)\n</section>', mock, re.S)
today_cls, today_attrs, today_inner = m.group(1), m.group(2), m.group(3)


def task(face, title, sub, tail=""):
    return f'<div class="opt"><img class="face" src="assets/{face}-cut.png" alt=""><div class="t"><b>{title}</b><span>{sub}</span></div>{tail}</div>'


def st(kind, text):
    return f'<span class="st {kind}">{text}</span>'


kanban_card = f'''<div class="mcard" data-float style="bottom:16px">
  <div class="grab"></div><div class="mh"><b>Kanban</b><span class="x">{ICON["x"]}</span></div>
  <div class="chips" data-scrolls><span class="on">Needs you 2</span><span>Running 1</span><span>Up next 7</span><span data-bleed>Done 5</span></div>
  {task("kai", "Publish the holiday theme", "kai · in review · 2 h", st("need", "Review"))}
  {task("architect", "Export the relay diagram", "architect · blocked · out of memory", st("on", "Open"))}
  <div class="sep"></div>
  <div class="mnote" style="padding-top:2px">Needs you is review and blocked; Up next is triage, to do, scheduled and ready. Tap a task and the card becomes it.</div>
  <div class="mbtns"><span class="mbtn pri">New task</span></div>
</div>'''

kanban = f'''<section class="{today_cls}" data-name="k01-kanban-card"{today_attrs}>
  <div class="under" data-behind>
{today_inner}
  </div>
  <div class="scrim" data-float></div>
  {kanban_card}
</section>
'''

extra_css = """
  .dock.three { justify-content: space-evenly; }
  .srow { display: flex; align-items: center; gap: 12px; min-height: 56px; }
  .srow .glyph { width: 40px; height: 40px; border-radius: 50%; background: var(--raised); box-shadow: inset 0 0 0 1px var(--rule); display: grid; place-items: center; color: var(--ink-2); flex: none; }
  .srow .glyph svg { width: 20px; height: 20px; }
  .srow .face { width: 40px; height: 40px; }
  .srow .sv { font: 500 13px/1 "Geist"; color: var(--ink-2); flex: none; }
  .srow .sc, .mlink .sc { color: var(--ink-3); flex: none; }
  .srow .sc svg, .mlink .sc svg { width: 18px; height: 18px; }
  .memo { margin: 8px 0 0; padding: 2px 0 2px 14px; border-left: 2px solid var(--rule); }
  .memo p { margin: 0; padding: 4px 0; font: 400 15px/1.4 "Geist"; }
  .mlink { display: flex; align-items: center; justify-content: space-between; height: 44px; font: 500 13px/1 "Geist"; color: var(--ink-2); }
  .usage { padding-top: 6px; display: grid; grid-template-columns: 1fr 96px; grid-template-rows: auto auto; column-gap: 12px; align-items: end; }
  .usage b { font: 600 17px/1.2 "Geist"; letter-spacing: -.02em; font-variant-numeric: tabular-nums; }
  .usage span { grid-row: 2; font: 400 13px/1.35 "Geist"; color: var(--ink-2); margin-top: 4px; }
  .usage .bars { grid-row: 1 / span 2; grid-column: 2; height: 44px; display: flex; align-items: flex-end; gap: 4px; }
  .usage .bars i { flex: 1; border-radius: 3px; background: var(--rule); }
  .usage .bars i.today { background: var(--ink); }
  .chips { display: flex; gap: 6px; padding: 0 16px 10px; overflow: hidden; }
  .chips span { flex: none; height: 36px; padding: 0 14px; border-radius: 999px; display: grid; place-items: center; font: 500 13px/1 "Geist"; color: var(--ink-2); box-shadow: inset 0 0 0 1px var(--rule); }
  .chips span.on { background: var(--ink); color: var(--raised); box-shadow: none; font-weight: 600; }
"""

html = f"""<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>Conduit, You and Kanban: mockups</title>
<link rel="preconnect" href="https://fonts.googleapis.com">
<link href="https://fonts.googleapis.com/css2?family=Geist:wght@400..800&display=swap" rel="stylesheet">
<link rel="stylesheet" href="file:///C:/Users/Kamran/.claude/skills/app-designer/assets/device.css">
<link rel="stylesheet" href="../app-design-2026-10-24/android.css">
<style>{css}{extra_css}</style>
</head>
<body>
{symbols}
{you}{kanban}
<script src="file:///C:/Users/Kamran/.claude/skills/app-designer/assets/device.js"></script>
{status_js}
</body>
</html>
"""
open(f"{folder}/you-kanban.html", "w", encoding="utf-8", newline="\n").write(html)
print("ok")
