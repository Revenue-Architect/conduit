import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/utils/debug_logger.dart';
import '../../../../shared/theme/theme_extensions.dart';
import '../../admin/hermes_admin_client.dart';
import '../../admin/hermes_admin_models.dart';
import '../../admin/hermes_admin_providers.dart';
import '../../admin/hermes_secret_redaction.dart';
import '../../sheets/hermes_model_sheet.dart'
    show hermesEffortLevels, hermesModelShortName;
import '../../sheets/hermez_modal_sheet.dart';
import '../../widgets/hermez_chat_palette.dart';
import '../../widgets/hermez_segments.dart';
import '../../widgets/hermez_skeleton.dart';
import '../../widgets/hermez_surfaces.dart';
import '../../widgets/hermez_visual_theme.dart';
import '../widgets/hermes_secret_field.dart';

/// Default model, fallbacks, reasoning, provider keys and sign-ins for one
/// bot (R19, R21, KTD8).
///
/// [scope] is the bot's (profile's) name. Every call carries it, so nothing
/// here touches another bot unless the owner asks ("Apply to all bots").
///
/// Each part loads on its own, with the shared page states (U15): a
/// [HermezSkeleton] while a read is in flight, an inline error with Retry
/// when it fails, and a disabled control with its reason when this Hermes
/// does not have the feature ([HermesAdminUnavailable]).
///
/// Keys are write-only. Hermes sends only its own masked preview, and a
/// saved key can only be replaced or removed; the page never asks for the
/// full value (R21). The page scrolls itself and needs no bounded height.
class HermesModelsProvidersPage extends ConsumerStatefulWidget {
  const HermesModelsProvidersPage({
    super.key,
    required this.scope,
    this.botTitle,
  });

  /// The bot's name (its profile).
  final String scope;

  /// What to call the bot, when it has a title besides its name.
  final String? botTitle;

  @override
  ConsumerState<HermesModelsProvidersPage> createState() =>
      _HermesModelsProvidersPageState();
}

// ---------------------------------------------------------------------------
// State of one part of the page
// ---------------------------------------------------------------------------

enum _Phase { loading, ready, failed, unavailable }

enum _Part { model, config, keys, signIns }

/// What one part of the page is showing.
final class _Slot<T> {
  const _Slot(this.phase, {this.value, this.message = ''});

  _Slot.loading() : this(_Phase.loading);

  final _Phase phase;
  final T? value;

  /// Safe to show: the error, or the reason a feature is unavailable.
  final String message;
}

typedef _Entry = ({String provider, String model});

/// The parts of the bot's config this page edits.
final class _ConfigView {
  const _ConfigView({required this.effort, required this.fallbacks});

  /// Hermes' `agent.reasoning_effort`; empty when it was never set.
  final String effort;
  final List<_Entry> fallbacks;

  _ConfigView copyWith({String? effort, List<_Entry>? fallbacks}) =>
      _ConfigView(
        effort: effort ?? this.effort,
        fallbacks: fallbacks ?? this.fallbacks,
      );

  static _ConfigView fromJson(Map<String, dynamic> config) {
    final agent = config['agent'];
    final rawEffort = agent is Map ? agent['reasoning_effort'] : null;
    final effort = rawEffort is String ? rawEffort.trim().toLowerCase() : '';
    _Entry? entry(Object? item) {
      if (item is! Map) return null;
      final provider = item['provider'];
      final model = item['model'];
      if (provider is! String || model is! String) return null;
      if (provider.trim().isEmpty || model.trim().isEmpty) return null;
      return (provider: provider.trim(), model: model.trim());
    }

    final listed = config['fallback_providers'];
    var fallbacks = <_Entry>[
      if (listed is List)
        for (final item in listed.take(32)) ?entry(item),
    ];
    if (fallbacks.isEmpty) {
      // The older single-entry key, which Hermes folds into the chain.
      final legacy = entry(config['fallback_model']);
      if (legacy != null) fallbacks = [legacy];
    }
    return _ConfigView(effort: effort, fallbacks: fallbacks);
  }
}

/// A line of feedback under a control.
final class _Note {
  const _Note(this.text, {this.error = false});

  final String text;
  final bool error;
}

/// How a key save went, for the status line.
final class _KeyReport {
  const _KeyReport({
    required this.label,
    required this.saved,
    required this.failed,
  });

  final String label;

  /// Bots the key was written to.
  final List<String> saved;

  /// Bots it could not be written to.
  final List<String> failed;
}

/// A running device-code sign-in.
final class _SignInFlow {
  _SignInFlow({
    required this.providerId,
    required this.providerName,
    required this.start,
    required this.client,
  });

  final String providerId;
  final String providerName;
  final HermesAdminSignInStart start;
  final HermesAdminClient client;

  /// Time spent waiting, counted in poll intervals.
  Duration waited = Duration.zero;
  int failedPolls = 0;
}

/// Polls that fail in a row before the sign-in is given up.
const int _kMaxFailedPolls = 3;

const List<String> _kBaseEfforts = ['none', 'low', 'medium', 'high', 'max'];

// ---------------------------------------------------------------------------
// The page
// ---------------------------------------------------------------------------

class _HermesModelsProvidersPageState
    extends ConsumerState<HermesModelsProvidersPage> {
  _Slot<HermesAdminModelOptions> _model = _Slot.loading();
  _Slot<_ConfigView> _config = _Slot.loading();
  _Slot<List<HermesAdminEnvKey>> _keys = _Slot.loading();
  _Slot<List<HermesAdminProviderSignIn>> _signIns = _Slot.loading();
  final List<int> _serials = List<int>.filled(_Part.values.length, 0);

  bool _modelBusy = false;
  _Note? _modelNote;
  String? _effortShown;
  bool _effortBusy = false;
  _Note? _effortNote;
  bool _fallbackBusy = false;
  _Note? _fallbackNote;

  /// The env key being replaced, or null.
  String? _replacing;
  bool _adding = false;
  String? _removing;
  _Note? _keyNote;

  _SignInFlow? _flow;
  Timer? _pollTimer;
  String? _startingProviderId;
  String? _disconnectingProviderId;
  _Note? _signInNote;

  String get _scope => widget.scope;
  String get _botName => widget.botTitle ?? widget.scope;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  @override
  void didUpdateWidget(covariant HermesModelsProvidersPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scope != widget.scope) {
      _endFlow(cancelRemote: true);
      _modelNote = null;
      _effortShown = null;
      _effortNote = null;
      _fallbackNote = null;
      _replacing = null;
      _adding = false;
      _removing = null;
      _keyNote = null;
      _signInNote = null;
      _loadAll();
    }
  }

  @override
  void dispose() {
    _endFlow(cancelRemote: true, notify: false);
    super.dispose();
  }

  // -------------------------------------------------------------------------
  // Loading
  // -------------------------------------------------------------------------

  void _loadAll() {
    unawaited(_loadModel());
    unawaited(_loadConfig());
    unawaited(_loadKeys());
    unawaited(_loadSignIns());
  }

  Future<void> _loadModel({bool quiet = false}) =>
      _load<HermesAdminModelOptions>(
        _Part.model,
        (client) => client.modelOptions(_scope),
        (slot) => _model = slot,
        quiet: quiet,
      );

  Future<void> _loadConfig({bool quiet = false}) => _load<_ConfigView>(
    _Part.config,
    (client) async => _ConfigView.fromJson(await client.config(_scope)),
    (slot) => _config = slot,
    quiet: quiet,
  );

  Future<void> _loadKeys({bool quiet = false}) =>
      _load<List<HermesAdminEnvKey>>(
        _Part.keys,
        (client) => client.listEnvKeys(_scope),
        (slot) => _keys = slot,
        quiet: quiet,
      );

  Future<void> _loadSignIns({bool quiet = false}) =>
      _load<List<HermesAdminProviderSignIn>>(
        _Part.signIns,
        (client) => client.providerSignIns(_scope),
        (slot) => _signIns = slot,
        quiet: quiet,
      );

  /// Reads one part. A [quiet] reload keeps what is on screen while it runs
  /// and, if it fails, keeps it afterwards.
  Future<void> _load<T>(
    _Part part,
    Future<T> Function(HermesAdminClient client) read,
    void Function(_Slot<T> slot) assign, {
    required bool quiet,
  }) async {
    final serial = ++_serials[part.index];
    if (!quiet) setState(() => assign(_Slot<T>.loading()));
    final slot = await _fetch<T>(part, read);
    if (!mounted || serial != _serials[part.index]) return;
    if (quiet && slot.phase != _Phase.ready) return;
    setState(() => assign(slot));
  }

  Future<_Slot<T>> _fetch<T>(
    _Part part,
    Future<T> Function(HermesAdminClient client) read,
  ) async {
    final client = ref.read(hermesAdminClientProvider);
    if (client == null) {
      return _Slot<T>(_Phase.unavailable, message: _kNoGatewayReason);
    }
    try {
      return _Slot<T>(_Phase.ready, value: await read(client));
    } on HermesAdminUnavailable {
      return _Slot<T>(_Phase.unavailable, message: _kUnavailableReason);
    } on ArgumentError {
      return _Slot<T>(_Phase.unavailable, message: _kUnavailableReason);
    } catch (error) {
      _logFailure('load', part.name, error);
      return _Slot<T>(
        _Phase.failed,
        message: _describe(error, "Couldn't load this. Check the connection."),
      );
    }
  }

  static const String _kNoGatewayReason =
      'Models and providers need a connection to a Hermes Desktop Gateway.';
  static const String _kUnavailableReason =
      'Not available on this Hermes server.';

  /// Only the failing step and the error's type go to the log, never a value.
  static void _logFailure(String action, String what, Object error) {
    DebugLogger.warning(
      'Models and providers: $action failed',
      scope: 'hermes/settings',
      data: {'step': what, 'errorType': error.runtimeType.toString()},
    );
  }

  /// Server text made safe to show.
  static String _describe(
    Object error,
    String fallback, {
    Iterable<String> secrets = const [],
  }) {
    if (error is HermesAdminUnavailable) return _kUnavailableReason;
    if (error is HermesAdminException) {
      final text = HermesSecretRedaction.redactText(
        error.message,
        secrets: secrets,
      ).trim();
      return text.isEmpty ? fallback : text;
    }
    return fallback;
  }

  HermesAdminClient? get _client => ref.read(hermesAdminClientProvider);

  String _providerLabel(String slug) {
    final providers = _model.value?.providers ?? const [];
    for (final provider in providers) {
      if (provider.slug == slug) return provider.name;
    }
    return slug;
  }

  // -------------------------------------------------------------------------
  // Model
  // -------------------------------------------------------------------------

  Future<void> _changeModel() async {
    final options = _model.value;
    if (options == null || _modelBusy) return;
    final pick = await _pickModel(
      title: 'Default model',
      providers: options.providers,
      currentProvider: options.provider,
      currentModel: options.model,
    );
    if (pick == null || !mounted) return;
    await _applyModel(pick);
  }

  Future<void> _applyModel(_Entry pick) async {
    final client = _client;
    if (client == null) return;
    setState(() {
      _modelBusy = true;
      _modelNote = null;
    });
    try {
      var write = await client.setModel(
        profile: _scope,
        provider: pick.provider,
        model: pick.model,
      );
      // Hermes can hold a model back (an expensive one) until the owner
      // agrees; nothing is written until then.
      while (write.needsConfirmation) {
        final confirmation = write.confirmation!;
        if (!mounted) return;
        // Waiting on the owner is not Hermes working: no spinner meanwhile.
        setState(() => _modelBusy = false);
        final agreed = await _confirm(
          title: 'Use this model?',
          message: confirmation.message,
          confirmLabel: 'Use model',
        );
        if (!mounted) return;
        if (!agreed) {
          setState(
            () =>
                _modelNote = const _Note('The default model was not changed.'),
          );
          return;
        }
        setState(() => _modelBusy = true);
        write = await confirmation.confirm();
      }
      if (!mounted) return;
      setState(() {
        _modelBusy = false;
        _model = _Slot(
          _Phase.ready,
          value: HermesAdminModelOptions(
            model: pick.model,
            provider: pick.provider,
            providers: _model.value?.providers ?? const [],
          ),
        );
        _modelNote = _Note(
          'Default model set to ${hermesModelShortName(pick.model)}. '
          'New chats use it.',
        );
      });
      unawaited(_loadModel(quiet: true));
    } catch (error) {
      _logFailure('set model', 'model', error);
      if (!mounted) return;
      setState(() {
        _modelBusy = false;
        _modelNote = _Note(
          _describe(error, "Couldn't change the model. Try again."),
          error: true,
        );
      });
    }
  }

  // -------------------------------------------------------------------------
  // Reasoning
  // -------------------------------------------------------------------------

  /// Hermes treats an unset effort as medium.
  String get _effort {
    final shown = _effortShown ?? _config.value?.effort ?? '';
    return shown.isEmpty ? 'medium' : shown;
  }

  Future<void> _setEffort(String effort) async {
    final client = _client;
    final config = _config.value;
    if (client == null || config == null || _effortBusy) return;
    if (effort == _effort) return;
    final previous = _effortShown;
    setState(() {
      _effortShown = effort;
      _effortBusy = true;
      _effortNote = null;
    });
    try {
      // `model/set` applies reasoning to auxiliary slots only; the bot's
      // default goes through the merging config route (0.21.5).
      await client.setReasoningEffort(_scope, effort);
      if (!mounted) return;
      setState(() {
        _effortBusy = false;
        _config = _Slot(_Phase.ready, value: config.copyWith(effort: effort));
        _effortShown = null;
        _effortNote = _Note(
          'Reasoning set to ${_effortLabel(effort)}. New chats use it.',
        );
      });
    } catch (error) {
      _logFailure('set reasoning', 'config', error);
      if (!mounted) return;
      setState(() {
        _effortBusy = false;
        _effortShown = previous;
        _effortNote = _Note(
          _describe(error, "Couldn't change reasoning. Try again."),
          error: true,
        );
      });
    }
  }

  static String _effortLabel(String value) {
    for (final (id, label) in hermesEffortLevels) {
      if (id == value) return label;
    }
    return value;
  }

  /// The levels offered. A level Hermes was set to elsewhere, and the
  /// segments do not list, is slotted in by its place in the scale.
  static List<String> _effortValues(String current) {
    if (_kBaseEfforts.contains(current)) return _kBaseEfforts;
    final order = [for (final (id, _) in hermesEffortLevels) id];
    int rank(String id) {
      final at = order.indexOf(id);
      return at < 0 ? order.length : at;
    }

    return [..._kBaseEfforts, current]..sort((a, b) => rank(a) - rank(b));
  }

  // -------------------------------------------------------------------------
  // Fallbacks
  // -------------------------------------------------------------------------

  Future<void> _addFallback() async {
    final options = _model.value;
    if (options == null || _fallbackBusy) return;
    final pick = await _pickModel(
      title: 'Add a fallback',
      providers: options.providers,
    );
    if (pick == null || !mounted) return;
    final current = _config.value?.fallbacks ?? const <_Entry>[];
    if (current.contains(pick)) {
      setState(
        () => _fallbackNote = const _Note(
          'That model is already a fallback.',
          error: true,
        ),
      );
      return;
    }
    await _saveFallbacks([...current, pick], done: 'Fallback added.');
  }

  Future<void> _moveFallback(int index, int by) async {
    final current = [...?_config.value?.fallbacks];
    final target = index + by;
    if (target < 0 || target >= current.length) return;
    final moved = current.removeAt(index);
    current.insert(target, moved);
    await _saveFallbacks(current, done: 'Fallback order saved.');
  }

  Future<void> _removeFallback(int index) async {
    final current = [...?_config.value?.fallbacks];
    if (index < 0 || index >= current.length) return;
    current.removeAt(index);
    await _saveFallbacks(current, done: 'Fallback removed.');
  }

  /// Saves the whole chain, in order, through a config merge.
  Future<void> _saveFallbacks(List<_Entry> next, {required String done}) async {
    final client = _client;
    final config = _config.value;
    if (client == null || config == null || _fallbackBusy) return;
    setState(() {
      _fallbackBusy = true;
      _fallbackNote = null;
      _config = _Slot(_Phase.ready, value: config.copyWith(fallbacks: next));
    });
    try {
      await client.setFallbackProviders(_scope, next);
      if (!mounted) return;
      setState(() {
        _fallbackBusy = false;
        _fallbackNote = _Note(done);
      });
    } catch (error) {
      _logFailure('save fallbacks', 'config', error);
      if (!mounted) return;
      setState(() {
        _fallbackBusy = false;
        _config = _Slot(_Phase.ready, value: config);
        _fallbackNote = _Note(
          _describe(error, "Couldn't save the fallbacks. Try again."),
          error: true,
        );
      });
    }
  }

  // -------------------------------------------------------------------------
  // Keys
  // -------------------------------------------------------------------------

  /// The provider API keys this page manages: provider credentials, not
  /// channel tokens or custom variables.
  static List<HermesAdminEnvKey> _providerKeys(List<HermesAdminEnvKey> all) => [
    for (final key in all)
      if (key.category == 'provider' && key.isPassword && !key.channelManaged)
        key,
  ];

  static String _keyLabel(HermesAdminEnvKey key) =>
      key.providerLabel.isNotEmpty ? key.providerLabel : key.name;

  void _keysSaved(_KeyReport report) {
    final partial = report.failed.isNotEmpty;
    final text = partial
        ? 'Saved ${report.label} for ${report.saved.join(', ')}. Couldn’t '
              'save it for ${report.failed.join(', ')}. Replace the key and '
              'apply it to all bots again to retry.'
        : report.saved.length > 1
        ? 'Saved ${report.label} for ${report.saved.length} bots '
              '(${report.saved.join(', ')}).'
        : 'Saved ${report.label}.';
    setState(() {
      _replacing = null;
      _adding = false;
      _keyNote = _Note(text, error: partial);
    });
    // A new key can make a provider's models available.
    unawaited(_loadKeys(quiet: true));
    unawaited(_loadModel(quiet: true));
  }

  Future<void> _removeKey(HermesAdminEnvKey key) async {
    final client = _client;
    if (client == null || _removing != null) return;
    final agreed = await _confirm(
      title: 'Remove ${_keyLabel(key)} key?',
      message:
          '$_botName will no longer be able to use ${_keyLabel(key)} until '
          'a key is added again. Other bots keep their own keys.',
      confirmLabel: 'Remove key',
      destructive: true,
    );
    if (!agreed || !mounted) return;
    setState(() {
      _removing = key.name;
      _keyNote = null;
    });
    try {
      try {
        await client.deleteEnvKey(_scope, key.name);
      } on HermesAdminNotFound {
        // Already gone.
      }
      if (!mounted) return;
      setState(() {
        _removing = null;
        _replacing = null;
        _keyNote = _Note('Removed ${_keyLabel(key)}.');
      });
      unawaited(_loadKeys(quiet: true));
      unawaited(_loadModel(quiet: true));
    } catch (error) {
      _logFailure('remove key', 'keys', error);
      if (!mounted) return;
      setState(() {
        _removing = null;
        _keyNote = _Note(
          _describe(error, "Couldn't remove the key. Try again."),
          error: true,
        );
      });
    }
  }

  // -------------------------------------------------------------------------
  // Sign-in
  // -------------------------------------------------------------------------

  Future<void> _startSignIn(HermesAdminProviderSignIn provider) async {
    final client = _client;
    if (client == null || _flow != null || _startingProviderId != null) return;
    setState(() {
      _startingProviderId = provider.id;
      _signInNote = null;
    });
    try {
      final start = await client.startProviderSignIn(_scope, provider.id);
      if (!mounted) {
        unawaited(_cancelRemote(client, start.sessionId));
        return;
      }
      final flow = _SignInFlow(
        providerId: provider.id,
        providerName: provider.name,
        start: start,
        client: client,
      );
      setState(() {
        _startingProviderId = null;
        _flow = flow;
      });
      _schedulePoll(flow);
    } catch (error) {
      _logFailure('start sign-in', 'signIns', error);
      if (!mounted) return;
      setState(() {
        _startingProviderId = null;
        _signInNote = _Note(
          _describe(error, "Couldn't start the sign-in. Try again."),
          error: true,
        );
      });
    }
  }

  void _schedulePoll(_SignInFlow flow) {
    _pollTimer?.cancel();
    _pollTimer = Timer(flow.start.pollInterval, () => unawaited(_poll(flow)));
  }

  Future<void> _poll(_SignInFlow flow) async {
    if (!mounted || !identical(_flow, flow)) return;
    flow.waited += flow.start.pollInterval;
    try {
      final result = await flow.client.pollProviderSignIn(
        _scope,
        flow.providerId,
        flow.start.sessionId,
      );
      if (!mounted || !identical(_flow, flow)) return;
      switch (result.state) {
        case HermesAdminSignInState.approved:
          _endFlow();
          setState(
            () => _signInNote = _Note('Signed in to ${flow.providerName}.'),
          );
          // The provider's models are available now.
          unawaited(_loadSignIns(quiet: true));
          unawaited(_loadModel(quiet: true));
        case HermesAdminSignInState.failed:
          _failFlow(result.errorMessage ?? 'The sign-in was not completed.');
        case HermesAdminSignInState.expired:
          _failFlow('The code expired. Start the sign-in again.');
        case HermesAdminSignInState.pending:
          flow.failedPolls = 0;
          if (flow.waited >= flow.start.expiresIn) {
            _failFlow('The code expired. Start the sign-in again.');
          } else {
            _schedulePoll(flow);
          }
      }
    } on HermesAdminNotFound {
      if (mounted && identical(_flow, flow)) {
        _failFlow('The sign-in ended before it was approved.');
      }
    } on HermesAdminUnavailable {
      if (mounted && identical(_flow, flow)) {
        _failFlow('Sign-in isn’t available on this Hermes server.');
      }
    } catch (error) {
      _logFailure('poll sign-in', 'signIns', error);
      if (!mounted || !identical(_flow, flow)) return;
      flow.failedPolls++;
      if (flow.failedPolls >= _kMaxFailedPolls) {
        _failFlow('Lost contact with Hermes while waiting. Try again.');
      } else {
        _schedulePoll(flow);
      }
    }
  }

  void _failFlow(String message) {
    _endFlow(cancelRemote: true);
    setState(() => _signInNote = _Note(message, error: true));
  }

  /// Stops the running sign-in. [cancelRemote] also tells Hermes to drop
  /// its session, which is best effort.
  void _endFlow({bool cancelRemote = false, bool notify = true}) {
    _pollTimer?.cancel();
    _pollTimer = null;
    final flow = _flow;
    _flow = null;
    if (flow != null && cancelRemote) {
      unawaited(_cancelRemote(flow.client, flow.start.sessionId));
    }
    if (flow != null && notify && mounted) setState(() {});
  }

  Future<void> _cancelRemote(HermesAdminClient client, String sessionId) async {
    try {
      await client.cancelProviderSignIn(_scope, sessionId);
    } catch (_) {
      // The session expires on its own.
    }
  }

  Future<void> _disconnect(HermesAdminProviderSignIn provider) async {
    final client = _client;
    if (client == null || _disconnectingProviderId != null) return;
    final agreed = await _confirm(
      title: 'Disconnect ${provider.name}?',
      message:
          '$_botName will be signed out of ${provider.name}. Other bots keep '
          'their own sign-ins.',
      confirmLabel: 'Disconnect',
      destructive: true,
    );
    if (!agreed || !mounted) return;
    setState(() {
      _disconnectingProviderId = provider.id;
      _signInNote = null;
    });
    try {
      await client.disconnectProvider(_scope, provider.id);
      if (!mounted) return;
      setState(() {
        _disconnectingProviderId = null;
        _signInNote = _Note('Disconnected ${provider.name}.');
      });
      unawaited(_loadSignIns(quiet: true));
      unawaited(_loadModel(quiet: true));
    } catch (error) {
      _logFailure('disconnect', 'signIns', error);
      if (!mounted) return;
      setState(() {
        _disconnectingProviderId = null;
        _signInNote = _Note(
          _describe(error, "Couldn't disconnect. Try again."),
          error: true,
        );
      });
    }
  }

  Future<void> _openVerification(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null || uri.scheme != 'https') return;
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      // The owner can still type the address by hand.
    }
  }

  // -------------------------------------------------------------------------
  // Sheets
  // -------------------------------------------------------------------------

  Future<bool> _confirm({
    required String title,
    required String message,
    required String confirmLabel,
    bool destructive = false,
  }) async {
    final danger = Theme.of(context).extension<HermezStatusColors>()?.danger;
    final agreed = await showHermezSheet<bool>(
      context,
      title: title,
      eyebrow: _botName,
      body: Builder(
        builder: (context) {
          final palette = HermezChatPalette.forBrightness(
            Theme.of(context).brightness,
          );
          return Text(
            message,
            key: const ValueKey('confirm-message'),
            style: HermezType.body(palette),
          );
        },
      ),
      footer: Builder(
        builder: (sheetContext) => Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(
              key: const ValueKey('confirm-cancel'),
              onPressed: () => Navigator.of(sheetContext).pop(false),
              child: const Text('Cancel'),
            ),
            const SizedBox(width: 8),
            FilledButton(
              key: const ValueKey('confirm-ok'),
              style: destructive && danger != null
                  ? FilledButton.styleFrom(backgroundColor: danger)
                  : null,
              onPressed: () => Navigator.of(sheetContext).pop(true),
              child: Text(confirmLabel),
            ),
          ],
        ),
      ),
    );
    return agreed == true;
  }

  Future<_Entry?> _pickModel({
    required String title,
    required List<HermesAdminModelProvider> providers,
    String? currentProvider,
    String? currentModel,
  }) => showHermezSheet<_Entry>(
    context,
    title: title,
    eyebrow: _botName,
    body: _ModelPicker(
      providers: providers,
      currentProvider: currentProvider,
      currentModel: currentModel,
    ),
  );

  // -------------------------------------------------------------------------
  // Build
  // -------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    // A reconnect hands over a new client; read everything again.
    ref.listen(hermesAdminClientProvider, (previous, next) {
      if (previous != next) _loadAll();
    });
    final palette = HermezChatPalette.forBrightness(
      Theme.of(context).brightness,
    );
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Models and providers',
            style: HermezType.section(palette).copyWith(fontSize: 20),
          ),
          const SizedBox(height: 6),
          Text(
            'For $_botName. Changes apply to its new chats. Keys are saved on '
            'this bot’s Hermes and show masked once saved; they are never '
            'shown in full again.',
            key: const ValueKey('models-providers-scope'),
            style: HermezType.meta(palette),
          ),
          const SizedBox(height: 14),
          _Card(title: 'Default model', child: _modelCard(palette)),
          _Card(
            title: 'Reasoning',
            subtitle:
                'How long Hermes thinks before it answers. Higher is slower '
                'and more careful.',
            child: _reasoningCard(palette),
          ),
          _Card(
            title: 'Fallback models',
            subtitle:
                'Tried in this order when the default model fails or is '
                'unavailable.',
            child: _fallbackCard(palette),
          ),
          _Card(
            title: 'Provider keys',
            subtitle:
                'Each bot has its own keys. A saved key can only be replaced '
                'or removed.',
            child: _keysCard(palette),
          ),
          _Card(
            title: 'Sign in with an account',
            subtitle: 'Some providers sign in with a code instead of a key.',
            child: _signInsCard(palette),
          ),
        ],
      ),
    );
  }

  /// The shared page states around one part's [ready] content.
  Widget _slotView<T>({
    required String id,
    required _Slot<T> slot,
    required VoidCallback retry,
    required Widget Function(T value) ready,
    required Widget disabledControl,
    required int bones,
  }) {
    switch (slot.phase) {
      case _Phase.loading:
        return Align(
          alignment: Alignment.topLeft,
          child: HermezSkeleton.lines(
            key: ValueKey('$id-loading'),
            count: bones,
          ),
        );
      case _Phase.failed:
        return _ErrorRow(
          key: ValueKey('$id-error'),
          retryKey: ValueKey('$id-retry'),
          message: slot.message,
          onRetry: retry,
        );
      case _Phase.unavailable:
        return _UnavailableNote(
          key: ValueKey('$id-unavailable'),
          reason: slot.message,
          control: disabledControl,
        );
      case _Phase.ready:
        return ready(slot.value as T);
    }
  }

  Widget _modelCard(HermezChatPalette palette) =>
      _slotView<HermesAdminModelOptions>(
        id: 'model',
        slot: _model,
        retry: () => unawaited(_loadModel()),
        bones: 2,
        disabledControl: const OutlinedButton(
          onPressed: null,
          child: Text('Change model'),
        ),
        ready: (options) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        options.model.isEmpty
                            ? 'No default model set'
                            : hermesModelShortName(options.model),
                        key: const ValueKey('model-current'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: HermezType.body(
                          palette,
                        ).copyWith(fontWeight: FontWeight.w800, fontSize: 16),
                      ),
                      if (options.provider.isNotEmpty)
                        Text(
                          'via ${_providerLabel(options.provider)}',
                          key: const ValueKey('model-provider'),
                          style: HermezType.meta(palette),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                if (_modelBusy)
                  const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  FilledButton.tonal(
                    key: const ValueKey('model-change'),
                    onPressed: _changeModel,
                    child: const Text('Change'),
                  ),
              ],
            ),
            if (options.providers.every((provider) => provider.models.isEmpty))
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'No provider has models yet. Add a key or sign in below.',
                  style: HermezType.meta(palette),
                ),
              ),
            _NoteLine(note: _modelNote, id: 'model-note'),
          ],
        ),
      );

  Widget _reasoningCard(HermezChatPalette palette) => _slotView<_ConfigView>(
    id: 'reasoning',
    slot: _config,
    retry: () => unawaited(_loadConfig()),
    bones: 2,
    disabledControl: AbsorbPointer(
      child: Opacity(
        opacity: 0.45,
        child: HermezSegments(
          labels: [for (final value in _kBaseEfforts) _effortLabel(value)],
          index: 2,
          onChanged: (_) {},
        ),
      ),
    ),
    ready: (config) {
      final values = _effortValues(_effort);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AbsorbPointer(
            absorbing: _effortBusy,
            child: HermezSegments(
              key: const ValueKey('reasoning-segments'),
              labels: [for (final value in values) _effortLabel(value)],
              index: values.indexOf(_effort),
              onChanged: (i) => unawaited(_setEffort(values[i])),
            ),
          ),
          if (config.effort.isEmpty && _effortShown == null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'Not set for this bot, so Hermes uses Medium.',
                style: HermezType.meta(palette),
              ),
            ),
          _NoteLine(note: _effortNote, id: 'reasoning-note'),
        ],
      );
    },
  );

  Widget _fallbackCard(HermezChatPalette palette) => _slotView<_ConfigView>(
    id: 'fallbacks',
    slot: _config,
    retry: () => unawaited(_loadConfig()),
    bones: 2,
    disabledControl: const OutlinedButton(
      onPressed: null,
      child: Text('Add fallback'),
    ),
    ready: (config) {
      final fallbacks = config.fallbacks;
      final canAdd = _model.phase == _Phase.ready && !_fallbackBusy;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (fallbacks.isEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                'No fallbacks. If the default model fails, the chat stops.',
                key: const ValueKey('fallbacks-empty'),
                style: HermezType.meta(palette),
              ),
            ),
          for (final (i, entry) in fallbacks.indexed)
            _FallbackRow(
              key: ValueKey('fallback-row-$i'),
              index: i,
              entry: entry,
              providerLabel: _providerLabel(entry.provider),
              canMoveUp: i > 0 && !_fallbackBusy,
              canMoveDown: i < fallbacks.length - 1 && !_fallbackBusy,
              canRemove: !_fallbackBusy,
              onUp: () => unawaited(_moveFallback(i, -1)),
              onDown: () => unawaited(_moveFallback(i, 1)),
              onRemove: () => unawaited(_removeFallback(i)),
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              key: const ValueKey('fallback-add'),
              onPressed: canAdd ? _addFallback : null,
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Add fallback'),
            ),
          ),
          if (_model.phase != _Phase.ready)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'The model list needs to load first.',
                style: HermezType.meta(palette),
              ),
            ),
          _NoteLine(note: _fallbackNote, id: 'fallbacks-note'),
        ],
      );
    },
  );

  Widget _keysCard(HermezChatPalette palette) =>
      _slotView<List<HermesAdminEnvKey>>(
        id: 'keys',
        slot: _keys,
        retry: () => unawaited(_loadKeys()),
        bones: 3,
        disabledControl: const OutlinedButton(
          onPressed: null,
          child: Text('Add a key'),
        ),
        ready: (all) {
          final client = _client;
          final provider = _providerKeys(all);
          final saved = [
            for (final key in provider)
              if (key.isSet) key,
          ]..sort((a, b) => _keyLabel(a).compareTo(_keyLabel(b)));
          final unset = [
            for (final key in provider)
              if (!key.isSet) key,
          ]..sort((a, b) => _keyLabel(a).compareTo(_keyLabel(b)));
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (saved.isEmpty && !_adding)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    'No provider keys saved for this bot yet.',
                    key: const ValueKey('keys-empty'),
                    style: HermezType.meta(palette),
                  ),
                ),
              for (final key in saved)
                _SavedKeyCard(
                  key: ValueKey('key-card-${key.name}'),
                  envKey: key,
                  label: _keyLabel(key),
                  removing: _removing == key.name,
                  editing: _replacing == key.name,
                  onReplace: () => setState(() {
                    _replacing = key.name;
                    _adding = false;
                    _keyNote = null;
                  }),
                  onRemove: () => unawaited(_removeKey(key)),
                  form: client == null
                      ? null
                      : _KeyForm(
                          key: ValueKey('key-form-${key.name}'),
                          client: client,
                          scope: _scope,
                          fixed: key,
                          choices: const [],
                          onDone: _keysSaved,
                          onCancel: () => setState(() => _replacing = null),
                        ),
                ),
              if (_adding && client != null)
                _KeyForm(
                  key: const ValueKey('key-form'),
                  client: client,
                  scope: _scope,
                  choices: unset,
                  onDone: _keysSaved,
                  onCancel: () => setState(() => _adding = false),
                )
              else
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    key: const ValueKey('key-add'),
                    onPressed: unset.isEmpty
                        ? null
                        : () => setState(() {
                            _adding = true;
                            _replacing = null;
                            _keyNote = null;
                          }),
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: const Text('Add a key'),
                  ),
                ),
              _NoteLine(note: _keyNote, id: 'keys-note'),
            ],
          );
        },
      );

  Widget _signInsCard(HermezChatPalette palette) =>
      _slotView<List<HermesAdminProviderSignIn>>(
        id: 'signins',
        slot: _signIns,
        retry: () => unawaited(_loadSignIns()),
        bones: 3,
        disabledControl: const SizedBox.shrink(),
        ready: (providers) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (providers.isEmpty)
              Text(
                'No sign-in providers on this Hermes.',
                style: HermezType.meta(palette),
              ),
            for (final provider in providers) _signInRow(provider, palette),
            _NoteLine(note: _signInNote, id: 'signin-note'),
          ],
        ),
      );

  Widget _signInRow(
    HermesAdminProviderSignIn provider,
    HermezChatPalette palette,
  ) {
    final flow = _flow;
    final active = flow != null && flow.providerId == provider.id;
    final starting = _startingProviderId == provider.id;
    final disconnecting = _disconnectingProviderId == provider.id;
    final success =
        Theme.of(context).extension<HermezStatusColors>()?.success ??
        Colors.green;
    final canSignIn = provider.supportsDeviceCode;
    return Container(
      key: ValueKey('signin-${provider.id}'),
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
      decoration: BoxDecoration(
        color: palette.canvas,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: palette.border.withValues(alpha: 0.7)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      provider.name,
                      style: HermezType.body(palette)
                          .copyWith(fontWeight: FontWeight.w700),
                    ),
                    Row(
                      children: [
                        if (provider.loggedIn)
                          Padding(
                            padding: const EdgeInsets.only(right: 4),
                            child: Icon(
                              Icons.check_circle_rounded,
                              size: 14,
                              color: success,
                            ),
                          ),
                        Flexible(
                          child: Text(
                            provider.loggedIn
                                ? (canSignIn
                                      ? 'Signed in'
                                      : 'Signed in on the server')
                                : 'Not signed in',
                            style: HermezType.meta(palette),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (canSignIn && !active)
                if (starting || disconnecting)
                  const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                else if (provider.loggedIn)
                  provider.disconnectable
                      ? TextButton(
                          key: ValueKey('signin-disconnect-${provider.id}'),
                          onPressed: () => unawaited(_disconnect(provider)),
                          child: const Text('Disconnect'),
                        )
                      : const SizedBox.shrink()
                else
                  FilledButton.tonal(
                    key: ValueKey('signin-start-${provider.id}'),
                    onPressed: _flow == null && _startingProviderId == null
                        ? () => unawaited(_startSignIn(provider))
                        : null,
                    child: const Text('Sign in'),
                  ),
            ],
          ),
          if (!canSignIn)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                _guidance(provider),
                key: ValueKey('signin-guidance-${provider.id}'),
                style: HermezType.meta(palette),
              ),
            ),
          if (active) _signInProgress(flow, palette),
        ],
      ),
    );
  }

  String _guidance(HermesAdminProviderSignIn provider) {
    final command = provider.cliCommand;
    final cli = command == null || command.trim().isEmpty
        ? ''
        : ' Or run “${HermesSecretRedaction.redactText(command.trim())}” '
              'on the server.';
    return '${provider.name} can’t sign in from the app. Add an API key '
        'under Provider keys.$cli';
  }

  Widget _signInProgress(_SignInFlow flow, HermezChatPalette palette) {
    final url = flow.start.verificationUrl;
    final canOpen = Uri.tryParse(url)?.scheme == 'https';
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        key: const ValueKey('signin-progress'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Open this page and enter the code:',
            style: HermezType.meta(palette),
          ),
          const SizedBox(height: 4),
          SelectableText(
            url,
            key: const ValueKey('signin-url'),
            style: HermezType.body(palette).copyWith(fontSize: 13),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: SelectableText(
                  flow.start.userCode,
                  key: const ValueKey('signin-code'),
                  style: TextStyle(
                    fontFamily: AppTypography.monospaceFontFamily,
                    fontFamilyFallback: const ['Consolas', 'Courier New'],
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 3,
                    color: palette.ink,
                  ),
                ),
              ),
              IconButton(
                key: const ValueKey('signin-copy'),
                tooltip: 'Copy code',
                icon: const Icon(Icons.copy_rounded, size: 20),
                onPressed: () => unawaited(
                  Clipboard.setData(ClipboardData(text: flow.start.userCode)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              const SizedBox.square(
                dimension: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Waiting for you to approve it…',
                  key: const ValueKey('signin-waiting'),
                  style: HermezType.meta(palette),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              if (canOpen)
                FilledButton.tonal(
                  key: const ValueKey('signin-open'),
                  onPressed: () => unawaited(_openVerification(url)),
                  child: const Text('Open sign-in page'),
                ),
              TextButton(
                key: const ValueKey('signin-cancel'),
                onPressed: () => _endFlow(cancelRemote: true),
                child: const Text('Cancel'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Layout pieces
// ---------------------------------------------------------------------------

class _Card extends StatelessWidget {
  const _Card({required this.title, required this.child, this.subtitle});

  final String title;
  final String? subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final palette = HermezChatPalette.forBrightness(
      Theme.of(context).brightness,
    );
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: palette.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title.toUpperCase(), style: HermezType.technical(palette.muted)),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(subtitle!, style: HermezType.meta(palette)),
          ],
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _ErrorRow extends StatelessWidget {
  const _ErrorRow({
    super.key,
    required this.retryKey,
    required this.message,
    required this.onRetry,
  });

  final Key retryKey;
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final palette = HermezChatPalette.forBrightness(
      Theme.of(context).brightness,
    );
    final danger =
        Theme.of(context).extension<HermezStatusColors>()?.danger ??
        Theme.of(context).colorScheme.error;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.error_outline_rounded, size: 18, color: danger),
        const SizedBox(width: 8),
        Expanded(child: Text(message, style: HermezType.body(palette))),
        const SizedBox(width: 8),
        OutlinedButton(
          key: retryKey,
          onPressed: onRetry,
          child: const Text('Retry'),
        ),
      ],
    );
  }
}

/// A part this Hermes does not have: the control stays, disabled, with the
/// reason beside it.
class _UnavailableNote extends StatelessWidget {
  const _UnavailableNote({
    super.key,
    required this.reason,
    required this.control,
  });

  final String reason;
  final Widget control;

  @override
  Widget build(BuildContext context) {
    final palette = HermezChatPalette.forBrightness(
      Theme.of(context).brightness,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Align(alignment: Alignment.centerLeft, child: control),
        const SizedBox(height: 6),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.block_rounded, size: 14, color: palette.muted),
            const SizedBox(width: 6),
            Expanded(child: Text(reason, style: HermezType.meta(palette))),
          ],
        ),
      ],
    );
  }
}

class _NoteLine extends StatelessWidget {
  const _NoteLine({required this.note, required this.id});

  final _Note? note;
  final String id;

  @override
  Widget build(BuildContext context) {
    final note = this.note;
    if (note == null) return const SizedBox.shrink();
    final palette = HermezChatPalette.forBrightness(
      Theme.of(context).brightness,
    );
    final status = Theme.of(context).extension<HermezStatusColors>();
    final color = note.error
        ? (status?.danger ?? Theme.of(context).colorScheme.error)
        : (status?.success ?? Colors.green);
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Semantics(
        liveRegion: true,
        child: Row(
          key: ValueKey(id),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              note.error
                  ? Icons.error_outline_rounded
                  : Icons.check_circle_outline_rounded,
              size: 16,
              color: color,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                note.text,
                style: HermezType.body(palette).copyWith(fontSize: 13),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FallbackRow extends StatelessWidget {
  const _FallbackRow({
    super.key,
    required this.index,
    required this.entry,
    required this.providerLabel,
    required this.canMoveUp,
    required this.canMoveDown,
    required this.canRemove,
    required this.onUp,
    required this.onDown,
    required this.onRemove,
  });

  final int index;
  final _Entry entry;
  final String providerLabel;
  final bool canMoveUp;
  final bool canMoveDown;
  final bool canRemove;
  final VoidCallback onUp;
  final VoidCallback onDown;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final palette = HermezChatPalette.forBrightness(
      Theme.of(context).brightness,
    );
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(14, 4, 4, 4),
      decoration: BoxDecoration(
        color: palette.canvas,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: palette.border.withValues(alpha: 0.7)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 22,
            child: Text('${index + 1}', style: HermezType.meta(palette)),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  hermesModelShortName(entry.model),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: HermezType.body(palette)
                      .copyWith(fontWeight: FontWeight.w700),
                ),
                Text(providerLabel, style: HermezType.meta(palette)),
              ],
            ),
          ),
          IconButton(
            key: ValueKey('fallback-up-$index'),
            tooltip: 'Move up',
            onPressed: canMoveUp ? onUp : null,
            icon: const Icon(Icons.arrow_upward_rounded, size: 20),
          ),
          IconButton(
            key: ValueKey('fallback-down-$index'),
            tooltip: 'Move down',
            onPressed: canMoveDown ? onDown : null,
            icon: const Icon(Icons.arrow_downward_rounded, size: 20),
          ),
          IconButton(
            key: ValueKey('fallback-remove-$index'),
            tooltip: 'Remove',
            onPressed: canRemove ? onRemove : null,
            icon: const Icon(Icons.close_rounded, size: 20),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Keys
// ---------------------------------------------------------------------------

/// A saved key: Hermes' masked preview, and only Replace and Remove (AE6).
/// Replace opens [form] in place; nothing here can show the full value.
class _SavedKeyCard extends StatelessWidget {
  const _SavedKeyCard({
    super.key,
    required this.envKey,
    required this.label,
    required this.removing,
    required this.editing,
    required this.onReplace,
    required this.onRemove,
    required this.form,
  });

  final HermesAdminEnvKey envKey;
  final String label;
  final bool removing;
  final bool editing;
  final VoidCallback onReplace;
  final VoidCallback onRemove;
  final Widget? form;

  /// Hermes' own preview, run through the secret detector in case a full
  /// value ever came back. Never longer than the preview.
  String get _masked {
    final preview = envKey.redactedValue;
    if (preview == null || preview.isEmpty) return '••••••••';
    return HermesSecretRedaction.redactText(preview);
  }

  @override
  Widget build(BuildContext context) {
    final palette = HermezChatPalette.forBrightness(
      Theme.of(context).brightness,
    );
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
      decoration: BoxDecoration(
        color: palette.canvas,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: palette.border.withValues(alpha: 0.7)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: HermezType.body(palette)
                          .copyWith(fontWeight: FontWeight.w700),
                    ),
                    Text(envKey.name, style: HermezType.meta(palette)),
                    const SizedBox(height: 2),
                    Text(
                      _masked,
                      key: ValueKey('key-masked-${envKey.name}'),
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontFamilyFallback: const ['Consolas', 'Courier New'],
                        fontSize: 13,
                        color: palette.ink,
                      ),
                    ),
                  ],
                ),
              ),
              if (removing)
                const Padding(
                  padding: EdgeInsets.all(12),
                  child: SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              else if (!editing) ...[
                TextButton(
                  key: ValueKey('key-replace-${envKey.name}'),
                  onPressed: onReplace,
                  child: const Text('Replace'),
                ),
                TextButton(
                  key: ValueKey('key-remove-${envKey.name}'),
                  onPressed: onRemove,
                  child: const Text('Remove'),
                ),
              ],
            ],
          ),
          if (editing && form != null) ...[const SizedBox(height: 8), form!],
        ],
      ),
    );
  }
}

/// Entry of a key: for a [fixed] key (Replace) or one picked from [choices]
/// (Add). Tests the key with its provider before saving, and can write it to
/// every bot.
///
/// - A key the provider rejects is not saved.
/// - When the key cannot be tested (offline, or this Hermes has no probe),
///   Save anyway is offered.
/// - The text is cleared as soon as the key is saved, and the page only ever
///   sees Hermes' masked preview after that.
class _KeyForm extends ConsumerStatefulWidget {
  const _KeyForm({
    super.key,
    required this.client,
    required this.scope,
    required this.choices,
    required this.onDone,
    required this.onCancel,
    this.fixed,
  });

  final HermesAdminClient client;
  final String scope;
  final HermesAdminEnvKey? fixed;
  final List<HermesAdminEnvKey> choices;
  final ValueChanged<_KeyReport> onDone;
  final VoidCallback onCancel;

  @override
  ConsumerState<_KeyForm> createState() => _KeyFormState();
}

class _KeyFormState extends ConsumerState<_KeyForm> {
  final TextEditingController _controller = TextEditingController();
  String? _selected;
  bool _applyAll = false;
  bool _busy = false;
  String? _error;

  /// Why the key could not be tested; Save anyway is offered while set.
  String? _untested;

  HermesAdminEnvKey? get _target {
    if (widget.fixed != null) return widget.fixed;
    for (final key in widget.choices) {
      if (key.name == _selected) return key;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      // Typing again clears a stale verdict.
      if (_untested != null || _error != null) {
        setState(() {
          _untested = null;
          _error = null;
        });
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save({required bool skipTest}) async {
    final target = _target;
    final value = HermesSecretField.normalize(_controller.text);
    if (target == null) {
      setState(() => _error = 'Choose a provider first.');
      return;
    }
    if (value.isEmpty) {
      setState(() => _error = 'Paste the key first.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _untested = null;
    });
    if (!skipTest) {
      final verdict = await _test(target, value);
      if (!mounted) return;
      if (verdict != null) {
        setState(() {
          _busy = false;
          if (verdict.blocked) {
            _error = verdict.message;
          } else {
            _untested = verdict.message;
          }
        });
        return;
      }
    }
    await _write(target, value);
  }

  /// Null when the key passed. A blocked verdict stops the save; otherwise
  /// the key could not be tested and the owner decides.
  Future<({bool blocked, String message})?> _test(
    HermesAdminEnvKey target,
    String value,
  ) async {
    try {
      final verdict = await widget.client.validateProviderKey(
        key: target.name,
        value: value,
      );
      if (verdict.ok) return null;
      if (verdict.rejected) {
        return (
          blocked: true,
          message: verdict.message.isEmpty
              ? 'The provider rejected this key. Check it and try again.'
              : verdict.message,
        );
      }
      return (
        blocked: false,
        message: verdict.message.isEmpty
            ? 'The key couldn’t be tested right now.'
            : 'The key couldn’t be tested: ${verdict.message}',
      );
    } on HermesAdminUnavailable {
      return (
        blocked: false,
        message:
            'This Hermes server can’t test keys, so this one is unchecked.',
      );
    } on HermesAdminException catch (error) {
      return (
        blocked: true,
        message: _HermesModelsProvidersPageState._describe(
          error,
          'Hermes refused to test this key.',
          secrets: [value],
        ),
      );
    } catch (error) {
      _HermesModelsProvidersPageState._logFailure('test key', 'keys', error);
      return (
        blocked: false,
        message:
            'Couldn’t reach Hermes or the provider to test the key. Check '
            'the connection.',
      );
    }
  }

  Future<void> _write(HermesAdminEnvKey target, String value) async {
    try {
      await widget.client.setEnvKey(widget.scope, target.name, value);
    } catch (error) {
      _HermesModelsProvidersPageState._logFailure('save key', 'keys', error);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = _HermesModelsProvidersPageState._describe(
          error,
          'Couldn’t save the key. Check the connection and try again.',
          secrets: [value],
        );
      });
      return;
    }
    final saved = <String>[widget.scope];
    final failed = <String>[];
    if (_applyAll) {
      for (final name in _otherBots()) {
        try {
          await widget.client.setEnvKey(name, target.name, value);
          saved.add(name);
        } catch (error) {
          _HermesModelsProvidersPageState._logFailure(
            'save key for another bot',
            'keys',
            error,
          );
          failed.add(name);
        }
      }
    }
    // The key is on the server now; nothing keeps it here.
    if (!mounted) return;
    _controller.clear();
    widget.onDone(
      _KeyReport(
        label: _HermesModelsProvidersPageState._keyLabel(target),
        saved: saved,
        failed: failed,
      ),
    );
  }

  List<String> _otherBots() => [
    for (final profile
        in ref.read(hermesAdminProfilesProvider).value ??
            const <HermesAdminProfile>[])
      if (profile.name != widget.scope) profile.name,
  ];

  @override
  Widget build(BuildContext context) {
    final palette = HermezChatPalette.forBrightness(
      Theme.of(context).brightness,
    );
    final status = Theme.of(context).extension<HermezStatusColors>();
    final warning = status?.warning ?? Colors.orange;
    // Watching keeps the bot list alive while the form is open.
    final profiles = ref.watch(hermesAdminProfilesProvider);
    final others = [
      for (final profile in profiles.value ?? const <HermesAdminProfile>[])
        if (profile.name != widget.scope) profile.name,
    ];
    final target = _target;
    return Container(
      key: const ValueKey('key-form-body'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: palette.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.fixed == null) ...[
            DropdownButtonFormField<String>(
              key: const ValueKey('key-provider-picker'),
              initialValue: _selected,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Provider'),
              items: [
                for (final key in widget.choices)
                  DropdownMenuItem(
                    value: key.name,
                    child: Text(
                      _HermesModelsProvidersPageState._keyLabel(key),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: _busy
                  ? null
                  : (value) => setState(() {
                      _selected = value;
                      _error = null;
                    }),
            ),
            const SizedBox(height: 10),
          ] else
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text(
                'New ${_HermesModelsProvidersPageState._keyLabel(widget.fixed!)} '
                'key. The saved one is replaced.',
                style: HermezType.meta(palette),
              ),
            ),
          HermesSecretField(
            key: const ValueKey('key-field'),
            controller: _controller,
            label: 'API key',
            enabled: !_busy,
            errorText: _error,
            onSubmitted: (_) => unawaited(_save(skipTest: false)),
          ),
          if (target != null && target.description.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                HermesSecretRedaction.redactText(target.description),
                style: HermezType.meta(palette),
              ),
            ),
          if (others.isNotEmpty)
            // A ListTile paints on the nearest Material; the form's own
            // decorated box would hide its ink.
            Material(
              type: MaterialType.transparency,
              child: CheckboxListTile(
                key: const ValueKey('apply-all-bots'),
                value: _applyAll,
                onChanged: _busy
                    ? null
                    : (value) => setState(() => _applyAll = value ?? false),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                dense: true,
                title: const Text('Apply to all bots'),
                subtitle: Text(
                  'Also saves this key for ${others.length} other '
                  '${others.length == 1 ? 'bot' : 'bots'}. Each bot keeps its '
                  'own copy.',
                ),
              ),
            ),
          if (_untested != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(
                key: const ValueKey('key-warning'),
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.warning_amber_rounded, size: 16, color: warning),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _untested!,
                      style: HermezType.body(palette).copyWith(fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 8),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: 8,
            runSpacing: 4,
            children: [
              TextButton(
                key: const ValueKey('key-cancel'),
                onPressed: _busy
                    ? null
                    : () {
                        _controller.clear();
                        widget.onCancel();
                      },
                child: const Text('Cancel'),
              ),
              if (_untested != null)
                OutlinedButton(
                  key: const ValueKey('key-save-anyway'),
                  onPressed: _busy
                      ? null
                      : () => unawaited(_save(skipTest: true)),
                  child: const Text('Save anyway'),
                ),
              FilledButton(
                key: const ValueKey('key-save'),
                onPressed: _busy
                    ? null
                    : () => unawaited(_save(skipTest: false)),
                child: _busy
                    ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Save'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Model picker
// ---------------------------------------------------------------------------

/// Models per provider listed before the owner searches.
const int _kModelsShown = 60;

/// Providers and their models, from `model.options`. Pops the chosen
/// provider and model.
class _ModelPicker extends StatefulWidget {
  const _ModelPicker({
    required this.providers,
    this.currentProvider,
    this.currentModel,
  });

  final List<HermesAdminModelProvider> providers;
  final String? currentProvider;
  final String? currentModel;

  @override
  State<_ModelPicker> createState() => _ModelPickerState();
}

class _ModelPickerState extends State<_ModelPicker> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final palette = HermezChatPalette.forBrightness(
      Theme.of(context).brightness,
    );
    final needle = _query.trim().toLowerCase();
    final usable = [
      for (final provider in widget.providers)
        if (provider.authenticated && provider.models.isNotEmpty) provider,
    ];
    final total = usable.fold<int>(0, (sum, p) => sum + p.models.length);
    final groups = <(HermesAdminModelProvider, List<String>, int)>[];
    for (final provider in usable) {
      final matching = [
        for (final model in provider.models)
          if (needle.isEmpty ||
              model.toLowerCase().contains(needle) ||
              provider.name.toLowerCase().contains(needle))
            model,
      ];
      if (matching.isEmpty) continue;
      final cap = needle.isEmpty ? _kModelsShown : _kModelsShown * 3;
      groups.add((provider, matching.take(cap).toList(), matching.length));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (total > 10) ...[
          TextField(
            key: const ValueKey('model-search'),
            onChanged: (value) => setState(() => _query = value),
            decoration: const InputDecoration(
              hintText: 'Find a model',
              prefixIcon: Icon(Icons.search_rounded, size: 18),
            ),
          ),
          const SizedBox(height: 12),
        ],
        if (groups.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Text(
              usable.isEmpty
                  ? 'No connected providers for this bot. Add a key or sign in '
                        'first.'
                  : 'Nothing matches.',
              style: HermezType.body(palette).copyWith(color: palette.muted),
            ),
          ),
        for (final (provider, shown, count) in groups) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 8, 4, 6),
            child: Text(
              provider.name.toUpperCase(),
              style: HermezType.technical(palette.muted),
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              color: palette.canvas,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              children: [
                for (final (i, model) in shown.indexed) ...[
                  if (i > 0)
                    Divider(
                      height: 1,
                      indent: 14,
                      endIndent: 14,
                      color: palette.border.withValues(alpha: 0.6),
                    ),
                  _ModelRow(
                    key: ValueKey('model-${provider.slug}/$model'),
                    model: model,
                    selected:
                        model == widget.currentModel &&
                        provider.slug == widget.currentProvider,
                    onTap: () => Navigator.of(context)
                        .pop<_Entry>((provider: provider.slug, model: model)),
                  ),
                ],
              ],
            ),
          ),
          if (count > shown.length)
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 6, 4, 0),
              child: Text(
                'Showing ${shown.length} of $count. Search to narrow it down.',
                style: HermezType.meta(palette),
              ),
            ),
        ],
        const SizedBox(height: 8),
        Text(
          'Don’t see a provider? Add its key or sign in on the settings page.',
          style: HermezType.meta(palette),
        ),
      ],
    );
  }
}

class _ModelRow extends StatelessWidget {
  const _ModelRow({
    super.key,
    required this.model,
    required this.selected,
    required this.onTap,
  });

  final String model;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = HermezChatPalette.forBrightness(
      Theme.of(context).brightness,
    );
    return Semantics(
      button: true,
      selected: selected,
      label: '${hermesModelShortName(model)}${selected ? ', current' : ''}',
      child: InkWell(
        onTap: selected ? null : onTap,
        borderRadius: BorderRadius.circular(14),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    hermesModelShortName(model),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: HermezType.body(palette).copyWith(
                      fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Icon(
                  selected ? Icons.check_circle_rounded : Icons.circle_outlined,
                  size: 22,
                  color: selected ? palette.accent : palette.border,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
