import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Every way to open a pop-up layer that isn't the one card
/// (docs/app-design-2026-10-30/POPUPS-PLAN.md, all 81 surfaces): Flutter's
/// own dialogs, sheets, menus and dropdowns, and the app wrappers that still
/// open one on Android. The card's own entry points (pushHermezCard,
/// pushHermezFullCard, showHermezSelectCard, showHermezDialog, the
/// ThemedDialogs helpers, AdaptivePopupMenuButton, pushHermezSheetRoute) are
/// what new code uses instead.
final _popUp = RegExp(
  r'\b(?:showDialog|showGeneralDialog|showModalBottomSheet|showBottomSheet|showMenu|PopupMenuButton|DropdownButton|DropdownMenu|AlertDialog|SimpleDialog|showCupertino\w*|CupertinoAlertDialog|CupertinoActionSheet|showConduitDialog|ThemedSheets\.(?:showCustom|showRoundedPage|showAdaptive))\b',
);
final _comment = RegExp(r'//.*$', multiLine: true);

/// Uses left, per file: a ratchet. A file may not add one, and once one is
/// moved onto the card its ceiling here must come down with it, so the
/// total can only go down. iOS paths (showCupertino*) stay native on purpose.
const _ceiling = <String, int>{
  'lib/core/services/platform_service.dart': 2,
  'lib/features/channels/views/channel_page.dart': 1,
  'lib/features/chat/views/chat_page.dart': 3,
  'lib/features/chat/widgets/chat_share_sheet.dart': 1,
  'lib/features/chat/widgets/modern_chat_input.dart': 2,
  'lib/features/direct_connections/views/direct_mcp_content_sheet.dart': 1,
  'lib/features/hermes/motion/hermez_dialog_card.dart': 2,
  'lib/features/navigation/views/folder_page.dart': 5,
  'lib/features/profile/views/personalization_page.dart': 1,
  'lib/features/release_notes/release_notes_presenter.dart': 1,
  'lib/features/workspace/views/knowledge/workspace_knowledge_file_browser.dart': 1,
  'lib/features/workspace/views/models/workspace_model_relationship_sheet.dart': 1,
  'lib/features/workspace/views/prompts/workspace_prompt_history.dart': 1,
  'lib/features/workspace/widgets/workspace_access_grants.dart': 2,
  'lib/features/workspace/widgets/workspace_import_sheet.dart': 1,
  'lib/features/workspace/widgets/workspace_tool_url_import_sheet.dart': 1,
  'lib/features/workspace/widgets/workspace_tool_valves_sheet.dart': 1,
  'lib/shared/widgets/adaptive_selection_sheet.dart': 1,
  'lib/shared/widgets/conduit_dialog_route.dart': 1,
  'lib/shared/widgets/markdown/markdown_config.dart': 2,
  'lib/shared/widgets/markdown/renderer/details_block_widget.dart': 1,
  'lib/shared/widgets/platform_ui/src/adaptive_controls.dart': 2,
  'lib/shared/widgets/platform_ui/src/adaptive_feedback.dart': 4,
  'lib/shared/widgets/themed_sheets.dart': 3,
};

/// The sum of [_ceiling]; lower it with the file entries.
const _total = 41;

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
