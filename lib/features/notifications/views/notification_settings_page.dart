import 'dart:async';

import 'package:conduit/shared/widgets/platform_ui/platform_ui.dart';
import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/app_providers.dart';
import '../../../core/services/settings_service.dart';
import '../../../core/utils/debug_logger.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/theme/theme_extensions.dart';
import '../../profile/widgets/settings_page_scaffold.dart';
import '../../../shared/widgets/utility_components.dart';
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
      return UtilityRow(
        enabled: interactive,
        title: title,
        subtitle: subtitle,
        semanticLabel:
            '$title. ${value ? l10n.enabled : l10n.disabled}. $subtitle',
        trailing: AdaptiveSwitch(
          value: value,
          onChanged: interactive ? onChanged : null,
        ),
        onTap: interactive ? () => onChanged(!value) : null,
      );
    }

    return UtilityPageScaffold.settings(
      title: l10n.notificationsTitle,
      children: [
        InsetGroupedList(
          children: [
            tile(
              title: l10n.notificationsEnabledTitle,
              subtitle: l10n.notificationsEnabledDescription,
              value: enabled,
              dependantOnMaster: false,
              onChanged: (value) => _setMaster(context, ref, value),
            ),
            UtilityRow(
              title: l10n.notificationSystemSettingsTitle,
              subtitle: l10n.notificationSystemSettingsDescription,
              showChevron: true,
              onTap: () => _openSystemSettings(context, ref),
            ),
          ],
        ),
        settingsSectionGap,
        // What Android actually reports, and a direct test, so a missing
        // notification can be traced to the device or to the event.
        const NotificationHealthSection(),
        settingsSectionGap,
        InsetGroupedList(
          children: [
            tile(
              title: l10n.notificationInAppBannerTitle,
              subtitle: l10n.notificationInAppBannerDescription,
              value: settings.notificationInAppBanner,
              onChanged: notifier.setNotificationInAppBanner,
            ),
            tile(
              title: l10n.notificationSystemTitle,
              subtitle: l10n.notificationSystemDescription,
              value: settings.notificationSystem,
              onChanged: notifier.setNotificationSystem,
            ),
            tile(
              title: l10n.notificationSoundTitle,
              subtitle: l10n.notificationSoundDescription,
              value: settings.notificationSound,
              onChanged: (value) => _setSound(ref, value),
            ),
            tile(
              title: l10n.notificationSoundAlwaysTitle,
              subtitle: l10n.notificationSoundAlwaysDescription,
              value: settings.notificationSoundAlways,
              onChanged: (value) => _setSoundAlways(ref, value),
            ),
          ],
        ),
        const SizedBox(height: Spacing.lg),
        InsetGroupedList(
          children: [
            tile(
              title: l10n.notificationChatTitle,
              subtitle: l10n.notificationChatDescription,
              value: settings.notificationChatEnabled,
              onChanged: notifier.setNotificationChatEnabled,
            ),
            tile(
              title: l10n.notificationChannelTitle,
              subtitle: l10n.notificationChannelDescription,
              value: settings.notificationChannelEnabled,
              onChanged: notifier.setNotificationChannelEnabled,
            ),
          ],
        ),
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

/// NOTIFICATION HEALTH: actual state from settings and from Android, a test
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

    Widget status(String title, String value, {String? subtitle}) => UtilityRow(
      title: title,
      subtitle: subtitle,
      semanticLabel: '$title: $value',
      trailing: Text(value),
    );

    String onOff(bool value) => value ? 'ON' : 'OFF';
    final permission = !_loaded
        ? 'CHECKING'
        : health == null
        ? 'NOT ANDROID'
        : switch (health.allowed) {
            true => 'ALLOWED',
            false => 'NOT ALLOWED',
            null => 'UNKNOWN',
          };
    final channel = !_loaded
        ? 'CHECKING'
        : health == null
        ? 'NOT ANDROID'
        : !health.channelExists
        ? 'NOT CREATED'
        : health.channelEnabled
        ? 'ENABLED'
        : 'TURNED OFF';

    return InsetGroupedList(
      title: 'NOTIFICATION HEALTH',
      children: [
        status('Conduit notifications', onOff(settings.notificationsEnabled)),
        status(
          'System notifications',
          onOff(settings.notificationSystem),
          subtitle: 'Android notifications while Hermez is in the background.',
        ),
        status('Android permission', permission),
        status('Android channel', channel),
        UtilityRow(
          title: 'Send test notification',
          subtitle:
              'Posts straight to Android, skipping Hermes, to check this '
              'device.',
          enabled: !_sending,
          showChevron: true,
          onTap: _sending ? null : () => unawaited(_sendTest()),
        ),
        UtilityRow(
          title: l10n.notificationSystemSettingsTitle,
          subtitle: 'Open Android settings',
          showChevron: true,
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
        const UtilityRow(
          title: 'Where notifications appear',
          subtitle:
              'System notifications are shown while Hermez is in the '
              'background. While the app is open, notifications appear '
              'inside the app. Hermez must be running (in the background is '
              'fine): a fully closed app cannot receive them.',
          subtitleMaxLines: 6,
        ),
      ],
    );
  }
}
