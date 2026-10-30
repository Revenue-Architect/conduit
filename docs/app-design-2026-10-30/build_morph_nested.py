"""Adds m10 and m11 to morph.html (run after build_morph.py).

Nothing opened from a card opens anything new: the card reshapes in place,
or grows into the screen it leads to.
"""
import importlib.util
import sys

folder = sys.argv[1]
spec = importlib.util.spec_from_file_location("bm", f"{folder}/build_morph.py")
bm = importlib.util.module_from_spec(spec)
sys.argv = [sys.argv[0], folder]
spec.loader.exec_module(bm)  # rebuilds morph.html with m01-m09 and exposes its helpers

I, head, pick, section = bm.I, bm.head, bm.pick, bm.section

_, _, chats = section("05-chats")
chats_gone = chats.replace('<span class="act">', '<span class="act" style="visibility:hidden">', 1)
chief_row = ('<div class="r unread"><img class="face" src="assets/chief-cut.png" alt=""><div class="t"><b>Chief</b>'
             '<span>Plan for Thursday: 3 meetings</span></div><div class="side"><time>6:58</time><span class="ud">2</span></div></div>')
assert chief_row in chats
chats_after = chats.replace(chief_row, (
    '<div class="r"><img class="face" src="assets/chief-cut.png" alt=""><div class="t"><b>Chief</b>'
    '<span>You: Scale this recipe to 3 loaves</span></div><div class="side"><time>7:47</time><span class="ud dot off"></span></div></div>'), 1)
# Chief's two unread were read in the chat, so 1 unread is left (kai's)
chats_badge = '<path d="M4 5h16v11H9l-5 4z"/></svg><em>3</em></span>Chats</a>'
assert chats_badge in chats_after
chats_after = (chats_after.replace("6 bots · 3 unread", "6 bots · 1 unread", 1)
               .replace(chats_badge, chats_badge.replace("<em>3</em>", "<em>1</em>"), 1))

FILE = '<svg class="i" viewBox="0 0 24 24"><path d="M7 3h7l5 5v13H7z"/><path d="M14 3v5h5"/></svg>'
FOLDER = '<svg class="i" viewBox="0 0 24 24"><path d="M3 7a2 2 0 0 1 2-2h4l2 2h8a2 2 0 0 1 2 2v8a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z"/></svg>'
PHOTO = '<svg class="i" viewBox="0 0 24 24"><rect x="3" y="5" width="18" height="14" rx="2"/><circle cx="9" cy="10" r="1.6"/><path d="M21 16l-5-5-8 8"/></svg>'
CAMERA = '<svg class="i" viewBox="0 0 24 24"><path d="M4 8h3l2-3h6l2 3h3v11H4z"/><circle cx="12" cy="13" r="3.5"/></svg>'
PLUS = '<svg class="i" viewBox="0 0 24 24"><path d="M12 5v14M5 12h14"/></svg>'


def glyph_row(icon, name, sub, tail="", sel=False):
    return (f'<div class="opt{" sel" if sel else ""}"><span class="glyph">{icon}</span>'
            f'<div class="t"><b>{name}</b><span>{sub}</span></div>{tail}</div>')


def new_chat_card(press=None, attached=False):
    plus = ' style="transform:scale(.94)"' if press == "plus" else ""
    start = ' style="transform:scale(.97)"' if press == "start" else ""
    att = f'<div class="att">{FILE}sourdough.pdf<span class="attx">{I["x"]}</span></div>' if attached else ""
    return f'''<div class="mcard" data-float style="bottom:16px">
  {head("New chat")}
  <div class="mlab">To</div>
  <div class="pks">{pick("chief", "Chief", "on")}{pick("kai", "kai")}{pick("ops", "ops", "live")}{pick("scout", "scout")}{pick("architect", "architect")}</div>
  {att}
  <div class="fld focus"><label>Message</label><div>Scale this recipe to 3 loaves, in grams<span class="caret"></span></div></div>
  <div class="fld sel"><div class="grow"><label>Model</label><div>gpt-6.1-terra</div></div><span class="chev">{I["down"]}</span></div>
  <div class="mbtns"><span class="mbtn icon"{plus}>{PLUS}</span><span class="mbtn pri"{start}>Start chat</span></div>
</div>'''


attach_card = f'''<div class="mcard nest" data-float style="bottom:16px">
  {head("Attach", nested=True)}
  {glyph_row(PHOTO, "Photos", "Recent and albums")}
  {glyph_row(CAMERA, "Camera", "Take a photo")}
  {glyph_row(FILE, "Files", "On this phone")}
  {glyph_row(FOLDER, "Umbrel files", "Home, Documents, Downloads", f'<span class="chev">{I["chev"]}</span>', sel=True)}
</div>'''

umbrel_card = f'''<div class="mcard" data-float style="bottom:16px">
  {head("Umbrel files", nested=True)}
  <div class="crumb">Home › Documents › Recipes</div>
  {glyph_row(FOLDER, "Bread", "6 files")}
  {glyph_row(FILE, "sourdough.pdf", "2 pages · 12 Oct", f'<span class="chk">{I["chk"]}</span>', sel=True)}
  {glyph_row(FILE, "pizza-dough.md", "3 KB · 4 Oct")}
  {glyph_row(FILE, "focaccia-notes.md", "2 KB · 21 Sep")}
</div>'''

grow_card = f'''<div class="mcard morphing" data-float style="left:8px; right:8px; top:150px; bottom:8px; border-radius:38px; display:block; padding:96px 20px 0">
  <div class="you" style="opacity:.6"><span class="att in">{FILE}sourdough.pdf</span><br>Scale this recipe to 3 loaves, in grams</div>
</div>'''

chat_landed = f'''<div class="body">
    <div class="bandwrap" style="height:128px"><svg class="city" style="height:40px; fill:#0F1E33"><use href="#city"/></svg>
    <div class="head over">
      <span class="back"><svg class="i" viewBox="0 0 24 24"><path d="M20 12H4M10 6l-6 6 6 6"/></svg></span>
      <img class="face" src="assets/chief-cut.png" alt="">
      <div class="who"><b>Chief</b><span>gpt-6.1-terra</span></div>
      <span class="back"><svg class="i" viewBox="0 0 24 24"><path d="M4 20h4L19 9l-4-4L4 16z"/></svg></span>
    </div></div>
    <div class="scroll" style="padding-top:4px">
      <div class="you"><span class="att in">{FILE}sourdough.pdf</span><br>Scale this recipe to 3 loaves, in grams</div>
      <div class="turn"><span class="pulse"></span>Reading sourdough.pdf <span class="meta">· 2s</span></div>
    </div>
  </div>
  <div class="composer" data-float><span class="ic">{PLUS}</span><span class="grow">Message Chief</span><span class="ic"><svg class="i" viewBox="0 0 24 24"><rect x="9" y="3" width="6" height="11" rx="3"/><path d="M5.5 11a6.5 6.5 0 0 0 13 0M12 17.5V21"/></svg></span></div>'''


def mini2(inner, time, extra="", cls="", bg="var(--ground)"):
    return f'''<div class="mini"><div class="mini-screen {cls}" data-chrome="light" data-time="{time}" style="background:{bg}">
<div class="under">{inner}</div>{extra}
</div></div>'''


SCRIM = '<div class="scrim"></div>'
story2 = f'''<!-- ============ m10 storyboard: nested inside one card ============ -->
<section class="screen story" data-name="m10-nested-one-card" data-chrome="none">
  <div class="grid">
    <figure>{mini2(chats_gone, "7:47", SCRIM + new_chat_card(press="plus"))}<figcaption><b>Depth 0</b>Typed a message, tap +</figcaption></figure>
    <figure>{mini2(chats_gone, "7:47", SCRIM + attach_card)}<figcaption><b>Depth 1</b>Same card narrows: Attach</figcaption></figure>
    <figure>{mini2(chats_gone, "7:47", SCRIM + umbrel_card)}<figcaption><b>Depth 2</b>Widens again: Umbrel files</figcaption></figure>
    <figure>{mini2(chats_gone, "7:47", SCRIM + new_chat_card(attached=True))}<figcaption><b>Back</b>File added, text still there</figcaption></figure>
  </div>
</section>

<!-- ============ m11 storyboard: a card grows into the screen it opens ============ -->
<section class="screen story" data-name="m11-card-becomes-screen" data-chrome="none">
  <div class="grid">
    <figure>{mini2(chats_gone, "7:47", SCRIM + new_chat_card(press="start", attached=True))}<figcaption><b>0 ms</b>Press Start chat</figcaption></figure>
    <figure>{mini2(chats_gone, "7:47", '<div class="scrim" style="opacity:.6"></div>' + grow_card)}<figcaption><b>160 ms</b>The card itself grows to full</figcaption></figure>
    <figure>{mini2(chat_landed, "7:47", "", cls="chat")}<figcaption><b>340 ms</b>It is the chat; Chief starts</figcaption></figure>
    <figure>{mini2(chats_after, "7:48")}<figcaption><b>Back</b>Folds into Chief's row</figcaption></figure>
  </div>
</section>
'''

extra_css = """
  .att { display: inline-flex; align-items: center; gap: 8px; height: 36px; margin: 0 22px 6px; padding: 0 4px 0 12px; border-radius: 999px; background: var(--soft); font: 500 13px/1 "Geist"; color: var(--ink); }
  .att svg { width: 16px; height: 16px; color: var(--ink-2); }
  .att .attx { width: 28px; height: 28px; display: grid; place-items: center; }
  .att .attx svg { width: 14px; height: 14px; }
  .att.in { height: 30px; margin: 0 0 8px; background: var(--raised); padding: 0 12px 0 10px; }
  .crumb { padding: 0 22px 8px; font: 500 12px/1.3 "Geist"; color: var(--ink-2); }
"""

path = f"{folder}/morph.html"
html = open(path, encoding="utf-8").read()
html = html.replace("</style>", extra_css + "</style>", 1)
marker = '<script src="file:///C:/Users/Kamran/.claude/skills/app-designer/assets/device.js">'
assert marker in html
html = html.replace(marker, story2 + "\n" + marker, 1)
open(path, "w", encoding="utf-8", newline="\n").write(html)
print("nested ok")
