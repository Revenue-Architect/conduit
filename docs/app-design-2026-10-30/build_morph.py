"""Build morph.html: Conduit's menus, modals and forms as one Morphlet card, over the round-4 screens."""
import re
import sys

folder = sys.argv[1]
mock = open(f"{folder}/mockup.html", encoding="utf-8").read()

head_css = re.search(r"<style>(.*?)</style>", mock, re.S).group(1)
status_js = re.search(r"(<script>\s*// One UI status bar.*?</script>)", mock, re.S).group(1)
symbols = re.search(r'(<svg width="0" height="0".*?</svg>)', mock, re.S).group(1)


def section(name):
    m = re.search(rf'(<section class="([^"]*)" data-name="{re.escape(name)}"([^>]*)>)\n(.*?)\n</section>', mock, re.S)
    return m.group(2), m.group(3), m.group(4)


def behind(name, hide):
    """The screen under the card, with the control that became the card hidden."""
    cls, attrs, inner = section(name)
    old, new = hide
    assert old in inner, (name, old)
    inner = inner.replace(old, new, 1)
    return cls, attrs, inner


I = {
    "x": '<svg class="i" viewBox="0 0 24 24"><path d="M6 6l12 12M18 6 6 18"/></svg>',
    "back": '<svg class="i" viewBox="0 0 24 24"><path d="M15 6l-6 6 6 6"/></svg>',
    "chk": '<svg class="i" viewBox="0 0 24 24"><path d="M5 12.5l4.5 4.5L19 7"/></svg>',
    "chev": '<svg class="i" viewBox="0 0 24 24"><path d="M9 6l6 6-6 6"/></svg>',
    "down": '<svg class="i" viewBox="0 0 24 24"><path d="M6 9l6 6 6-6"/></svg>',
}


def head(title, nested=False, face=None):
    left = f'<span class="bk">{I["back"]}</span>' if nested else ""
    f = f'<img class="face" src="assets/{face}-cut.png" alt="">' if face else ""
    return f'<div class="grab"></div><div class="mh{" nested" if nested else ""}">{left}{f}<b>{title}</b><span class="x">{I["x"]}</span></div>'


def bot(face, name, sub, sel=False, live=False):
    s = f'<span class="lv">{sub}</span>' if live else f"<span>{sub}</span>"
    ring = " lring" if live else ""
    tail = f'<span class="chk">{I["chk"]}</span>' if sel else ""
    return f'<div class="opt{" sel" if sel else ""}"><img class="face{ring}" src="assets/{face}-cut.png" alt=""><div class="t"><b>{name}</b>{s}</div>{tail}</div>'


def model(name, sub, sel=False, glyph="ow"):
    av = ('<span class="glyph"><img src="assets/open-webui.png" alt="Open WebUI"></span>' if glyph == "ow"
          else '<span class="glyph"><svg class="i" viewBox="0 0 24 24"><path d="M9 3v5M15 3v5M6 8h12v3a6 6 0 0 1-12 0zM12 17v4"/></svg></span>' if glyph == "direct"
          else '<span class="glyph"><svg class="i" viewBox="0 0 24 24"><path d="M7 18h10a4 4 0 0 0 .6-7.95A6 6 0 0 0 6.2 9.4 4.3 4.3 0 0 0 7 18z"/></svg></span>')
    tail = f'<span class="chk">{I["chk"]}</span>' if sel else ""
    return f'<div class="opt{" sel" if sel else ""}">{av}<div class="t"><b>{name}</b><span>{sub}</span></div>{tail}</div>'


cards = {}

cards["send-to"] = f'''<div class="mcard" data-float style="bottom:16px">
  {head("Send to")}
  {bot("chief", "Chief", "Plans, email and your calendar", sel=True)}
  {bot("kai", "kai", "Kaizen store and catalogue")}
  {bot("ops", "ops", "Working: push server, 5 min", live=True)}
  {bot("scout", "scout", "Research and changelogs")}
  {bot("architect", "architect", "System design")}
  {bot("hermuse", "hermuse", "Writing")}
  <div class="sep"></div>
  <div class="opt"><span class="glyph"><img src="assets/open-webui.png" alt="Open WebUI"></span><div class="t"><b>Open WebUI models</b><span>Llama 3.3 70B and 3 more</span></div><span class="chev">{I["chev"]}</span></div>
</div>'''

cards["send-to-models"] = f'''<div class="mcard nest" data-float style="bottom:16px">
  {head("Open WebUI", nested=True)}
  {model("Llama 3.3 70B", "On your Umbrel · fast", sel=True)}
  {model("Qwen 3 32B", "On your Umbrel · code")}
  {model("Gemma 3 27B", "On your Umbrel · reads images")}
  {model("gpt-6.1-terra", "Direct endpoint", glyph="direct")}
</div>'''

cards["review"] = f'''<div class="mcard" data-float style="bottom:16px">
  {head("Chief's draft", face="chief")}
  <div class="dr">
    <div class="dt">Kickoff confirmation</div>
    <div class="lab first">Draft / not sent</div>
    <div class="lab">To</div><div class="val">jordan@mapleandpine.ca</div>
    <div class="lab">Subject</div><div class="val">Tuesday kickoff</div>
    <div class="lab">Message</div><div class="val">Hi Jordan, confirming our kickoff Tuesday at 10:00 on Teams. The link is below. See you then.<br>Kamran</div>
  </div>
  <div class="mbtns"><span class="mbtn">Edit</span><span class="mbtn pri">Send</span></div>
</div>'''

cards["edit"] = f'''<div class="mcard nest" data-float style="bottom:16px">
  {head("Edit draft", nested=True)}
  <div class="fld"><label>To</label><div>jordan@mapleandpine.ca</div></div>
  <div class="fld"><label>Subject</label><div>Tuesday kickoff</div></div>
  <div class="fld focus"><label>Message</label><div>Hi Jordan, confirming our kickoff Tuesday at 10:00 on Teams. The link is below. Could we keep it to 45 minutes?<span class="caret"></span></div></div>
  <div class="mnote">Chief keeps your version as the draft. Nothing is sent until you press Send.</div>
  <div class="mbtns"><span class="mbtn pri">Save</span></div>
</div>'''

cards["model"] = f'''<div class="mcard" data-float style="bottom:16px">
  {head("Model for this chat")}
  {model("gpt-6.1-terra", "Chief's default · planning and email", sel=True, glyph="cloud")}
  {model("gpt-6.1-mini", "Quicker answers, lighter work", glyph="cloud")}
  {model("Llama 3.3 70B", "Open WebUI · stays on your Umbrel")}
  <div class="sep"></div>
  <div class="fld sel"><div class="grow"><label>Reasoning</label><div>High</div></div><span class="chev">{I["down"]}</span></div>
  <div class="tog"><span>Use for new chats with Chief</span><span class="sw"></span></div>
</div>'''

cards["take-over"] = f'''<div class="mcard" data-float style="bottom:16px">
  {head("Take over ops' screen?", face="ops")}
  <p class="mp">While you have control, ops can't use its screen or browser. Commands it already started keep running. Leaving hands it back.</p>
  <div class="mbtns"><span class="mbtn">Keep watching</span><span class="mbtn pri">Take over</span></div>
</div>'''


def pick(face, name, cls=""):
    return f'<div class="pk {cls}"><img class="face" src="assets/{face}-cut.png" alt=""><span>{name}</span></div>'


cards["new-chat"] = f'''<div class="mcard" data-float style="bottom:16px">
  {head("New chat")}
  <div class="mlab">To</div>
  <div class="pks" data-scrolls>{pick("chief", "Chief", "on")}{pick("kai", "kai")}{pick("ops", "ops", "live")}{pick("scout", "scout")}{pick("architect", "architect")}<div class="pk" data-bleed><img class="face" src="assets/hermuse-cut.png" alt=""><span>hermuse</span></div></div>
  <div class="fld tall"><label>Message</label><div class="ph">What should Chief do?</div></div>
  <div class="fld sel"><div class="grow"><label>Model</label><div>gpt-6.1-terra</div></div><span class="chev">{I["down"]}</span></div>
  <div class="mbtns"><span class="mbtn icon"><svg class="i" viewBox="0 0 24 24"><path d="M12 5v14M5 12h14"/></svg></span><span class="mbtn pri">Start chat</span></div>
</div>'''

screens = [
    ("m01-send-to", "01-today-morning", ('<span class="to">', '<span class="to" style="visibility:hidden">'), "send-to"),
    ("m02-send-to-open-webui", "01-today-morning", ('<span class="to">', '<span class="to" style="visibility:hidden">'), "send-to-models"),
    ("m03-review-draft", "01-today-morning", ('<span class="go">Review</span>', '<span class="go" style="visibility:hidden">Review</span>'), "review"),
    ("m04-edit-draft", "01-today-morning", ('<span class="go">Review</span>', '<span class="go" style="visibility:hidden">Review</span>'), "edit"),
    ("m05-model-picker", "03-chat-chief", ('<div class="chip" data-float>', '<div class="chip" data-float style="visibility:hidden">'), "model"),
    ("m06-take-over", "02-live-window", ('<span class="go">Take over</span>', '<span class="go" style="visibility:hidden">Take over</span>'), "take-over"),
    ("m07-new-chat", "05-chats", ('<span class="act">', '<span class="act" style="visibility:hidden">'), "new-chat"),
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
  {cards[card]}
</section>
''')

# storyboard: Review pill -> card -> landed -> Send folds back into the row
_, _, today = section("01-today-morning")
press = today.replace('<span class="go">Review</span>', '<span class="go" style="transform:scale(.94)">Review</span>', 1)
gone = today.replace('<span class="go">Review</span>', '<span class="go" style="visibility:hidden">Review</span>', 1)
sent = today.replace(
    '<div class="need"><img class="face" src="assets/chief-cut.png" alt=""><div class="t"><b>Reply to Jordan about Tuesday</b><span>Chief · draft ready, not sent</span></div><span class="go">Review</span></div>',
    f'<div class="need"><img class="face" src="assets/chief-cut.png" alt=""><div class="t"><b>Reply to Jordan about Tuesday</b><span>Sent 7:43 · Chief filed it</span></div><span class="go soft sentpill">{I["chk"]}Sent</span></div>', 1)
assert sent != today
review_card = cards["review"]
mid_card = '''<div class="mcard morphing" data-float style="left:176px; right:28px; bottom:220px; height:150px; border-radius:26px; background:color-mix(in srgb, var(--ink) 40%, var(--raised))">
  <span class="ghostlabel" style="opacity:.45">Review</span>
</div>'''
chip_mid = '''<div class="mcard morphing" data-float style="left:150px; right:40px; bottom:236px; height:210px; border-radius:24px; background:color-mix(in srgb, var(--soft) 55%, var(--raised))">
  <span class="ghostlabel dark" style="opacity:.4"><img class="face" src="assets/chief-cut.png" alt="">Chief</span>
</div>'''

def mini(inner, time, extra=""):
    return f'''<div class="mini"><div class="mini-screen skyscreen" data-chrome="light" data-time="{time}" style="background:#0F1E33">
<div class="under">{inner}</div>{extra}
</div></div>'''


chip_press = today.replace('<span class="to">', '<span class="to" style="transform:scale(.94)">', 1)
chip_gone = today.replace('<span class="to">', '<span class="to" style="visibility:hidden">', 1)
chip_after = today.replace(
    '<span class="grow">Ask the team</span><span class="to"><img class="face" src="assets/chief-cut.png" alt="">Chief',
    '<span class="grow">Ask Llama 3.3 70B</span><span class="to"><img class="face" src="assets/open-webui.png" alt="">Llama 3.3', 1)
assert chip_after != today

story = f'''<!-- ============ m08 storyboard: a pill becomes the card ============ -->
<section class="screen story" data-name="m08-review-round-trip" data-chrome="none">
  <div class="grid">
    <figure>{mini(press, "7:42")}<figcaption><b>0 ms</b>Press: Review gives to 0.94</figcaption></figure>
    <figure>{mini(gone, "7:42", '<div class="scrim" style="opacity:.45"></div>' + mid_card)}<figcaption><b>120 ms</b>The pill itself stretches up</figcaption></figure>
    <figure>{mini(gone, "7:42", '<div class="scrim"></div>' + review_card)}<figcaption><b>300 ms</b>Landed as the draft, haptic</figcaption></figure>
    <figure>{mini(sent, "7:43")}<figcaption><b>Send</b>Folds back into the row: Sent</figcaption></figure>
  </div>
</section>

<!-- ============ m09 storyboard: a chip becomes the card, then reshapes ============ -->
<section class="screen story" data-name="m09-recipient-round-trip" data-chrome="none">
  <div class="grid">
    <figure>{mini(chip_press, "7:42")}<figcaption><b>0 ms</b>Press: the Chief chip gives</figcaption></figure>
    <figure>{mini(chip_gone, "7:42", '<div class="scrim" style="opacity:.45"></div>' + chip_mid)}<figcaption><b>140 ms</b>The chip stretches into a card</figcaption></figure>
    <figure>{mini(chip_gone, "7:42", '<div class="scrim"></div>' + cards["send-to-models"])}<figcaption><b>Nested</b>Same card narrows, slides 8 px</figcaption></figure>
    <figure>{mini(chip_after, "7:42")}<figcaption><b>Pick</b>Folds back: the chip says Llama</figcaption></figure>
  </div>
</section>
'''
out.append(story)

morph_css = """
  /* ---------- Morphlet card: every menu, modal and form is this one card ---------- */
  .under { position: absolute; inset: 0; }
  .scrim { position: absolute; inset: 0; background: rgba(8,10,14,.34); }
  .mcard { position: absolute; left: 16px; right: 16px; background: var(--raised); color: var(--ink); border-radius: 32px; box-shadow: 0 18px 48px rgba(8,10,14,.24); padding: 8px 0 12px; overflow: hidden; font-family: "Geist", sans-serif; }
  .mcard.nest { left: 36px; right: 36px; }
  .grab { width: 36px; height: 4px; border-radius: 2px; background: var(--rule); margin: 0 auto 4px; }
  .mh { display: flex; align-items: center; gap: 10px; padding: 4px 10px 10px 22px; }
  .mh.nested { padding-left: 4px; gap: 2px; }
  .mh .face { width: 28px; height: 28px; }
  .mh b { flex: 1; min-width: 0; font: 600 17px/1.2 "Geist"; letter-spacing: -.02em; }
  .mh .x, .mh .bk { width: 44px; height: 44px; border-radius: 50%; display: grid; place-items: center; color: var(--ink-2); flex: none; }
  .mh .x { background: var(--soft); width: 36px; height: 36px; margin: 4px; }
  .mh .x svg, .mh .bk svg { width: 18px; height: 18px; stroke-width: 2.2; }
  .mh .bk svg { width: 22px; height: 22px; color: var(--ink); }
  .opt { display: flex; align-items: center; gap: 12px; min-height: 56px; margin: 0 8px; padding: 0 14px; border-radius: 20px; }
  .opt.sel { background: var(--soft); }
  .opt .face { width: 36px; height: 36px; }
  .opt .t b { font-weight: 500; }
  .opt.sel .t b { font-weight: 600; }
  .opt .t .lv { color: var(--live-text); font-weight: 500; }
  .opt .glyph, .fld .glyph { width: 36px; height: 36px; border-radius: 50%; background: var(--soft); display: grid; place-items: center; color: var(--ink-2); flex: none; }
  .opt.sel .glyph { background: var(--raised); }
  .opt .glyph img { width: 22px; height: 22px; border-radius: 50%; display: block; }
  .opt .glyph svg { width: 18px; height: 18px; }
  .opt .chk, .opt .chev, .fld .chev { color: var(--ink); flex: none; }
  .opt .chk svg { width: 20px; height: 20px; stroke-width: 2.4; }
  .opt .chev svg, .fld .chev svg { width: 20px; height: 20px; color: var(--ink-2); }
  .sep { height: 1px; background: var(--rule); margin: 6px 22px; }
  .mbtns { display: flex; gap: 8px; padding: 16px 16px 4px; }
  .mbtn { flex: 1; height: 52px; border-radius: 999px; display: grid; place-items: center; font: 600 15px/1 "Geist"; background: var(--soft); color: var(--ink); }
  .mbtn.pri { background: var(--ink); color: var(--raised); }
  .mbtn.icon { flex: none; width: 52px; color: var(--ink-2); }
  .mbtn.icon svg { width: 22px; height: 22px; }
  .mp { margin: 0; padding: 0 22px; font: 400 15px/1.45 "Geist"; color: var(--ink-2); }
  .mnote { padding: 6px 22px 0; font: 400 12px/1.4 "Geist"; color: var(--ink-3); }
  .mlab { padding: 2px 22px 8px; font: 500 12px/1 "Geist"; color: var(--ink-2); }
  .fld { margin: 0 22px 2px; padding: 10px 0 11px; border-bottom: 1px solid var(--rule); }
  .fld label { display: block; font: 500 12px/1.2 "Geist"; color: var(--ink-2); }
  .fld > div, .fld .grow > div { margin-top: 4px; font: 400 15px/1.4 "Geist"; color: var(--ink); }
  .fld .ph { color: var(--ink-3); }
  .fld.tall { min-height: 92px; }
  .fld.focus { border-bottom: 2px solid var(--ink); padding-bottom: 10px; }
  .fld.focus label { color: var(--ink); }
  .fld.sel { display: flex; align-items: center; gap: 8px; }
  .fld .grow { flex: 1; min-width: 0; }
  .caret { display: inline-block; width: 2px; height: 18px; background: var(--ink); vertical-align: -3px; margin-left: 1px; }
  .tog { display: flex; align-items: center; justify-content: space-between; min-height: 56px; padding: 0 22px; font: 400 15px/1.3 "Geist"; }
  .sw { position: relative; width: 52px; height: 32px; border-radius: 16px; background: var(--ink); flex: none; }
  .sw::after { content: ""; position: absolute; right: 4px; top: 4px; width: 24px; height: 24px; border-radius: 50%; background: var(--raised); }
  .pks { display: flex; gap: 4px; padding: 6px 14px 14px; overflow: hidden; }
  /* while a card is open, the dock steps down out of view: one surface at the bottom */
  .under:has(~ .scrim) .dock, .under:has(~ .scrim) .composer, .under:has(~ .scrim) .chip { visibility: hidden; }
  .pk { width: 64px; flex: none; display: flex; flex-direction: column; align-items: center; gap: 6px; font: 500 12px/1.2 "Geist"; color: var(--ink-2); }
  .pk .face { width: 48px; height: 48px; }
  .pk.on .face { box-shadow: 0 0 0 2px var(--raised), 0 0 0 4px var(--ink); }
  .pk.on span { color: var(--ink); font-weight: 600; }
  .pk.live .face { box-shadow: 0 0 0 2px var(--raised), 0 0 0 4px var(--live); }
  /* the DraftReview A2UI surface, kept in its own structure; the card is its box */
  .dr { padding: 0 22px 2px; }
  .dr .dt { font: 600 17px/1.2 "Geist"; letter-spacing: -.02em; }
  .dr .lab { margin-top: 12px; font: 600 11px/1 "Geist"; letter-spacing: .12em; text-transform: uppercase; color: var(--ink-3); }
  .dr .lab.first { margin-top: 8px; }
  .dr .val { margin-top: 5px; font: 400 15px/1.4 "Geist"; }
  .sentpill { display: inline-flex; align-items: center; gap: 4px; }
  .sentpill svg { width: 16px; height: 16px; stroke-width: 2.4; }
  .mini-screen .under .dock, .mini-screen .under .sheetfade { position: absolute; }
  .mcard.morphing { display: grid; place-items: center; box-shadow: 0 10px 30px rgba(8,10,14,.18); }
  .ghostlabel { display: inline-flex; align-items: center; gap: 6px; font: 600 15px/1 "Geist"; color: #fff; }
  .ghostlabel.dark { color: var(--ink); }
  .ghostlabel .face { width: 24px; height: 24px; }
"""

html = f'''<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>Conduit, one card: mockups</title>
<link rel="preconnect" href="https://fonts.googleapis.com">
<link href="https://fonts.googleapis.com/css2?family=Geist:wght@400..800&display=swap" rel="stylesheet">
<link rel="stylesheet" href="file:///C:/Users/Kamran/.claude/skills/app-designer/assets/device.css">
<link rel="stylesheet" href="../app-design-2026-10-24/android.css">
<style>{head_css}{morph_css}</style>
</head>
<body>
{symbols}

{"".join(out)}
<script src="file:///C:/Users/Kamran/.claude/skills/app-designer/assets/device.js"></script>
{status_js}
</body>
</html>
'''
open(f"{folder}/morph.html", "w", encoding="utf-8", newline="\n").write(html)
print("ok", len(html))
