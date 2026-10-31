"""Builds screens2.html: the screens the r4 direction never designed.

Settings (all, Chat, Notifications), Spaces (list, a Space's pages with its
menu card, the page editor), Artifacts, onboarding, and the full-height model
picker. Same tokens, status bar, symbols and card CSS as morph.html /
you-kanban.html. Nothing here edits another file: build_morph.py's helpers are
exec'd without its final write.

    python build_screens2.py <docs folder>
"""
import re
import sys

folder = sys.argv[1]
mock = open(f"{folder}/mockup.html", encoding="utf-8").read()
morph = open(f"{folder}/morph.html", encoding="utf-8").read()
css = re.search(r"<style>(.*?)</style>", morph, re.S).group(1)
status_js = re.search(r"(<script>\s*// One UI status bar.*?</script>)", mock, re.S).group(1)
symbols = re.search(r'(<svg width="0" height="0".*?</svg>)', mock, re.S).group(1)

# build_morph.py's helpers (I, head, bot, model, behind ...) without its write
_src = open(f"{folder}/build_morph.py", encoding="utf-8").read().split("\nscreens = [")[0]
_ns = {"__name__": "bm"}
exec(compile(_src, "build_morph_helpers", "exec"), _ns)
I, head, behind = _ns["I"], _ns["head"], _ns["behind"]


def svg(inner):
    return f'<svg class="i" viewBox="0 0 24 24">{inner}</svg>'


IC = {
    "back": svg('<path d="M20 12H4M10 6l-6 6 6 6"/>'),
    "chev": svg('<path d="M9 6l6 6-6 6"/>'),
    "down": svg('<path d="M6 9l6 6 6-6"/>'),
    "chk": svg('<path d="M5 12.5l4.5 4.5L19 7"/>'),
    "x": svg('<path d="M6 6l12 12M18 6 6 18"/>'),
    "more": svg('<circle cx="12" cy="5" r="1.3"/><circle cx="12" cy="12" r="1.3"/><circle cx="12" cy="19" r="1.3"/>'),
    "plus": svg('<path d="M12 5v14M5 12h14"/>'),
    "search": svg('<circle cx="11" cy="11" r="6.5"/><path d="M16 16l4.5 4.5"/>'),
    "bell": svg('<path d="M6 16V11a6 6 0 0 1 12 0v5l1.5 2h-15z"/><path d="M10 20.5a2 2 0 0 0 4 0"/>'),
    "chat": svg('<path d="M4 5h16v11H9l-5 4z"/>'),
    "wave": svg('<path d="M6 10v4M10 7v10M14 9v6M18 11v2"/>'),
    "contrast": svg('<circle cx="12" cy="12" r="8.5"/><path d="M12 3.5a8.5 8.5 0 0 1 0 17z"/>'),
    "book": svg('<path d="M5 4h10a3 3 0 0 1 3 3v13H8a3 3 0 0 1-3-3z"/><path d="M5 17a3 3 0 0 1 3-3h10"/>'),
    "team": svg('<circle cx="12" cy="8" r="3"/><circle cx="5.5" cy="10" r="2.2"/><circle cx="18.5" cy="10" r="2.2"/><path d="M6.5 20c.4-3.2 2.7-5 5.5-5s5.1 1.8 5.5 5"/>'),
    "server": svg('<rect x="4" y="4" width="16" height="7" rx="2"/><rect x="4" y="13" width="16" height="7" rx="2"/><path d="M8 7.5h.01M8 16.5h.01"/>'),
    "grid": svg('<rect x="4" y="4" width="7" height="7" rx="1.5"/><rect x="13" y="4" width="7" height="7" rx="1.5"/><rect x="4" y="13" width="7" height="7" rx="1.5"/><rect x="13" y="13" width="7" height="7" rx="1.5"/>'),
    "plug": svg('<path d="M9 3v5M15 3v5M6 8h12v3a6 6 0 0 1-12 0zM12 17v4"/>'),
    "info": svg('<circle cx="12" cy="12" r="8.5"/><path d="M12 11v5M12 8h.01"/>'),
    "gift": svg('<path d="M5 11h14v9H5zM4 7h16v4H4zM12 7v13"/><path d="M12 7c-2 0-4-1-4-3s3-2 4 3c1-5 4-5 4-3s-2 3-4 3"/>'),
    "heart": svg('<path d="M12 20s-7-4.5-7-10a4 4 0 0 1 7-2.5A4 4 0 0 1 19 10c0 5.5-7 10-7 10z"/>'),
    "logout": svg('<path d="M10 4H5v16h5M15 8l4 4-4 4M19 12H9"/>'),
    "ext": svg('<path d="M8 16 16 8M9 8h7v7"/>'),
    "radio": svg('<path d="M12 12h.01M8.5 8.5a5 5 0 0 0 0 7M15.5 8.5a5 5 0 0 1 0 7M5.5 5.5a9 9 0 0 0 0 13M18.5 5.5a9 9 0 0 1 0 13"/>'),
    "cloud": svg('<path d="M7 18h10a4 4 0 0 0 .6-7.95A6 6 0 0 0 6.2 9.4 4.3 4.3 0 0 0 7 18z"/>'),
    "folder": svg('<path d="M3 7a2 2 0 0 1 2-2h4l2 2h8a2 2 0 0 1 2 2v8a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z"/>'),
    "pageplus": svg('<path d="M6 3h8l4 4v14H6z"/><path d="M14 3v4h4M12 11v6M9 14h6"/>'),
    "refresh": svg('<path d="M20 12a8 8 0 1 1-2.5-5.8M20 4v5h-5"/>'),
    "pin": svg('<path d="M9 4h6l-1 6 3 3H7l3-3zM12 13v7"/>'),
    "bolt": svg('<path d="M13 3 5 14h6l-1 7 8-11h-6z"/>'),
    "clock": svg('<circle cx="12" cy="12" r="8.5"/><path d="M12 7.5V12l3 2"/>'),
    "doc": svg('<path d="M6 3h8l4 4v14H6z"/><path d="M14 3v4h4M9 12h6M9 16h6"/>'),
    "image": svg('<rect x="4" y="5" width="16" height="14" rx="2"/><circle cx="9" cy="10" r="1.5"/><path d="M4 17l5-4 4 3 3-2 4 3"/>'),
    "mic": svg('<rect x="9" y="3" width="6" height="11" rx="3"/><path d="M5.5 11a6.5 6.5 0 0 0 13 0M12 17.5V21"/>'),
    "shield": svg('<path d="M12 3l8 3v6c0 4.5-3.4 8.2-8 9-4.6-.8-8-4.5-8-9V6z"/>'),
    "cube": svg('<path d="m12 3 8 4.5v9L12 21l-8-4.5v-9z"/><path d="M4 7.5 12 12l8-4.5M12 12v9"/>'),
    "phone": svg('<rect x="7" y="3" width="10" height="18" rx="2.5"/><path d="M11 18h2"/>'),
    "trash": svg('<path d="M5 7h14M10 7V5h4v2M7 7l1 13h8l1-13"/>'),
    "edit": svg('<path d="M4 20h4L19 9l-4-4L4 16z"/>'),
    "sort": svg('<path d="M4 7h16M4 12h10M4 17h5"/>'),
    "code": svg('<path d="M8 8l-4 4 4 4M16 8l4 4-4 4"/>'),
    "link": svg('<path d="M10 14a4 4 0 0 0 5.7 0l3-3a4 4 0 0 0-5.7-5.7l-1 1M14 10a4 4 0 0 0-5.7 0l-3 3a4 4 0 0 0 5.7 5.7l1-1"/>'),
    "ul": svg('<path d="M9 6h11M9 12h11M9 18h11M4.5 6h.01M4.5 12h.01M4.5 18h.01"/>'),
    "ol": svg('<path d="M10 6h10M10 12h10M10 18h10M4 5l1.5-1v4M4 14h3l-3 3h3"/>'),
    "quote": svg('<path d="M5 18v-5h4v5zM5 13c0-3 1-5 4-6M14 18v-5h4v5zM14 13c0-3 1-5 4-6"/>'),
    "copy": svg('<rect x="8" y="8" width="12" height="12" rx="2"/><path d="M16 8V6a2 2 0 0 0-2-2H6a2 2 0 0 0-2 2v8a2 2 0 0 0 2 2h2"/>'),
    "key": svg('<circle cx="8" cy="15" r="4"/><path d="M11 12l9-9M16 7l3 3"/>'),
}


# --------------------------------------------------------------------------- bands

SKY = {
    "dawn": ("", "#0F1E33"),
    "dusk": ("background:linear-gradient(#081224 0%, #14284A 38%, #3B5A82 66%, #B89474 100%);", "#0A1220"),
}


def band(title, sub="", acts="", sky="dawn", h=168):
    bg, city = SKY[sky]
    a = f'<span class="acts">{acts}</span>' if acts else ""
    m = f"<!--sub:{sub}-->" if sub else ""
    return (f'<div class="bandwrap" style="height:{h}px;{bg}"><svg class="city" style="fill:{city}"><use href="#city"/></svg>'
            f'<div class="pagehead sub over"><span class="back">{IC["back"]}</span><b>{title}</b>{a}</div></div>{m}')


def band_small(title, sub="", acts="", sky="dawn", pill=""):
    """Folded header: what the band becomes once the page has scrolled."""
    bg, city = SKY[sky]
    s = f"<span>{sub}</span>" if sub else ""
    return (f'<div class="bandwrap" style="height:128px;{bg}"><svg class="city" style="height:40px; fill:{city}"><use href="#city"/></svg>'
            f'<div class="head over"><span class="back">{IC["back"]}</span><div class="who"><b>{title}</b>{s}</div>{pill}<span class="acts in">{acts}</span></div></div>')


def act(icon, hide=False):
    st = ' style="visibility:hidden"' if hide else ""
    return f'<span{st}>{IC[icon]}</span>'


def page_inner(headhtml, inner, fade=True):
    m = re.search(r"<!--sub:(.*?)-->", headhtml)
    if m:
        headhtml = headhtml.replace(m.group(0), "")
        inner = f'<div class="lede2">{m.group(1)}</div>' + inner
    f = '<div class="pagefade" data-float></div>' if fade else ""
    return (f'<div class="body">{headhtml}<div data-scrolls style="margin-top:-8px; flex:1; min-height:0; overflow:hidden">{inner}</div></div>{f}')


def screen(name, time, inner, cls="", dark=False, extra=""):
    th = ' data-theme="dark"' if dark else ""
    home = "light" if dark else "dark"
    return (f'<section class="screen {cls}" data-name="{name}" data-time="{time}" data-chrome="light" data-home="{home}"{th}{extra}>\n'
            f'{inner}\n</section>\n')


def card_screen(name, time, under, card, cls="", extra=""):
    return (f'<section class="screen {cls}" data-name="{name}" data-time="{time}" data-chrome="light" data-home="dark"{extra}>\n'
            f'  <div class="under" data-behind>\n{under}\n  </div>\n  <div class="scrim" data-float></div>\n  {card}\n</section>\n')


# --------------------------------------------------------------------------- rows

def srow(icon, title, sub="", value="", chev=True, cls="", end="chev"):
    v = f'<span class="sv">{value}</span>' if value else ""
    c = f'<span class="sc">{IC[end]}</span>' if chev else ""
    s = f"<span>{sub}</span>" if sub else ""
    return f'<div class="srow {cls}"><span class="glyph">{IC[icon]}</span><div class="t"><b>{title}</b>{s}</div>{v}{c}</div>'


def trow(title, sub, on=True, dim=False):
    sw = '<span class="sw"></span>' if on else '<span class="sw off"></span>'
    d = (" dim" if dim else "") + ("" if sub else " slim")
    return f'<div class="trow{d}"><div class="t"><b>{title}</b><span>{sub}</span></div>{sw}</div>'


def stat(title, value, sub=""):
    s = f"<span>{sub}</span>" if sub else ""
    return f'<div class="stat"><div class="t"><b>{title}</b>{s}</div><em>{value}</em></div>'


def lrow(title, sub="", chev=True, danger=False, tail=""):
    c = f'<span class="sc">{IC["chev"]}</span>' if chev else ""
    s = f"<span>{sub}</span>" if sub else ""
    d = " danger" if danger else ""
    return f'<div class="lrow{d}"><div class="t"><b>{title}</b>{s}</div>{tail}{c}</div>'


def grp(title, body, note=""):
    n = f'<div class="gnote">{note}</div>' if note else ""
    h = f"<h3>{title}</h3>" if title else ""
    return f'<section class="grp">{h}{body}{n}</section>'


def face_img(face, cls="face"):
    return f'<img class="{cls}" src="assets/{face}-cut.png" alt="">'


# --------------------------------------------------------------------------- s01 all settings

def all_settings(dark=False):
    sky = "dusk" if dark else "dawn"
    acct = (f'<div class="acct"><span class="av">K</span><div class="t"><b>Kamran</b><span>Signed in to Open WebUI on umbrel.local</span></div>'
            f'<span class="sc">{IC["chev"]}</span></div>')
    body = (
        f'<section class="grp first">{acct}</section>'
        + grp("Your team",
              srow("team", "Hermes Agent", "Connected to your Umbrel · 6 bots", "On")
              + srow("bell", "Notifications", "Banners, alerts and push from your team"))
        + grp("Chatting",
              srow("chat", "Chat", "Model, quick actions, sending", "gpt-6.1-terra")
              + srow("book", "Personalization", "Your prompt and server memory")
              + srow("wave", "Audio", "Dictation and spoken answers"))
        + grp("This app", srow("contrast", "Appearance", "Theme, accent and language", "System"))
        + grp("Servers",
              srow("radio", "Open WebUI connection", "umbrel.local · live updates", "Healthy")
              + srow("grid", "Workspace", "Models, tools and access on the server")
              + srow("plug", "Direct connections", "OpenAI-compatible APIs and Ollama", "2"))
    )
    return screen("s01-all-settings" if not dark else "s01-all-settings-dark", "18:52" if dark else "7:49",
                  page_inner(band("All settings", "Kamran · Toronto", sky=sky), body), dark=dark)


def all_settings_end():
    body = (
        grp("Servers",
            srow("radio", "Open WebUI connection", "umbrel.local · live updates", "Healthy")
            + srow("grid", "Workspace", "Models, tools and access on the server")
            + srow("plug", "Direct connections", "OpenAI-compatible APIs and Ollama", "2"))
        + grp("About Conduit", srow("info", "About", "Build 270 · what's new and licences"))
        + grp("Support Conduit",
              srow("gift", "Buy me a coffee", "A one-time thank you", end="ext")
              + srow("heart", "GitHub Sponsors", "Recurring support for the roadmap", end="ext"),
              note="Conduit stays independent when its users fund it.")
        + f'<section class="grp">{srow("logout", "Sign out", "End your Open WebUI session", chev=False, cls="danger")}</section>' + '<div style="height:64px"></div>'
    )
    return screen("s01b-all-settings-end", "7:50",
                  page_inner(band_small("All settings"), body, fade=False))


# --------------------------------------------------------------------------- s02 chat

def chat_settings():
    qa = ""
    for label, on in [("Web", True), ("Image Gen", False), ("Weather", True), ("Umbrel files", False), ("Concise answers", True)]:
        qa += f'<span class="{"on" if on else ""}">{IC["chk"] if on else ""}{label}</span>'
    body = (
        grp("Default model", srow("cloud", "gpt-6.1-terra", "Used when you start a new chat"))
        + f'''<section class="grp"><h3>Quick actions in chat <span class="n">3 selected</span></h3>
          <div class="gsub">The shortcuts that sit above your message box.</div>
          <div class="qa">{qa}</div><div class="lnk">Clear all</div></section>'''
        + grp("Sending",
              trow("Send with Enter", "Press Enter to send on a hardware keyboard.", True)
              + trow("Start temporary chats", "New chats aren't saved unless you keep them.", False)
              + trow("Show citation page titles", "Citation badges use page titles, not website names.", True))
        + grp("Android assistant", srow("phone", "Android digital assistant", "Show quick overlay"))
        + grp("Advanced", srow("cube", "Model system prompts", "14 models you can edit", end="down"))
    )
    return screen("s02-settings-chat", "7:51", page_inner(band("Chat", "Models, quick actions and sending"), body))


# --------------------------------------------------------------------------- s03 notifications

def notif_a():
    body = (
        grp("", trow("Enable notifications", "Allow banners and system alerts.", True)
            + srow("phone", "Android notification settings", "Permission, sound and banners for Conduit"))
        + grp("While you use Conduit",
              trow("In-app banners", "Show a banner while the app is open.", True)
              + trow("System notifications", "Show an alert when Conduit is in the background.", True)
              + trow("Sound", "Play a cue when a notification arrives.", True)
              + trow("Always play sound", "Play it even when the app is open and focused.", False))
        + grp("What you hear about",
              trow("Chat responses", "When an answer finishes in a chat you are not viewing.", True)
              + trow("Channel messages", "When someone writes in a channel or a direct message.", True),
              note="Channel messages come from Open WebUI and only show with a server account.")
    )
    return screen("s03-notifications", "7:52", page_inner(band("Notifications", "Banners, alerts and push"), body))


def notif_b():
    ok = f'<span class="gl">{IC["chk"]}</span>'
    body = (
        grp("Check this phone",
            stat("Conduit notifications", "On")
            + stat("System notifications", "On", "Android alerts while Conduit is in the background")
            + stat("Android permission", "Allowed")
            + stat("Android channel", "Enabled")
            + lrow("Send test notification", "Goes straight to Android, skipping Hermes, to check this phone."),
            note="Alerts show inside the app while it is open, and as Android notifications while it is in the background. A fully closed app cannot receive them.")
        + grp("Push from Hermes",
              f'<div class="health"><span class="gl">{IC["info"]}</span><div class="t"><b>Push is set up, with things to check.</b><span>Last push received 4 min ago.</span></div></div>'
              + '<div class="issue"><div class="t"><b>Conduit battery use is restricted</b><span>Set Conduit to Unrestricted battery use, so push arrives with the phone idle.</span></div>'
              + '<span class="go soft">Battery settings</span></div>'
              + lrow("Check again"))
    )
    return screen("s03b-notifications-push", "7:53",
                  page_inner(band_small("Notifications"), body, fade=True))


def notif_c():
    cats = ["Alerts", "Proactive", "Briefs", "Agent messages", "Watches", "Status"]
    on = {"Alerts": True, "Proactive": True, "Briefs": True, "Agent messages": True, "Watches": False, "Status": False}
    crow = "".join(trow(c, "", on[c]).replace("<span></span>", "") for c in cats)
    body = (
        grp("", lrow("Approvals", "Pending requests and history")
            + lrow("Pair again", "Enter a one-time code from your Umbrel")
            + lrow("Unpair this phone", danger=True))
        + grp("What Hermes can push",
              trow("Receive push", "Master switch for everything below.", True) + crow
              + lrow("Sound and vibration", "Android settings for each category"),
              note="Approvals and critical alerts stay on whenever push is on. Critical alerts do not bypass Do Not Disturb.")
    )
    return screen("s03c-notifications-categories", "7:54", page_inner(band_small("Notifications"), body))


# --------------------------------------------------------------------------- spaces

def spaces_list():
    def sp(name, n, when):
        return (f'<div class="srow"><span class="glyph">{IC["folder"]}</span><div class="t"><b>{name}</b>'
                f'<span>{n} · {when}</span></div><span class="sc">{IC["chev"]}</span></div>')
    body = (
        '<section class="grp first">'
        + sp("Kaizen", "7 pages", "6:12")
        + sp("Maple &amp; Pine", "4 pages", "Wed")
        + sp("Hermes", "3 pages", "1:20")
        + sp("Home", "5 pages", "Tue")
        + sp("Personal", "2 pages", "22 Oct")
        + '</section><div class="gnote pad">A Space holds Pages: plans, research and notes you keep improving with Hermes.</div>'
    )
    return screen("s04-spaces", "7:55",
                  page_inner(band("Spaces", "Pages you and Hermes keep working on", acts=act("plus")), body))


def page_rows():
    def pr(title, ex, meta):
        return f'<div class="prow"><b>{title}</b><p>{ex}</p><time>{meta}</time></div>'
    return (
        f'<div class="search">{IC["search"]}Search pages</div>'
        '<section class="grp first plist">'
        + pr("Holiday theme launch plan", "Goes live Friday at 9:00 once kai's three-size check is done. Open: banner copy, shipping note.", "6:12 · 2 subpages")
        + pr("Catalogue clean-up rules", "Titles under 70 characters, one vendor per product, no all-caps names.", "Yesterday")
        + pr("Weekly numbers", "Orders, returns and the two slow collections to watch before Friday.", "Tue · in Holiday theme launch plan")
        + pr("Checkout extension changes", "Two Shopify changelog entries touch checkout. Nothing breaks the current theme.", "Tue")
        + pr("Maple &amp; Pine kickoff notes", "Jordan wants Tuesday at 10 on Teams. Still missing: logo files and the shipping zones.", "Mon")
        + '</section>'
    )


def space_library(hide_more=False):
    acts = act("pageplus") + act("more", hide=hide_more)
    return page_inner(band("Kaizen", "7 pages", acts=acts), page_rows())


def space_menu_card():
    def mrow(icon, text, check=False, danger=False):
        c = f'<span class="chk">{IC["chk"]}</span>' if check else ""
        d = " danger" if danger else ""
        return f'<div class="opt menurow{d}"><span class="micon">{IC[icon]}</span><div class="t"><b>{text}</b></div>{c}</div>'
    return f'''<div class="mcard" data-float style="bottom:16px; padding-top:10px">
  <div class="mlab">Sort pages</div>
  {mrow("clock", "Recently updated", check=True)}
  {mrow("sort", "Name")}
  <div class="sep"></div>
  {mrow("edit", "Rename Space")}
  {mrow("trash", "Delete Space", danger=True)}
</div>'''


# --------------------------------------------------------------------------- page editor

def editor(conflict=False):
    banner = ""
    if conflict:
        banner = f'''<div class="conf"><b>This page changed somewhere else.</b><span>Your draft is still safe.</span>
          <div class="cbtns"><span class="go">Review latest</span><span class="go soft">Keep my draft</span><span class="go soft">Use latest</span><span class="go soft">Copy draft</span></div></div>'''
    pill = '<span class="go">Ask Hermes</span>'
    headhtml = (f'<div class="bandwrap paper" style="height:128px"><svg class="city" style="height:40px; fill:#0F1E33"><use href="#city"/></svg>'
                f'<div class="head over"><span class="back">{IC["back"]}</span><div class="who"><b class="saved">{"Changed elsewhere" if conflict else "Saved"}</b><span>in Kaizen</span></div>{pill}<span class="acts in">{act("more")}</span></div></div>')
    body = f'''{banner}<div class="doc">
        <h1>Holiday theme launch plan</h1>
        <p>The theme goes live on Friday at 9:00, once kai has checked it on three phone sizes. Everything below is open until then.</p>
        <h2>Before Friday</h2>
        <ul><li>Banner copy: waiting on Jordan</li><li>Shipping note for orders after 18 Dec</li><li>Check out once on the small phone</li></ul>
        <h2>What to watch</h2>
        <p>The old theme converted at 2.4% last week. Compare on Monday morning<span class="caret"></span></p>
      </div>'''
    tool = ''.join(f'<span>{x}</span>' for x in [
        '<b class="tb">B</b>', '<i class="tb">I</i>', '<s class="tb">S</s>', IC["code"], '<b class="tb h">H</b>', IC["ul"], IC["ol"], IC["quote"], IC["link"]])
    toolbar = f'<div class="etool" data-float>{tool}</div>'
    return (f'<div class="body">{headhtml}<div data-scrolls style="margin-top:-8px; flex:1; min-height:0; overflow:hidden; background:var(--raised)">{body}</div></div>{toolbar}')


# --------------------------------------------------------------------------- artifacts

THUMBS = {
    "banner": '<svg viewBox="0 0 160 104" width="100%" height="100%" preserveAspectRatio="xMidYMid slice"><rect width="160" height="104" fill="#E9DFCB"/><path d="M0 104V84l22-22 18 20 26-36 24 30 20-16 30 26 20-10V104z" fill="#2F4A3C"/><rect x="18" y="16" width="70" height="8" rx="3" fill="#0E1116"/><rect x="18" y="30" width="44" height="5" rx="2.5" fill="#0E1116" opacity=".45"/><circle cx="130" cy="26" r="9" fill="#FFFFFF" opacity=".8"/></svg>',
    "qa": '<svg viewBox="0 0 160 104" width="100%" height="100%" preserveAspectRatio="xMidYMid slice"><rect width="160" height="104" fill="#E3E6EB"/><g fill="#FFFFFF" stroke="#0E1116" stroke-width="2"><rect x="18" y="22" width="34" height="62" rx="6"/><rect x="62" y="16" width="38" height="74" rx="6"/><rect x="110" y="12" width="34" height="80" rx="6"/></g><g stroke="#0E1116" stroke-opacity=".35" stroke-width="3" stroke-linecap="round"><path d="M24 36h22M24 46h16M68 32h26M68 42h18M116 28h22M116 38h14"/></g></svg>',
}


def tile(name, ext, thumb="", icon="doc"):
    inner = thumb if thumb else IC[icon]
    return (f'<div class="tile"><div class="th{" glyphth" if not thumb else ""}">{inner}</div>'
            f'<b>{name}</b><span>{ext}</span></div>')


def artifacts(hide_tile=None):
    chips = '<span class="on">All</span><span>Images</span><span>Docs</span><span>Media</span>'
    tiles = [
        ("holiday-banner-v3.png", "PNG", THUMBS["banner"], "image"),
        ("theme-qa-3-sizes.png", "PNG", THUMBS["qa"], "image"),
        ("push-relay-split.pdf", "PDF", "", "doc"),
        ("catalogue-sync-oct-29.csv", "CSV", "", "doc"),
        ("morning-brief-oct-30.m4a", "M4A", "", "wave"),
        ("relay-diagram.svg", "SVG", "", "image"),
    ]
    t = ""
    for n, e, th, ic in tiles:
        h = tile(n, e, th, ic)
        if hide_tile == n:
            h = h.replace('class="tile"', 'class="tile" style="visibility:hidden"')
        t += h
    body = (f'<div class="fchips">{chips}</div><div class="fcount">9 files</div><div class="tiles">{t}</div>')
    return page_inner(band("Artifacts", "Files Hermes made for you", acts=act("refresh")), body)


def artifact_card():
    page = '''<svg viewBox="0 0 220 150" width="100%" height="100%" preserveAspectRatio="xMidYMid meet"><rect x="52" y="6" width="116" height="138" rx="6" fill="#FFFFFF" stroke="#E6E7EA"/><rect x="64" y="20" width="64" height="7" rx="3" fill="#0E1116"/><g fill="#0E1116" opacity=".28"><rect x="64" y="38" width="92" height="4" rx="2"/><rect x="64" y="48" width="88" height="4" rx="2"/><rect x="64" y="58" width="92" height="4" rx="2"/></g><rect x="64" y="76" width="44" height="26" rx="4" fill="#E6E7EA"/><rect x="114" y="76" width="42" height="26" rx="4" fill="#E6E7EA"/><g fill="#0E1116" opacity=".28"><rect x="64" y="112" width="86" height="4" rx="2"/><rect x="64" y="122" width="60" height="4" rx="2"/></g></svg>'''
    return f'''<div class="mcard" data-float style="bottom:16px">
  <div class="grab"></div>
  <div class="mh"><span class="ktile">{IC["doc"]}</span><div class="mt"><b>push-relay-split.pdf</b><span>PDF · Hermes artifact</span></div><span class="x">{IC["x"]}</span></div>
  <div class="preview">{page}</div>
  <div class="fctx">
    <div class="fh"><b>File context</b><span class="sc">{IC["down"]}</span></div>
    <div class="kv2"><span>Source</span><b>architect</b></div>
    <div class="kv2"><span>Conversation</span><b>Push relay split</b></div>
    <div class="kv2"><span>Type</span><b>PDF</b></div>
    <div class="kv2"><span>First seen</span><b>1:20</b></div>
    <div class="kv2"><span>Saved at</span><b>/opt/data/artifacts/<wbr>push-relay-split.pdf</b></div>
  </div>
  <div class="opt"><span class="glyph">{IC["chat"]}</span><div class="t"><b>Related conversation</b><span>Push relay split</span></div><span class="chev">{IC["chev"]}</span></div>
</div>'''


# --------------------------------------------------------------------------- onboarding

def onboarding(name, time, step, display1, display2, sheet, sheet_cls=""):
    return f'''<section class="screen skyscreen" data-name="{name}" data-time="{time}" data-chrome="light" data-home="dark">
  <div class="sky dawn tall" style="height:300px"><svg class="city" style="height:92px; fill:#0F1E33"><use href="#city"/></svg></div>
  <div class="body">
    <div class="top"><b>Conduit</b><span>{step}</span></div>
    <div class="display" style="padding-top:26px">{display1}<br><span>{display2}</span></div>
    <div class="sheet onb {sheet_cls}">{sheet}</div>
  </div>
</section>
'''


def choose():
    def orow(glyph, title, sub):
        return (f'<div class="srow big"><span class="glyph">{glyph}</span><div class="t"><b>{title}</b><span>{sub}</span></div>'
                f'<span class="sc">{IC["chev"]}</span></div>')
    ow = '<img src="assets/open-webui.png" alt="Open WebUI" style="width:24px;height:24px;border-radius:50%">'
    sheet = (
        '<h3>Self-hosted</h3>'
        + orow(ow, "Open WebUI", "Sign in to your server for synced chats, notes and more.")
        + orow(IC["team"], "Hermes Agent", "Connect your team of bots on a self-hosted Hermes.")
        + '<h3 style="margin-top:22px">Model APIs</h3>'
        + orow(IC["plug"], "Connect directly", "An OpenAI-compatible or Ollama API. Keys stay on this phone.")
        + '<div class="mnote" style="padding:22px 0 0">You can add the others later in All settings.</div>'
    )
    return onboarding("s08a-onboarding-choose", "7:30", "1 of 3", "Connect your team.", "Pick one to start.", sheet)


def connect():
    sheet = f'''<div class="seg"><span class="on">Responses API</span><span>Desktop Gateway</span></div>
      <div class="fld focus"><label>Server URL</label><div>http://umbrel.local:8642<span class="caret"></span></div></div>
      <div class="fld"><label>API key</label><div>••••••••••••••••</div></div>
      <div class="fld"><label>Memory key (optional)</label><div class="ph">Made for you if left blank</div></div>
      <div class="mnote" style="padding:8px 0 0">The memory key keeps long-term memory tied to you.</div>
      <div class="obtn"><span class="mbtn pri">Connect Hermes</span></div>'''
    return onboarding("s08b-onboarding-connect", "7:31", "2 of 3", "Connect Hermes.", "Enter its address.", sheet)


def pair():
    sheet = f'''<div class="done"><span class="gl">{IC["chk"]}</span><div class="t"><b>Umbrel connected</b><span>6 bots found</span></div></div>
      <div class="pgap"></div>
      <h3>Pair this phone</h3>
      <p class="pp">On the Umbrel, run this command. It prints a code that works once, for five minutes.</p>
      <div class="cmd">docker exec hermes-notify notifyctl pair</div>
      <div class="fld focus"><label>Pairing code</label><div class="code">K7QM-4D<span class="caret"></span></div></div>
      <div class="fld"><label>Name for this phone</label><div>S25 Ultra</div></div>
      <div class="fld"><label>Gateway address</label><div>https://umbrel.tailnet.ts.net:8450</div></div>
      <div class="obtn"><span class="mbtn pri">Pair</span></div>
      <div class="mnote" style="padding:8px 0 0; text-align:center">Type the code. Scanning a QR code isn't available yet.</div>'''
    return onboarding("s08-onboarding-pair", "7:33", "3 of 3", "Pair this phone.", "So alerts reach you.", sheet, "pairsheet")


# --------------------------------------------------------------------------- s09 model picker

def mopt(icon_html, name, sub, sel=False, pinned=False, caps=(), tail=""):
    chips = "".join(f'<i class="cap">{c}</i>' for c in caps)
    pin = f'<span class="pn">{IC["pin"]}</span>' if pinned else ""
    chk = f'<span class="chk"{"" if sel else " style=visibility:hidden"}>{IC["chk"]}</span>'
    return (f'<div class="opt{" sel" if sel else ""}">{icon_html}<div class="t"><b>{name}</b>'
            f'<span class="ln"><em>{sub}</em>{chips}</span></div>{tail}{pin}{chk}</div>')


def picker_card():
    ow = '<span class="glyph"><img src="assets/open-webui.png" alt="Open WebUI"></span>'
    cl = f'<span class="glyph">{IC["cloud"]}</span>'
    pl = f'<span class="glyph">{IC["plug"]}</span>'
    more = f'<span class="mact">{IC["more"]}</span>'
    rows = (
        '<div class="mlab">Pinned</div>'
        + mopt(cl, "gpt-6.1-terra", "Chief's default", sel=True, pinned=True, caps=("Reasoning",))
        + mopt(cl, "gpt-6.1-mini", "Quicker, lighter work", pinned=True, caps=("Reasoning",))
        + mopt(ow, "Llama 3.3 70B", "On your Umbrel", pinned=True)
        + '<div class="mlab g">Open WebUI</div>'
        + mopt(ow, "Qwen 3 32B", "On your Umbrel · code", caps=("Reasoning",))
        + mopt(ow, "Gemma 3 27B", "On your Umbrel", caps=("Multimodal",))
        + mopt(ow, "Mistral Small 3 24B", "On your Umbrel")
        + mopt(ow, "Phi-4 14B", "On your Umbrel · quick")
        + '<div class="mlab g">Direct</div>'
        + mopt(pl, "llama3.2 3B", "Ollama · this phone", caps=("Loaded",), tail=more)
        + mopt(pl, "gemma3 12B", "Ollama · desktop", caps=("Multimodal",), tail=more)
        + mopt(cl, "gpt-6.1-nano", "Direct endpoint")
    )
    return f'''<div class="mcard tall" data-float style="bottom:16px; top:52px">
  {head("Model for this chat")}
  <div class="msearch">{IC["search"]}Search models</div>
  <div class="mscroll" data-scrolls>{rows}<div class="mfade"></div></div>
  <div class="mfoot" data-float>
    <div class="fld sel"><div class="grow"><label>Effort</label><div>High</div></div><span class="chev">{IC["down"]}</span></div>
    <div class="tog"><span>Fast tier</span><span class="sw off"></span></div>
  </div>
</div>'''


# --------------------------------------------------------------------------- assemble

out = []
out.append(all_settings())
out.append(all_settings_end())
out.append(all_settings(dark=True))
out.append(chat_settings())
out.append(notif_a())
out.append(notif_b())
out.append(notif_c())
out.append(spaces_list())
out.append(card_screen("s05-space-pages-menu", "7:56", space_library(hide_more=True), space_menu_card()))
out.append(screen("s06-page-editor", "7:57", editor()))
out.append(screen("s06b-page-editor-conflict", "7:58", editor(conflict=True)))
out.append(screen("s07-artifacts", "7:59", artifacts()))
out.append(card_screen("s07b-artifact-card", "8:00", artifacts(hide_tile="push-relay-split.pdf"), artifact_card()))
out.append(choose())
out.append(connect())
out.append(pair())

# the model picker sits over the chat it opened from, its chip hidden: the chip became the card
cls, attrs, inner = behind("03-chat-chief", ('<div class="chip" data-float>', '<div class="chip" data-float style="visibility:hidden">'))
out.append(f'''<section class="{cls}" data-name="s09-model-picker" data-time="7:44" data-chrome="light" data-home="dark">
  <div class="under" data-behind>
{inner}
  </div>
  <div class="scrim" data-float></div>
  {picker_card()}
</section>
''')
out = [o for o in out if o]

extra_css = """
  /* ---------- screens2: settings, spaces, artifacts, onboarding, picker ---------- */
  .pagehead.sub { padding-top: 2px; }
  .pagehead.sub .back { margin-left: -14px; margin-bottom: -2px; color: #fff; }
  .pagehead .acts, .head .acts { display: flex; }
  .pagehead .acts { position: absolute; right: 8px; top: 2px; }
  .acts span { width: 48px; height: 48px; display: grid; place-items: center; color: #fff; }
  .acts svg { width: 22px; height: 22px; }
  .head .acts.in { margin-right: -8px; }
  .head .who b.saved { font-size: 16px; }
  .head .go { height: 40px; line-height: 40px; background: #FFFFFF; color: #0E1116; }
  .pagefade { position: absolute; left: 0; right: 0; bottom: 0; height: 64px; background: linear-gradient(color-mix(in srgb, var(--ground) 0%, transparent), var(--ground) 80%); pointer-events: none; }
  .lede2 { padding: 16px var(--m) 0; font: 400 15px/1.4 "Geist"; color: var(--ink-2); }
  .lede2 + .grp.first { padding-top: 4px; }
  .grp.first { padding-top: 14px; }
  .grp .gnote { margin-top: 10px; font: 400 13px/1.4 "Geist"; color: var(--ink-3); }
  .gnote.pad { padding: 14px var(--m) 0; font: 400 13px/1.4 "Geist"; color: var(--ink-3); }
  .gsub { margin: 2px 0 0; font: 400 13px/1.35 "Geist"; color: var(--ink-2); }
  .grp h3 .n { margin-left: auto; }
  .srow { display: flex; align-items: center; gap: 12px; min-height: 56px; }
  .srow .glyph { width: 40px; height: 40px; border-radius: 50%; background: var(--raised); box-shadow: inset 0 0 0 1px var(--rule); display: grid; place-items: center; color: var(--ink-2); flex: none; }
  .srow .glyph svg { width: 20px; height: 20px; }
  .srow .glyph img { width: 24px; height: 24px; border-radius: 50%; display: block; }
  .srow .t span { white-space: normal; overflow: visible; }
  .srow .sv { font: 500 13px/1 "Geist"; color: var(--ink-2); flex: none; max-width: 120px; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
  .srow .sc { color: var(--ink-3); flex: none; }
  .srow .sc svg { width: 18px; height: 18px; }
  .srow.danger .t b, .srow.danger .glyph { color: var(--neg); }
  .srow.big { min-height: 72px; }
  .srow.big .glyph { width: 44px; height: 44px; }
  .srow { padding: 4px 0; }
  .acct { display: flex; align-items: center; gap: 14px; min-height: 64px; }
  .acct .av { width: 52px; height: 52px; border-radius: 50%; background: var(--ink); color: var(--raised); display: grid; place-items: center; font: 600 20px/1 "Geist"; flex: none; }
  .acct .sc { color: var(--ink-3); } .acct .sc svg { width: 18px; height: 18px; }
  .trow { display: flex; align-items: center; gap: 16px; min-height: 64px; padding: 6px 0; }
  .trow .t span { white-space: normal; overflow: visible; }
  .trow .t span:empty { display: none; }
  .trow.slim { min-height: 52px; }
  .trow .t b { font-weight: 500; }
  .sw.off { background: var(--soft); box-shadow: inset 0 0 0 2px var(--ink-3); }
  .sw.off::after { right: auto; left: 8px; top: 8px; width: 16px; height: 16px; background: var(--ink-3); }
  .stat { display: flex; align-items: center; gap: 12px; min-height: 52px; padding: 4px 0; }
  .stat .t b { font-weight: 500; }
  .stat .t span { white-space: normal; overflow: visible; }
  .stat em { font: 500 13px/1 "Geist"; font-style: normal; color: var(--ink-2); flex: none; }
  .lrow { display: flex; align-items: center; gap: 12px; min-height: 56px; padding: 4px 0; }
  .lrow .t b { font-weight: 500; }
  .lrow .t span { white-space: normal; overflow: visible; }
  .lrow .sc { color: var(--ink-3); flex: none; } .lrow .sc svg { width: 18px; height: 18px; }
  .lrow.danger .t b { color: var(--neg); }
  .health { display: flex; gap: 12px; align-items: flex-start; padding: 6px 0 8px; }
  .health .t b { white-space: normal; font-size: 15px; }
  .gl { width: 28px; height: 28px; border-radius: 50%; background: var(--ink); color: var(--raised); display: grid; place-items: center; flex: none; }
  .gl svg { width: 16px; height: 16px; stroke-width: 2.4; }
  .health .gl { background: var(--soft); color: var(--ink); }
  .issue { display: flex; align-items: center; gap: 12px; padding: 10px 0 10px 40px; }
  .issue .t b { white-space: normal; font-weight: 500; }
  .issue .t span { white-space: normal; overflow: visible; }
  .issue .go { height: 40px; line-height: 40px; padding: 0 14px; }
  .qa { display: flex; flex-wrap: wrap; gap: 8px; padding: 12px 0 0; }
  .qa span { height: 40px; padding: 0 16px; border-radius: 999px; display: inline-flex; align-items: center; gap: 6px; font: 500 13px/1 "Geist"; color: var(--ink-2); box-shadow: inset 0 0 0 1px var(--rule); }
  .qa span.on { background: var(--ink); color: var(--raised); box-shadow: none; font-weight: 600; }
  .qa span svg { width: 16px; height: 16px; stroke-width: 2.4; }
  .lnk { height: 44px; display: flex; align-items: center; font: 600 13px/1 "Geist"; color: var(--ink); }
  .prow { padding: 10px 0 12px; }
  .prow b { display: block; font: 600 15px/1.25 "Geist"; letter-spacing: -.02em; }
  .prow p { margin: 4px 0 0; font: 400 13px/1.4 "Geist"; color: var(--ink-2); display: -webkit-box; -webkit-line-clamp: 2; -webkit-box-orient: vertical; overflow: hidden; }
  .prow time { display: block; margin-top: 6px; font: 500 12px/1.3 "Geist"; font-variant-numeric: tabular-nums; color: var(--ink-3); }
  .menurow { min-height: 52px; }
  .menurow .micon { width: 22px; color: var(--ink-2); display: grid; place-items: center; }
  .menurow .micon svg { width: 20px; height: 20px; }
  .menurow.danger .t b, .menurow.danger .micon { color: var(--neg); }
  /* the page editor */
  .bandwrap.paper::after { background: var(--raised); }
  .doc { padding: 6px 22px 0; }
  .doc h1 { margin: 0; font: 600 30px/1.12 "Geist"; letter-spacing: -.035em; }
  .doc p { margin: 14px 0 0; font: 400 17px/1.45 "Geist"; letter-spacing: -.005em; }
  .doc h2 { margin: 24px 0 0; font: 600 20px/1.2 "Geist"; letter-spacing: -.025em; }
  .doc ul { margin: 8px 0 0; padding-left: 22px; font: 400 17px/1.45 "Geist"; }
  .doc li { padding: 2px 0; }
  .etool { position: absolute; left: 12px; right: 12px; bottom: 30px; height: 52px; border-radius: 999px; background: var(--raised); box-shadow: inset 0 0 0 1px var(--rule), 0 6px 20px rgba(8,10,14,.12); display: flex; align-items: center; justify-content: space-around; padding: 0 6px; color: var(--ink); }
  .etool span { width: 40px; height: 40px; display: grid; place-items: center; border-radius: 50%; }
  .etool svg { width: 20px; height: 20px; }
  .etool .tb { font: 700 17px/1 "Geist"; font-style: normal; text-decoration: none; }
  .etool i.tb { font-weight: 500; font-style: italic; }
  .etool s.tb { font-weight: 500; text-decoration: line-through; }
  .conf { margin: 18px 16px 12px; padding: 14px 16px 14px; border-radius: 20px; background: var(--soft); }
  .conf b { display: block; font: 600 15px/1.3 "Geist"; }
  .conf span { display: block; font: 400 13px/1.3 "Geist"; color: var(--ink-2); margin-top: 2px; }
  .cbtns { display: grid; grid-template-columns: 1fr 1fr; gap: 8px; margin-top: 12px; }
  .cbtns .go { height: 44px; line-height: 44px; padding: 0 16px; text-align: center; margin: 0; color: var(--raised); font-size: 13px; }
  .cbtns .go.soft { background: var(--raised); color: var(--ink); }
  .doc { padding-top: 12px; }
  /* artifacts: files are objects you pick up, so tiles are earned here */
  .fchips { display: flex; gap: 8px; padding: 14px var(--m) 0; }
  .fchips span { height: 40px; padding: 0 16px; border-radius: 999px; display: grid; place-items: center; font: 500 13px/1 "Geist"; color: var(--ink-2); box-shadow: inset 0 0 0 1px var(--rule); }
  .fchips span.on { background: var(--ink); color: var(--raised); box-shadow: none; font-weight: 600; }
  .fcount { padding: 14px var(--m) 0; font: 500 12px/1 "Geist"; font-variant-numeric: tabular-nums; color: var(--ink-3); }
  .tiles { display: grid; grid-template-columns: 1fr 1fr; gap: 10px; padding: 10px var(--m) 0; }
  .tile { padding: 0 0 6px; }
  .tile .th { height: 112px; border-radius: 20px; background: var(--soft); overflow: hidden; display: grid; place-items: center; box-shadow: inset 0 0 0 1px var(--rule); }
  .tile .th.glyphth svg { width: 34px; height: 34px; color: var(--ink-2); }
  .tile b { display: block; margin: 10px 4px 0; font: 600 13px/1.3 "Geist"; letter-spacing: -.01em; overflow: hidden; display: -webkit-box; -webkit-line-clamp: 2; -webkit-box-orient: vertical; word-break: break-all; }
  .tile span { display: block; margin: 3px 4px 0; font: 500 12px/1.2 "Geist"; color: var(--ink-3); }
  .mcard.tall { display: flex; flex-direction: column; }
  .mh .ktile { width: 44px; height: 44px; border-radius: 14px; background: var(--soft); display: grid; place-items: center; color: var(--ink); flex: none; }
  .mh .ktile svg { width: 22px; height: 22px; }
  .mh .mt { flex: 1; min-width: 0; }
  .mh .mt b { display: block; font: 600 17px/1.2 "Geist"; letter-spacing: -.02em; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
  .mh .mt span { display: block; margin-top: 2px; font: 400 13px/1.3 "Geist"; color: var(--ink-2); }
  .preview { margin: 4px 16px 0; height: 200px; border-radius: 20px; background: var(--soft); overflow: hidden; flex: none; }
  .fctx { margin: 14px 22px 8px; padding-top: 14px; border-top: 1px solid var(--rule); }
  .fctx .fh { display: flex; justify-content: space-between; align-items: center; font: 600 15px/1 "Geist"; margin-bottom: 8px; }
  .fctx .fh .sc svg { width: 18px; height: 18px; color: var(--ink-2); }
  .kv2 { display: grid; grid-template-columns: 104px 1fr; gap: 8px; padding: 5px 0; align-items: baseline; }
  .kv2 span { font: 400 13px/1.3 "Geist"; color: var(--ink-2); }
  .kv2 b { font: 500 15px/1.3 "Geist"; overflow-wrap: anywhere; }
  /* onboarding on the sky */
  .sheet.onb { flex: 1; height: auto; margin-top: 104px; min-height: 0; padding-bottom: 26px; }
  .sheet.onb h3 { margin-bottom: 6px; }
  .sheet.onb .fld { margin: 0 0 2px; }
  .seg { display: flex; padding: 4px; border-radius: 999px; background: var(--soft); margin: 4px 0 14px; }
  .seg span { flex: 1; height: 40px; border-radius: 999px; display: grid; place-items: center; font: 500 13px/1 "Geist"; color: var(--ink-2); }
  .seg span.on { background: var(--ink); color: var(--raised); font-weight: 600; }
  .obtn { padding-top: 20px; }
  .obtn .mbtn { height: 56px; }
  .done { display: flex; align-items: center; gap: 12px; min-height: 48px; }
  .done .t span { white-space: normal; }
  .pgap { height: 1px; background: var(--rule); margin: 10px 0 18px; }
  .pp { margin: 0 0 12px; font: 400 15px/1.4 "Geist"; color: var(--ink-2); }
  .cmd { padding: 12px 14px; border-radius: 14px; background: var(--soft); font: 500 13px/1.3 "Geist"; letter-spacing: 0; margin-bottom: 10px; }
  .fld .code { font: 600 26px/1.2 "Geist"; letter-spacing: .06em; font-variant-numeric: tabular-nums; }
  .pairsheet .fld { padding: 8px 0 9px; }
  /* the full-height picker */
  .msearch { margin: 0 16px 8px; height: 46px; border-radius: 999px; background: var(--soft); display: flex; align-items: center; gap: 10px; padding: 0 16px; font: 400 15px/1 "Geist"; color: var(--ink-2); flex: none; }
  .msearch svg { width: 20px; height: 20px; color: var(--ink-2); }
  .mscroll { position: relative; flex: 1; min-height: 0; overflow: hidden; }
  .mfade { position: absolute; left: 0; right: 0; bottom: 0; height: 36px; background: linear-gradient(color-mix(in srgb, var(--raised) 0%, transparent), var(--raised)); }
  .mlab.g { padding-top: 14px; }
  .mscroll .mlab { padding-left: 22px; }
  .opt .ln { display: flex; align-items: center; gap: 6px; font: 400 13px/1.3 "Geist"; color: var(--ink-2); white-space: nowrap; overflow: hidden; }
  .opt .ln em { font-style: normal; overflow: hidden; text-overflow: ellipsis; }
  .cap { flex: none; font: 500 11px/1 "Geist"; font-style: normal; padding: 4px 7px; border-radius: 999px; background: var(--soft); color: var(--ink-2); }
  .opt.sel .cap { background: var(--raised); }
  .opt .pn { color: var(--ink-3); flex: none; display: grid; }
  .opt .pn svg { width: 16px; height: 16px; }
  .opt .mact { width: 36px; height: 36px; border-radius: 50%; display: grid; place-items: center; color: var(--ink-2); flex: none; }
  .opt .mact svg { width: 18px; height: 18px; }
  .mfoot { flex: none; border-top: 1px solid var(--rule); margin: 0 0 0; padding-top: 4px; }
  .mfoot .fld.sel { border-bottom: 0; }
  .mfoot .tog { min-height: 52px; }
  .opt .t b { font-size: 15px; }
  /* 375 x 667: the sky gives way, the sheet comes up */
  @container (max-height: 760px) {
    .screen .sky.tall { height: 240px !important; }
    .screen .sky.tall .city { height: 70px !important; }
    .screen .display { font-size: 34px; }
    .screen .sheet.onb { margin-top: 40px; height: auto; padding-top: 18px; padding-bottom: 14px; }
    .screen .sheet.onb .srow.big { min-height: 64px; }
    .screen .sheet.onb .obtn { padding-top: 12px; }
    .screen .sheet.onb .obtn .mbtn { height: 52px; }
    .screen .sheet.onb .seg { margin-bottom: 6px; }
    .screen .sheet.onb .pgap { margin: 6px 0 10px; }
    .screen .sheet.onb .pp { margin-bottom: 8px; }
    .screen .sheet.onb .cmd { margin-bottom: 4px; padding: 9px 12px; }
    .screen .pairsheet .mnote { display: none; }
    .screen .mscroll > :nth-child(n+8):not(.mfade) { display: none; }
  }
"""

html = f"""<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>Conduit, settings, spaces, artifacts, onboarding and the model picker: mockups</title>
<link rel="preconnect" href="https://fonts.googleapis.com">
<link href="https://fonts.googleapis.com/css2?family=Geist:wght@400..800&display=swap" rel="stylesheet">
<link rel="stylesheet" href="file:///C:/Users/Kamran/.claude/skills/app-designer/assets/device.css">
<link rel="stylesheet" href="../app-design-2026-10-24/android.css">
<style>{css}{extra_css}</style>
</head>
<body>
{symbols}
{"".join(out)}
<script src="file:///C:/Users/Kamran/.claude/skills/app-designer/assets/device.js"></script>
{status_js}
</body>
</html>
"""
open(f"{folder}/screens2.html", "w", encoding="utf-8", newline="\n").write(html)
print("ok", len(out), "screens")
