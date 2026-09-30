#!/usr/bin/env python3
"""Validate A2UI v0.9 surface messages the way Conduit expects them.

Usage:
  a2ui_check.py FILE.jsonl [FILE2.jsonl ...]
  a2ui_check.py --from-md FILE.md        # validate every fenced ```a2ui block in markdown

Checks per payload (a JSONL file or one fenced block = one reply payload):
  - every non-blank line parses as JSON with "version": "v0.9"
  - createSurface: surfaceId present; catalogId is the exact basic catalog URL
  - updateComponents: surfaceId was created in the same payload (createSurface first)
  - components: ids unique; exactly one "root"; all child/children/tabs/modal refs resolve
  - required props per component; enum checks (StatusBadge state, MiniChart kind, variants)
  - Button action must contain only an event (with name); MetricTile value finite numeric
  - network asset components are unavailable; use authenticated MEDIA: instead
  - MiniChart needs >= 2 points, each with a numeric value

Errors: a direct width-dependent Row child without a positive integer weight.
Warnings (do not fail): components unreachable from root; payload with several surfaces
(Conduit convention is one surface per reply); unweighted Row mixing Text+Button
(Conduit stacks it, so add weight only if side-by-side layout is intended).

Exit code: 0 = all payloads valid, 1 = at least one error.
"""
import argparse
import json
import math
import re
import sys

CATALOG = "https://a2ui.org/specification/v0_9/catalogs/basic/catalog.json"
ACTION_NAME = re.compile(r"^[A-Za-z][A-Za-z0-9_-]*(?:\.[A-Za-z][A-Za-z0-9_-]*)*$")

KNOWN = {
    "Text", "Image", "Icon", "Video", "AudioPlayer", "Row", "Column", "List", "Card",
    "Tabs", "Modal", "Divider", "Button", "TextField", "CheckBox", "ChoicePicker",
    "Slider", "DateTimeInput",
    # Conduit app components
    "StatusBadge", "MetricTile", "MiniChart",
    "InfoRow", "StepRail", "ActionCallout", "ArtifactTile", "BotBadge",
    "ExpandableSection",
    "ProgressMeter", "ActivityFeed", "ScheduleTile", "MessagePreview",
    "CommandBlock", "TaskTile", "KeyValueGrid", "ComparisonCard",
}

# Structural Hermez components: every prop is declared (anything else is
# rejected), with the same bounds the Flutter widgets enforce.
_ICONS = {
    "check", "warning", "error", "info", "clock", "calendar", "person", "bot",
    "file", "link", "storage", "server", "chart", "task",
}
STRUCTURE_PROPS = {
    "InfoRow": {"title": 80, "detail": 160, "meta": 60, "icon": None,
                "state": None, "compact": None},
    "StepRail": {"steps": None},
    "ActionCallout": {"eyebrow": 32, "title": 100, "detail": 200, "tone": None,
                      "icon": None, "actionChild": 128},
    "ArtifactTile": {"name": 80, "kind": None, "sizeLabel": 24, "detail": 120,
                     "actionChild": 128},
    "BotBadge": {"label": 40, "identity": None, "detail": 80},
    "ExpandableSection": {"title": 60, "subtitle": 120, "count": None,
                          "child": 128, "initiallyExpanded": None},
    "ProgressMeter": {"label": 80, "current": None, "total": None, "unit": 24,
                      "detail": 120, "state": None, "segmented": None},
    "ActivityFeed": {"items": None, "compact": None},
    "ScheduleTile": {"title": 80, "start": 40, "end": 40, "date": 40,
                     "location": 100, "detail": 120, "owner": 60,
                     "state": None, "icon": None},
    "MessagePreview": {"sender": 80, "title": 100, "preview": 240,
                       "timestamp": 40, "channel": None, "unread": None,
                       "importance": None},
    "CommandBlock": {"content": 4000, "label": 40, "language": None,
                     "copyable": None},
    "TaskTile": {"title": 100, "status": None, "assignee": 60, "due": 40,
                 "priority": None, "detail": 160, "countLabel": 40},
    "KeyValueGrid": {"title": 60, "items": None, "compact": None},
    "ComparisonCard": {"title": 80, "subtitle": 120, "badge": 40,
                       "facts": None, "detail": 160},
}
_STATES = {"ok", "warning", "error", "unknown"}
BOOL_PROPS = {"compact", "initiallyExpanded", "segmented", "copyable", "unread"}

# Rich full-width objects: never direct Row children, weighted or not (the
# client stacks them; author them in a Column).
ROW_NEVER = {
    "ProgressMeter", "ActivityFeed", "ScheduleTile", "MessagePreview",
    "CommandBlock", "TaskTile", "KeyValueGrid", "ComparisonCard",
}
STEP_STATES = {"done", "current", "upcoming", "warning", "error"}

# Keep in sync with _stackInRowComponentTypes in Conduit's read-time normalizer.
# These supported component types need a bounded, allocated share of horizontal
# space when placed directly in a Row. MetricTile-only rows remain comparable
# when each tile has a positive weight; otherwise the client repairs old data.
ROW_WIDTH_DEPENDENT = {
    "MetricTile", "MiniChart", "StatusBadge", "Slider", "TextField",
    "ChoicePicker", "DateTimeInput", "Card", "Column", "Row", "List", "Tabs",
    "InfoRow", "StepRail", "ActionCallout", "ArtifactTile", "BotBadge",
    "ExpandableSection",
}

REQUIRED = {
    "Text": ["text"], "Image": ["url"], "Icon": ["name"], "Video": ["url"],
    "AudioPlayer": ["url"], "Row": ["children"], "Column": ["children"],
    "List": ["children"], "Card": ["child"], "Tabs": ["tabs"], "Modal": ["trigger", "content"],
    "Button": ["child", "action"], "TextField": ["label"], "CheckBox": ["label", "value"],
    "ChoicePicker": ["options", "value"], "Slider": ["value", "max"],
    "DateTimeInput": ["value"],
    "StatusBadge": ["label", "state"], "MetricTile": ["label", "value"],
    "MiniChart": ["label", "kind", "points"],
    "InfoRow": ["title"], "StepRail": ["steps"], "ActionCallout": ["title"],
    "ArtifactTile": ["name", "kind"], "BotBadge": ["label", "identity"],
    "ExpandableSection": ["title", "child"],
    "ProgressMeter": ["label", "current", "total"], "ActivityFeed": ["items"],
    "ScheduleTile": ["title", "start"], "MessagePreview": ["sender", "preview"],
    "CommandBlock": ["content"], "TaskTile": ["title", "status"],
    "KeyValueGrid": ["items"], "ComparisonCard": ["title", "facts"],
}

ENUMS = {
    "StatusBadge": {"state": {"ok", "warning", "error", "unknown"}},
    "MiniChart": {"kind": {"line", "bar"}},
    "InfoRow": {"state": {"ok", "warning", "error", "unknown"}, "icon": _ICONS},
    "ActionCallout": {"tone": {"neutral", "attention", "success", "error"},
                      "icon": _ICONS},
    "ArtifactTile": {"kind": {"document", "image", "spreadsheet", "audio",
                              "video", "file"}},
    "BotBadge": {"identity": {"neutral", "kai", "local", "autopilot", "fast",
                              "strong"}},
    "ProgressMeter": {"state": _STATES},
    "ScheduleTile": {"state": _STATES, "icon": _ICONS},
    "MessagePreview": {
        "channel": {"email", "teams", "agentmail", "message", "unknown"},
        "importance": {"normal", "important"},
    },
    "CommandBlock": {"language": {"shell", "sql", "json", "yaml", "text"}},
    "TaskTile": {
        "status": {"todo", "in_progress", "blocked", "done", "unknown"},
        "priority": {"low", "normal", "high", "urgent"},
    },
    "Text": {"variant": {"h1", "h2", "h3", "h4", "h5", "caption", "body"}},
    "Button": {"variant": {"default", "primary", "borderless"}},
    "TextField": {"variant": {"longText", "number", "shortText", "obscured"}},
    "ChoicePicker": {
        "variant": {"multipleSelection", "mutuallyExclusive"},
        "displayStyle": {"checkbox", "chips"},
    },
}


def _num(v):
    if not isinstance(v, (int, float)) or isinstance(v, bool):
        return False
    try:
        return math.isfinite(v)
    except OverflowError:
        return False


def _has_positive_weight(component):
    weight = component.get("weight")
    return isinstance(weight, int) and not isinstance(weight, bool) and weight > 0


def _safe_context_value(value, depth=0):
    if depth > 3:
        return False
    if isinstance(value, bool):
        return True
    if _num(value):
        return True
    if isinstance(value, str):
        return len(value) <= 2048
    if isinstance(value, list):
        return len(value) <= 32 and all(_safe_context_value(v, depth + 1) for v in value)
    if isinstance(value, dict):
        return set(value) == {"path"} and isinstance(value["path"], str) and len(value["path"]) <= 256
    return False


def check_components(name, comps, errors, warnings):
    if not isinstance(comps, list) or not comps:
        errors.append(f"{name}: updateComponents has no components list")
        return
    ids = [c.get("id") for c in comps if isinstance(c, dict)]
    if len(ids) != len(set(ids)):
        errors.append(f"{name}: duplicate component ids")
    by_id = {c.get("id"): c for c in comps if isinstance(c, dict) and isinstance(c.get("id"), str)}
    roots = [c for c in comps if isinstance(c, dict) and c.get("id") == "root"]
    if len(roots) != 1:
        errors.append(f"{name}: expected exactly one 'root' component, found {len(roots)}")

    parents = {}
    for c in comps:
        if not isinstance(c, dict):
            errors.append(f"{name}: component entry is not an object")
            continue
        cid = c.get("id", "?")
        ctype = c.get("component")
        if ctype not in KNOWN:
            errors.append(f"{name}: component {cid!r} has unknown type {ctype!r}")
            continue
        if ctype in {"Image", "Video", "AudioPlayer"}:
            errors.append(
                f"{name}: {ctype} {cid!r} is unavailable in Conduit's "
                "no-network-asset catalog; use authenticated MEDIA: artifacts"
            )
        for req in REQUIRED.get(ctype, []):
            if req not in c:
                errors.append(f"{name}: {ctype} {cid!r} missing required prop {req!r}")
        for prop, allowed in ENUMS.get(ctype, {}).items():
            if prop in c and c[prop] not in allowed:
                errors.append(f"{name}: {ctype} {cid!r} {prop}={c[prop]!r} not one of {sorted(allowed)}")
        if ctype == "MetricTile" and "value" in c and not _num(c["value"]):
            errors.append(f"{name}: MetricTile {cid!r} value must be a number")
        if ctype == "MiniChart":
            pts = c.get("points")
            if not isinstance(pts, list) or len(pts) < 2:
                errors.append(f"{name}: MiniChart {cid!r} needs at least 2 points")
            else:
                for p in pts:
                    if not isinstance(p, dict) or not _num(p.get("value")):
                        errors.append(f"{name}: MiniChart {cid!r} every point needs a numeric value")
                        break
        if ctype == "Button":
            act = c.get("action")
            if not isinstance(act, dict) or set(act) != {"event"}:
                errors.append(f"{name}: Button {cid!r} action must contain only an 'event'")
            else:
                ev = act.get("event")
                if not isinstance(ev, dict) or not isinstance(ev.get("name"), str):
                    errors.append(f"{name}: Button {cid!r} event missing 'name'")
                elif set(ev) - {"name", "context"} or len(ev["name"]) > 80 or not ACTION_NAME.fullmatch(ev["name"]):
                    errors.append(f"{name}: Button {cid!r} event name/context is not supported")
                elif "context" in ev:
                    context = ev["context"]
                    if not isinstance(context, dict) or len(context) > 16:
                        errors.append(f"{name}: Button {cid!r} event context must be a small object")
                    elif any(
                        not isinstance(k, str) or not k or len(k) > 80 or not _safe_context_value(v)
                        for k, v in context.items()
                    ):
                        errors.append(f"{name}: Button {cid!r} event context contains an unsafe value")
        if ctype in STRUCTURE_PROPS:
            spec = STRUCTURE_PROPS[ctype]
            for prop in set(c) - {"id", "component", "weight"} - set(spec):
                errors.append(f"{name}: {ctype} {cid!r} has unsupported prop {prop!r}")
            for prop, limit in spec.items():
                if limit is None or prop not in c:
                    continue
                v = c[prop]
                if not isinstance(v, str) or not v.strip() or len(v) > limit:
                    errors.append(
                        f"{name}: {ctype} {cid!r} {prop} must be a non-empty string of at most {limit} chars"
                    )
            for flag in BOOL_PROPS:
                if flag in c and flag in spec and not isinstance(c[flag], bool):
                    errors.append(f"{name}: {ctype} {cid!r} {flag} must be a boolean")
            if ctype == "ProgressMeter":
                cur, tot = c.get("current"), c.get("total")
                if not _num(cur) or cur < 0:
                    errors.append(f"{name}: ProgressMeter {cid!r} current must be a finite number >= 0")
                if not _num(tot) or tot <= 0:
                    errors.append(f"{name}: ProgressMeter {cid!r} total must be a finite number > 0")
            for list_prop, lo, hi, allowed, required, limits in (
                ("items", 1, 20, {"title", "detail", "time", "icon", "state"}, {"title"},
                 {"title": 80, "detail": 140, "time": 40}) if ctype == "ActivityFeed" else
                ("items", 1, 8, {"label", "value"}, {"label", "value"},
                 {"label": 40, "value": 120}) if ctype == "KeyValueGrid" else
                ("facts", 1, 8, {"label", "value", "state"}, {"label", "value"},
                 {"label": 40, "value": 100}) if ctype == "ComparisonCard" else
                (None, 0, 0, set(), set(), {}),
            ):
                if list_prop is None:
                    continue
                entries = c.get(list_prop)
                if not isinstance(entries, list) or not lo <= len(entries) <= hi:
                    errors.append(f"{name}: {ctype} {cid!r} {list_prop} needs {lo}-{hi} entries")
                    continue
                for entry in entries:
                    if not isinstance(entry, dict) or set(entry) - allowed or required - set(entry):
                        errors.append(
                            f"{name}: {ctype} {cid!r} {list_prop} entries accept only "
                            f"{sorted(allowed)} and need {sorted(required)}"
                        )
                        break
                    if any(k in entry and (not isinstance(entry[k], str) or not entry[k].strip()
                                           or len(entry[k]) > lim) for k, lim in limits.items()):
                        errors.append(f"{name}: {ctype} {cid!r} {list_prop} text missing or too long")
                        break
                    if "state" in entry and entry["state"] not in _STATES:
                        errors.append(f"{name}: {ctype} {cid!r} state must be one of {sorted(_STATES)}")
                        break
                    if "icon" in entry and entry["icon"] not in _ICONS:
                        errors.append(f"{name}: {ctype} {cid!r} icon must be one of {sorted(_ICONS)}")
                        break
            if ctype == "ExpandableSection" and "count" in c:
                n = c["count"]
                if not isinstance(n, int) or isinstance(n, bool) or not 0 <= n <= 9999:
                    errors.append(f"{name}: ExpandableSection {cid!r} count must be an integer 0-9999")
            if ctype == "StepRail":
                steps = c.get("steps")
                if not isinstance(steps, list) or not 1 <= len(steps) <= 10:
                    errors.append(f"{name}: StepRail {cid!r} needs 1-10 steps")
                else:
                    for st in steps:
                        if not isinstance(st, dict) or set(st) - {"label", "detail", "meta", "state"}:
                            errors.append(f"{name}: StepRail {cid!r} steps accept only label/detail/meta/state")
                            break
                        if not isinstance(st.get("label"), str) or not st["label"].strip() or len(st["label"]) > 60:
                            errors.append(f"{name}: StepRail {cid!r} every step needs a label of at most 60 chars")
                            break
                        if st.get("state") not in STEP_STATES:
                            errors.append(f"{name}: StepRail {cid!r} step state must be one of {sorted(STEP_STATES)}")
                            break
                        if any(k in st and (not isinstance(st[k], str) or len(st[k]) > lim)
                               for k, lim in (("detail", 120), ("meta", 40))):
                            errors.append(f"{name}: StepRail {cid!r} step detail/meta too long or not text")
                            break
        if ctype == "Tabs":
            tabs = c.get("tabs")
            if not isinstance(tabs, list) or not tabs:
                errors.append(f"{name}: Tabs {cid!r} needs a non-empty tabs array")
            else:
                for t in tabs:
                    if not isinstance(t, dict) or not t.get("label") or not t.get("content"):
                        errors.append(f"{name}: Tabs {cid!r} entries need 'label' and 'content'")
                    elif t["content"] not in by_id:
                        errors.append(f"{name}: Tabs {cid!r} content {t['content']!r} not found")
        if ctype == "Modal":
            for k in ("trigger", "content"):
                if not isinstance(c.get(k), str) or c[k] not in by_id:
                    errors.append(f"{name}: Modal {cid!r} {k} {c.get(k)!r} not found")

        refs = []
        if isinstance(c.get("child"), str):
            refs.append(c["child"])
        if isinstance(c.get("actionChild"), str):
            refs.append(c["actionChild"])
        ch = c.get("children")
        if isinstance(ch, list):
            refs.extend([x for x in ch if isinstance(x, str)])
        elif isinstance(ch, dict):
            warnings.append(f"{name}: {ctype} {cid!r} uses a dynamic children template; not validated")
        for r in refs:
            if r not in by_id:
                errors.append(f"{name}: component {cid!r} references missing id {r!r}")
            else:
                parents.setdefault(r, []).append(cid)
        if ctype == "Tabs" and isinstance(c.get("tabs"), list):
            for tab in c["tabs"]:
                if isinstance(tab, dict) and tab.get("content") in by_id:
                    parents.setdefault(tab["content"], []).append(cid)
        if ctype == "Modal":
            for key in ("trigger", "content"):
                if isinstance(c.get(key), str) and c[key] in by_id:
                    parents.setdefault(c[key], []).append(cid)

    for child, owners in parents.items():
        if len(owners) > 1:
            errors.append(
                f"{name}: component {child!r} has multiple parents {owners!r}; "
                "remove duplicate child from surrounding children list"
            )

    # Reachability from root
    if len(roots) == 1:
        seen, stack = set(), ["root"]
        while stack:
            cur = stack.pop()
            if cur in seen or cur not in by_id:
                continue
            seen.add(cur)
            c = by_id[cur]
            if isinstance(c.get("child"), str):
                stack.append(c["child"])
            if isinstance(c.get("actionChild"), str):
                stack.append(c["actionChild"])
            if isinstance(c.get("children"), list):
                stack.extend([x for x in c["children"] if isinstance(x, str)])
            if isinstance(c.get("tabs"), list):
                for t in c["tabs"]:
                    if isinstance(t, dict) and isinstance(t.get("content"), str):
                        stack.append(t["content"])
            for k in ("trigger", "content"):
                if c.get("component") == "Modal" and isinstance(c.get(k), str):
                    stack.append(c[k])
        orphans = sorted(i for i in by_id if i not in seen)
        if orphans:
            warnings.append(f"{name}: unreachable from root: {orphans}")

    # Phone-layout validation: width-dependent direct children need flex space.
    for c in comps:
        if isinstance(c, dict) and c.get("component") == "Row" and isinstance(c.get("children"), list):
            kids = [by_id[k] for k in c["children"] if k in by_id]
            types = [k.get("component") for k in kids]
            for child in kids:
                child_type = child.get("component")
                if child_type in ROW_NEVER:
                    errors.append(
                        f"{name}: Row {c.get('id')!r} has {child_type} {child.get('id')!r}; "
                        "it is a full-width object, put it in a Column"
                    )
                    continue
                if child_type in ROW_WIDTH_DEPENDENT and not _has_positive_weight(child):
                    errors.append(
                        f"{name}: Row {c.get('id')!r} has width-dependent child "
                        f"{child.get('id')!r} ({child_type}) without a positive integer weight; "
                        "add weight to the direct child or use a Column"
                    )
            if "Text" in types and "Button" in types:
                texts = [k for k in kids if k.get("component") == "Text"]
                if any(not _has_positive_weight(k) for k in texts):
                    warnings.append(
                        f"{name}: Row {c.get('id')!r} mixes Text+Button without weight; "
                        "Conduit stacks such rows (add weight only if side-by-side is intended)"
                    )


def validate_payload(name, lines, errors, warnings):
    msgs = []
    for i, ln in enumerate(lines, 1):
        if not ln.strip():
            continue
        try:
            msgs.append(json.loads(ln))
        except Exception as e:
            errors.append(f"{name}: line {i} is not valid JSON ({e})")
    created = []
    for m in msgs:
        if not isinstance(m, dict):
            errors.append(f"{name}: message is not a JSON object")
            continue
        if m.get("version") != "v0.9":
            errors.append(f"{name}: message version must be 'v0.9'")
            continue
        if "createSurface" in m:
            cs = m.get("createSurface") or {}
            sid = cs.get("surfaceId")
            if not sid:
                errors.append(f"{name}: createSurface missing surfaceId")
            if cs.get("catalogId") != CATALOG:
                errors.append(f"{name}: catalogId must be exactly {CATALOG!r}")
            created.append(sid)
        elif "updateComponents" in m:
            uc = m.get("updateComponents") or {}
            sid = uc.get("surfaceId")
            if sid not in created:
                errors.append(f"{name}: updateComponents surfaceId {sid!r} was not created in this payload")
            check_components(name, uc.get("components"), errors, warnings)
        elif "deleteSurface" in m or "updateDataModel" in m:
            pass
        else:
            errors.append(f"{name}: unrecognized message keys {sorted(m.keys())}")
    if len(set(created)) > 1:
        warnings.append(f"{name}: payload contains {len(set(created))} surfaces; Conduit convention is one surface per reply")
    if not msgs:
        errors.append(f"{name}: no messages found")


def main():
    ap = argparse.ArgumentParser(description="Validate A2UI v0.9 surface payloads.")
    ap.add_argument("files", nargs="+", help="JSONL file(s), or markdown file(s) with --from-md")
    ap.add_argument("--from-md", action="store_true", help="Extract fenced ```a2ui blocks from markdown and validate each")
    args = ap.parse_args()

    errors, warnings, ok = [], [], []
    for path in args.files:
        with open(path, encoding="utf-8") as fh:
            text = fh.read()
        if args.from_md:
            for match in re.finditer(r"```(?:json|jsonl)\s*\n(.*?)```", text, re.S | re.I):
                if re.search(
                    r'"(?:surfaceUpdate|beginRendering|dataModelUpdate|createSurface|updateComponents)"\s*:',
                    match.group(1),
                ):
                    errors.append(
                        f"{path}: A2UI-like JSON is fenced as json/jsonl; "
                        "Conduit requires a fenced a2ui block with v0.9 createSurface/updateComponents"
                    )
            blocks = re.findall(r"```a2ui\s*\n(.*?)```", text, re.S)
            if not blocks:
                errors.append(f"{path}: no fenced a2ui blocks found")
            for i, b in enumerate(blocks, 1):
                name = f"{path}#block{i}"
                nerr, nwarn = len(errors), len(warnings)
                validate_payload(name, b.splitlines(), errors, warnings)
                if len(errors) == nerr:
                    ok.append(name)
        else:
            lines = text.splitlines()
            name = path
            nerr = len(errors)
            validate_payload(name, lines, errors, warnings)
            if len(errors) == nerr:
                ok.append(name)

    for w in warnings:
        print(f"WARN  {w}")
    for e in errors:
        print(f"ERROR {e}")
    for o in ok:
        print(f"OK    {o}")
    print(f"--- {len(ok)} payload(s) valid, {len(warnings)} warning(s), {len(errors)} error(s)")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
