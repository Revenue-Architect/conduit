import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/persistence/persistence_keys.dart';
import '../../../core/persistence/preferences_store.dart';
import '../admin/hermes_admin_providers.dart';

/// The Hermes settings categories, in the order the settings list shows them.
///
/// Connection & app is today's Hermes settings page. The others are the
/// per-bot pages; Bots joins the list once the bot screen exists.
enum HermesSettingsCategory {
  connection(
    slug: 'connection',
    label: 'Connection & app',
    subtitle: 'Server, sign-in, notifications and sounds',
    icon: Icons.settings_ethernet_rounded,
  ),
  tools(
    slug: 'tools',
    label: 'Tools & extensions',
    subtitle: 'Toolsets, skills, MCP servers and plugins',
    icon: Icons.extension_outlined,
  ),
  models(
    slug: 'models',
    label: 'Models & providers',
    subtitle: 'Default model, fallbacks, reasoning and API keys',
    icon: Icons.memory_rounded,
  ),
  advanced(
    slug: 'advanced',
    label: 'Advanced config',
    subtitle: 'Edit config.yaml for a bot or the server',
    icon: Icons.data_object_rounded,
  );

  const HermesSettingsCategory({
    required this.slug,
    required this.label,
    required this.subtitle,
    required this.icon,
  });

  final String slug;
  final String label;
  final String subtitle;
  final IconData icon;

  /// Whether the "Applies to" scope picks a bot for this category.
  bool get isBotScoped => this != connection;

  /// Only the advanced config editor can act on the server root.
  bool get allowsRoot => this == advanced;

  static HermesSettingsCategory? fromSlug(String? slug) {
    for (final category in values) {
      if (category.slug == slug) return category;
    }
    return null;
  }
}

/// The bot every bot-scoped settings page applies to.
///
/// Remembered across launches. Hermes' own `default` profile is the
/// fallback, both on first run and when the remembered bot has gone.
class HermesSettingsScopeNotifier extends Notifier<String> {
  static const fallback = 'default';

  @override
  String build() {
    final saved = PreferencesStore.getString(
      PreferenceKeys.hermesSettingsScope,
    );
    return saved == null || saved.isEmpty ? fallback : saved;
  }

  void select(String bot) {
    if (bot.isEmpty || bot == state) return;
    state = bot;
    PreferencesStore.put(PreferenceKeys.hermesSettingsScope, bot);
  }

  /// Back to [fallback], when the remembered bot was deleted.
  void reset() {
    state = fallback;
    PreferencesStore.put(PreferenceKeys.hermesSettingsScope, null);
  }
}

final hermesSettingsScopeProvider =
    NotifierProvider<HermesSettingsScopeNotifier, String>(
      HermesSettingsScopeNotifier.new,
    );

/// The remembered scope, checked against the bots Hermes has now.
///
/// While the bot list is loading, or when it can't load, the remembered
/// scope stands; once it has loaded, a bot that no longer exists falls back
/// to `default`.
final hermesResolvedSettingsScopeProvider = Provider.autoDispose<String>((ref) {
  final scope = ref.watch(hermesSettingsScopeProvider);
  final profiles = ref.watch(hermesAdminProfilesProvider).value;
  if (profiles == null || profiles.isEmpty) return scope;
  if (profiles.any((profile) => profile.name == scope)) return scope;
  return HermesSettingsScopeNotifier.fallback;
});
