"""Adds m12-m14 to morph.html (runs build_morph.py and build_morph_nested.py first).

Ideas taken from CoWork OS (coworkosapp.com), drawn in Conduit's own language:
an approval says what will happen, where, and how to undo it; scheduled work is
a list of routines with a trigger, a bot and a status; a new routine starts
paused with a scope (Observe, Propose, Act).
"""
import importlib.util
import sys

folder = sys.argv[1]
spec = importlib.util.spec_from_file_location("bmn", f"{folder}/build_morph_nested.py")
bmn = importlib.util.module_from_spec(spec)
sys.argv = [sys.argv[0], folder]
spec.loader.exec_module(bmn)  # rebuilds morph.html with m01-m11
bm = bmn.bm
I, head, section, behind = bm.I, bm.head, bm.section, bm.behind


def kv(pairs):
    cells = "".join(f'<div><span>{k}</span><b>{v}</b></div>' for k, v in pairs)
    return f'<div class="kv">{cells}</div>'


approve_card = f'''<div class="mcard" data-float style="bottom:16px">
  {head("Publish the holiday theme?", face="kai")}
  <p class="mp">kai asked at 7:38 before making the Holiday 2026 theme live on mapleandpine.ca. It checked the theme on 3 phone sizes first.</p>
  {kv([("Asks to run", "Shopify theme publish"), ("Bot", "kai, on your Umbrel")])}
  <div class="mlink" style="margin:6px 22px 0">Show the exact command<span class="sc">{I["chev"]}</span></div>
  <div class="mbtns"><span class="mbtn">Deny</span><span class="mbtn pri">Approve once</span></div>
</div>'''


def st(kind, text):
    return f'<span class="st {kind}">{text}</span>'


def routine(face, name, sub, status):
    return (f'<div class="opt"><img class="face" src="assets/{face}-cut.png" alt="">'
            f'<div class="t"><b>{name}</b><span>{sub}</span></div>{status}</div>')


routines_card = f'''<div class="mcard" data-float style="bottom:16px">
  {head("Scheduled")}
  <div class="mlab">10 on · 1 failed · 1 paused</div>
  {routine("ops", "Push relay health", "Every 15 min · ops", st("live", "Running"))}
  {routine("chief", "Support reply drafts", "Every 30 min · Chief · failed 6:40", st("fail", "Failed"))}
  {routine("chief", "Morning brief", "Daily 7:30 · Chief, to Today", st("on", "On"))}
  {routine("scout", "Shopify changelog", "Daily 5:30 · scout", st("on", "On"))}
  {routine("kai", "Competitor price watch", "Mondays 9:00 · kai", st("off", "Paused"))}
  <div class="sep"></div>
  <div class="opt"><span class="glyph"><svg class="i" viewBox="0 0 24 24"><path d="M12 5v14M5 12h14"/></svg></span><div class="t"><b>Schedule something</b><span>New routines start paused</span></div><span class="chev">{I["chev"]}</span></div>
</div>'''

new_routine_card = f'''<div class="mcard nest" data-float style="bottom:16px">
  {head("New routine", nested=True)}
  <div class="fld focus"><label>What</label><div>Check the storefront for broken images<span class="caret"></span></div></div>
  <div class="fld sel"><div class="grow"><label>Who</label><div>kai</div></div><span class="chev">{I["down"]}</span></div>
  <div class="fld sel"><div class="grow"><label>When</label><div>Weekdays 8:00</div></div><span class="chev">{I["down"]}</span></div>
  <div class="mlab" style="padding-top:12px">Tools kai may use</div>
  <div class="tchips"><span class="on">{I["chk"]}Web</span><span class="on">{I["chk"]}Browser</span><span>Files</span><span>Terminal</span></div>
  <div class="mnote">Risky commands never run in routines; Hermes blocks them. It starts paused until you turn it on.</div>
  <div class="mbtns"><span class="mbtn pri">Save, paused</span></div>
</div>'''

screens = [
    ("m12-approve-with-scope", "01-today-morning",
     ('<span class="go">Approve</span>', '<span class="go" style="visibility:hidden">Approve</span>'), approve_card),
    ("m13-scheduled-routines", "01-today-morning", ('<span class="to">', '<span class="to">'), routines_card),
    ("m14-new-routine-paused", "01-today-morning", ('<span class="to">', '<span class="to">'), new_routine_card),
]

out = []
for slug, base, hide, card in screens:
    cls, attrs, inner = behind(base, hide)
    out.append(f'''<!-- ============ {slug} ============ -->
<section class="{cls}" data-name="{slug}"{attrs}>
  <div class="under" data-behind>
{inner}
  </div>
  <div class="scrim" data-float></div>
  {card}
</section>
''')

extra_css = """
  .kv { display: grid; grid-template-columns: 1fr 1fr; gap: 14px 12px; margin: 16px 22px 0; padding-top: 14px; border-top: 1px solid var(--rule); }
  .kv span { display: block; font: 400 12px/1.3 "Geist"; color: var(--ink-2); }
  .kv b { display: block; margin-top: 3px; font: 500 15px/1.3 "Geist"; }
  .st { flex: none; height: 28px; padding: 0 11px; border-radius: 999px; display: inline-flex; align-items: center; gap: 6px; font: 600 12px/1 "Geist"; }
  .st.on { background: var(--soft); color: var(--ink); }
  .st.need { background: var(--ink); color: var(--raised); }
  .st.off { box-shadow: inset 0 0 0 1px var(--rule); color: var(--ink-2); font-weight: 500; }
  .st.live { color: var(--live-text); padding: 0 2px 0 11px; }
  .st.live::before { content: ""; width: 8px; height: 8px; border-radius: 50%; background: var(--live); }
  .st.fail { color: var(--neg); box-shadow: inset 0 0 0 1px var(--rule); }
  .mlink { display: flex; align-items: center; justify-content: space-between; height: 44px; font: 500 13px/1 "Geist"; color: var(--ink-2); }
  .mlink .sc svg { width: 18px; height: 18px; }
  .tchips { display: flex; flex-wrap: wrap; gap: 8px; padding: 0 22px 4px; }
  .tchips span { height: 36px; padding: 0 14px; border-radius: 999px; display: inline-flex; align-items: center; gap: 6px; font: 500 14px/1 "Geist"; color: var(--ink-2); box-shadow: inset 0 0 0 1px var(--rule); }
  .tchips span.on { background: var(--ink); color: var(--raised); box-shadow: none; font-weight: 600; }
  .tchips span svg { width: 15px; height: 15px; stroke-width: 2.4; }
  .seg { display: flex; margin: 0 16px; padding: 4px; border-radius: 999px; background: var(--soft); }
  .seg span { flex: 1; height: 40px; border-radius: 999px; display: grid; place-items: center; font: 500 14px/1 "Geist"; color: var(--ink-2); }
  .seg span.on { background: var(--raised); color: var(--ink); font-weight: 600; box-shadow: 0 1px 2px rgba(8,10,14,.12); }
"""

path = f"{folder}/morph.html"
html = open(path, encoding="utf-8").read()
html = html.replace("</style>", extra_css + "</style>", 1)
marker = '<!-- ============ m08 storyboard'
assert marker in html
html = html.replace(marker, "".join(out) + marker, 1)
open(path, "w", encoding="utf-8", newline="\n").write(html)
print("cowork ok")
