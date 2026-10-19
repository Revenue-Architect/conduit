import 'dart:async';

import 'package:conduit/shared/widgets/platform_ui/platform_ui.dart'
    show AdaptiveSwitch;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../../core/services/navigation_service.dart';
import '../../../shared/widgets/utility_components.dart';
import '../../notifications/services/local_notification_service.dart';
import '../models/push_envelope.dart';
import '../models/push_health.dart';
import '../providers/push_providers.dart';
import '../services/push_registration_service.dart' show PushEnableResult;

/// Categories the person can switch off. Approvals and critical stay on
/// whenever push is on.
const List<PushCategory> switchableCategories = [
  PushCategory.alerts,
  PushCategory.proactive,
  PushCategory.briefs,
  PushCategory.agent,
  PushCategory.watch,
  PushCategory.status,
];

/// The "Push from Hermes" part of the notification settings: health first
/// (what is wrong and how to fix it), then the switches.
class PushSettingsSection extends ConsumerStatefulWidget {
  const PushSettingsSection({super.key});

  @override
  ConsumerState<PushSettingsSection> createState() => _PushSettingsSectionState();
}

class _PushSettingsSectionState extends ConsumerState<PushSettingsSection>
    with WidgetsBindingObserver {
  bool _prefsLoaded = false;
  bool _enabled = true;
  Set<String> _disabled = {};
  String _packageName = '';
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_loadPrefs());
    unawaited(_loadPackage());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Back from Android settings (battery, notifications): re-read.
    if (state == AppLifecycleState.resumed) {
      unawaited(ref.read(pushStatusProvider.notifier).refresh());
    }
  }

  Future<void> _loadPackage() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (mounted) setState(() => _packageName = info.packageName);
    } catch (_) {
      // The battery link just stays hidden.
    }
  }

  Future<void> _loadPrefs() async {
    final service = ref.read(pushRegistrationServiceProvider);
    if (!service.supported) {
      if (mounted) setState(() => _prefsLoaded = true);
      return;
    }
    try {
      final prefs = await service.prefs();
      if (!mounted) return;
      setState(() {
        _enabled = prefs.enabled;
        _disabled = prefs.disabledCategories.toSet();
        _prefsLoaded = true;
      });
    } catch (_) {
      if (mounted) setState(() => _prefsLoaded = true);
    }
  }

  Future<void> _savePrefs() => ref
      .read(pushRegistrationServiceProvider)
      .setPrefs(enabled: _enabled, disabledCategories: _disabled);

  Future<void> _check() async {
    setState(() => _checking = true);
    await ref.read(pushStatusProvider.notifier).refresh();
    if (mounted) setState(() => _checking = false);
  }

  Future<void> _register() async {
    final result = await ref.read(pushRegistrationServiceProvider).enable();
    if (!mounted) return;
    final text = switch (result) {
      PushEnableResult.ok => 'Registration requested.',
      PushEnableResult.noDistributor =>
        'Install ntfy and open it once, then try again.',
      PushEnableResult.notPaired => 'Pair this phone first.',
      PushEnableResult.failed => 'Android did not register push.',
    };
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(text)));
    await _check();
  }

  Future<void> _chooseDistributor() async {
    final service = ref.read(pushRegistrationServiceProvider);
    final options = await service.distributors();
    if (!mounted || options.isEmpty) return;
    final picked = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Which app delivers push?',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
              ),
            ),
            for (final option in options)
              ListTile(
                title: Text(option),
                subtitle: option == 'io.heckel.ntfy'
                    ? const Text('ntfy (recommended)')
                    : null,
                onTap: () => Navigator.of(context).pop(option),
              ),
          ],
        ),
      ),
    );
    if (picked == null) return;
    await service.chooseDistributor(picked);
    await _check();
  }

  Future<void> _channelSheet() async {
    final picked = await showModalBottomSheet<PushCategory>(
      context: context,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Sound and vibration per category',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
              ),
            ),
            for (final category in PushCategory.values)
              ListTile(
                title: Text(category.label),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => Navigator.of(context).pop(category),
              ),
          ],
        ),
      ),
    );
    if (picked == null) return;
    await ref.read(pushRegistrationServiceProvider).openChannelSettings(picked.name);
  }

  Future<void> _unpair() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Unpair this phone?'),
        content: const Text(
          'Hermez stops receiving push and cannot decide approvals until it '
          'is paired again. Revoke the device on the Umbrel too if the phone '
          'is lost.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Unpair'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(pushPairingControllerProvider).unpair();
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = ref.watch(pushStatusProvider);
    final service = ref.watch(pushRegistrationServiceProvider);
    if (!service.supported) return const SizedBox.shrink();
    final value = status.asData?.value;
    final health = value?.health;
    final native = value?.native;
    final distributor = native?.distributor;

    final healthRows = <Widget>[
      UtilityRow(
        title: health == null ? 'Checking push…' : health.headline,
        subtitle: health?.lastPushAt == null
            ? null
            : 'Last push received ${_ago(health!.lastPushAt!)}.',
        leading: Icon(
          switch (health?.level) {
            PushHealthLevel.healthy => Icons.check_circle_rounded,
            PushHealthLevel.warning => Icons.warning_amber_rounded,
            PushHealthLevel.problem => Icons.error_rounded,
            _ => Icons.sync_rounded,
          },
          color: switch (health?.level) {
            PushHealthLevel.healthy => const Color(0xFF2E9E5B),
            PushHealthLevel.warning => const Color(0xFFD99A00),
            PushHealthLevel.problem => const Color(0xFFD64545),
            _ => null,
          },
        ),
        semanticLabel: health?.headline ?? 'Checking push',
        subtitleMaxLines: 3,
      ),
      if (health != null)
        for (final issue in health.issues)
          _issueRow(issue, distributor: distributor),
      UtilityRow(
        title: 'Check again',
        subtitle: _checking ? 'Checking…' : null,
        showChevron: true,
        enabled: !_checking,
        onTap: _checking ? null : () => unawaited(_check()),
      ),
      if (native != null && native.paired)
        UtilityRow(
          title: 'Approvals',
          subtitle: 'Pending requests and history',
          showChevron: true,
          onTap: () => context.push(Routes.hermesApprovals),
        ),
      UtilityRow(
        title: native != null && native.paired ? 'Pair again' : 'Pair this phone',
        subtitle: 'Enter a one-time code from the Umbrel',
        showChevron: true,
        onTap: () => context.push(Routes.hermesPushPairing),
      ),
      if (native != null && native.paired)
        UtilityRow(
          title: 'Unpair this phone',
          destructive: true,
          showChevron: true,
          onTap: () => unawaited(_unpair()),
        ),
    ];

    Widget category(PushCategory c) {
      final on = _enabled && !_disabled.contains(c.name);
      return UtilityRow(
        enabled: _enabled && _prefsLoaded,
        title: c.label,
        semanticLabel: '${c.label}. ${on ? 'On' : 'Off'}',
        trailing: AdaptiveSwitch(
          value: on,
          onChanged: _enabled && _prefsLoaded
              ? (v) {
                  setState(() {
                    if (v) {
                      _disabled.remove(c.name);
                    } else {
                      _disabled.add(c.name);
                    }
                  });
                  unawaited(_savePrefs());
                }
              : null,
        ),
        onTap: _enabled && _prefsLoaded
            ? () {
                setState(() {
                  if (on) {
                    _disabled.add(c.name);
                  } else {
                    _disabled.remove(c.name);
                  }
                });
                unawaited(_savePrefs());
              }
            : null,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InsetGroupedList(title: 'PUSH FROM HERMES', children: healthRows),
        settingsGap,
        InsetGroupedList(
          title: 'PUSH CATEGORIES',
          footer:
              'Approvals and critical alerts stay on whenever push is on. '
              'Critical alerts do not bypass Do Not Disturb.',
          children: [
            UtilityRow(
              title: 'Receive push',
              semanticLabel: 'Receive push. ${_enabled ? 'On' : 'Off'}',
              trailing: AdaptiveSwitch(
                value: _enabled,
                onChanged: _prefsLoaded
                    ? (v) {
                        setState(() => _enabled = v);
                        unawaited(_savePrefs());
                      }
                    : null,
              ),
              onTap: _prefsLoaded
                  ? () {
                      setState(() => _enabled = !_enabled);
                      unawaited(_savePrefs());
                    }
                  : null,
            ),
            for (final c in switchableCategories) category(c),
            UtilityRow(
              title: 'Sound and vibration',
              subtitle: 'Android settings for each category',
              showChevron: true,
              onTap: () => unawaited(_channelSheet()),
            ),
          ],
        ),
      ],
    );
  }

  Widget _issueRow(PushIssue issue, {String? distributor}) {
    final text = describePushIssue(issue, distributor: _short(distributor));
    VoidCallback? action;
    String? actionLabel;
    switch (issue) {
      case PushIssue.notificationsBlocked:
        actionLabel = 'Open settings';
        action = () => unawaited(
          ref.read(localNotificationServiceProvider).openSystemSettings(),
        );
      case PushIssue.notPaired:
        actionLabel = 'Pair';
        action = () => context.push(Routes.hermesPushPairing);
      case PushIssue.distributorNotSelected:
        actionLabel = 'Choose';
        action = () => unawaited(_chooseDistributor());
      case PushIssue.notRegistered:
      case PushIssue.uploadFailed:
      case PushIssue.uploadPending:
        actionLabel = 'Register now';
        action = () => unawaited(_register());
      case PushIssue.appBatteryRestricted:
        if (_packageName.isNotEmpty) {
          actionLabel = 'Battery settings';
          action = () => unawaited(
            ref.read(pushRegistrationServiceProvider).openBatterySettings(_packageName),
          );
        }
      case PushIssue.distributorBatteryRestricted:
        if (distributor != null) {
          actionLabel = 'Battery settings';
          action = () => unawaited(
            ref.read(pushRegistrationServiceProvider).openBatterySettings(distributor),
          );
        }
      case PushIssue.noDistributor:
      case PushIssue.unsupported:
      case PushIssue.distributorTemporarilyDown:
      case PushIssue.serverUnreachable:
      case PushIssue.serverEndpointNotVerified:
      case PushIssue.fallbackActive:
        break;
    }
    return UtilityRow(
      title: _issueTitle(issue),
      subtitle: text,
      subtitleMaxLines: 6,
      leading: const Icon(Icons.chevron_right_rounded, size: 18),
      status: actionLabel == null
          ? null
          : TextButton(onPressed: action, child: Text(actionLabel)),
      semanticLabel: '${_issueTitle(issue)}. $text',
    );
  }

  String? _short(String? distributor) =>
      distributor == 'io.heckel.ntfy' ? 'ntfy' : distributor;

  String _issueTitle(PushIssue issue) => switch (issue) {
    PushIssue.unsupported => 'Not supported here',
    PushIssue.notificationsBlocked => 'Notifications are blocked',
    PushIssue.notPaired => 'Not paired',
    PushIssue.noDistributor => 'ntfy is not installed',
    PushIssue.distributorNotSelected => 'No delivery app chosen',
    PushIssue.notRegistered => 'Not registered yet',
    PushIssue.uploadPending => 'Delivery address not sent yet',
    PushIssue.uploadFailed => 'Delivery address rejected',
    PushIssue.appBatteryRestricted => 'Hermez battery use is restricted',
    PushIssue.distributorBatteryRestricted => 'ntfy battery use is restricted',
    PushIssue.distributorTemporarilyDown => 'ntfy server unavailable',
    PushIssue.serverUnreachable => 'Hermes unreachable',
    PushIssue.serverEndpointNotVerified => 'Delivery not confirmed',
    PushIssue.fallbackActive => 'Using plain ntfy for some alerts',
  };

  String _ago(DateTime time) {
    final diff = DateTime.now().difference(time);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inHours < 1) return '${diff.inMinutes} min ago';
    if (diff.inDays < 1) return '${diff.inHours} h ago';
    return '${diff.inDays} d ago';
  }
}

const SizedBox settingsGap = SizedBox(height: 16);
