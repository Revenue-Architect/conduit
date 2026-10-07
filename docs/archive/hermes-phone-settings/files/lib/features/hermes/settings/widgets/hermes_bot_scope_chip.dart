import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../admin/hermes_admin_models.dart';
import '../../admin/hermes_admin_providers.dart';
import '../../widgets/hermez_chat_palette.dart';
import '../hermes_settings_categories.dart';

/// The "Applies to" control: which bot the settings below act on.
///
/// [allowRoot] adds "Server (root)" for the advanced config editor; [root]
/// says whether it is the current choice there. Picking a bot sets the
/// remembered scope for every bot-scoped page.
class HermesBotScopeChip extends ConsumerWidget {
  const HermesBotScopeChip({
    super.key,
    this.allowRoot = false,
    this.root = false,
    this.onRootChanged,
  });

  final bool allowRoot;
  final bool root;
  final ValueChanged<bool>? onRootChanged;

  static const rootValue = '\u0000root';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = HermezChatPalette.forBrightness(
      Theme.of(context).brightness,
    );
    final scope = ref.watch(hermesResolvedSettingsScopeProvider);
    final profiles =
        ref.watch(hermesAdminProfilesProvider).value ??
        const <HermesAdminProfile>[];
    final showingRoot = allowRoot && root;
    final current = showingRoot ? 'Server (root)' : _labelFor(scope, profiles);

    return PopupMenuButton<String>(
      key: const ValueKey<String>('hermes-bot-scope-chip'),
      tooltip: 'Choose which bot these settings apply to',
      onSelected: (value) {
        if (value == rootValue) {
          onRootChanged?.call(true);
          return;
        }
        onRootChanged?.call(false);
        ref.read(hermesSettingsScopeProvider.notifier).select(value);
      },
      itemBuilder: (context) => [
        for (final profile in profiles)
          CheckedPopupMenuItem<String>(
            value: profile.name,
            checked: !showingRoot && profile.name == scope,
            child: Text(_labelFor(profile.name, profiles)),
          ),
        if (profiles.isEmpty)
          CheckedPopupMenuItem<String>(
            value: scope,
            checked: !showingRoot,
            child: Text(scope),
          ),
        if (allowRoot) ...[
          const PopupMenuDivider(),
          CheckedPopupMenuItem<String>(
            value: rootValue,
            checked: showingRoot,
            child: const Text('Server (root)'),
          ),
        ],
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: palette.surface,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: palette.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Applies to ',
              style: TextStyle(color: palette.muted, fontSize: 13),
            ),
            Flexible(
              child: Text(
                current,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: palette.ink,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 4),
            Icon(Icons.expand_more_rounded, size: 18, color: palette.muted),
          ],
        ),
      ),
    );
  }

  static String _labelFor(String name, List<HermesAdminProfile> profiles) {
    for (final profile in profiles) {
      if (profile.name == name) {
        return profile.displayName.isNotEmpty ? profile.displayName : name;
      }
    }
    return name;
  }
}
