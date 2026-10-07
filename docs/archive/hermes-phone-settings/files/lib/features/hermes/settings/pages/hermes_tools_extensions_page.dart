import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/utils/debug_logger.dart';
import '../../admin/hermes_admin_client.dart';
import '../../admin/hermes_admin_models.dart';
import '../../admin/hermes_admin_providers.dart';
import '../../models/hermes_mcp.dart';
import '../../motion/hermez_motion.dart';
import '../../views/hermes_mcp_page.dart'
    show HermesMcpPage, showHermesMcpAddSheet;
import '../../widgets/hermez_chat_palette.dart';
import '../../widgets/hermez_segments.dart';
import '../../widgets/hermez_skeleton.dart';
import '../../widgets/hermez_surfaces.dart';
import '../../widgets/hermez_visual_theme.dart';

/// The route name the settings shell registers for this editor (U15). The
/// bot to edit travels as the `profile` path parameter and the tab as the
/// [kHermesToolsExtensionsTabParam] query parameter.
const String kHermesToolsExtensionsRouteName = 'hermes-tools-extensions';

/// Query parameter that names the tab to open; see
/// [HermesToolsExtensionsTab.parse].
const String kHermesToolsExtensionsTabParam = 'tab';

/// The editor's four tabs.
enum HermesToolsExtensionsTab {
  toolsets('Toolsets'),
  skills('Skills'),
  mcp('MCP'),
  plugins('Plugins');

  const HermesToolsExtensionsTab(this.label);

  final String label;

  /// The tab a route parameter names; [toolsets] when it names none.
  static HermesToolsExtensionsTab parse(String? value) =>
      values.firstWhere((tab) => tab.name == value, orElse: () => toolsets);
}

/// How a screen that links to this editor opens it. The default pushes a
/// full page, which is right for a phone; a shell that shows the editor in
/// its own panel overrides [hermesToolsExtensionsOpenerProvider].
typedef HermesToolsExtensionsOpener = void Function(
  BuildContext context, {
  required String profile,
  HermesToolsExtensionsTab tab,
  String? botTitle,
});

/// What the "toolsets" chips and links call to open a bot's editor.
final hermesToolsExtensionsOpenerProvider =
    Provider<HermesToolsExtensionsOpener>((ref) => openHermesToolsExtensions);

/// Opens [HermesToolsExtensionsPage] for [profile] as a full page.
void openHermesToolsExtensions(
  BuildContext context, {
  required String profile,
  HermesToolsExtensionsTab tab = HermesToolsExtensionsTab.toolsets,
  String? botTitle,
}) {
  unawaited(
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => _ToolsExtensionsRoute(
          profile: profile,
          tab: tab,
          botTitle: botTitle,
        ),
      ),
    ),
  );
}

class _ToolsExtensionsRoute extends StatelessWidget {
  const _ToolsExtensionsRoute({
    required this.profile,
    required this.tab,
    required this.botTitle,
  });

  final String profile;
  final HermesToolsExtensionsTab tab;
  final String? botTitle;

  @override
  Widget build(BuildContext context) {
    final theme = hermezVisualTheme(Theme.of(context));
    final palette = HermezChatPalette.forBrightness(theme.brightness);
    return Theme(
      data: theme,
      child: Scaffold(
        backgroundColor: palette.canvas,
        appBar: AppBar(
          backgroundColor: palette.canvas,
          surfaceTintColor: Colors.transparent,
          scrolledUnderElevation: 0,
          title: const Text('Tools & extensions'),
        ),
        body: SafeArea(
          child: HermesToolsExtensionsPage(
            scope: profile,
            botTitle: botTitle,
            initialTab: tab,
            showTitle: false,
          ),
        ),
      ),
    );
  }
}

/// A bot's toolsets, skills, MCP servers and plugins (R17, KTD7).
///
/// [scope] is the bot's name; every read and write names it, so nothing here
/// touches another bot or the server's own config. Each tab loads when it is
/// first opened.
///
/// - Switches are optimistic: the switch moves at once, the row shows a
///   spinner while Hermes answers, and a failure puts it back with the reason
///   under the row.
/// - Toolsets use the per-toolset route that writes the enforced
///   `platform_toolsets` key; skills use the skills toggle (which writes the
///   bot's `disabled_skills`); MCP servers use the per-bot enable route.
/// - A change to MCP is followed by `reload.mcp`. That clears the prompt cache
///   of running chats, so when Hermes asks first the question shows in the
///   tab and nothing reloads until it is answered.
/// - Plugin changes need a restart of Hermes. The page says so and offers to
///   restart it, behind an explicit confirmation.
/// - A feature this Hermes does not have shows as disabled, with the reason.
///
/// The page has no chrome of its own and needs a bounded height.
class HermesToolsExtensionsPage extends ConsumerStatefulWidget {
  const HermesToolsExtensionsPage({
    super.key,
    required this.scope,
    this.botTitle,
    this.initialTab = HermesToolsExtensionsTab.toolsets,
    this.showTitle = true,
  });

  /// The bot's name (its Hermes profile).
  final String scope;

  /// What to call the bot, when it has a title besides its name.
  final String? botTitle;

  final HermesToolsExtensionsTab initialTab;

  /// Whether the page names itself; false where the host already does.
  final bool showTitle;

  @override
  ConsumerState<HermesToolsExtensionsPage> createState() =>
      _HermesToolsExtensionsPageState();
}

enum _Phase { idle, loading, ready, failed, unavailable }

/// One tab's list and how loading it went.
final class _Slot<T> {
  _Phase phase = _Phase.idle;
  List<T> items = const [];

  /// Why the tab failed or is unavailable; shown to the owner.
  String message = '';

  /// Set when reading works but writing does not: switches turn off and this
  /// says why.
  String? writeDisabled;

  /// Guards against an older answer replacing a newer one.
  int serial = 0;

  void reset() {
    phase = _Phase.idle;
    items = const [];
    message = '';
    writeDisabled = null;
    serial++;
  }
}

/// Where the MCP reload that follows a change stands.
enum _Reload { idle, running, done, asking, failed, unsupported }

/// Where the Hermes restart that a plugin change needs stands.
enum _Restart { idle, confirming, running, requested, unsupported, failed }

class _HermesToolsExtensionsPageState
    extends ConsumerState<HermesToolsExtensionsPage> {
  late HermesToolsExtensionsTab _tab = widget.initialTab;

  final _Slot<HermesAdminToolset> _toolsets = _Slot();
  final _Slot<HermesAdminSkill> _skills = _Slot();
  final _Slot<HermesMcpServer> _mcp = _Slot();
  final _Slot<HermesAdminPlugin> _plugins = _Slot();

  /// The value each toggled row shows until a fresh list says otherwise, keyed
  /// `tab:id`. It is the optimistic value while the write is in flight.
  final Map<String, bool> _shown = {};

  /// Rows whose write is in flight.
  final Set<String> _pending = {};

  /// Why a row's last change did not happen.
  final Map<String, String> _rowError = {};

  /// Rows that cannot be switched, and why.
  final Map<String, String> _rowLocked = {};

  final TextEditingController _search = TextEditingController();
  String _query = '';

  // MCP.
  _Reload _reload = _Reload.idle;
  HermesAdminConfirmation<void>? _reloadAsk;
  bool _addingMcp = false;
  String? _mcpActionError;

  // Plugins.
  final Set<String> _restartNeeded = {};
  _Restart _restart = _Restart.idle;

  @override
  void initState() {
    super.initState();
    _search.addListener(() {
      final next = _search.text.trim().toLowerCase();
      if (next != _query) setState(() => _query = next);
    });
    _ensureLoaded(_tab);
  }

  @override
  void didUpdateWidget(covariant HermesToolsExtensionsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scope != widget.scope) _resetAll();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  // -------------------------------------------------------------------------
  // Loading
  // -------------------------------------------------------------------------

  void _resetAll() {
    setState(() {
      _toolsets.reset();
      _skills.reset();
      _mcp.reset();
      _plugins.reset();
      _shown.clear();
      _pending.clear();
      _rowError.clear();
      _rowLocked.clear();
      _reload = _Reload.idle;
      _reloadAsk = null;
      _mcpActionError = null;
      _restartNeeded.clear();
      _restart = _Restart.idle;
    });
    _ensureLoaded(_tab);
  }

  _Slot<Object?> _slot(HermesToolsExtensionsTab tab) => switch (tab) {
    HermesToolsExtensionsTab.toolsets => _toolsets,
    HermesToolsExtensionsTab.skills => _skills,
    HermesToolsExtensionsTab.mcp => _mcp,
    HermesToolsExtensionsTab.plugins => _plugins,
  };

  void _ensureLoaded(HermesToolsExtensionsTab tab) {
    if (_slot(tab).phase == _Phase.idle) unawaited(_load(tab));
  }

  Future<void> _load(HermesToolsExtensionsTab tab, {bool silent = false}) {
    final scope = widget.scope;
    return switch (tab) {
      HermesToolsExtensionsTab.toolsets => _fetch(
        tab,
        _toolsets,
        (client) => client.toolsets(scope),
        what: 'toolsets',
        silent: silent,
      ),
      HermesToolsExtensionsTab.skills => _fetch(
        tab,
        _skills,
        (client) => client.skills(scope),
        what: 'skills',
        silent: silent,
      ),
      HermesToolsExtensionsTab.mcp => _fetch(
        tab,
        _mcp,
        (client) => client.mcpServers(scope),
        what: 'MCP servers',
        silent: silent,
      ),
      HermesToolsExtensionsTab.plugins => _fetch(
        tab,
        _plugins,
        (client) => client.plugins(scope),
        what: 'plugins',
        silent: silent,
      ),
    };
  }

  /// Reads one tab's list. A [silent] read keeps what is on screen and
  /// ignores its own failure: it only brings the list up to date.
  Future<void> _fetch<T>(
    HermesToolsExtensionsTab tab,
    _Slot<T> slot,
    Future<List<T>> Function(HermesAdminClient client) read, {
    required String what,
    bool silent = false,
  }) async {
    final client = ref.read(hermesAdminClientProvider);
    final serial = ++slot.serial;
    if (client == null) {
      setState(() {
        slot
          ..phase = _Phase.unavailable
          ..message =
              'Tools and extensions need a Desktop Gateway connection to '
              'Hermes.';
      });
      return;
    }
    if (!silent) {
      setState(() {
        slot
          ..phase = _Phase.loading
          ..message = '';
      });
    }
    try {
      final items = await read(client);
      if (!mounted || serial != slot.serial) return;
      setState(() {
        slot
          ..items = items
          ..phase = _Phase.ready
          ..message = '';
        // The list is the truth again, except for rows still being written.
        _shown.removeWhere(
          (key, _) => key.startsWith('${tab.name}:') && !_pending.contains(key),
        );
      });
    } on HermesAdminUnavailable {
      if (!mounted || serial != slot.serial || silent) return;
      setState(() {
        slot
          ..phase = _Phase.unavailable
          ..message =
              "This Hermes server can't manage $what. Update Hermes to "
              'use this from the app.';
      });
    } on HermesAdminException catch (error) {
      _logFailure('load-$what', error);
      if (!mounted || serial != slot.serial || silent) return;
      setState(() {
        slot
          ..phase = _Phase.failed
          ..message = error is HermesAdminNotFound
              ? 'Hermes can’t find this bot. It may have been deleted.'
              : 'Hermes couldn’t load $what. ${error.message}'.trim();
      });
    } catch (error) {
      _logFailure('load-$what', error);
      if (!mounted || serial != slot.serial || silent) return;
      setState(() {
        slot
          ..phase = _Phase.failed
          ..message = 'Couldn’t load $what from Hermes.';
      });
    }
  }

  void _logFailure(String what, Object error) {
    DebugLogger.warning(
      'tools-extensions-failed',
      scope: 'hermes/settings',
      data: {'what': what, 'errorType': error.runtimeType.toString()},
    );
  }

  // -------------------------------------------------------------------------
  // Toggling
  // -------------------------------------------------------------------------

  static String _key(HermesToolsExtensionsTab tab, String id) =>
      '${tab.name}:$id';

  /// Switches one row. The row shows [value] at once and a spinner until
  /// Hermes answers; a failure puts it back and says why.
  Future<void> _toggle({
    required HermesToolsExtensionsTab tab,
    required String id,
    required bool value,
    required String what,
    required Future<void> Function(HermesAdminClient client) write,
    Future<void> Function()? after,
  }) async {
    final key = _key(tab, id);
    final client = ref.read(hermesAdminClientProvider);
    if (client == null || !_pending.add(key)) return;
    final scope = widget.scope;
    setState(() {
      _shown[key] = value;
      _rowError.remove(key);
    });
    try {
      await write(client);
      if (!mounted || scope != widget.scope) return;
      setState(() => _pending.remove(key));
      // Bring the list up to date, then carry on with whatever the change
      // needs (an MCP reload).
      unawaited(_load(tab, silent: true));
      if (after != null) await after();
    } on HermesAdminUnavailable {
      _revert(
        key,
        scope,
        disableTab: tab,
        disableReason: "This Hermes server can't change $what.",
      );
    } on HermesAdminRejected catch (error) {
      _logFailure('toggle-$what', error);
      if (tab == HermesToolsExtensionsTab.mcp && error.code == 409) {
        // Hermes answers 409 for a server a plugin provides.
        _revert(
          key,
          scope,
          lock:
              'Provided by a plugin, so it can’t be switched here. Turn the '
              'plugin off under Plugins instead.',
        );
      } else {
        _revert(
          key,
          scope,
          message: error.message.isEmpty
              ? 'Hermes refused the change. Nothing was changed.'
              : '${error.message} Nothing was changed.',
        );
      }
    } on HermesAdminException catch (error) {
      _logFailure('toggle-$what', error);
      _revert(
        key,
        scope,
        message: error is HermesAdminNotFound
            ? 'Hermes can’t find this bot. Nothing was changed.'
            : 'Hermes couldn’t make the change. Nothing was changed.',
      );
    } on ArgumentError catch (error) {
      _logFailure('toggle-$what', error);
      _revert(
        key,
        scope,
        message: 'This can’t be changed from the app. Nothing was changed.',
      );
    } catch (error) {
      _logFailure('toggle-$what', error);
      _revert(
        key,
        scope,
        message: 'Couldn’t reach Hermes. Nothing was changed.',
      );
    }
  }

  void _revert(
    String key,
    String scope, {
    HermesToolsExtensionsTab? disableTab,
    String? disableReason,
    String? message,
    String? lock,
  }) {
    if (!mounted || scope != widget.scope) return;
    setState(() {
      _pending.remove(key);
      _shown.remove(key);
      if (message != null) _rowError[key] = message;
      if (lock != null) _rowLocked[key] = lock;
      if (disableTab != null) _slot(disableTab).writeDisabled = disableReason;
    });
  }

  Future<void> _setToolset(HermesAdminToolset toolset, bool value) => _toggle(
    tab: HermesToolsExtensionsTab.toolsets,
    id: toolset.name,
    value: value,
    what: 'toolsets',
    write: (client) =>
        client.setToolsetEnabled(widget.scope, toolset.name, value),
  );

  Future<void> _setSkill(HermesAdminSkill skill, bool value) => _toggle(
    tab: HermesToolsExtensionsTab.skills,
    id: skill.name,
    value: value,
    what: 'skills',
    write: (client) => client.setSkillEnabled(widget.scope, skill.name, value),
  );

  Future<void> _setMcp(HermesMcpServer server, bool value) => _toggle(
    tab: HermesToolsExtensionsTab.mcp,
    id: server.name,
    value: value,
    what: 'MCP servers',
    write: (client) =>
        client.setMcpServerEnabled(widget.scope, server.name, value),
    after: _reloadMcp,
  );

  Future<void> _setPlugin(HermesAdminPlugin plugin, bool value) => _toggle(
    tab: HermesToolsExtensionsTab.plugins,
    id: plugin.key,
    value: value,
    what: 'plugins',
    write: (client) async {
      await client.setPluginEnabled(widget.scope, plugin.key, value);
      if (mounted) {
        setState(() {
          _restartNeeded.add(plugin.key);
          if (_restart == _Restart.requested) _restart = _Restart.idle;
        });
      }
    },
  );

  // -------------------------------------------------------------------------
  // MCP: add and reload
  // -------------------------------------------------------------------------

  Future<void> _addMcp([HermezMorphOrigin? origin]) async {
    final scope = widget.scope;
    final draft = await showHermesMcpAddSheet(context, origin);
    if (draft == null || !mounted) return;
    final client = ref.read(hermesAdminClientProvider);
    if (client == null) return;
    setState(() {
      _addingMcp = true;
      _mcpActionError = null;
    });
    var added = false;
    try {
      await client.addMcpServer(
        scope,
        name: draft.name,
        url: draft.url,
        command: draft.command,
        arguments: draft.arguments,
        bearerToken: draft.secret,
      );
      added = true;
    } on HermesAdminUnavailable {
      _mcpActionError = 'This Hermes server can’t add MCP servers.';
    } on HermesAdminException catch (error) {
      _logFailure('add-mcp', error);
      _mcpActionError =
          'Couldn’t add ${draft.name}. '
          '${error.message.isEmpty ? 'Hermes refused it.' : error.message}';
    } catch (error) {
      _logFailure('add-mcp', error);
      _mcpActionError = 'Couldn’t reach Hermes. ${draft.name} was not added.';
    }
    if (!mounted || scope != widget.scope) return;
    setState(() => _addingMcp = false);
    if (!added) return;
    unawaited(_load(HermesToolsExtensionsTab.mcp, silent: true));
    await _reloadMcp();
  }

  /// Reloads MCP so running chats see the change. Not per bot. Hermes may
  /// ask first, since it clears the prompt cache: that comes back as
  /// [_Reload.asking] and waits for the owner.
  Future<void> _reloadMcp() async {
    final client = ref.read(hermesAdminClientProvider);
    if (client == null || !mounted) return;
    setState(() {
      _reload = _Reload.running;
      _reloadAsk = null;
    });
    try {
      final result = await client.reloadMcp();
      if (!mounted) return;
      setState(() {
        _reloadAsk = result.confirmation;
        _reload = result.needsConfirmation ? _Reload.asking : _Reload.done;
      });
    } on HermesAdminUnavailable {
      if (mounted) setState(() => _reload = _Reload.unsupported);
    } catch (error) {
      _logFailure('reload-mcp', error);
      if (mounted) setState(() => _reload = _Reload.failed);
    }
  }

  Future<void> _confirmReload() async {
    final ask = _reloadAsk;
    if (ask == null) return;
    setState(() {
      _reloadAsk = null;
      _reload = _Reload.running;
    });
    try {
      await ask.confirm();
      if (mounted) setState(() => _reload = _Reload.done);
    } on HermesAdminUnavailable {
      if (mounted) setState(() => _reload = _Reload.unsupported);
    } catch (error) {
      _logFailure('reload-mcp', error);
      if (mounted) setState(() => _reload = _Reload.failed);
    }
  }

  Future<void> _openMcpManager() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) =>
            HermesMcpPage(profile: widget.scope, botTitle: widget.botTitle),
      ),
    );
    if (mounted) unawaited(_load(HermesToolsExtensionsTab.mcp, silent: true));
  }

  // -------------------------------------------------------------------------
  // Plugins: restart
  // -------------------------------------------------------------------------

  /// Restarts Hermes. Only ever called after the owner pressed Restart in the
  /// confirmation, because it interrupts every bot's running chats.
  Future<void> _restartHermes() async {
    final client = ref.read(hermesAdminClientProvider);
    if (client == null) return;
    setState(() => _restart = _Restart.running);
    try {
      await client.restartGateway(ownerConfirmed: true);
      if (!mounted) return;
      setState(() {
        _restart = _Restart.requested;
        _restartNeeded.clear();
      });
    } on HermesAdminUnavailable {
      if (mounted) setState(() => _restart = _Restart.unsupported);
    } catch (error) {
      _logFailure('restart-gateway', error);
      if (mounted) setState(() => _restart = _Restart.failed);
    }
  }

  // -------------------------------------------------------------------------
  // Build
  // -------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    // A connection that arrives after the page opened.
    ref.listen(hermesAdminClientProvider, (previous, next) {
      if (previous == null && next != null) _resetAll();
    });
    final theme = hermezVisualTheme(Theme.of(context));
    final palette = HermezChatPalette.forBrightness(theme.brightness);
    return Theme(
      data: theme,
      child: Material(
        type: MaterialType.transparency,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final body = Padding(
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _header(palette),
                  const SizedBox(height: 12),
                  HermezSegments(
                    key: const ValueKey('tools-tabs'),
                    labels: [
                      for (final tab in HermesToolsExtensionsTab.values)
                        tab.label,
                    ],
                    index: _tab.index,
                    onChanged: (i) {
                      final next = HermesToolsExtensionsTab.values[i];
                      setState(() => _tab = next);
                      _ensureLoaded(next);
                    },
                  ),
                  const SizedBox(height: 8),
                  Expanded(child: _content(palette)),
                ],
              ),
            );
            return constraints.hasBoundedHeight
                ? body
                : SizedBox(height: 560, child: body);
          },
        ),
      ),
    );
  }

  Widget _header(HermezChatPalette palette) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (widget.showTitle) ...[
        Text(
          'Tools & extensions',
          style: HermezType.section(palette).copyWith(fontSize: 20),
        ),
        const SizedBox(height: 6),
      ],
      Text(
        'Editing ${widget.botTitle ?? widget.scope}’s tools and extensions '
        '(${widget.scope}). Changes apply to its new chats.',
        key: const ValueKey('tools-scope'),
        style: HermezType.meta(palette),
      ),
    ],
  );

  Widget _content(HermezChatPalette palette) {
    final tab = _tab;
    final slot = _slot(tab);
    final body = switch (slot.phase) {
      _Phase.idle || _Phase.loading => Align(
        alignment: Alignment.topCenter,
        child: HermezSkeleton.rows(
          key: ValueKey('tools-loading-${tab.name}'),
          count: 5,
          leading: false,
        ),
      ),
      _Phase.failed => _Notice(
        key: ValueKey('tools-error-${tab.name}'),
        icon: Icons.error_outline_rounded,
        message: slot.message,
        action: OutlinedButton(
          key: ValueKey('tools-retry-${tab.name}'),
          onPressed: () => unawaited(_load(tab)),
          child: const Text('Retry'),
        ),
      ),
      _Phase.unavailable => _Notice(
        key: ValueKey('tools-unavailable-${tab.name}'),
        icon: Icons.block_rounded,
        message: slot.message,
      ),
      _Phase.ready => _list(tab, palette),
    };
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 820),
        child: body,
      ),
    );
  }

  Widget _list(HermesToolsExtensionsTab tab, HermezChatPalette palette) =>
      switch (tab) {
        HermesToolsExtensionsTab.toolsets => _toolsetList(palette),
        HermesToolsExtensionsTab.skills => _skillList(palette),
        HermesToolsExtensionsTab.mcp => _mcpList(palette),
        HermesToolsExtensionsTab.plugins => _pluginList(palette),
      };

  bool _on(HermesToolsExtensionsTab tab, String id, bool listed) =>
      _shown[_key(tab, id)] ?? listed;

  Widget _toolsetList(HermezChatPalette palette) {
    const tab = HermesToolsExtensionsTab.toolsets;
    final reason = _toolsets.writeDisabled;
    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        _Intro(
          'Switch a group of tools on or off for this bot. New chats pick '
          'it up; chats already running keep the tools they have.',
          palette: palette,
        ),
        if (reason != null) _WriteNotice(reason),
        if (_toolsets.items.isEmpty)
          _Empty('Hermes lists no toolsets for this bot.', palette: palette),
        for (final toolset in _toolsets.items)
          _ToggleRow(
            rowKey: 'toolset-${toolset.name}',
            title: toolset.label,
            subtitle: [
              if (toolset.description.isNotEmpty) toolset.description,
              if (toolset.toolCount > 0)
                '${toolset.toolCount} tool${toolset.toolCount == 1 ? '' : 's'}',
            ].join(' · '),
            note: toolset.configured
                ? null
                : 'Needs setup before it works: add its key or sign in.',
            value: _on(tab, toolset.name, toolset.enabled),
            pending: _pending.contains(_key(tab, toolset.name)),
            locked: reason != null,
            error: _rowError[_key(tab, toolset.name)],
            onChanged: (value) => unawaited(_setToolset(toolset, value)),
          ),
      ],
    );
  }

  Widget _skillList(HermezChatPalette palette) {
    const tab = HermesToolsExtensionsTab.skills;
    final reason = _skills.writeDisabled;
    final shown = [
      for (final skill in _skills.items)
        if (_query.isEmpty ||
            skill.name.toLowerCase().contains(_query) ||
            skill.description.toLowerCase().contains(_query))
          skill,
    ];
    final enabledCount = _skills.items
        .where((skill) => _on(tab, skill.name, skill.enabled))
        .length;
    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        _Intro(
          'Turn a skill off to stop this bot using it. New chats pick it '
          'up. $enabledCount of ${_skills.items.length} on.',
          palette: palette,
        ),
        if (reason != null) _WriteNotice(reason),
        if (_skills.items.length > 6)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: TextField(
              key: const ValueKey('skills-search'),
              controller: _search,
              autocorrect: false,
              enableSuggestions: false,
              decoration: const InputDecoration(
                hintText: 'Search skills',
                prefixIcon: Icon(Icons.search_rounded),
                isDense: true,
              ),
            ),
          ),
        if (_skills.items.isEmpty)
          _Empty('This bot has no skills installed.', palette: palette)
        else if (shown.isEmpty)
          _Empty(
            'No skill matches “${_search.text.trim()}”.',
            palette: palette,
          ),
        for (final skill in shown)
          _ToggleRow(
            rowKey: 'skill-${skill.name}',
            title: skill.name,
            subtitle: skill.description,
            chips: [
              _provenance(skill.provenance),
              if (skill.category != null) skill.category!,
            ],
            value: _on(tab, skill.name, skill.enabled),
            pending: _pending.contains(_key(tab, skill.name)),
            locked: reason != null,
            error: _rowError[_key(tab, skill.name)],
            onChanged: (value) => unawaited(_setSkill(skill, value)),
          ),
      ],
    );
  }

  static String _provenance(String value) => switch (value) {
    'hub' => 'From the hub',
    'bundled' => 'Built in',
    _ => 'Written by the bot',
  };

  Widget _mcpList(HermezChatPalette palette) {
    const tab = HermesToolsExtensionsTab.mcp;
    final reason = _mcp.writeDisabled;
    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        _Intro(
          'MCP servers give this bot more tools. Changing one reloads MCP '
          'in Hermes so running chats see it.',
          palette: palette,
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              Builder(
                builder: (buttonContext) => FilledButton.icon(
                  key: const ValueKey('mcp-add'),
                  onPressed: _addingMcp
                      ? null
                      : () => unawaited(
                          _addMcp(
                            HermezMorphOrigin.of(
                              buttonContext,
                              radius: 20,
                              color: Theme.of(buttonContext)
                                  .colorScheme
                                  .surface,
                            ),
                          ),
                        ),
                  icon: _addingMcp
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.add_rounded, size: 18),
                  label: const Text('Add server'),
                ),
              ),
              OutlinedButton.icon(
                key: const ValueKey('mcp-manage'),
                onPressed: () => unawaited(_openMcpManager()),
                icon: const Icon(Icons.tune_rounded, size: 18),
                label: const Text('Test, sign in, remove…'),
              ),
            ],
          ),
        ),
        if (_mcpActionError != null)
          _MessageRow(
            key: const ValueKey('mcp-action-error'),
            icon: Icons.error_outline_rounded,
            color: _danger(context),
            text: _mcpActionError!,
          ),
        _mcpReloadBanner(palette),
        if (reason != null) _WriteNotice(reason),
        if (_mcp.items.isEmpty)
          _Empty('This bot has no MCP servers yet.', palette: palette),
        for (final server in _mcp.items)
          _ToggleRow(
            rowKey: 'mcp-${server.name}',
            title: server.name,
            subtitle: [
              if (server.description.isNotEmpty) server.description,
              if (server.tools.isNotEmpty)
                '${server.tools.length} tool${server.tools.length == 1 ? '' : 's'}',
              if (server.auth?.isNotEmpty ?? false) 'Sign-in: ${server.auth}',
            ].join(' · '),
            value: _on(tab, server.name, server.enabled),
            pending: _pending.contains(_key(tab, server.name)),
            locked: reason != null,
            disabledReason: _rowLocked[_key(tab, server.name)],
            error: _rowError[_key(tab, server.name)],
            onChanged: (value) => unawaited(_setMcp(server, value)),
          ),
      ],
    );
  }

  Widget _mcpReloadBanner(HermezChatPalette palette) {
    const key = ValueKey('mcp-reload');
    return switch (_reload) {
      _Reload.idle => const SizedBox.shrink(),
      _Reload.running => const _Banner(
        key: key,
        busy: true,
        text: 'Reloading MCP…',
      ),
      _Reload.done => const _Banner(
        key: key,
        icon: Icons.check_circle_outline_rounded,
        text: 'MCP reloaded.',
      ),
      _Reload.asking => _Banner(
        key: key,
        icon: Icons.refresh_rounded,
        text:
            'Reload MCP to apply this? ${_reloadAsk?.message ?? ''} '
            'It applies to every running chat, not only this bot.',
        actions: [
          TextButton(
            key: const ValueKey('mcp-reload-later'),
            onPressed: () => setState(() {
              _reload = _Reload.idle;
              _reloadAsk = null;
            }),
            child: const Text('Later'),
          ),
          FilledButton(
            key: const ValueKey('mcp-reload-confirm'),
            onPressed: () => unawaited(_confirmReload()),
            child: const Text('Reload'),
          ),
        ],
      ),
      _Reload.failed => _Banner(
        key: key,
        icon: Icons.error_outline_rounded,
        danger: true,
        text:
            'Saved, but Hermes couldn’t reload MCP, so running chats don’t '
            'have the change yet.',
        actions: [
          OutlinedButton(
            key: const ValueKey('mcp-reload-retry'),
            onPressed: () => unawaited(_reloadMcp()),
            child: const Text('Try again'),
          ),
        ],
      ),
      _Reload.unsupported => const _Banner(
        key: key,
        icon: Icons.info_outline_rounded,
        text:
            'Saved. This Hermes can’t reload MCP from the app, so new chats '
            'pick the change up and running ones keep what they have.',
      ),
    };
  }

  Widget _pluginList(HermezChatPalette palette) {
    const tab = HermesToolsExtensionsTab.plugins;
    final reason = _plugins.writeDisabled;
    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        _Intro(
          'Plugins add features to Hermes itself. A plugin change takes '
          'effect after Hermes restarts.',
          palette: palette,
        ),
        _restartNotice(palette),
        if (reason != null) _WriteNotice(reason),
        if (_plugins.items.isEmpty)
          _Empty('Hermes lists no plugins for this bot.', palette: palette),
        for (final plugin in _plugins.items)
          _ToggleRow(
            rowKey: 'plugin-${plugin.key}',
            title: plugin.version.isEmpty
                ? plugin.name
                : '${plugin.name} ${plugin.version}',
            subtitle: plugin.description,
            chips: [
              if (plugin.source.isNotEmpty) plugin.source,
              if (_restartNeeded.contains(plugin.key)) 'Restart needed',
            ],
            value: _on(tab, plugin.key, plugin.enabled),
            pending: _pending.contains(_key(tab, plugin.key)),
            locked: reason != null,
            error: _rowError[_key(tab, plugin.key)],
            onChanged: (value) => unawaited(_setPlugin(plugin, value)),
          ),
      ],
    );
  }

  Widget _restartNotice(HermezChatPalette palette) {
    const key = ValueKey('plugins-restart');
    return switch (_restart) {
      _Restart.running => const _Banner(
        key: key,
        busy: true,
        text: 'Asking Hermes to restart…',
      ),
      _Restart.requested => const _Banner(
        key: key,
        icon: Icons.check_circle_outline_rounded,
        text:
            'Restart requested. Hermes will be back in a moment; reconnect '
            'if this page stops answering.',
      ),
      _Restart.unsupported => const _Banner(
        key: key,
        icon: Icons.info_outline_rounded,
        text:
            'Restart needed to apply plugin changes. This Hermes can’t '
            'restart from the app, so restart it from Umbrel.',
      ),
      _ when _restartNeeded.isEmpty && _restart == _Restart.idle =>
        const SizedBox.shrink(),
      _Restart.confirming => _Banner(
        key: key,
        icon: Icons.warning_amber_rounded,
        danger: true,
        text:
            'Restart Hermes? Every bot’s running chats are interrupted '
            'while it restarts.',
        actions: [
          TextButton(
            key: const ValueKey('plugins-restart-cancel'),
            onPressed: () => setState(() => _restart = _Restart.idle),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const ValueKey('plugins-restart-confirm'),
            onPressed: () => unawaited(_restartHermes()),
            child: const Text('Restart'),
          ),
        ],
      ),
      _ => _Banner(
        key: key,
        icon: Icons.restart_alt_rounded,
        text: _restart == _Restart.failed
            ? 'Hermes didn’t restart. Restart Hermes to apply plugin changes.'
            : 'Restart Hermes to apply plugin changes.',
        danger: _restart == _Restart.failed,
        actions: [
          OutlinedButton(
            key: const ValueKey('plugins-restart-start'),
            onPressed: () => setState(() => _restart = _Restart.confirming),
            child: const Text('Restart Hermes…'),
          ),
        ],
      ),
    };
  }

  Color _danger(BuildContext context) =>
      Theme.of(context).extension<HermezStatusColors>()?.danger ??
      Theme.of(context).colorScheme.error;
}

// ---------------------------------------------------------------------------
// Pieces
// ---------------------------------------------------------------------------

/// One switchable row: the switch moves at once, a spinner shows while Hermes
/// answers, and a [disabledReason] or [error] says why it did not (or could
/// not) change.
class _ToggleRow extends StatelessWidget {
  const _ToggleRow({
    required this.rowKey,
    required this.title,
    required this.value,
    required this.pending,
    required this.onChanged,
    this.subtitle = '',
    this.note,
    this.chips = const [],
    this.locked = false,
    this.disabledReason,
    this.error,
  });

  final String rowKey;
  final String title;
  final String subtitle;

  /// A caution that does not stop the switch, such as "needs setup".
  final String? note;
  final List<String> chips;
  final bool value;
  final bool pending;

  /// The whole tab is read-only (a note above the rows says why).
  final bool locked;

  /// Why this row's switch is off for good; shown under it.
  final String? disabledReason;

  /// Why the last change did not happen.
  final String? error;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = HermezChatPalette.forBrightness(
      Theme.of(context).brightness,
    );
    final status = Theme.of(context).extension<HermezStatusColors>();
    final danger = status?.danger ?? Theme.of(context).colorScheme.error;
    final warning = status?.warning ?? Colors.orange;
    final off = locked || disabledReason != null;
    return DecoratedBox(
      key: ValueKey('row-$rowKey'),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: palette.border)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: HermezType.body(palette)
                            .copyWith(fontWeight: FontWeight.w700),
                      ),
                      if (subtitle.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            subtitle,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: HermezType.meta(palette),
                          ),
                        ),
                      if (chips.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            children: [
                              for (final chip in chips)
                                _Chip(chip, palette: palette),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                if (pending)
                  const Padding(
                    padding: EdgeInsets.only(right: 10),
                    child: SizedBox(
                      key: ValueKey('pending'),
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                Semantics(
                  label: title,
                  child: Switch(
                    key: ValueKey('switch-$rowKey'),
                    value: value,
                    onChanged: pending || off ? null : onChanged,
                  ),
                ),
              ],
            ),
            if (note != null)
              _MessageRow(
                icon: Icons.warning_amber_rounded,
                color: warning,
                text: note!,
              ),
            if (disabledReason != null)
              _MessageRow(
                key: ValueKey('reason-$rowKey'),
                icon: Icons.lock_outline_rounded,
                color: palette.muted,
                text: disabledReason!,
              ),
            if (error != null)
              _MessageRow(
                key: ValueKey('error-$rowKey'),
                icon: Icons.error_outline_rounded,
                color: danger,
                text: error!,
                live: true,
              ),
          ],
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip(this.label, {required this.palette});

  final String label;
  final HermezChatPalette palette;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(999),
      border: Border.all(color: palette.border),
    ),
    child: Text(label, style: HermezType.meta(palette)),
  );
}

class _MessageRow extends StatelessWidget {
  const _MessageRow({
    super.key,
    required this.icon,
    required this.color,
    required this.text,
    this.live = false,
  });

  final IconData icon;
  final Color color;
  final String text;
  final bool live;

  @override
  Widget build(BuildContext context) {
    final palette = HermezChatPalette.forBrightness(
      Theme.of(context).brightness,
    );
    return Semantics(
      liveRegion: live,
      child: Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                text,
                style: HermezType.meta(palette).copyWith(color: palette.ink),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Intro extends StatelessWidget {
  const _Intro(this.text, {required this.palette});

  final String text;
  final HermezChatPalette palette;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(text, style: HermezType.meta(palette)),
  );
}

class _Empty extends StatelessWidget {
  const _Empty(this.text, {required this.palette});

  final String text;
  final HermezChatPalette palette;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 20),
    child: Text(text, style: HermezType.body(palette)),
  );
}

/// Reading works but changing does not: says so once, above the rows, which
/// are switched off.
class _WriteNotice extends StatelessWidget {
  const _WriteNotice(this.reason);

  final String reason;

  @override
  Widget build(BuildContext context) => _MessageRow(
    key: const ValueKey('tools-write-disabled'),
    icon: Icons.lock_outline_rounded,
    color: HermezChatPalette.forBrightness(Theme.of(context).brightness).muted,
    text: reason,
  );
}

/// A line of news about the tab: a reload, a restart, a question.
class _Banner extends StatelessWidget {
  const _Banner({
    super.key,
    required this.text,
    this.icon,
    this.busy = false,
    this.danger = false,
    this.actions = const [],
  });

  final String text;
  final IconData? icon;
  final bool busy;
  final bool danger;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final palette = HermezChatPalette.forBrightness(
      Theme.of(context).brightness,
    );
    final status = Theme.of(context).extension<HermezStatusColors>();
    final accent = danger
        ? status?.danger ?? Theme.of(context).colorScheme.error
        : palette.border;
    return Semantics(
      container: true,
      liveRegion: true,
      child: Container(
        margin: const EdgeInsets.only(top: 6, bottom: 6),
        padding: const EdgeInsets.fromLTRB(12, 10, 10, 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: accent),
          color: palette.surface,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (busy)
                  const Padding(
                    padding: EdgeInsets.only(top: 2),
                    child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                else if (icon != null)
                  Icon(icon, size: 18, color: danger ? accent : palette.muted),
                const SizedBox(width: 10),
                Expanded(child: Text(text, style: HermezType.body(palette))),
              ],
            ),
            if (actions.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: OverflowBar(
                  alignment: MainAxisAlignment.end,
                  spacing: 8,
                  children: actions,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// A tab that failed to load or is not available, with Retry when it can be
/// retried.
class _Notice extends StatelessWidget {
  const _Notice({
    super.key,
    required this.icon,
    required this.message,
    this.action,
  });

  final IconData icon;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final palette = HermezChatPalette.forBrightness(
      Theme.of(context).brightness,
    );
    return Align(
      alignment: Alignment.topLeft,
      child: Padding(
        padding: const EdgeInsets.only(top: 16),
        child: Semantics(
          liveRegion: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(icon, size: 18, color: palette.muted),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(message, style: HermezType.body(palette)),
                  ),
                ],
              ),
              if (action != null) ...[const SizedBox(height: 10), action!],
            ],
          ),
        ),
      ),
    );
  }
}
