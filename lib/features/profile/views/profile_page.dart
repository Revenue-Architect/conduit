import 'package:conduit/shared/widgets/platform_ui/platform_ui.dart';

import 'package:material_ui/material_ui.dart';

import '../../../shared/theme/theme_extensions.dart';

import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:conduit/l10n/app_localizations.dart';

import '../../../shared/widgets/conduit_loading.dart';
import '../../../shared/widgets/adaptive_route_shell.dart';

import '../../../shared/utils/ui_utils.dart';
import '../../../shared/utils/external_link_launcher.dart';
import '../../../shared/widgets/sign_out_options_dialog.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/providers/backend_mode_providers.dart';
import '../../../core/services/navigation_service.dart';
import '../../auth/providers/unified_auth_providers.dart';
import '../../workspace/providers/workspace_capabilities_provider.dart';
import '../../hermes/manga/manga_prefs.dart';
import '../../hermes/manga/manga_theme.dart';
import '../../hermes/manga/manga_widgets.dart';
import '../../hermes/views/hermes_page_chrome.dart' show MangaPageHeader;
import '../../hermes/widgets/hermes_tab_dock.dart' show hermesDockClearance;
import '../../../core/services/api_service.dart';
import '../../../core/models/user.dart' as models;
import '../../../core/utils/user_display_name.dart';
import '../../../core/utils/user_avatar_utils.dart';
import '../../../shared/widgets/user_avatar.dart';
import '../../../shared/widgets/utility_components.dart';

/// Profile page (You tab) showing user info and main actions
/// Enhanced with production-grade design tokens for better cohesion
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
    // Watched here so every row below rebuilds when the layout flips.
    ref.watch(mangaClassicLayoutProvider);
    final api = ref.watch(apiServiceProvider);

    Widget body;
    if (isAuthLoading && user == null) {
      body = _buildCenteredState(
        context,
        ImprovedLoadingState(
          message: AppLocalizations.of(context)!.loadingProfile,
        ),
      );
    } else {
      body = _buildProfileBody(context, ref, user, api);
    }

    return _buildScaffold(context, body: body);
  }

  Widget _buildScaffold(BuildContext context, {required Widget body}) {
    final l10n = AppLocalizations.of(context)!;
    if (mangaLayoutOf(context)) {
      // The manga page: its own title, plain paper, no app bar.
      return Material(
        color: MangaInk.of(context).ground,
        child: SafeArea(
          bottom: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: MangaPageHeader(title: l10n.you, subtitle: ''),
              ),
              Expanded(child: body),
            ],
          ),
        ),
      );
    }

    return AdaptiveRouteShell(
      backgroundColor: context.conduitTheme.surfaceBackground,
      appBar: AdaptiveAppBar(title: l10n.you),
      body: body,
    );
  }

  Widget _buildCenteredState(BuildContext context, Widget child) {
    final topPadding = _topContentPadding(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        Spacing.pagePadding,
        topPadding,
        Spacing.pagePadding,
        Spacing.pagePadding + MediaQuery.of(context).padding.bottom,
      ),
      child: Center(child: child),
    );
  }

  Widget _buildProfileBody(
    BuildContext context,
    WidgetRef ref,
    dynamic userData,
    ApiService? api,
  ) {
    final mediaQuery = MediaQuery.of(context);
    final topPadding = _topContentPadding(context);
    final directPrimary =
        ref.watch(preferredBackendProvider) == PreferredBackend.direct;
    final hasOpenWebUiAccount = userData != null && api != null;
    final items = _buildSettingsItems(
      context,
      ref,
      directPrimary: directPrimary,
      hasOpenWebUiAccount: hasOpenWebUiAccount,
    );
    final manga = mangaLayoutOf(context);
    return ListView(
      physics: const BouncingScrollPhysics(
        parent: AlwaysScrollableScrollPhysics(),
      ),
      padding: EdgeInsets.fromLTRB(
        manga ? 14 : Spacing.pagePadding,
        manga ? 0 : topPadding,
        manga ? 14 : Spacing.pagePadding,
        Spacing.pagePadding +
            mediaQuery.padding.bottom +
            (manga ? hermesDockClearance(context) : 0),
      ),
      children: [
        if (hasOpenWebUiAccount) ...[
          InsetGroupedList(
            children: [_buildProfileHeader(context, userData, api)],
          ),
          const SizedBox(height: Spacing.sm),
        ],
        ...items,
        const SizedBox(height: Spacing.xl),
        _buildDonationSection(context),
        if (hasOpenWebUiAccount) const SizedBox(height: Spacing.xl),
        if (hasOpenWebUiAccount)
          InsetGroupedList(children: [_buildSignOutOption(context, ref)]),
      ],
    );
  }

  double _topContentPadding(BuildContext context) {
    return Spacing.lg;
  }

  Widget _buildDonationSection(BuildContext context) {
    final theme = context.conduitTheme;
    final l10n = AppLocalizations.of(context)!;
    final donationOptions = [
      _buildSupportOption(
        context,
        icon: UiUtils.platformIcon(
          ios: CupertinoIcons.gift,
          android: Icons.coffee,
        ),
        title: l10n.buyMeACoffeeTitle,
        subtitle: l10n.buyMeACoffeeSubtitle,
        url: _buyMeACoffeeUrl,
        color: theme.warning,
      ),
      _buildSupportOption(
        context,
        icon: UiUtils.platformIcon(
          ios: CupertinoIcons.heart,
          android: Icons.favorite_border,
        ),
        title: l10n.githubSponsorsTitle,
        subtitle: l10n.githubSponsorsSubtitle,
        url: _githubSponsorsUrl,
        color: theme.success,
      ),
    ];

    return InsetGroupedList(
      key: const Key('settings-donations'),
      title: l10n.supportConduit,
      description: l10n.supportConduitSubtitle,
      children: donationOptions,
    );
  }

  Widget _buildSupportOption(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required String url,
    required Color color,
  }) {
    final theme = context.conduitTheme;
    return UtilityRow(
      onTap: () => _openExternalLink(context, url),
      leading: _buildIconBadge(context, icon, color: color),
      title: title,
      subtitle: subtitle,
      trailing: Icon(
        UiUtils.platformIcon(
          ios: CupertinoIcons.arrow_up_right,
          android: Icons.open_in_new,
        ),
        color: theme.iconSecondary,
        size: IconSize.small,
      ),
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
    return UtilityRow(
      onTap: () => context.pushNamed(RouteNames.accountSettings),
      leading: UserAvatar(size: 56, imageUrl: avatarUrl, fallbackText: initial),
      title: displayName,
      subtitle: email,
      showChevron: true,
      padding: const EdgeInsets.all(Spacing.md),
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

    final appItems = <Widget>[
      _buildAccountOption(
        context,
        icon: UiUtils.platformIcon(
          ios: CupertinoIcons.paintbrush,
          android: Icons.palette_outlined,
        ),
        title: l10n.settingsAppearance,
        subtitle: l10n.settingsAppearanceSubtitle,
        onTap: () => context.pushNamed(RouteNames.appearanceSettings),
      ),
      _buildAccountOption(
        context,
        icon: UiUtils.platformIcon(
          ios: CupertinoIcons.bubble_left_bubble_right,
          android: Icons.chat_bubble_outline,
        ),
        title: l10n.chatSettings,
        subtitle: l10n.settingsChatSubtitle,
        onTap: () => context.pushNamed(RouteNames.chatSettings),
      ),
      _buildAccountOption(
        context,
        icon: UiUtils.platformIcon(
          ios: CupertinoIcons.waveform,
          android: Icons.graphic_eq,
        ),
        title: l10n.audioSettingsTitle,
        subtitle: l10n.audioSettingsSubtitle,
        onTap: () => context.pushNamed(RouteNames.audioSettings),
      ),
      // Hermes runs notify too, so this is not an Open WebUI-only setting.
      _buildAccountOption(
        context,
        icon: UiUtils.platformIcon(
          ios: CupertinoIcons.bell,
          android: Icons.notifications_outlined,
        ),
        title: l10n.notificationsTitle,
        subtitle: l10n.notificationsSubtitle,
        onTap: () => context.pushNamed(RouteNames.notificationSettings),
      ),
      if (hasOpenWebUiAccount || directPrimary)
        _buildAccountOption(
          context,
          icon: UiUtils.platformIcon(
            ios: CupertinoIcons.person_crop_circle_badge_checkmark,
            android: Icons.auto_awesome,
          ),
          title: l10n.personalization,
          subtitle: l10n.personalizationSubtitle,
          onTap: () => context.pushNamed(RouteNames.personalization),
        ),
    ];
    final connectionItems = <Widget>[
      _buildAccountOption(
        context,
        iconAsset: 'assets/icons/hermes_agent.png',
        title: l10n.hermesAgentSettingsTitle,
        subtitle: l10n.hermesAgentSettingsSubtitle,
        onTap: () => context.pushNamed(RouteNames.hermesSettings),
      ),
      if (canManageWorkspace)
        _buildAccountOption(
          context,
          key: const Key('workspace-entry'),
          icon: UiUtils.platformIcon(
            ios: CupertinoIcons.square_grid_2x2,
            android: Icons.dashboard_customize_outlined,
          ),
          title: l10n.workspaceTitle,
          subtitle: l10n.workspaceSubtitle,
          onTap: () => context.pushNamed(RouteNames.workspace),
        ),
      if (hasOpenWebUiAccount)
        _buildAccountOption(
          context,
          key: const Key('data-connection-entry'),
          icon: UiUtils.platformIcon(
            ios: CupertinoIcons.antenna_radiowaves_left_right,
            android: Icons.hub_outlined,
          ),
          title: l10n.settingsDataAndConnection,
          subtitle: l10n.connectionHealth,
          onTap: () => context.pushNamed(RouteNames.dataConnectionSettings),
        ),
      _buildAccountOption(
        context,
        icon: UiUtils.platformIcon(
          ios: CupertinoIcons.link,
          android: Icons.hub_outlined,
        ),
        title: l10n.directConnectionsTitle,
        subtitle: l10n.directConnectionsSubtitle,
        onTap: () => context.pushNamed(RouteNames.directConnections),
      ),
      if (!hasOpenWebUiAccount)
        _buildAccountOption(
          context,
          icon: UiUtils.platformIcon(
            ios: CupertinoIcons.add_circled,
            android: Icons.add_circle_outline,
          ),
          title: l10n.connectOpenWebUITitle,
          subtitle: l10n.connectOpenWebUISubtitle,
          onTap: () => context.goNamed(RouteNames.serverConnection),
        ),
    ];
    if (mangaLayoutOf(context)) {
      return [
        _MangaSection(
          title: 'App',
          children: [
            ...appItems,
            // The rollback, where the owner looks for it.
            _MangaClassicRow(),
          ],
        ),
        _MangaSection(title: 'Connections', children: connectionItems),
        _MangaSection(title: 'About', children: [_buildAboutTile(context)]),
      ];
    }
    return [
      InsetGroupedList(children: appItems),
      const SizedBox(height: Spacing.lg),
      InsetGroupedList(children: connectionItems),
      const SizedBox(height: Spacing.lg),
      InsetGroupedList(children: [_buildAboutTile(context)]),
    ];
  }

  Widget _buildSignOutOption(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    return _buildAccountOption(
      context,
      key: const Key('settings-sign-out'),
      icon: UiUtils.platformIcon(
        ios: CupertinoIcons.square_arrow_left,
        android: Icons.logout,
      ),
      title: l10n.signOut,
      subtitle: l10n.endYourSession,
      onTap: () => _signOut(context, ref),
      showChevron: false,
      destructive: true,
    );
  }

  Widget _buildAccountOption(
    BuildContext context, {
    Key? key,
    IconData? icon,
    String? iconAsset,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    bool showChevron = true,
    bool destructive = false,
  }) {
    assert(
      (icon == null) != (iconAsset == null),
      'Provide exactly one of icon or iconAsset.',
    );
    final theme = context.conduitTheme;
    final color = theme.buttonPrimary;
    if (mangaLayoutOf(context)) {
      return _MangaRow(
        key: key,
        onTap: onTap,
        glyph: iconAsset != null
            ? Image.asset(
                iconAsset,
                key: const Key('hermes-settings-logo'),
                width: IconSize.medium + 2,
                height: IconSize.medium + 2,
                color: destructive ? theme.error : MangaInk.of(context).ink,
                colorBlendMode: BlendMode.srcIn,
              )
            : Icon(
                icon,
                size: 22,
                color: destructive ? theme.error : MangaInk.of(context).ink,
              ),
        title: title,
        subtitle: subtitle,
        showChevron: showChevron,
        destructive: destructive,
      );
    }
    return UtilityRow(
      key: key,
      onTap: onTap,
      leading: iconAsset != null
          ? _buildAssetIconBadge(context, iconAsset, color: color)
          : _buildIconBadge(context, icon!, color: color),
      title: title,
      subtitle: subtitle,
      showChevron: showChevron,
      destructive: destructive,
    );
  }

  Widget _buildIconBadge(
    BuildContext context,
    IconData icon, {
    required Color color,
  }) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(AppBorderRadius.small),
        border: Border.all(
          color: color.withValues(alpha: 0.2),
          width: BorderWidth.thin,
        ),
      ),
      alignment: Alignment.center,
      child: Icon(icon, color: color, size: IconSize.medium),
    );
  }

  Widget _buildAssetIconBadge(
    BuildContext context,
    String asset, {
    required Color color,
  }) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(AppBorderRadius.small),
        border: Border.all(
          color: color.withValues(alpha: 0.2),
          width: BorderWidth.thin,
        ),
      ),
      alignment: Alignment.center,
      child: Image.asset(
        asset,
        key: const Key('hermes-settings-logo'),
        width: IconSize.medium + 2,
        height: IconSize.medium + 2,
        color: color,
        colorBlendMode: BlendMode.srcIn,
        filterQuality: FilterQuality.high,
      ),
    );
  }

  // Theme and language controls moved to AppCustomizationPage.

  Widget _buildAboutTile(BuildContext context) {
    return _buildAccountOption(
      context,
      icon: UiUtils.platformIcon(
        ios: CupertinoIcons.info,
        android: Icons.info_outline,
      ),
      title: AppLocalizations.of(context)!.aboutApp,
      subtitle: AppLocalizations.of(context)!.aboutAppSubtitle,
      onTap: () => context.pushNamed(RouteNames.about),
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

/// A You section in the manga layout: the panel face over a thick ink rule,
/// then plain rows on the paper.
class _MangaSection extends StatelessWidget {
  const _MangaSection({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final ink = MangaInk.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            child: Container(
              padding: const EdgeInsets.only(bottom: 6),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: ink.ink, width: ink.border),
                ),
              ),
              child: Text(title, style: MangaType.panel(ink.ink)),
            ),
          ),
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) Divider(height: 1, thickness: 1, color: ink.rule),
            children[i],
          ],
        ],
      ),
    );
  }
}

/// One You row in the manga layout: a square ink glyph tile, the title in
/// the page face, one quiet line, a chevron.
class _MangaRow extends StatelessWidget {
  const _MangaRow({
    super.key,
    required this.onTap,
    required this.glyph,
    required this.title,
    required this.subtitle,
    this.trailing,
    this.showChevron = true,
    this.destructive = false,
  });

  final VoidCallback? onTap;
  final Widget glyph;
  final String title;
  final String subtitle;
  final Widget? trailing;
  final bool showChevron;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final ink = MangaInk.of(context);
    final titleColour = destructive ? context.conduitTheme.error : ink.ink;
    return MangaPress(
      semanticLabel: '$title. $subtitle',
      scale: .985,
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 64),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 2),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  border: Border.all(color: ink.ink, width: ink.border),
                ),
                child: glyph,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: MangaType.title(titleColour)),
                    if (subtitle.isNotEmpty)
                      Text(
                        subtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: MangaType.meta(ink.ink2),
                      ),
                  ],
                ),
              ),
              ?trailing,
              if (trailing == null && showChevron)
                Icon(Icons.chevron_right_rounded, color: ink.ink3),
            ],
          ),
        ),
      ),
    );
  }
}

/// "Classic layout": the switch back to the list screens.
class _MangaClassicRow extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final classic = ref.watch(mangaClassicLayoutProvider);
    final notifier = ref.read(mangaClassicLayoutProvider.notifier);
    final ink = MangaInk.of(context);
    return _MangaRow(
      key: const Key('settings-classic-layout'),
      onTap: () => notifier.set(!classic),
      glyph: Icon(Icons.view_agenda_outlined, size: 22, color: ink.ink),
      title: 'Classic layout',
      subtitle: 'Pre-manga list screens',
      trailing: Switch(value: classic, onChanged: notifier.set),
    );
  }
}
