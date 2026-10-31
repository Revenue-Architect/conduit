"""Generates test/features/hermes/hermez_no_new_popups_test.dart.

Counts every way to open a pop-up layer that isn't the one card, per file,
ignoring // comments, and writes them as an exact ceiling (a ratchet).
"""
import os
import re
import sys

root_dir = sys.argv[1]
os.chdir(root_dir)

# Keep in sync with _popUp in the generated test.
NAMES = (
    r"showDialog|showGeneralDialog|showModalBottomSheet|showBottomSheet|showMenu|"
    r"PopupMenuButton|DropdownButton|DropdownMenu|AlertDialog|SimpleDialog|"
    r"showCupertino\w*|CupertinoAlertDialog|CupertinoActionSheet|"
    r"showConduitDialog|"
    r"ThemedSheets\.(?:showCustom|showRoundedPage|showAdaptive)"
)
pat = re.compile(r"\b(?:" + NAMES + r")\b")
comment = re.compile(r"//.*$", re.M)


def uses(text):
    return len(pat.findall(comment.sub("", text)))


counts = {}
for root, _, files in os.walk("lib"):
    for f in files:
        if f.endswith(".dart") and not f.endswith((".g.dart", ".freezed.dart")):
            p = os.path.join(root, f).replace(os.sep, "/")
            n = uses(open(p, encoding="utf-8", errors="ignore").read())
            if n:
                counts[p] = n

entries = "\n".join(f"  '{k}': {v}," for k, v in sorted(counts.items()))
total = sum(counts.values())
names_dart = NAMES.replace("\\", "\\\\").replace("'", "\\'")
test = f"""import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Every way to open a pop-up layer that isn't the one card
/// (docs/app-design-2026-10-30/POPUPS-PLAN.md, all 81 surfaces): Flutter's
/// own dialogs, sheets, menus and dropdowns, and the app wrappers that still
/// open one on Android. The card's own entry points (pushHermezCard,
/// pushHermezFullCard, showHermezSelectCard, showHermezDialog, the
/// ThemedDialogs helpers, AdaptivePopupMenuButton, pushHermezSheetRoute) are
/// what new code uses instead.
final _popUp = RegExp(
  r'\\b(?:{NAMES})\\b',
);
final _comment = RegExp(r'//.*$', multiLine: true);

/// Uses left, per file: a ratchet. A file may not add one, and once one is
/// moved onto the card its ceiling here must come down with it, so the
/// total can only go down. iOS paths (showCupertino*) stay native on purpose.
const _ceiling = <String, int>{{
{entries}
}};

/// The sum of [_ceiling]; lower it with the file entries.
const _total = {total};

void main() {{
  // The rule: no new pop-up layers. Menus, dialogs, sheets and pickers are
  // one card that grows out of what was pressed.
  test('pop-up layers outside the one card only ever go down', () {{
    final wrong = <String>[];
    final seen = <String>{{}};
    for (final entity in Directory('lib').listSync(recursive: true)) {{
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final path = entity.path.replaceAll(Platform.pathSeparator, '/');
      if (path.endsWith('.g.dart') || path.endsWith('.freezed.dart')) continue;
      final source = entity.readAsStringSync().replaceAll(_comment, '');
      final uses = _popUp.allMatches(source).length;
      final ceiling = _ceiling[path] ?? 0;
      if (uses > 0) seen.add(path);
      if (uses > ceiling) {{
        wrong.add('$path: $uses pop-up layers (ceiling $ceiling). Use the card.');
      }} else if (uses < ceiling) {{
        wrong.add('$path: $uses left; lower its ceiling to $uses.');
      }}
    }}
    for (final path in _ceiling.keys) {{
      if (!seen.contains(path)) wrong.add('$path: none left; remove its entry.');
    }}
    expect(wrong, isEmpty);
    expect(_ceiling.values.fold<int>(0, (a, b) => a + b), _total);
  }});
}}
"""
open("test/features/hermes/hermez_no_new_popups_test.dart", "w", encoding="utf-8", newline="\n").write(test)
print(len(counts), "files,", total, "uses")
