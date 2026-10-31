import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/backend_mode_providers.dart';
import '../../../l10n/app_localizations.dart';
import '../../push/providers/push_providers.dart';
import '../../push/views/push_pairing_page.dart' show defaultGatewayOrigin;
import '../controllers/hermes_connection_controller.dart';
import '../models/hermes_config.dart';
import '../motion/hermez_card_route.dart';
import '../motion/hermez_card_stack.dart';
import '../providers/hermes_providers.dart';
import '../services/hermes_connection_service.dart';
import '../views/hermes_desktop_connection_section.dart';
import '../widgets/hermez_chat_palette.dart';

/// Connect Hermes, then pair this phone, as one card (screens2 s08b and
/// s08): the Hermes row grows into the connection form, and once Hermes
/// answers the same card reshapes into pairing. Returns true when Hermes was
/// connected.
///
/// Nothing already connected is dropped: on a first run Hermes becomes the
/// app's backend; with a backend already chosen Hermes is saved and turned
/// on beside it, and the current choice stays. Pairing only replaces an
/// existing pairing once the new code has worked.
Future<bool> showHermesConnectCard(BuildContext context) async {
  final connected = await pushHermezCard<bool>(
    context,
    semanticLabel: 'Connect Hermes',
    builder: (_) => const _ConnectCard(),
  );
  return connected ?? false;
}

/// How the card connects Hermes without dropping what is already connected:
/// only a first run (no backend chosen) makes Hermes the app's backend;
/// otherwise Hermes is tested, saved and turned on beside the current one.
@visibleForTesting
Future<bool> connectHermesKeepingCurrent({
  required PreferredBackend backend,
  required Future<bool> Function() finishOnboarding,
  required Future<bool> Function() testConnection,
  required Future<bool> Function() save,
  required Future<void> Function() enable,
}) async {
  if (backend == PreferredBackend.unset) return finishOnboarding();
  if (!await testConnection() || !await save()) return false;
  await enable();
  return true;
}

class _ConnectCard extends ConsumerStatefulWidget {
  const _ConnectCard();

  @override
  ConsumerState<_ConnectCard> createState() => _ConnectCardState();
}

class _ConnectCardState extends ConsumerState<_ConnectCard> {
  late final HermesConnectionController _connection =
      HermesConnectionController(
        initialConfig: ref.read(hermesConfigProvider),
        gateway: ref.read(hermesConnectionGatewayProvider),
      )..addListener(_changed);
  bool _connected = false;

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _connection
      ..removeListener(_changed)
      ..dispose();
    super.dispose();
  }

  HermesConnectionMessages _messages(AppLocalizations l10n) =>
      HermesConnectionMessages(
        connecting: l10n.connecting,
        connected: l10n.connectedToServer,
        saved: l10n.saved,
        unreachable: l10n.couldNotConnectGeneric,
        persistenceFailed: l10n.directConnectionSaveFailed,
        activationFailed: l10n.hermesOnboardingFailed,
      );

  Future<bool> _save() => _connection.save(
    ref.read(hermesConfigProvider),
    messages: _messages(AppLocalizations.of(context)!),
  );

  Future<void> _test() => _connection.testConnection(
    saved: ref.read(hermesConfigProvider),
    messages: _messages(AppLocalizations.of(context)!),
  );

  /// First run: Hermes becomes the backend. Otherwise it is tested, saved
  /// and turned on beside what is already connected.
  Future<bool> _connect() async {
    FocusManager.instance.primaryFocus?.unfocus();
    final l10n = AppLocalizations.of(context)!;
    final saved = ref.read(hermesConfigProvider);
    return connectHermesKeepingCurrent(
      backend: ref.read(preferredBackendProvider),
      finishOnboarding: () async =>
          (await _connection.finishOnboarding(
            saved: saved,
            messages: _messages(l10n),
          )).outcome ==
          HermesConnectionOutcome.success,
      testConnection: () =>
          _connection.testConnection(saved: saved, messages: _messages(l10n)),
      save: _save,
      enable: () => ref.read(hermesConfigProvider.notifier).setEnabled(true),
    );
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 4, 4, 14),
    child: HermezCardStack(
      root: HermezCardView(
        title: 'Connect Hermes',
        builder: (stackContext) => _ConnectForm(
          connection: _connection,
          saveSettings: _save,
          testConnection: _test,
          onConnect: () async {
            if (!await _connect() || !stackContext.mounted) return;
            _connected = true;
            HermezCardStack.of(stackContext).push(
              HermezCardView(
                title: 'Pair this phone',
                builder: (_) =>
                    _PairForm(onDone: () => Navigator.pop(context, _connected)),
              ),
            );
          },
        ),
      ),
    ),
  );
}

/// The connection form: mode, address, key, and the optional memory key.
class _ConnectForm extends ConsumerWidget {
  const _ConnectForm({
    required this.connection,
    required this.saveSettings,
    required this.testConnection,
    required this.onConnect,
  });

  final HermesConnectionController connection;
  final Future<bool> Function() saveSettings;
  final Future<void> Function() testConnection;
  final Future<void> Function() onConnect;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = HermezChatPalette.forBrightness(
      Theme.of(context).brightness,
    );
    final busy = connection.operation.isBusy;
    final responses = connection.mode == HermesBackendMode.responsesApi;
    final attempt = connection.attempt.message;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SegmentedButton<HermesBackendMode>(
            segments: const [
              ButtonSegment(
                value: HermesBackendMode.responsesApi,
                label: Text('Responses API'),
              ),
              ButtonSegment(
                value: HermesBackendMode.desktopGateway,
                label: Text('Desktop Gateway'),
              ),
            ],
            selected: {connection.mode},
            onSelectionChanged: busy
                ? null
                : (mode) => connection.setMode(mode.single),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: connection.url,
            enabled: !busy,
            keyboardType: TextInputType.url,
            autocorrect: false,
            decoration: const InputDecoration(labelText: 'Server URL'),
          ),
          if (responses) ...[
            const SizedBox(height: 10),
            TextField(
              controller: connection.apiKey,
              enabled: !busy,
              obscureText: true,
              autocorrect: false,
              onChanged: (_) => connection.markApiKeyChanged(),
              decoration: const InputDecoration(labelText: 'API key'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: connection.sessionKey,
              enabled: !busy,
              obscureText: true,
              autocorrect: false,
              onChanged: (_) => connection.markSessionKeyChanged(),
              decoration: const InputDecoration(
                labelText: 'Memory key (optional)',
                hintText: 'Made for you if left blank',
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'The memory key keeps long-term memory tied to you.',
              style: TextStyle(fontSize: 12, color: palette.muted),
            ),
          ] else ...[
            const SizedBox(height: 10),
            HermesDesktopConnectionSection(
              controller: connection,
              saveSettings: saveSettings,
              testConnection: testConnection,
            ),
          ],
          if (attempt != null) ...[
            const SizedBox(height: 10),
            Semantics(
              liveRegion: true,
              child: Text(
                attempt,
                style: TextStyle(fontSize: 13, color: palette.muted),
              ),
            ),
          ],
          const SizedBox(height: 16),
          FilledButton(
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
            ),
            onPressed: busy ? null : onConnect,
            child: Text(busy ? 'Connecting…' : 'Connect Hermes'),
          ),
        ],
      ),
    );
  }
}

/// Pair this phone for push alerts: the command, the one-time code, a name
/// and the gateway. "Not now" leaves it for Notifications later.
class _PairForm extends ConsumerStatefulWidget {
  const _PairForm({required this.onDone});

  final VoidCallback onDone;

  @override
  ConsumerState<_PairForm> createState() => _PairFormState();
}

class _PairFormState extends ConsumerState<_PairForm> {
  late final _gateway = TextEditingController(
    text: defaultGatewayOrigin(ref.read(hermesConfigProvider).baseUrl),
  );
  final _code = TextEditingController();
  final _name = TextEditingController(text: 'Android phone');
  bool _busy = false;
  String? _message;

  @override
  void dispose() {
    _gateway.dispose();
    _code.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _pair() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    final message = await ref
        .read(pushPairingControllerProvider)
        .pair(origin: _gateway.text, code: _code.text, deviceName: _name.text);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _message = message;
    });
    if (message == null) widget.onDone();
  }

  @override
  Widget build(BuildContext context) {
    final palette = HermezChatPalette.forBrightness(
      Theme.of(context).brightness,
    );
    final bots = ref.watch(hermesBotsProvider).value?.length;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.check_circle_rounded, color: palette.ink),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  bots == null
                      ? 'Hermes connected'
                      : 'Hermes connected · $bots bots found',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: palette.ink,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            'On the Umbrel, run this command. It prints a code that works '
            'once, for five minutes.',
            style: TextStyle(fontSize: 13, height: 1.4, color: palette.muted),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: palette.canvas,
              borderRadius: BorderRadius.circular(14),
            ),
            child: SelectableText(
              'docker exec hermes-notify notifyctl pair',
              style: TextStyle(fontSize: 14, color: palette.ink),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _code,
            enabled: !_busy,
            autocorrect: false,
            textCapitalization: TextCapitalization.characters,
            style: const TextStyle(fontSize: 22, letterSpacing: 2),
            decoration: const InputDecoration(labelText: 'Pairing code'),
            onSubmitted: (_) => unawaited(_pair()),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _name,
            enabled: !_busy,
            decoration: const InputDecoration(labelText: 'Name for this phone'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _gateway,
            enabled: !_busy,
            keyboardType: TextInputType.url,
            autocorrect: false,
            decoration: const InputDecoration(labelText: 'Gateway address'),
          ),
          if (_message != null) ...[
            const SizedBox(height: 10),
            Semantics(
              liveRegion: true,
              child: Text(
                _message!,
                style: TextStyle(fontSize: 13, color: palette.failed),
              ),
            ),
          ],
          const SizedBox(height: 16),
          FilledButton(
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
            ),
            onPressed: _busy ? null : () => unawaited(_pair()),
            child: Text(_busy ? 'Pairing…' : 'Pair'),
          ),
          TextButton(
            onPressed: _busy ? null : widget.onDone,
            child: const Text('Not now'),
          ),
          Text(
            'You can pair later in Notifications.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: palette.muted),
          ),
        ],
      ),
    );
  }
}
