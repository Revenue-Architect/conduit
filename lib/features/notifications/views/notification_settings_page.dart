import 'dart:async';

import 'package:conduit/shared/widgets/platform_ui/platform_ui.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/app_providers.dart';
import '../../../core/services/settings_service.dart';
import '../../../core/utils/debug_logger.dart';
import '../../../l10n/app_localizations.dart';
import '../../profile/widgets/settings_sky_page.dart';
import '../../push/views/push_settings_section.dart';
import '../services/local_notification_service.dart';

/// Notification preferences. The master toggle requests OS permission on
/// opt-in. The three Open WebUI-aligned prefs (master / sound / sound-always)
/// are mirrored to the server for cross-device parity; the rest are local-only.
class NotificationSettingsPage extends ConsumerWidget {
  const NotificationSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final settings = ref.watch(appSettingsProvider);
    final notifier = ref.read(appSettingsProvider.notifier);
    final enabled = settings.notificationsEnabled;

    Widget tile({
      required String title,
      required String subtitle,
      required bool value,
      required ValueChanged<bool> onChanged,
      bool dependantOnMaster = true,
    }) {
      final interactive = !dependantOnMaster || enabled;
      return SettingsSwitchRow(
        title: title,
        sub: subtitle,
        semanticLabel:
            '$title. ${value ? l10n.enabled : l10n.disabled}. $subtitle',
        value: value,
        onChanged: interactive ? onChanged : null,
      );
    }

    final hasServer = ref.watch(apiServiceProvider) != null;
    // The plain switches come first; what Android reports and Push from
    // Hermes (health, pairing, categories) sit below them.
    return SettingsSkyPage(
      title: l10n.notificationsTitle,
      lede: 'Banners, alerts and push',
      children: [
        SettingsGroup(
          children: [
            tile(
              title: l10n.notificationsEnabledTitle,
              subtitle: 'Allow banners and system alerts.',
              value: enabled,
              dependantOnMaster: false,
              onChanged: (value) => _setMaster(context, ref, value),
            ),
            SettingsRow(
              leading: const SettingsGlyph(icon: Icons.smartphone_outlined),
              title: 'Android notification settings',
              sub: 'Permission, sound and banners for Conduit',
              onTap: () => _openSystemSettings(context, ref),
            ),
          ],
        ),
        SettingsGroup(
          title: 'While you use Conduit',
          children: [
            tile(
              title: l10n.notificationInAppBannerTitle,
              subtitle: 'Show a banner while the app is open.',
              value: settings.notificationInAppBanner,
              onChanged: notifier.setNotificationInAppBanner,
            ),
            tile(
              title: l10n.notificationSystemTitle,
              subtitle: 'Show an alert when Conduit is in the background.',
              value: settings.notificationSystem,
              onChanged: notifier.setNotificationSystem,
            ),
            tile(
              title: l10n.notificationSoundTitle,
              subtitle: 'Play a cue when a notification arrives.',
              value: settings.notificationSound,
              onChanged: (value) => _setSound(ref, value),
            ),
            tile(
              title: l10n.notificationSoundAlwaysTitle,
              subtitle: 'Play it even when the app is open and focused.',
              value: settings.notificationSoundAlways,
              onChanged: (value) => _setSoundAlways(ref, value),
            ),
          ],
        ),
        SettingsGroup(
          title: 'What you hear about',
          note: hasServer
              ? 'Channel messages come from Open WebUI and only show with a '
                    'server account.'
              : null,
          children: [
            tile(
              title: l10n.notificationChatTitle,
              subtitle:
                  'When an answer finishes in a chat you are not viewing.',
              value: settings.notificationChatEnabled,
              onChanged: notifier.setNotificationChatEnabled,
            ),
            // Channels are Open WebUI only.
            if (hasServer)
              tile(
                title: l10n.notificationChannelTitle,
                subtitle:
                    'When someone writes in a channel or a direct message.',
                value: settings.notificationChannelEnabled,
                onChanged: notifier.setNotificationChannelEnabled,
              ),
          ],
        ),
        // What Android actually reports, and a direct test, so a missing
        // notification can be traced to the device or to the event.
        const NotificationHealthSection(),
        // Push from the Umbrel (UnifiedPush): health, pairing, categories.
        const PushSettingsSection(),
      ],
    );
  }

  Future<void> _openSystemSettings(BuildContext context, WidgetRef ref) async {
    final opened = await ref
        .read(localNotificationServiceProvider)
        .openSystemSettings();
    if (!opened && context.mounted) {
      AdaptiveSnackBar.show(
        context,
        message: AppLocalizations.of(context)!
            .notificationSystemSettingsOpenFailed,
        type: AdaptiveSnackBarType.warning,
      );
    }
  }

  Future<void> _setMaster(
    BuildContext context,
    WidgetRef ref,
    bool value,
  ) async {
    await ref.read(appSettingsProvider.notifier).setNotificationsEnabled(value);
    _syncToServer(ref, enabled: value);

    if (value) {
      final granted = await ref
          .read(localNotificationServiceProvider)
          .requestPermissions();
      if (!granted && context.mounted) {
        AdaptiveSnackBar.show(
          context,
          message: AppLocalizations.of(context)!.notificationsPermissionDenied,
          type: AdaptiveSnackBarType.warning,
        );
      }
    }
  }

  Future<void> _setSound(WidgetRef ref, bool value) async {
    await ref.read(appSettingsProvider.notifier).setNotificationSound(value);
    _syncToServer(ref, sound: value);
  }

  Future<void> _setSoundAlways(WidgetRef ref, bool value) async {
    await ref
        .read(appSettingsProvider.notifier)
        .setNotificationSoundAlways(value);
    _syncToServer(ref, soundAlways: value);
  }

  /// Mirrors the three Open WebUI-aligned prefs to the server. Fire-and-forget:
  /// local persistence already succeeded, so a failed sync only loses
  /// cross-device parity, not the setting itself.
  void _syncToServer(
    WidgetRef ref, {
    bool? enabled,
    bool? sound,
    bool? soundAlways,
  }) {
    final api = ref.read(apiServiceProvider);
    if (api == null) return;
    unawaited(
      api
          .updateUserNotificationSettings(
            notificationEnabled: enabled,
            notificationSound: sound,
            notificationSoundAlways: soundAlways,
          )
          .then(
            (_) {},
            onError: (Object e, StackTrace st) {
              DebugLogger.error(
                'failed to sync notification prefs to server',
                error: e,
                stackTrace: st,
                scope: 'notifications/settings',
              );
            },
          ),
    );
  }
}

/// Check this phone: actual state from settings and from Android, a test
/// notification, and how the foreground / background split works.
class NotificationHealthSection extends ConsumerStatefulWidget {
  const NotificationHealthSection({super.key});

  @override
  ConsumerState<NotificationHealthSection> createState() =>
      _NotificationHealthSectionState();
}

class _NotificationHealthSectionState
    extends ConsumerState<NotificationHealthSection>
    with WidgetsBindingObserver {
  AndroidNotificationHealth? _health;
  bool _loaded = false;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_load());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // Back from Android settings: show what changed.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_load());
  }

  Future<void> _load() async {
    final health = await ref
        .read(localNotificationServiceProvider)
        .androidHealth();
    if (!mounted) return;
    setState(() {
      _health = health;
      _loaded = true;
    });
  }

  Future<void> _sendTest() async {
    if (_sending) return;
    setState(() => _sending = true);
    final result = await ref
        .read(localNotificationServiceProvider)
        .sendDiagnosticNotification();
    if (!mounted) return;
    setState(() => _sending = false);
    unawaited(_load());
    final (message, type) = switch (result) {
      DiagnosticNotificationResult.submitted => (
        'Test notification sent to Android. It appears even with the app '
            'open.',
        AdaptiveSnackBarType.success,
      ),
      DiagnosticNotificationResult.notAllowed => (
        'Android is not allowing notifications for this app. Open Android '
            'settings to allow them.',
        AdaptiveSnackBarType.warning,
      ),
      DiagnosticNotificationResult.failed => (
        'Android refused the test notification.',
        AdaptiveSnackBarType.error,
      ),
      DiagnosticNotificationResult.unsupported => (
        'This device has no system notifications here.',
        AdaptiveSnackBarType.warning,
      ),
    };
    AdaptiveSnackBar.show(context, message: message, type: type);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final settings = ref.watch(appSettingsProvider);
    final health = _health;

    Widget status(String title, String value, {String? subtitle}) =>
        SettingsStatRow(title: title, value: value, sub: subtitle);

    String onOff(bool value) => value ? 'On' : 'Off';
    final permission = !_loaded
        ? 'Checking'
        : health == null
        ? 'Not Android'
        : switch (health.allowed) {
            true => 'Allowed',
            false => 'Not allowed',
            null => 'Unknown',
          };
    final channel = !_loaded
        ? 'Checking'
        : health == null
        ? 'Not Android'
        : !health.channelExists
        ? 'Not created'
        : health.channelEnabled
        ? 'Enabled'
        : 'Turned off';

    return SettingsGroup(
      title: 'Check this phone',
      note:
          'Alerts show inside the app while it is open, and as Android '
          'notifications while it is in the background. A fully closed app '
          'cannot receive them.',
      children: [
        status('Conduit notifications', onOff(settings.notificationsEnabled)),
        status(
          'System notifications',
          onOff(settings.notificationSystem),
          subtitle: 'Android alerts while Conduit is in the background',
        ),
        status('Android permission', permission),
        status('Android channel', channel),
        SettingsRow(
          title: 'Send test notification',
          sub:
              'Goes straight to Android, skipping Hermes, to check this '
              'phone.',
          enabled: !_sending,
          onTap: _sending ? null : () => unawaited(_sendTest()),
        ),
        // The page's first group already links to Android settings; here
        // the link appears only as the fix for a problem shown above.
        if (health != null &&
            (health.allowed == false ||
                !health.channelExists ||
                !health.channelEnabled))
          SettingsRow(
            title: l10n.notificationSystemSettingsTitle,
            sub: 'Open Android settings to turn notifications back on',
            onTap: () async {
              final opened = await ref
                  .read(localNotificationServiceProvider)
                  .openSystemSettings();
              if (!opened && context.mounted) {
                AdaptiveSnackBar.show(
                  context,
                  message: l10n.notificationSystemSettingsOpenFailed,
                  type: AdaptiveSnackBarType.warning,
                );
              }
            },
          ),
      ],
    );
  }
}
