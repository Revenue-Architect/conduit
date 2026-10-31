import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Every way to open a pop-up layer that isn't the one card
/// (docs/app-design-2026-10-30/POPUPS-PLAN.md, all 81 surfaces): Flutter's
/// own dialogs, sheets, menus and dropdowns, and the app wrappers that still
/// open one on Android. The card's own entry points (pushHermezCard,
/// pushHermezFullCard, showHermezSelectCard, showHermezDialog, the
/// ThemedDialogs and ThemedSheets helpers, AdaptivePopupMenuButton,
/// pushHermezSheetRoute) are what new code uses instead.
final _popUp = RegExp(
  r'\b(?:showDialog|showGeneralDialog|showModalBottomSheet|showBottomSheet|showMenu|PopupMenuButton|DropdownButton|DropdownMenu|AlertDialog|SimpleDialog|showCupertino\w*|CupertinoAlertDialog|CupertinoActionSheet|showConduitDialog)\b',
);
final _comment = RegExp(r'//.*$', multiLine: true);

/// Uses left, per file: a ratchet. A file may not add one, and once one is
/// moved onto the card its ceiling here must come down with it, so the
/// total can only go down. iOS paths (showCupertino*) stay native on purpose.
const _ceiling = <String, int>{
  'lib/core/services/platform_service.dart': 2,
  'lib/features/hermes/motion/hermez_dialog_card.dart': 2,
  'lib/shared/widgets/conduit_dialog_route.dart': 1,
  'lib/shared/widgets/platform_ui/src/adaptive_controls.dart': 2,
  'lib/shared/widgets/platform_ui/src/adaptive_feedback.dart': 4,
  'lib/shared/widgets/themed_sheets.dart': 3,
};

/// The sum of [_ceiling]; lower it with the file entries.
const _total = 14;

void main() {
  // The rule: no new pop-up layers. Menus, dialogs, sheets and pickers are
  // one card that grows out of what was pressed.
  test('pop-up layers outside the one card only ever go down', () {
    final wrong = <String>[];
    final seen = <String>{};
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final path = entity.path.replaceAll(Platform.pathSeparator, '/');
      if (path.endsWith('.g.dart') || path.endsWith('.freezed.dart')) continue;
      final source = entity.readAsStringSync().replaceAll(_comment, '');
      final uses = _popUp.allMatches(source).length;
      final ceiling = _ceiling[path] ?? 0;
      if (uses > 0) seen.add(path);
      if (uses > ceiling) {
        wrong.add('$path: $uses pop-up layers (ceiling $ceiling). Use the card.');
      } else if (uses < ceiling) {
        wrong.add('$path: $uses left; lower its ceiling to $uses.');
      }
    }
    for (final path in _ceiling.keys) {
      if (!seen.contains(path)) wrong.add('$path: none left; remove its entry.');
    }
    expect(wrong, isEmpty);
    expect(_ceiling.values.fold<int>(0, (a, b) => a + b), _total);
  });
}
