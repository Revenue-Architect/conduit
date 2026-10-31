import 'package:material_ui/material_ui.dart';

import '../../../shared/theme/theme_extensions.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:conduit/l10n/app_localizations.dart';

import '../../../shared/widgets/conduit_loading.dart';

import '../../../shared/utils/ui_utils.dart';
import '../../../shared/utils/external_link_launcher.dart';
import '../../../shared/widgets/sign_out_options_dialog.dart';
import '../../../core/models/model.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/providers/backend_mode_providers.dart';
import '../../../core/services/navigation_service.dart';
import '../../../core/services/settings_service.dart';
import '../../auth/providers/unified_auth_providers.dart';
import '../../direct_connections/providers/direct_connection_providers.dart';
import '../../hermes/models/hermes_bot.dart';
import '../../hermes/providers/hermes_providers.dart';
import '../../hermes/sky/hermez_weather.dart' show kHermezCity;
import '../../hermes/widgets/hermez_chat_palette.dart';
import '../../workspace/providers/workspace_capabilities_provider.dart';
import '../../../core/services/api_service.dart';
import '../../../core/models/user.dart' as models;
import '../../../core/utils/user_display_name.dart';
import '../../../core/utils/user_avatar_utils.dart';
import '../../../shared/widgets/user_avatar.dart';
import '../widgets/settings_sky_page.dart';
import 'personalization_page.dart' show hasOpenRouterImageModel;

/// All settings (docs/app-design-2026-10-30, s01): every setting in one
/// page, grouped by what you are doing (your team, chatting, this app,
/// servers, about) rather than by who built it.
class ProfilePage extends ConsumerWidget {
  static const _githubSponsorsUrl = 'https://github.com/sponsors/cogwheel0';
  static const _buyMeACoffeeUrl = 'https://www.buymeacoffee.com/cogwheel0';

  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authUser = ref.watch(currentUserProvider2);
    final asyncUser = ref.watch(currentUserProvider);
    final user = asyncUser.maybeWhen(
      data: (value) => value ?? authUser,
      orElse: () => authUser,
    );
    final isAuthLoading = ref.watch(isAuthLoadingProvider2);
    final api = ref.watch(apiServiceProvider);
    final l10n = AppLocalizations.of(context)!;

    if (isAuthLoading && user == null) {
      return SettingsSkyPage(
        title: 'All settings',
        children: [
          Padding(
            padding: const EdgeInsets.all(Spacing.xl),
            child: Center(
              child: ImprovedLoadingState(message: l10n.loadingProfile),
            ),
          ),
        ],
      );
    }
    final directPrimary =
        ref.watch(preferredBackendProvider) == PreferredBackend.direct;
    final hasOpenWebUiAccount = user != null && api != null;
    final name = hasOpenWebUiAccount
        ? deriveUserDisplayName(user, fallback: l10n.userFallbackName)
        : null;
    return SettingsSkyPage(
      title: 'All settings',
      lede: name == null ? kHermezCity : '$name · $kHermezCity',
      children: [
        if (hasOpenWebUiAccount)
          SettingsGroup(
            first: true,
            children: [_buildProfileHeader(context, user, api)],
          ),
        ..._buildSettingsItems(
          context,
          ref,
          directPrimary: directPrimary,
          hasOpenWebUiAccount: hasOpenWebUiAccount,
        ),
        _buildDonationSection(context),
        if (hasOpenWebUiAccount)
          SettingsGroup(children: [_buildSignOutOption(context, ref)]),
      ],
    );
  }

  Widget _buildDonationSection(BuildContext context) {
    return SettingsGroup(
      key: const Key('settings-donations'),
      title: 'Support Conduit',
      note: 'Conduit stays independent when its users fund it.',
      children: [
        SettingsRow(
          leading: const SettingsGlyph(icon: Icons.card_giftcard_outlined),
          title: 'Buy me a coffee',
          sub: 'A one-time thank you',
          chevron: Icons.north_east_rounded,
          onTap: () => _openExternalLink(context, _buyMeACoffeeUrl),
        ),
        SettingsRow(
          leading: const SettingsGlyph(icon: Icons.favorite_border),
          title: 'GitHub Sponsors',
          sub: 'Recurring support for the roadmap',
          chevron: Icons.north_east_rounded,
          onTap: () => _openExternalLink(context, _githubSponsorsUrl),
        ),
      ],
    );
  }

  Future<void> _openExternalLink(BuildContext context, String url) async {
    final launched = await launchExternalLink(url, scope: 'profile/support');
    if (!launched && context.mounted) {
      UiUtils.showMessage(context, AppLocalizations.of(context)!.errorMessage);
    }
  }

  Widget _buildProfileHeader(
    BuildContext context,
    dynamic user,
    ApiService? api,
  ) {
    final l10n = AppLocalizations.of(context)!;
    final displayName = deriveUserDisplayName(
      user,
      fallback: l10n.userFallbackName,
    );
    final characters = displayName.characters;
    final initial = characters.isNotEmpty
        ? characters.first.toUpperCase()
        : 'U';
    final avatarUrl = resolveUserAvatarUrlForUser(api, user);

    String? extractEmail(dynamic source) {
      if (source is models.User) {
        return source.email;
      }
      if (source is Map) {
        final value = source['email'];
        if (value is String && value.trim().isNotEmpty) {
          return value.trim();
        }
        final nested = source['user'];
        if (nested is Map) {
          final nestedValue = nested['email'];
          if (nestedValue is String && nestedValue.trim().isNotEmpty) {
            return nestedValue.trim();
          }
        }
      }
      return null;
    }

    final email = extractEmail(user) ?? l10n.noEmailLabel;
    return SettingsRow(
      onTap: () => context.pushNamed(RouteNames.accountSettings),
      leading: UserAvatar(size: 52, imageUrl: avatarUrl, fallbackText: initial),
      title: displayName,
      sub: email,
      minHeight: 64,
    );
  }

  List<Widget> _buildSettingsItems(
    BuildContext context,
    WidgetRef ref, {
    required bool directPrimary,
    required bool hasOpenWebUiAccount,
  }) {
    final l10n = AppLocalizations.of(context)!;
    final canManageWorkspace = canManageAnyWorkspaceSection(ref);
    final defaultModelId = ref.watch(
      appSettingsProvider.select((s) => s.defaultModel),
    );
    final allModels = ref.watch(modelsProvider).value ?? const <Model>[];
    final bots = ref.watch(hermesBotsProvider).value ?? const <HermesBot>[];
    final directCount =
        ref.watch(directConnectionProfilesProvider).value?.length ?? 0;
    final buildNumber = ref.watch(packageInfoProvider).value?.buildNumber ?? '';
    final themeMode = ref.watch(appThemeModeProvider);
    // The default model's name, so the row shows what a new chat starts on.
    final defaultModel = defaultModelId == null
        ? null
        : allModels
                  .where((m) => m.id == defaultModelId)
                  .map((m) => m.name)
                  .firstOrNull ??
              defaultModelId;
    // Personalization holds the image model, your prompt and memories; with
    // only direct connections it has something only for an image model.
    final showPersonalization =
        hasOpenWebUiAccount ||
        (directPrimary && hasOpenRouterImageModel(allModels));

    return [
      SettingsGroup(
        title: 'Your team',
        children: [
          SettingsRow(
            leading: const SettingsGlyphShell(child: _HermesLogo()),
            title: 'Hermes Agent',
            sub: bots.isEmpty
                ? 'Self-hosted agent'
                : 'Connected to your Umbrel · ${bots.length} bots',
            onTap: () => context.pushNamed(RouteNames.hermesSettings),
          ),
          SettingsRow(
            leading: const SettingsGlyph(icon: Icons.notifications_none),
            title: l10n.notificationsTitle,
            sub: 'Banners, alerts and push from your team',
            onTap: () => context.pushNamed(RouteNames.notificationSettings),
          ),
        ],
      ),
      SettingsGroup(
        title: 'Chatting',
        children: [
          SettingsRow(
            leading: const SettingsGlyph(icon: Icons.chat_bubble_outline),
            title: l10n.chatSettings,
            sub: 'Model, quick actions, sending',
            value: defaultModel,
            onTap: () => context.pushNamed(RouteNames.chatSettings),
          ),
          if (showPersonalization)
            SettingsRow(
              leading: const SettingsGlyph(icon: Icons.menu_book_outlined),
              title: l10n.personalization,
              sub: 'Your prompt and server memory',
              onTap: () => context.pushNamed(RouteNames.personalization),
            ),
          SettingsRow(
            leading: const SettingsGlyph(icon: Icons.graphic_eq),
            title: l10n.audioSettingsTitle,
            sub: 'Dictation and spoken answers',
            onTap: () => context.pushNamed(RouteNames.audioSettings),
          ),
        ],
      ),
      SettingsGroup(
        title: 'This app',
        children: [
          SettingsRow(
            leading: const SettingsGlyph(icon: Icons.contrast),
            title: l10n.settingsAppearance,
            sub: 'Theme, accent and language',
            value: switch (themeMode) {
              ThemeMode.system => l10n.system,
              ThemeMode.light => l10n.themeLight,
              ThemeMode.dark => l10n.themeDark,
            },
            onTap: () => context.pushNamed(RouteNames.appearanceSettings),
          ),
        ],
      ),
      SettingsGroup(
        title: 'Servers',
        children: [
          if (kShowOpenWebUi && !hasOpenWebUiAccount)
            SettingsRow(
              leading: const SettingsGlyph(icon: Icons.add_circle_outline),
              title: 'Connect to Open WebUI',
              sub: 'Add a self-hosted Open WebUI server',
              onTap: () => context.goNamed(RouteNames.serverConnection),
            ),
          if (kShowOpenWebUi && hasOpenWebUiAccount)
            SettingsRow(
              key: const Key('data-connection-entry'),
              leading: const SettingsGlyph(icon: Icons.sensors),
              title: 'Open WebUI connection',
              sub: l10n.connectionHealth,
              onTap: () => context.pushNamed(RouteNames.dataConnectionSettings),
            ),
          if (kShowOpenWebUi && canManageWorkspace)
            SettingsRow(
              key: const Key('workspace-entry'),
              leading: const SettingsGlyph(icon: Icons.grid_view_outlined),
              title: l10n.workspaceTitle,
              sub: 'Models, tools and access on the server',
              onTap: () => context.pushNamed(RouteNames.workspace),
            ),
          SettingsRow(
            leading: const SettingsGlyph(icon: Icons.power_outlined),
            title: 'Direct connections',
            sub: l10n.directConnectionsSubtitle,
            value: directCount > 0 ? '$directCount' : null,
            onTap: () => context.pushNamed(RouteNames.directConnections),
          ),
        ],
      ),
      SettingsGroup(
        title: 'About Conduit',
        children: [
          SettingsRow(
            leading: const SettingsGlyph(icon: Icons.info_outline),
            title: l10n.aboutApp,
            sub: buildNumber.isEmpty
                ? l10n.aboutAppSubtitle
                : 'Build $buildNumber · what’s new and licences',
            onTap: () => context.pushNamed(RouteNames.about),
          ),
        ],
      ),
    ];
  }

  Widget _buildSignOutOption(BuildContext context, WidgetRef ref) {
    return SettingsRow(
      key: const Key('settings-sign-out'),
      leading: SettingsGlyph(
        icon: Icons.logout,
        color: HermezChatPalette.forBrightness(Theme.of(context).brightness)
            .failed,
      ),
      title: AppLocalizations.of(context)!.signOut,
      sub: 'End your Open WebUI session',
      chevron: null,
      destructive: true,
      onTap: () => _signOut(context, ref),
    );
  }

  void _signOut(BuildContext context, WidgetRef ref) async {
    final keepServerDetails = await showSignOutOptionsDialog(context);

    if (!context.mounted || keepServerDetails == null) return;
    try {
      await ref
          .read(signOutCoordinatorProvider)
          .signOut(keepServerDetails: keepServerDetails);
    } catch (_) {
      if (!context.mounted) return;
      UiUtils.showMessage(context, AppLocalizations.of(context)!.errorMessage);
    }
  }
}

/// The Hermes mark, tinted like the other glyphs.
class _HermesLogo extends StatelessWidget {
  const _HermesLogo();

  @override
  Widget build(BuildContext context) => Image.asset(
    'assets/icons/hermes_agent.png',
    key: const Key('hermes-settings-logo'),
    width: 24,
    height: 24,
    color: HermezChatPalette.forBrightness(Theme.of(context).brightness).muted,
    colorBlendMode: BlendMode.srcIn,
    filterQuality: FilterQuality.high,
  );
}
