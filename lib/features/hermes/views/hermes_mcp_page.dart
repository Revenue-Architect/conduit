import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/utils/debug_logger.dart';
import '../models/hermes_mcp.dart';
import '../providers/hermes_providers.dart';
import '../services/hermes_desktop_api_service.dart';
import '../motion/hermez_motion.dart';
import '../sheets/hermez_modal_sheet.dart';

final class HermesMcpPage extends ConsumerStatefulWidget {
  const HermesMcpPage({super.key});

  @override
  ConsumerState<HermesMcpPage> createState() => _HermesMcpPageState();
}

final class _HermesMcpPageState extends ConsumerState<HermesMcpPage> {
  late Future<List<HermesMcpServer>> _servers;
  final Map<String, HermesMcpTestResult> _testResults = {};
  final Set<String> _oauthPending = {};

  /// The server whose action tray is open under its row.
  String? _openActions;

  /// The server whose removal is held open in its tray.
  String? _confirmingRemove;

  @override
  void initState() {
    super.initState();
    _servers = _load();
  }

  HermesDesktopApiService get _service {
    final service = ref.read(hermesApiServiceProvider);
    if (service is! HermesDesktopApiService) {
      throw StateError('Desktop Gateway is not connected.');
    }
    return service;
  }

  Future<List<HermesMcpServer>> _load() async {
    try {
      return await _service.mcpServers();
    } catch (error) {
      DebugLogger.warning(
        'mcp-load-failed',
        scope: 'hermes/mcp',
        data: {'errorType': error.runtimeType.toString()},
      );
      rethrow;
    }
  }

  void _refresh() {
    if (mounted) setState(() => _servers = _load());
  }

  Future<void> _run(Future<void> Function() action) async {
    try {
      await action();
    } catch (error) {
      DebugLogger.warning(
        'mcp-action-failed',
        scope: 'hermes/mcp',
        data: {'errorType': error.runtimeType.toString()},
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Hermes MCP action failed.')),
      );
    }
  }

  Future<void> _add([HermezMorphOrigin? origin]) async {
    final name = TextEditingController();
    final url = TextEditingController();
    final command = TextEditingController();
    final args = TextEditingController();
    final secret = TextEditingController();
    // The + grows into the editor and the editor contracts back into it.
    final accepted = await pushHermezSheetRoute<bool>(
      context,
      origin: origin,
      builder: (context) => HermezModalSheet(
        eyebrow: 'MCP',
        title: 'Add MCP server',
        // material_ui fields need material_ui's own Material here.
        body: Material(
          type: MaterialType.transparency,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: name,
                decoration: const InputDecoration(labelText: 'Name'),
              ),
              TextField(
                controller: url,
                decoration: const InputDecoration(labelText: 'HTTP URL'),
              ),
              TextField(
                controller: command,
                decoration: const InputDecoration(labelText: 'stdio command'),
              ),
              TextField(
                controller: args,
                decoration: const InputDecoration(
                  labelText: 'Arguments (one per line)',
                ),
              ),
              TextField(
                controller: secret,
                obscureText: true,
                enableSuggestions: false,
                autocorrect: false,
                decoration: const InputDecoration(
                  labelText: 'API key (optional)',
                ),
              ),
            ],
          ),
        ),
        footer: Material(
          type: MaterialType.transparency,
          child: OverflowBar(
            alignment: MainAxisAlignment.end,
            spacing: 8,
            children: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Add'),
              ),
            ],
          ),
        ),
      ),
    );
    try {
      if (accepted != true || name.text.trim().isEmpty) return;
      await _service.addMcpServer(
        name: name.text.trim(),
        url: url.text.trim(),
        command: command.text.trim(),
        arguments: args.text
            .split('\n')
            .map((value) => value.trim())
            .where((value) => value.isNotEmpty)
            .toList(),
        bearerToken: secret.text,
      );
      _refresh();
    } finally {
      // Controllers—and therefore the only local copy of the MCP secret—are
      // discarded immediately after the RPC settles.
      name.dispose();
      url.dispose();
      command.dispose();
      args.dispose();
      secret.dispose();
    }
  }

  Future<void> _test(String name) async {
    final result = await _service.testMcpServer(name);
    if (!mounted) return;
    setState(() => _testResults[name] = result);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          result.ok
              ? 'Connected · ${result.tools} tools · ${result.resources} resources · ${result.prompts} prompts'
              : result.error ?? 'MCP test failed',
        ),
      ),
    );
  }

  Future<void> _addPreset([HermezMorphOrigin? origin]) async {
    final entries = await _service.mcpCatalog();
    if (!mounted) return;
    final selected = await pushHermezSheetRoute<HermesMcpCatalogEntry>(
      context,
      origin: origin,
      builder: (context) => HermezModalSheet(
        eyebrow: 'MCP catalog',
        title: 'Add catalog server',
        body: Material(
          type: MaterialType.transparency,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final entry in entries)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: HermezMotionSurface(
                    weight: HermezMotionWeight.light,
                    semanticLabel: 'Add ${entry.name}',
                    onTap: () => Navigator.pop(context, entry),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: Theme.of(context).colorScheme.outlineVariant,
                        ),
                      ),
                      child: ListTile(
                        title: Text(entry.name),
                        subtitle: Text(entry.description),
                        trailing: const Icon(Icons.add_rounded),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
    if (selected == null) return;
    final name = selected.name;
    if (name.isEmpty) return;
    await _service.addMcpPreset(name);
    _refresh();
  }

  Future<void> _setApiKey(String name, [HermezMorphOrigin? origin]) async {
    final value = TextEditingController();
    final accepted = await pushHermezSheetRoute<bool>(
      context,
      origin: origin,
      heightFactor: 0.6,
      builder: (context) => HermezModalSheet(
        eyebrow: 'Set API key',
        title: name,
        body: Material(
          type: MaterialType.transparency,
          child: TextField(
            controller: value,
            obscureText: true,
            enableSuggestions: false,
            autocorrect: false,
            enableIMEPersonalizedLearning: false,
            decoration: const InputDecoration(labelText: 'API key'),
          ),
        ),
        footer: Material(
          type: MaterialType.transparency,
          child: OverflowBar(
            alignment: MainAxisAlignment.end,
            spacing: 8,
            children: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Save'),
              ),
            ],
          ),
        ),
      ),
    );
    try {
      if (accepted != true || value.text.isEmpty) return;
      await _service.setMcpApiKey(name, value.text);
      _refresh();
    } finally {
      value.dispose();
    }
  }

  Future<void> _setEnabled(HermesMcpServer server, bool enabled) async {
    final name = server.name;
    if (name.isEmpty) return;
    await _service.setMcpServerEnabled(name, enabled);
    _refresh();
  }

  Future<void> _oauth(String name) async {
    if (mounted) setState(() => _oauthPending.add(name));
    try {
      if (!await _service.authenticateMcpServer(name)) {
        throw StateError('MCP authentication failed.');
      }
      _refresh();
    } finally {
      if (mounted) setState(() => _oauthPending.remove(name));
    }
  }

  Future<void> _remove(String name) async {
    if (mounted) {
      setState(() {
        _confirmingRemove = null;
        _openActions = null;
      });
    }
    await _service.removeMcpServer(name);
    _refresh();
  }

  String _serverSubtitle(HermesMcpServer server) {
    final result = _testResults[server.name];
    final tools = result?.toolNames ?? server.tools;
    return [
      server.enabled ? 'Enabled' : 'Disabled',
      if (server.auth?.isNotEmpty == true) server.auth!,
      if (server.description.isNotEmpty) server.description,
      if (tools.isNotEmpty) 'Tools: ${tools.join(', ')}',
      if (result != null)
        '${result.resources} resources · ${result.prompts} prompts',
    ].join('\n');
  }

  @override
  Widget build(BuildContext context) {
    final connectedService = ref.watch(hermesApiServiceProvider);
    final supportsCredentialUpdate =
        connectedService is HermesDesktopApiService &&
        connectedService.supportsMcpCredentialUpdate;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Hermes MCP'),
        actions: [
          Builder(
            builder: (iconContext) => RepaintBoundary(
              child: IconButton(
                tooltip: 'Add from catalog',
                onPressed: () => unawaited(
                  _run(
                    () => _addPreset(
                      HermezMorphOrigin.of(
                        iconContext,
                        radius: 24,
                        color: Theme.of(iconContext).colorScheme.surface,
                      ),
                    ),
                  ),
                ),
                icon: const Icon(Icons.auto_awesome_outlined),
              ),
            ),
          ),
        ],
      ),
      body: FutureBuilder<List<HermesMcpServer>>(
        future: _servers,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            if (snapshot.hasError) {
              return const Center(child: Text('Could not load MCP servers.'));
            }
            return const Center(child: CircularProgressIndicator.adaptive());
          }
          final servers = snapshot.data!;
          if (servers.isEmpty) {
            return const Center(child: Text('No MCP servers configured.'));
          }
          return ListView(
            padding: const EdgeInsets.only(bottom: 96),
            children: [
              for (final server in servers)
                Builder(
                  builder: (rowContext) {
                    final name = server.name;
                    final open = _openActions == name;
                    HermezMorphOrigin? rowOrigin() => HermezMorphOrigin.of(
                      rowContext,
                      radius: 14,
                      color: Theme.of(rowContext).colorScheme.surface,
                    );
                    return RepaintBoundary(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          ListTile(
                            title: Text(name),
                            subtitle: Text(
                              _serverSubtitle(server),
                              maxLines: 5,
                              overflow: TextOverflow.ellipsis,
                            ),
                            isThreeLine: true,
                            trailing: _oauthPending.contains(name)
                                ? const CircularProgressIndicator.adaptive()
                                : IconButton(
                                    tooltip: 'Server actions',
                                    isSelected: open,
                                    onPressed: () => setState(() {
                                      _openActions = open ? null : name;
                                      _confirmingRemove = null;
                                    }),
                                    icon: const Icon(Icons.more_horiz_rounded),
                                  ),
                          ),
                          // Actions open in place under the server's row and
                          // push the list down.
                          HermezReveal(
                            visible: open,
                            weight: HermezMotionWeight.medium,
                            revealKey: ValueKey('mcp-actions-$name'),
                            child: _ActionTray(
                              children: [
                                _TrayAction(
                                  icon: Icons.network_check_rounded,
                                  label: 'Test',
                                  onTap: () =>
                                      unawaited(_run(() => _test(name))),
                                ),
                                _TrayAction(
                                  icon: Icons.login_rounded,
                                  label: 'Authenticate',
                                  onTap: () =>
                                      unawaited(_run(() => _oauth(name))),
                                ),
                                if (supportsCredentialUpdate)
                                  _TrayAction(
                                    icon: Icons.key_rounded,
                                    label: 'Set API key',
                                    onTap: () => unawaited(
                                      _run(() => _setApiKey(name, rowOrigin())),
                                    ),
                                  ),
                                _TrayAction(
                                  icon: server.enabled
                                      ? Icons.toggle_off_outlined
                                      : Icons.toggle_on_outlined,
                                  label: server.enabled
                                      ? 'Disable tools'
                                      : 'Enable tools',
                                  onTap: () => unawaited(
                                    _run(
                                      () =>
                                          _setEnabled(server, !server.enabled),
                                    ),
                                  ),
                                ),
                                _TrayAction(
                                  icon: Icons.delete_outline_rounded,
                                  label: 'Remove',
                                  destructive: true,
                                  onTap: () => setState(
                                    () => _confirmingRemove =
                                        _confirmingRemove == name ? null : name,
                                  ),
                                ),
                                HermezReveal(
                                  visible: _confirmingRemove == name,
                                  weight: HermezMotionWeight.medium,
                                  revealKey: ValueKey('mcp-remove-$name'),
                                  child: _RemoveGuard(
                                    name: name,
                                    onCancel: () => setState(
                                      () => _confirmingRemove = null,
                                    ),
                                    onRemove: () =>
                                        unawaited(_run(() => _remove(name))),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
            ],
          );
        },
      ),
      floatingActionButton: Builder(
        builder: (fabContext) => RepaintBoundary(
          child: FloatingActionButton(
            tooltip: 'Add MCP server',
            onPressed: () => unawaited(
              _run(
                () => _add(
                  HermezMorphOrigin.of(
                    fabContext,
                    radius: 16,
                    color: Theme.of(fabContext).colorScheme.primaryContainer,
                  ),
                ),
              ),
            ),
            child: const Icon(Icons.add),
          ),
        ),
      ),
    );
  }
}

/// A server's actions, opened in place under its row.
class _ActionTray extends StatelessWidget {
  const _ActionTray({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
    child: DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    ),
  );
}

class _TrayAction extends StatelessWidget {
  const _TrayAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.destructive = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final color = destructive ? Theme.of(context).colorScheme.error : null;
    return ListTile(
      leading: Icon(icon, color: color),
      title: Text(label, style: TextStyle(color: color)),
      onTap: onTap,
    );
  }
}

/// Remove, held open for one more decision inside the server's tray.
class _RemoveGuard extends StatelessWidget {
  const _RemoveGuard({
    required this.name,
    required this.onCancel,
    required this.onRemove,
  });

  final String name;
  final VoidCallback onCancel;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final danger = Theme.of(context).colorScheme.error;
    return Semantics(
      container: true,
      liveRegion: true,
      label: 'Remove $name? This removes the server from Hermes.',
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        padding: const EdgeInsets.fromLTRB(14, 12, 10, 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: danger.withValues(alpha: 0.55)),
          color: danger.withValues(alpha: 0.06),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ExcludeSemantics(
              child: Text(
                'REMOVE ${name.toUpperCase()}?',
                style: TextStyle(
                  color: danger,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.2,
                  fontSize: 12,
                ),
              ),
            ),
            const SizedBox(height: 4),
            const ExcludeSemantics(
              child: Text('This removes the server from Hermes.'),
            ),
            OverflowBar(
              alignment: MainAxisAlignment.end,
              spacing: 8,
              children: [
                TextButton(
                  style: TextButton.styleFrom(minimumSize: const Size(64, 44)),
                  onPressed: onCancel,
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: danger,
                    foregroundColor: Theme.of(context).colorScheme.onError,
                    minimumSize: const Size(64, 44),
                  ),
                  onPressed: onRemove,
                  child: const Text('Remove'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
