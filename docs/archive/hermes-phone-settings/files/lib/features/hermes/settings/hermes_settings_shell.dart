import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../desktop/shell/desktop_nav_scope.dart';
import '../views/hermes_settings_page.dart';
import '../widgets/hermez_chat_palette.dart';
import 'hermes_settings_categories.dart';
import 'pages/hermes_advanced_config_page.dart';
import 'pages/hermes_models_providers_page.dart';
import 'pages/hermes_tools_extensions_page.dart';
import 'widgets/hermes_bot_scope_chip.dart';

/// The desktop settings page: categories on the left, the chosen category's
/// details on the right, with the "Applies to" bot chip in the detail header.
///
/// The phone shows the same categories as entries in its own Hermes settings
/// list instead; each pushes a [HermesSettingsCategoryPage].
class HermesSettingsShell extends ConsumerStatefulWidget {
  const HermesSettingsShell({
    super.key,
    this.initial = HermesSettingsCategory.connection,
  });

  final HermesSettingsCategory initial;

  @override
  ConsumerState<HermesSettingsShell> createState() =>
      _HermesSettingsShellState();
}

class _HermesSettingsShellState extends ConsumerState<HermesSettingsShell> {
  late HermesSettingsCategory _category = widget.initial;
  bool _root = false;
  bool _dirty = false;

  @override
  void didUpdateWidget(covariant HermesSettingsShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initial != widget.initial) _category = widget.initial;
  }

  Future<void> _select(HermesSettingsCategory next) async {
    if (next == _category) return;
    if (_dirty && !await confirmDiscardHermesSettings(context)) return;
    if (!mounted) return;
    setState(() {
      _category = next;
      _dirty = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final palette = HermezChatPalette.forBrightness(
      Theme.of(context).brightness,
    );
    final leading = desktopNavMenuLeading(context);
    return Material(
      color: palette.canvas,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 24, 8),
              child: Row(
                children: [
                  ?leading,
                  const SizedBox(width: 8),
                  Text(
                    'Settings',
                    style: TextStyle(
                      color: palette.ink,
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    width: 264,
                    child: _CategoryList(
                      selected: _category,
                      onSelected: _select,
                    ),
                  ),
                  VerticalDivider(width: 1, color: palette.border),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _DetailHeader(
                          category: _category,
                          root: _root,
                          onRootChanged: (value) =>
                              setState(() => _root = value),
                        ),
                        Expanded(
                          child: KeyedSubtree(
                            key: ValueKey<String>(
                              'hermes-settings-detail-${_category.slug}',
                            ),
                            child: HermesSettingsCategoryBody(
                              category: _category,
                              root: _root,
                              embeddedConnection: true,
                              onDirtyChanged: (dirty) => _dirty = dirty,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CategoryList extends StatelessWidget {
  const _CategoryList({required this.selected, required this.onSelected});

  final HermesSettingsCategory selected;
  final ValueChanged<HermesSettingsCategory> onSelected;

  @override
  Widget build(BuildContext context) {
    final palette = HermezChatPalette.forBrightness(
      Theme.of(context).brightness,
    );
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
      children: [
        for (final category in HermesSettingsCategory.values)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                key: ValueKey<String>(
                  'hermes-settings-category-${category.slug}',
                ),
                borderRadius: BorderRadius.circular(12),
                onTap: () => onSelected(category),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    color: category == selected ? palette.surface : null,
                    border: Border.all(
                      color: category == selected
                          ? palette.border
                          : Colors.transparent,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(category.icon, size: 20, color: palette.ink),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          category.label,
                          style: TextStyle(
                            color: palette.ink,
                            fontWeight: category == selected
                                ? FontWeight.w700
                                : FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _DetailHeader extends StatelessWidget {
  const _DetailHeader({
    required this.category,
    required this.root,
    required this.onRootChanged,
  });

  final HermesSettingsCategory category;
  final bool root;
  final ValueChanged<bool> onRootChanged;

  @override
  Widget build(BuildContext context) {
    final palette = HermezChatPalette.forBrightness(
      Theme.of(context).brightness,
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  category.label,
                  style: TextStyle(
                    color: palette.ink,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  category.subtitle,
                  style: TextStyle(color: palette.muted, fontSize: 13),
                ),
              ],
            ),
          ),
          if (category.isBotScoped)
            HermesBotScopeChip(
              allowRoot: category.allowsRoot,
              root: root,
              onRootChanged: onRootChanged,
            ),
        ],
      ),
    );
  }
}

/// The body of one settings category, shared by the desktop shell and the
/// phone's pushed pages.
class HermesSettingsCategoryBody extends ConsumerWidget {
  const HermesSettingsCategoryBody({
    super.key,
    required this.category,
    this.root = false,
    this.embeddedConnection = false,
    this.onDirtyChanged,
  });

  final HermesSettingsCategory category;
  final bool root;
  final bool embeddedConnection;
  final ValueChanged<bool>? onDirtyChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scope = ref.watch(hermesResolvedSettingsScopeProvider);
    return switch (category) {
      HermesSettingsCategory.connection => HermesSettingsPage(
        embedded: embeddedConnection,
      ),
      HermesSettingsCategory.tools => HermesToolsExtensionsPage(
        key: ValueKey<String>('tools-$scope'),
        scope: scope,
        showTitle: false,
      ),
      HermesSettingsCategory.models => HermesModelsProvidersPage(
        key: ValueKey<String>('models-$scope'),
        scope: scope,
      ),
      HermesSettingsCategory.advanced => HermesAdvancedConfigPage(
        key: ValueKey<String>('advanced-${root ? '~root' : scope}'),
        scope: root ? null : scope,
        onDirtyChanged: onDirtyChanged,
      ),
    };
  }
}

/// A phone page for one bot-scoped category, pushed from the Hermes settings
/// list: a title bar, the "Applies to" row, then the category itself.
class HermesSettingsCategoryPage extends ConsumerStatefulWidget {
  const HermesSettingsCategoryPage({super.key, required this.category});

  final HermesSettingsCategory category;

  @override
  ConsumerState<HermesSettingsCategoryPage> createState() =>
      _HermesSettingsCategoryPageState();
}

class _HermesSettingsCategoryPageState
    extends ConsumerState<HermesSettingsCategoryPage> {
  bool _root = false;
  bool _dirty = false;

  @override
  Widget build(BuildContext context) {
    final category = widget.category;
    final palette = HermezChatPalette.forBrightness(
      Theme.of(context).brightness,
    );
    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final navigator = Navigator.of(context);
        if (await confirmDiscardHermesSettings(context) && mounted) {
          setState(() => _dirty = false);
          navigator.pop();
        }
      },
      child: Scaffold(
        backgroundColor: palette.canvas,
        appBar: AppBar(
          backgroundColor: palette.canvas,
          title: Text(category.label),
        ),
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (category.isBotScoped)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: HermesBotScopeChip(
                    allowRoot: category.allowsRoot,
                    root: _root,
                    onRootChanged: (value) => setState(() => _root = value),
                  ),
                ),
              ),
            Expanded(
              child: HermesSettingsCategoryBody(
                category: category,
                root: _root,
                onDirtyChanged: (dirty) {
                  if (dirty != _dirty) setState(() => _dirty = dirty);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Asks before leaving unsaved config edits behind.
Future<bool> confirmDiscardHermesSettings(BuildContext context) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Discard unsaved changes?'),
      content: const Text('Your config edits haven\'t been saved.'),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Keep editing'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Discard'),
        ),
      ],
    ),
  );
  return result ?? false;
}
