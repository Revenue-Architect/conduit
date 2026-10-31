import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Pop-up layers the redesign replaces with the one card
/// (docs/app-design-2026-10-30, "One card"; SPEC.md phase 6).
final _popUp = RegExp(
  r'\b(showDialog|showModalBottomSheet|PopupMenuButton|DropdownButton|AlertDialog|showCupertino\w*)\b',
);

/// Uses that existed on 2026-10-30, per file. Moving one onto the card
/// lowers its count here; a count may only go down.
const _allowed = <String, int>{
  'lib/core/error/enhanced_error_service.dart': 1,
  'lib/core/services/enhanced_accessibility_service.dart': 1,
  'lib/core/services/platform_service.dart': 1,
  'lib/core/services/user_friendly_error_handler.dart': 1,
  'lib/features/hermes/widgets/hermez_bot_icons.dart': 1,
  'lib/features/prompts/widgets/prompt_variable_dialog.dart': 1,
  'lib/features/push/views/approval_widgets.dart': 2,
  'lib/features/push/views/push_settings_section.dart': 4,
  'lib/features/spaces/views/space_library_page.dart': 1,
  'lib/features/spaces/views/space_page_editor.dart': 1,
  'lib/shared/widgets/conduit_dialog_route.dart': 3,
  'lib/shared/widgets/markdown/citation_badge.dart': 1,
  'lib/shared/widgets/platform_ui/src/adaptive_controls.dart': 1,
  'lib/shared/widgets/platform_ui/src/adaptive_feedback.dart': 4,
  'lib/shared/widgets/themed_dialogs.dart': 6,
  'lib/shared/widgets/themed_sheets.dart': 3,
};

void main() {
  // The rule: no new pop-up layers. Menus, dialogs, sheets and dropdowns
  // are one card that grows out of what was pressed.
  test('no file adds a pop-up layer outside the one card', () {
    final grown = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final path = entity.path.replaceAll(Platform.pathSeparator, '/');
      if (path.endsWith('.g.dart') || path.endsWith('.freezed.dart')) continue;
      final uses = _popUp.allMatches(entity.readAsStringSync()).length;
      final allowed = _allowed[path] ?? 0;
      if (uses > allowed) grown.add('$path: $uses (allowed $allowed)');
    }
    expect(grown, isEmpty, reason: 'Use HermezCardStack in a one-card panel.');
  });
}
