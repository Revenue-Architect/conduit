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

KNOWN = {
    "Text", "Image", "Icon", "Video", "AudioPlayer", "Row", "Column", "List", "Card",
    "Tabs", "Modal", "Divider", "Button", "TextField", "CheckBox", "ChoicePicker",
    "Slider", "DateTimeInput",
    # Conduit app components
    "StatusBadge", "MetricTile", "MiniChart",
}

# Keep in sync with _stackInRowComponentTypes in Conduit's read-time normalizer.
# These supported component types need a bounded, allocated share of horizontal
# space when placed directly in a Row. MetricTile-only rows remain comparable
# when each tile has a positive weight; otherwise the client repairs old data.
ROW_WIDTH_DEPENDENT = {
    "MetricTile", "MiniChart", "StatusBadge", "Slider", "TextField",
    "ChoicePicker", "DateTimeInput", "Card", "Column", "Row", "List", "Tabs",
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
}

ENUMS = {
    "StatusBadge": {"state": {"ok", "warning", "error", "unknown"}},
    "MiniChart": {"kind": {"line", "bar"}},
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
            if not isinstance(act, dict) or "event" not in act or "functionCall" in act:
                errors.append(f"{name}: Button {cid!r} action must contain only an 'event'")
            elif "event" in act:
                ev = act.get("event")
                if not isinstance(ev, dict) or not ev.get("name"):
                    errors.append(f"{name}: Button {cid!r} event missing 'name'")
                elif "context" in ev and not isinstance(ev["context"], dict):
                    errors.append(f"{name}: Button {cid!r} event context must be an object")
        if ctype == "Tabs":
            tabs = c.get("tabs")
            if not isinstance(tabs, list) or not tabs:
                errors.append(f"{name}: Tabs {cid!r} needs a non-empty tabs array")
            else:
                for t in tabs:
                    if not isinstance(t, dict) or not t.get("title") or not t.get("child"):
                        errors.append(f"{name}: Tabs {cid!r} entries need 'title' and 'child'")
                    elif t["child"] not in by_id:
                        errors.append(f"{name}: Tabs {cid!r} child {t['child']!r} not found")
        if ctype == "Modal":
            for k in ("trigger", "content"):
                if not isinstance(c.get(k), str) or c[k] not in by_id:
                    errors.append(f"{name}: Modal {cid!r} {k} {c.get(k)!r} not found")

        refs = []
        if isinstance(c.get("child"), str):
            refs.append(c["child"])
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
                if isinstance(tab, dict) and tab.get("child") in by_id:
                    parents.setdefault(tab["child"], []).append(cid)
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
            if isinstance(c.get("children"), list):
                stack.extend([x for x in c["children"] if isinstance(x, str)])
            if isinstance(c.get("tabs"), list):
                for t in c["tabs"]:
                    if isinstance(t, dict) and isinstance(t.get("child"), str):
                        stack.append(t["child"])
            for k in ("trigger", "content"):
                if isinstance(c.get(k), str):
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
