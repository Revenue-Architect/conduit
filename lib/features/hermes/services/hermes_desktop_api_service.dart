import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/utils/debug_logger.dart';
import '../../../shared/utils/external_link_launcher.dart';
import '../models/hermes_bot.dart';
import '../models/hermes_chat_input.dart';
import '../models/hermes_config.dart';
import '../models/hermes_mcp.dart';
import '../models/hermes_model.dart';
import '../models/hermes_run_event.dart';
import '../models/hermes_team.dart';
import 'hermes_backend_service.dart';
import 'hermes_http_transport.dart';
import 'hermes_dashboard_rest_bridge.dart';
import 'hermes_dashboard_webview_policy.dart';
import 'hermes_desktop_transport.dart';
import 'hermes_identifier.dart';
import 'hermes_json_guard.dart';
import 'hermes_pending_decision_store.dart';
import 'hermes_live_activity.dart';

part 'hermes_desktop_administration.dart';
part 'hermes_desktop_auth_rest.dart';
part 'hermes_desktop_bots.dart';
part 'hermes_desktop_teams.dart';
part 'hermes_desktop_event_projection.dart';
part 'hermes_desktop_live_runtime.dart';
part 'hermes_desktop_turn_runtime.dart';

typedef HermesDesktopCredentialsWriter = Future<void> Function(
  HermesDesktopCredentials credentials,
);

({String? model, String? provider}) hermesDesktopSessionModelSelection(
  String? model,
  String? provider,
) {
  final rawModel = model?.trim();
  final rawProvider = provider?.trim();
  final safeModel = validateHermesOpaqueIdentifier(rawModel);
  final safeProvider = validateHermesOpaqueIdentifier(rawProvider);
  if (safeModel == null ||
      (rawProvider?.isNotEmpty == true && safeProvider == null)) {
    return (model: null, provider: null);
  }
  // The synthetic fallback means "use Hermes' configured default"; sending
  // the literal model name "default" creates the wrong per-session override.
  if (safeModel == 'default' && safeProvider == null) {
    return (model: null, provider: null);
  }
  return (model: safeModel, provider: safeProvider);
}

/// Returns models discovered from explicitly configured providers in a
/// `model.options` response.
List<Map<String, dynamic>> parseHermesDesktopConfiguredModels(
  Map<String, dynamic> result,
) {
  final models = <Map<String, dynamic>>[];
  final seen = <String>{};

  void addModel(Object? rawModel, String provider, Object? capabilities) {
    if (models.length >= 1000 || provider.isEmpty) return;
    final model = rawModel is Map
        ? (rawModel['id'] ?? rawModel['name'])?.toString().trim()
        : rawModel?.toString().trim();
    if (model == null || model.isEmpty || !seen.add('$provider\u0000$model')) {
      return;
    }
    models.add({
      'id': model,
      'name': rawModel is Map ? (rawModel['name'] ?? model).toString() : model,
      'provider': provider,
      if (capabilities is Map)
        'capabilities': Map<String, dynamic>.from(capabilities),
    });
  }

  final providers = result['providers'];
  if (providers is List) {
    for (final raw in providers.take(1000)) {
      if (raw is! Map) continue;
      final row = Map<String, dynamic>.from(raw);
      if (row['authenticated'] == false) continue;
      final provider = (row['slug'] ?? row['id'] ?? row['name'])
          ?.toString()
          .trim();
      if (provider == null || provider.isEmpty) continue;
      final providerModels = row['models'];
      if (providerModels is! List) continue;
      final capabilities = row['capabilities'];
      for (final model in providerModels) {
        final modelId = model is Map
            ? (model['id'] ?? model['name'])?.toString()
            : model?.toString();
        addModel(
          model,
          provider,
          capabilities is Map ? capabilities[modelId] : null,
        );
        if (models.length >= 1000) break;
      }
    }
  }

  return models;
}

/// Default and smallest page sizes for `GET /api/sessions/{id}/messages`.
///
/// A single 500-message page of a long tool-heavy conversation can exceed the
/// REST transport's character cap, so the pager starts smaller and shrinks
/// further whenever a page is rejected as too large.
const int kHermesDesktopTranscriptPageSize = 200;
const int kHermesDesktopTranscriptMinimumPageSize = 25;

@visibleForTesting
Future<List<Map<String, dynamic>>> loadHermesDesktopTranscriptPages(
  Future<List<Map<String, dynamic>>> Function(int offset, int limit) loadPage, {
  int maximum = 10000,
  int pageSize = kHermesDesktopTranscriptPageSize,
  int minimumPageSize = kHermesDesktopTranscriptMinimumPageSize,
}) async {
  assert(pageSize > 0 && minimumPageSize > 0);
  final messages = <Map<String, dynamic>>[];
  var currentPageSize = pageSize;
  while (messages.length < maximum) {
    final limit = min(currentPageSize, maximum - messages.length);
    final List<Map<String, dynamic>> page;
    try {
      page = await loadPage(messages.length, limit);
    } on HermesResponseTooLargeException {
      if (limit <= minimumPageSize) rethrow;
      currentPageSize = max(minimumPageSize, limit ~/ 2);
      DebugLogger.warning(
        'transcript-page-too-large',
        scope: 'hermes/desktop',
        data: {
          'offset': messages.length,
          'limit': limit,
          'retryLimit': currentPageSize,
        },
      );
      continue;
    }
    messages.addAll(page.take(limit));
    if (page.length < limit) break;
  }
  return messages;
}

@visibleForTesting
List<Map<String, dynamic>> preferLastUsableHermesTranscript(
  List<Map<String, dynamic>> previous,
  List<Map<String, dynamic>> candidate,
) => candidate.length < previous.length ? previous : candidate;

@visibleForTesting
bool hermesNativeRefreshAllowsRetry(
  HermesDesktopTokenSet? previous,
  HermesDesktopTokenSet? refreshed,
) => refreshed != null && !identical(previous, refreshed);

@visibleForTesting
bool hermesSlashNeedsCommandDispatch(HermesDesktopRpcException error) =>
    error.code == -32601 || error.code == 4018;

@visibleForTesting
String hermesExpandedAliasCommand(String target, String original) {
  final argument = original
      .replaceFirst(RegExp(r'^/+'), '')
      .split(' ')
      .skip(1)
      .join(' ')
      .trim();
  return argument.isEmpty ? target : '$target $argument';
}

@visibleForTesting
bool hermesTranscriptHasNewPrompt(Set<String> baseline, Set<String> current) =>
    current.difference(baseline).isNotEmpty;

@visibleForTesting
Uri? parseHermesOAuthUrl(Object? value) {
  final uri = parseAllowedExternalLink(value?.toString() ?? '');
  return uri != null && const {'http', 'https'}.contains(uri.scheme)
      ? uri
      : null;
}

/// Hermes Dashboard REST + Desktop Gateway implementation.
///
final class HermesDesktopApiService
    with WidgetsBindingObserver
    implements HermesBackendService, HermesDesktopTurnService {
  HermesDesktopApiService({
    required this.config,
    Dio? dio,
    HermesDesktopRpcClient? rpc,
    this.onCredentialsChanged,
  }) : _nativeTokens = config.desktopCredentials?.nativeTokens,
       _origin =
           HermesConfig.connectionOrigin(config.baseUrl) ??
           (throw const FormatException('Invalid Hermes Desktop URL.')),
       _root = _normalizeDesktopRoot(config.baseUrl),
       _dio =
           dio ??
           Dio(
             BaseOptions(
               connectTimeout: const Duration(seconds: 20),
               receiveTimeout: const Duration(seconds: 60),
               followRedirects: false,
               receiveDataWhenStatusError: false,
             ),
           ),
       _rpc = rpc ?? HermesDesktopRpcClient() {
    configureHermesTransport(_dio, config);
    _administration = _HermesDesktopAdministration(this);
    _rpc.setDefaultParams({'profile': config.desktopProfile});
  }

  final String _origin;
  final Uri _root;
  @override
  final HermesConfig config;
  final Dio _dio;
  final HermesDesktopRpcClient _rpc;
  late final _HermesDesktopAdministration _administration;
  HermesDashboardRestBridge? _dashboardBridge;
  final HermesDesktopCredentialsWriter? onCredentialsChanged;
  HermesDesktopTokenSet? _nativeTokens;
  bool _closed = false;
  final Map<String, HermesSessionBinding> _bindings = {};
  final Map<String, int> _bindingSocketGenerations = {};
  final Set<String> _freshSessionIds = {};
  final Map<String, List<Map<String, dynamic>>> _lastTranscripts = {};
  final Map<String, String> _appliedSessionOptions = {};

  /// Sessions owned by another profile (Bot Mode chats), keyed by stored id.
  /// Absent means the connection's configured profile owns the session.
  final Map<String, String> _sessionProfiles = {};
  final HermesDesktopEventBuffer _eventBuffer = HermesDesktopEventBuffer();
  final _turnStates = StreamController<HermesDesktopTurnState>.broadcast();
  final _sessionTurnStateChanges = StreamController<String>.broadcast();
  final Map<String, HermesDesktopTurnState> _sessionTurnStates = {};
  final _transcriptChanges = StreamController<String>.broadcast();
  final _desktopContractChanges = StreamController<int>.broadcast();

  Map<String, dynamic>? _status;
  Future<void>? _connecting;
  Future<HermesDesktopTokenSet?>? _refreshing;
  Future<void>? _foregroundReconciliation;
  StreamSubscription<HermesDesktopEvent>? _stateSubscription;
  bool _authoritativeRunning = true;
  bool _supportsMcpRpcLifecycle = true;
  bool _reconciliationStale = false;
  bool _observingLifecycle = false;
  int _desktopContract = 0;

  void startLifecycleObservation() {
    if (_closed || _observingLifecycle) return;
    WidgetsBinding.instance.addObserver(this);
    _observingLifecycle = true;
  }

  /// Reuses the authenticated Gateway credentials for same-origin artifact
  /// downloads. Native PKCE tokens are refreshed and persisted by this service.
  Future<Map<String, String>?> artifactAuthorizationHeaders() async {
    if (_closed || config.desktopAuthKind != HermesDesktopAuthKind.nativePkce) {
      return null;
    }
    try {
      return await _headers(authenticated: true);
    } on StateError {
      return null;
    }
  }

  /// Kanban JSON uses the same native PKCE bearer and refresh path as Desktop
  /// Gateway REST. The installed OAuth gate accepts valid native bearer tokens
  /// on plugin routes; this method cannot reach a different API namespace.
  Future<Object?> requestKanbanJson(
    String method,
    String path, {
    String? board,
    Map<String, Object?>? body,
  }) {
    if (_closed ||
        config.desktopAuthKind != HermesDesktopAuthKind.nativePkce ||
        !const {'GET', 'POST', 'PATCH'}.contains(method) ||
        !path.startsWith('/api/plugins/kanban/') ||
        path.contains('..') ||
        (path != '/api/plugins/kanban/boards' &&
            (board == null || board.trim().isEmpty))) {
      throw StateError('Invalid native Kanban request.');
    }
    return _requestJson(
      method,
      path,
      query: board == null ? null : {'board': board},
      body: body,
    );
  }

  Stream<HermesDesktopTurnState> get turnStates => _turnStates.stream;
  final Map<String, List<HermesLiveActivityEvent>> _activityHistory = {};
  final StreamController<String> _activityChanges =
      StreamController<String>.broadcast();
  final StreamController<HermesLiveActivityEvent> _activityEvents =
      StreamController<HermesLiveActivityEvent>.broadcast();

  /// Every activity event as it is recorded, for any session on this
  /// connection. Used to tell the user when a run finishes or needs them.
  Stream<HermesLiveActivityEvent> get activityEvents => _activityEvents.stream;

  List<HermesLiveActivityEvent> activitySnapshotFor(String storedId) =>
      List.unmodifiable(_activityHistory[storedId] ?? const []);

  Stream<List<HermesLiveActivityEvent>> activityFor(String storedId) =>
      Stream<List<HermesLiveActivityEvent>>.multi((controller) {
        final subscription = _activityChanges.stream.listen(
          (changedId) {
            if (changedId == storedId)
              controller.add(activitySnapshotFor(storedId));
          },
          onError: controller.addError,
          onDone: controller.close,
        );
        controller
          ..add(activitySnapshotFor(storedId))
          ..onCancel = subscription.cancel;
      });
  Stream<HermesDesktopTurnState> turnStatesFor(String storedId) =>
      Stream<HermesDesktopTurnState>.multi((controller) {
        final subscription = _sessionTurnStateChanges.stream.listen(
          (changedId) {
            final binding = _bindings[storedId];
            if (changedId == storedId ||
                changedId == binding?.storedId ||
                changedId == binding?.runtimeId) {
              controller.add(turnStateFor(storedId));
            }
          },
          onError: controller.addError,
          onDone: controller.close,
        );
        controller
          ..add(turnStateFor(storedId))
          ..onCancel = subscription.cancel;
      });

  HermesDesktopTurnState turnStateFor(String storedId) {
    if (!_authoritativeRunning) {
      return HermesDesktopTurnState.unsupportedGateway;
    }
    final binding = _bindings[storedId];
    return _sessionTurnStates[storedId] ??
        _sessionTurnStates[binding?.storedId] ??
        _sessionTurnStates[binding?.runtimeId] ??
        HermesDesktopTurnState.idle;
  }

  Stream<String> get transcriptChanges => _transcriptChanges.stream;
  Stream<int> get desktopContractChanges => _desktopContractChanges.stream;
  Stream<int> desktopContracts() => Stream<int>.multi((controller) {
    final subscription = _desktopContractChanges.stream.listen(
      controller.add,
      onError: controller.addError,
      onDone: controller.close,
    );
    controller
      ..add(_desktopContract)
      ..onCancel = subscription.cancel;
  });
  int get desktopContract => _desktopContract;
  bool get supportsAuthoritativeRunning => _authoritativeRunning;
  bool get supportsMcpCredentialUpdate => _supportsMcpRpcLifecycle;
  HermesDesktopRpcClient get rpc => _rpc;
  static Uri _normalizeDesktopRoot(String value) {
    final endpoint = HermesConfig.connectionEndpoint(value);
    if (endpoint == null) {
      throw const FormatException('Invalid Hermes Desktop URL.');
    }
    return Uri.parse(endpoint);
  }

  Uri _uri(String path, [Map<String, dynamic>? query]) {
    final prefix = _root.path == '/' ? '' : _root.path;
    return _root.replace(
      path: '$prefix$path'.replaceAll(RegExp(r'//+'), '/'),
      queryParameters: query?.map(
        (key, value) => MapEntry(key, value.toString()),
      ),
    );
  }

  bool _isProfileScopedRestPath(String path) =>
      path.startsWith('/api/sessions') ||
      path.startsWith('/api/cron') ||
      path.startsWith('/api/mcp');

  @override
  Future<bool> health() => _authHealth();
  Future<Map<String, dynamic>> statusProbe({bool refresh = false}) =>
      _authStatusProbe(refresh: refresh);
  Future<List<String>> listProfiles() => _authListProfiles();
  Future<HermesDesktopTokenSet> signInNative({String? provider}) =>
      _authSignInNative(provider: provider);

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) =>
      _runtimeDidChangeAppLifecycleState(state);

  @override
  Future<String> createSession({String? title, CancelToken? cancelToken}) =>
      _runtimeCreateSession(title: title, cancelToken: cancelToken);
  @override
  Future<String> createDesktopSession({
    String? title,
    HermesDesktopSessionOptions options = const HermesDesktopSessionOptions(),
    CancelToken? cancelToken,
  }) => _runtimeCreateDesktopSession(
    title: title,
    options: options,
    cancelToken: cancelToken,
  );
  @override
  Future<List<Map<String, dynamic>>> listSessions() => _runtimeListSessions();

  /// A profile-specific read for Bot Detail. Never silently relabel another
  /// profile's sessions as this bot's conversations.
  Future<List<Map<String, dynamic>>> listSessionsForProfile(
    String profile,
  ) async {
    if (!HermesConfig.isValidDesktopProfile(profile)) {
      throw ArgumentError.value(profile, 'profile');
    }
    return _objects(
      await _requestJson(
        'GET',
        '/api/profiles/sessions',
        query: {
          'profile': profile,
          'limit': 200,
          'offset': 0,
          'order': 'recent',
        },
      ),
      'sessions',
    );
  }

  /// Associates a server-advertised session with its profile before resume or
  /// transcript reads. A fresh process has no in-memory bot bindings yet.
  void bindSessionProfile(String storedId, String profile) {
    final id = validateHermesOpaqueIdentifier(storedId);
    if (id == null || !HermesConfig.isValidDesktopProfile(profile)) {
      throw ArgumentError('Invalid Hermes session profile binding.');
    }
    _sessionProfiles[id] = profile;
  }

  /// Authoritative profile counts, independent of the paged recent-session list.
  Future<Map<String, int>> sessionTotalsByProfile() async {
    final response = await _requestJson(
      'GET',
      '/api/profiles/sessions',
      query: {'limit': 1, 'offset': 0, 'order': 'recent'},
    );
    final raw = response is Map ? response['profile_totals'] : null;
    if (raw is! Map) return const {};
    return {
      for (final entry in raw.entries)
        if (entry.key is String &&
            HermesConfig.isValidDesktopProfile(entry.key as String) &&
            entry.value is int &&
            (entry.value as int) >= 0)
          entry.key as String: entry.value as int,
    };
  }

  @override
  Future<List<Map<String, dynamic>>> getSessionMessages(
    String id, {
    CancelToken? cancelToken,
  }) => _runtimeGetSessionMessages(id, cancelToken: cancelToken);
  Future<List<HermesPendingDesktopDecision>> pendingDecisionsForSession(
    String storedId,
  ) => _runtimePendingDecisionsForSession(storedId);

  /// Local, exact-session presentation read. Never resumes a Desktop session
  /// merely to decide whether its chat needs an attention footer.
  Future<List<HermesPendingDesktopDecision>> pendingStoredDecisionsForSession(
    String storedId,
  ) => HermesPendingDecisionStore.forSession(
    origin: _origin,
    storedSessionId: storedId,
  );
  @override
  Future<void> renameSession(String id, String title) =>
      _runtimeRenameSession(id, title);
  @override
  Future<void> deleteSession(String id, {CancelToken? cancelToken}) =>
      _runtimeDeleteSession(id, cancelToken: cancelToken);
  bool sessionIdsReferToSameBinding(String left, String right) =>
      _runtimeSessionIdsReferToSameBinding(left, right);
  @override
  Future<String> forkSession(String id) => _runtimeForkSession(id);

  /// Bot Mode roster; empty when the gateway does not support Bot Mode.
  Future<List<HermesBot>> listBots() => _listBots();

  /// A bot's avatar as a data URL, or null when it has none.
  Future<String?> botAvatar(String profile) => _botAvatar(profile);

  /// Opens (creating when needed) a bot's canonical chat and returns its
  /// stored session id. Later calls for that session stay scoped to the bot.
  Future<String> openBotChat(HermesBot bot) => _openBotChat(bot);

  /// Starts a visible, independent conversation bound to this bot's profile.
  /// The canonical Bot Chat remains available in conversation history.
  Future<String> createBotConversation(HermesBot bot) async {
    if (!HermesConfig.isValidDesktopProfile(bot.name)) {
      throw ArgumentError.value(bot.name, 'profile');
    }
    final id = await _runtimeCreateDesktopSession(
      options: const HermesDesktopSessionOptions(),
      profile: bot.name,
    );
    _sessionProfiles[id] = bot.name;
    return id;
  }

  Future<List<HermesDesktopModelOption>> configuredModels() =>
      _administration.configuredModels();

  @override
  Future<List<Map<String, dynamic>>> listSkills() =>
      _administration.listSkills();
  Future<List<Map<String, dynamic>>> listSkillsForProfile(String profile) =>
      _administration.listSkillsForProfile(profile);
  Future<List<Map<String, dynamic>>> listCommands() =>
      _administration.listCommands();

  Future<Map<String, dynamic>> reloadSkills() => _administration.reloadSkills();

  @override
  Future<List<Map<String, dynamic>>> listToolsets() =>
      _administration.listToolsets();
  Future<List<Map<String, dynamic>>> listToolsetsForProfile(String profile) =>
      _administration.listToolsetsForProfile(profile);

  Future<void> configureTools(List<String> names, {required bool enabled}) =>
      _administration.configureTools(names, enabled: enabled);

  Future<List<HermesMcpServer>> mcpServers() => _administration.mcpServers();

  Future<List<HermesMcpCatalogEntry>> mcpCatalog() =>
      _administration.mcpCatalog();

  Future<void> addMcpServer({
    required String name,
    String? url,
    String? command,
    List<String> arguments = const [],
    String? bearerToken,
  }) => _administration.addMcpServer(
    name: name,
    url: url,
    command: command,
    arguments: arguments,
    bearerToken: bearerToken,
  );

  Future<void> addMcpPreset(String name) => _administration.addMcpPreset(name);

  Future<HermesMcpTestResult> testMcpServer(String name) =>
      _administration.testMcpServer(name);

  Future<void> setMcpApiKey(String name, String value) =>
      _administration.setMcpApiKey(name, value);

  Future<void> removeMcpServer(String name) =>
      _administration.removeMcpServer(name);

  Future<bool> authenticateMcpServer(String name) =>
      _administration.authenticateMcpServer(name);

  Future<void> setMcpServerEnabled(String name, bool enabled) =>
      _administration.setMcpServerEnabled(name, enabled);

  Future<void> reloadMcp({String? runtimeId}) =>
      _administration.reloadMcp(runtimeId: runtimeId);

  @override
  Future<Map<String, dynamic>> getCapabilities() =>
      _administration.capabilities();

  @override
  Future<Map<String, dynamic>> healthDetailed() => statusProbe(refresh: true);

  @override
  Future<List<Map<String, dynamic>>> listJobs() => _administration.listJobs();
  Future<List<Map<String, dynamic>>> listJobsForProfile(String profile) =>
      _administration.listJobsForProfile(profile);
  Future<Map<String, dynamic>> learningGraph(String profile) =>
      _administration.learningGraph(profile);

  // Teams: Hermes Group Chat rooms (`groups.*`).
  Future<Map<String, dynamic>> teamCapabilities() => _teamCapabilities();
  Future<List<HermesTeam>> listTeams() => _listTeams();
  Future<HermesTeam> createTeam({
    required String name,
    required List<Map<String, Object?>> members,
  }) => _createTeam(name: name, members: members);
  Future<({HermesTeam team, HermesTeamStatus status})> teamState(
    String roomId,
  ) => _teamState(roomId);
  Future<({List<HermesTeamEvent> events, int cursor, bool hasMore})> teamLog(
    String roomId, {
    int sinceSeq = 0,
    int limit = 200,
  }) => _teamLog(roomId, sinceSeq: sinceSeq, limit: limit);
  Future<void> sendToTeam(String roomId, String text) =>
      _sendToTeam(roomId, text);
  Future<void> stopTeam(String roomId) => _stopTeam(roomId);
  Future<void> answerTeamApproval(
    String roomId,
    HermesTeamApproval approval, {
    required bool allow,
  }) => _answerTeamApproval(roomId, approval, allow: allow);
  Future<void> retryTeamTask(String roomId, String taskId) =>
      _retryTeamTask(roomId, taskId);
  Future<void> disbandTeam(String roomId) => _disbandTeam(roomId);
  Future<List<Map<String, dynamic>>> skillCatalog(String profile) =>
      _administration.skillCatalog(profile);

  @override
  Future<Map<String, dynamic>> createJob({
    required String name,
    required String prompt,
    required String schedule,
  }) =>
      _administration.createJob(name: name, prompt: prompt, schedule: schedule);

  @override
  Future<void> updateJob(
    String id, {
    String? name,
    String? prompt,
    String? schedule,
    bool? enabled,
  }) => _administration.updateJob(
    id,
    name: name,
    prompt: prompt,
    schedule: schedule,
    enabled: enabled,
  );

  @override
  Future<void> deleteJob(String id) =>
      _administration.mutateJob(id, "DELETE", "");
  @override
  Future<void> pauseJob(String id) =>
      _administration.mutateJob(id, "POST", "/pause");
  Future<void> pauseJobForProfile(String profile, String id) =>
      _administration.mutateJob(id, 'POST', '/pause', profile: profile);
  @override
  Future<void> resumeJob(String id) =>
      _administration.mutateJob(id, "POST", "/resume");
  Future<void> resumeJobForProfile(String profile, String id) =>
      _administration.mutateJob(id, 'POST', '/resume', profile: profile);
  @override
  Future<void> runJob(String id) =>
      _administration.mutateJob(id, "POST", "/trigger");
  Future<void> runJobForProfile(String profile, String id) =>
      _administration.mutateJob(id, 'POST', '/trigger', profile: profile);
  Future<void> updateJobForProfile(
    String profile,
    String id, {
    String? name,
    String? prompt,
    String? schedule,
    bool? enabled,
  }) => _administration.updateJob(
    id,
    profile: profile,
    name: name,
    prompt: prompt,
    schedule: schedule,
    enabled: enabled,
  );

  Future<List<Map<String, dynamic>>> listJobRuns(String id) =>
      _administration.listJobRuns(id);
  Future<List<Map<String, dynamic>>> listJobRunsForProfile(
    String profile,
    String id,
  ) => _administration.listJobRunsForProfile(profile, id);

  Future<List<HermesPendingDesktopDecision>> pendingDecisions({
    String? profile,
  }) => HermesPendingDecisionStore.forOrigin(origin: _origin, profile: profile);

  @override
  Future<HermesResponseStream> streamDesktopResponse(
    HermesChatInput input, {
    String? sessionId,
    required HermesDesktopSessionOptions options,
    CancelToken? cancelToken,
  }) => _runtimeStreamDesktopResponse(
    input,
    sessionId: sessionId,
    options: options,
    cancelToken: cancelToken,
  );
  Future<void> interrupt(String storedId) => _runtimeInterrupt(storedId);
  Future<bool> steer(String storedId, String text) =>
      _runtimeSteer(storedId, text);
  Future<void> queue(String storedId, String text) =>
      _runtimeQueue(storedId, text);
  @override
  Future<void> resolveApproval(
    String runId, {
    required String approvalId,
    required bool approved,
  }) => _runtimeResolveApproval(
    runId,
    approvalId: approvalId,
    approved: approved,
  );
  Future<void> resolveApprovalForSession(
    String storedSessionId, {
    required String approvalId,
    required bool approved,
  }) => _runtimeResolveApprovalForSession(
    storedSessionId,
    approvalId: approvalId,
    approved: approved,
  );
  Future<void> resolveApprovalChoice(
    String runtimeId, {
    required String approvalId,
    required String choice,
  }) => _runtimeResolveApprovalChoice(
    runtimeId,
    approvalId: approvalId,
    choice: choice,
  );
  Future<void> resolveApprovalChoiceForSession(
    String storedSessionId, {
    required String approvalId,
    required String choice,
  }) => _runtimeResolveApprovalChoiceForSession(
    storedSessionId,
    approvalId: approvalId,
    choice: choice,
  );
  Future<void> respondToDecision({
    required String runtimeId,
    String? storedSessionId,
    required String requestId,
    required HermesDecisionKind kind,
    required String value,
    String? mcpServer,
    String? mcpAction,
  }) => _runtimeRespondToDecision(
    runtimeId: runtimeId,
    storedSessionId: storedSessionId,
    requestId: requestId,
    kind: kind,
    value: value,
    mcpServer: mcpServer,
    mcpAction: mcpAction,
  );
  @override
  void close() {
    if (_closed) return;
    _closed = true;
    if (_observingLifecycle) WidgetsBinding.instance.removeObserver(this);
    _dio.close(force: true);
    unawaited(_dashboardBridge?.close());
    unawaited(_stateSubscription?.cancel());
    unawaited(_rpc.close());
    unawaited(_turnStates.close());
    unawaited(_sessionTurnStateChanges.close());
    unawaited(_activityChanges.close());
    unawaited(_activityEvents.close());
    unawaited(_transcriptChanges.close());
    unawaited(_desktopContractChanges.close());
    _eventBuffer.clear();
    _bindings.clear();
    _bindingSocketGenerations.clear();
    _freshSessionIds.clear();
    _lastTranscripts.clear();
    _appliedSessionOptions.clear();
    _sessionTurnStates.clear();
    _activityHistory.clear();
  }

  void _emitTurnState(HermesDesktopTurnState state) {
    if (!_closed) _turnStates.add(state);
  }

  void _emitSessionTurnState(String id) {
    if (!_closed) _sessionTurnStateChanges.add(id);
  }

  void _emitTranscriptChange(String id) {
    if (!_closed) _transcriptChanges.add(id);
  }

  void _emitDesktopContract(int value) {
    if (!_closed) _desktopContractChanges.add(value);
  }
}
