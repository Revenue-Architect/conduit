import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/services/navigation_service.dart';
import '../providers/hermes_providers.dart';
import '../services/hermes_desktop_api_service.dart';
import '../views/hermes_dashboard_auth_page.dart';
import '../widgets/hermez_chat_palette.dart';
import '../widgets/hermez_visual_theme.dart';
import 'hermes_kanban_client.dart';

/// The pop Future resolves before Material's dialog exit animation. Wait for
/// the overlay to be removed before rebuilding Kanban or disposing its fields.
Future<T?> _settledDialog<T>(
  BuildContext context,
  WidgetBuilder builder,
) async {
  final route = DialogRoute<T>(context: context, builder: builder);
  final result = await Navigator.of(context).push<T>(route);
  await route.completed;
  return result;
}

Future<String?> _kanbanTextDialog(
  BuildContext context,
  String title, {
  String? hint,
  String? initial,
  int maxLength = 500,
}) async {
  final controller = TextEditingController(text: initial);
  var closing = false;
  try {
    return await _settledDialog<String>(
      context,
      (dialogContext) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: maxLength,
          decoration: hint == null ? null : InputDecoration(hintText: hint),
        ),
        actions: [
          TextButton(
            onPressed: () {
              if (closing) return;
              closing = true;
              Navigator.pop(dialogContext);
            },
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (closing) return;
              closing = true;
              Navigator.pop(dialogContext, controller.text.trim());
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  } finally {
    controller.dispose();
  }
}

class HermesKanbanPage extends ConsumerStatefulWidget {
  const HermesKanbanPage({super.key, this.client});

  /// Injected only by tests; production uses the configured Hermes session.
  final HermesKanbanClient? client;

  @override
  ConsumerState<HermesKanbanPage> createState() => _HermesKanbanPageState();
}

class _HermesKanbanPageState extends ConsumerState<HermesKanbanPage>
    with WidgetsBindingObserver {
  HermesKanbanClient? _client;
  List<KanbanBoardRef> _boards = const [];
  KanbanSnapshot? _snapshot;
  String? _board;
  String _lane = 'todo';
  String? _error;
  bool _loading = true;
  bool _busy = false;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    Future<void>.microtask(_loadBoards);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_refresh());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    final client = _client;
    if (client != null) unawaited(client.close());
    super.dispose();
  }

  HermesKanbanClient _api() {
    if (widget.client != null) return widget.client!;
    if (_client != null) return _client!;
    final service = ref.read(hermesApiServiceProvider);
    return _client = HermesKanbanClient(
      ref.read(hermesConfigProvider),
      nativeRequest: service is HermesDesktopApiService
          ? service.requestKanbanJson
          : null,
    );
  }

  Future<void> _loadBoards() async {
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final boards = await _api().boards();
      if (!mounted || generation != _generation) return;
      setState(() {
        _boards = boards;
        _board = boards.any((b) => b.slug == _board)
            ? _board
            : (boards.isEmpty ? null : boards.first.slug);
      });
      await _refresh();
    } catch (error) {
      if (mounted && generation == _generation) {
        setState(() {
          _error = _message(error);
          _loading = false;
        });
      }
    }
  }

  Future<void> _refresh() async {
    final board = _board;
    if (board == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final snapshot = await _api().board(board);
      if (!mounted || generation != _generation || _board != board) return;
      setState(() {
        _snapshot = snapshot;
        _loading = false;
      });
    } catch (error) {
      if (mounted && generation == _generation) {
        setState(() {
          _error = _message(error);
          _loading = false;
        });
      }
    }
  }

  void _selectBoard(String slug) {
    if (slug == _board) return;
    setState(() {
      _board = slug;
      _snapshot = null;
      _lane = 'todo';
    });
    unawaited(_refresh());
  }

  String _message(Object error) {
    if (error is KanbanApiException) return error.message;
    return 'Kanban is unavailable. Check Hermes sign-in and retry.';
  }

  Future<void> _signIn() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) =>
            HermesDashboardAuthPage(config: ref.read(hermesConfigProvider)),
      ),
    );
    if (mounted) await _loadBoards();
  }

  Future<void> _create() async {
    final board = _board;
    if (board == null || _busy) return;
    final title = await _askText('New task', 'Task title');
    if (title == null || title.trim().isEmpty || !mounted) return;
    final triage = _lane == 'triage';
    setState(() => _busy = true);
    try {
      await _api().create(board, title.trim(), triage: triage);
      if (mounted && _board == board) {
        // The installed Hermes API creates ordinary tasks in Ready.
        // Keep the new card in view instead of leaving the user on Todo.
        setState(() => _lane = triage ? 'triage' : 'ready');
        await _refresh();
      }
    } catch (error) {
      _showError(error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<String?> _askText(String title, String hint, {String? initial}) =>
      _kanbanTextDialog(context, title, hint: hint, initial: initial);

  void _showError(Object error) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(_message(error))));
  }

  Future<void> _openTask(KanbanTask task) async {
    final board = _board;
    if (board == null) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => FractionallySizedBox(
        heightFactor: 0.86,
        child: _KanbanTaskSheet(
          board: board,
          task: task,
          client: _api(),
          onChanged: () async {
            if (_board == board) await _refresh();
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final useHermez = shouldUseHermezChatVisuals(
      debugBuild: kDebugMode,
      android: Platform.isAndroid,
      hermes: true,
    );
    final theme = useHermez
        ? hermezVisualTheme(Theme.of(context))
        : Theme.of(context);
    return Theme(
      data: theme,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Kanban'),
          actions: [
            IconButton(
              tooltip: 'Refresh board',
              onPressed: _loading ? null : _refresh,
              icon: const Icon(Icons.refresh_rounded),
            ),
          ],
        ),
        floatingActionButton: _board == null
            ? null
            : FloatingActionButton.extended(
                onPressed: _busy ? null : _create,
                icon: const Icon(Icons.add),
                label: const Text('New task'),
              ),
        body: Column(
          children: [
            if (_boards.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: DropdownButtonFormField<String>(
                  key: ValueKey(_board),
                  initialValue: _board,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Board'),
                  items: [
                    for (final board in _boards)
                      DropdownMenuItem(
                        value: board.slug,
                        child: Text(
                          board.name,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: (value) {
                    if (value != null) _selectBoard(value);
                  },
                ),
              ),
            if (_snapshot != null && _snapshot!.boardSlug == _board)
              SizedBox(
                height: 58,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  children: [
                    for (final lane in kanbanLanes)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: ChoiceChip(
                          label: Text(
                            '${_label(lane)} ${_snapshot!.lanes[lane]?.length ?? 0}',
                          ),
                          selected: lane == _lane,
                          onSelected: (_) => setState(() => _lane = lane),
                        ),
                      ),
                  ],
                ),
              ),
            if (_loading) const LinearProgressIndicator(minHeight: 2),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        const Icon(Icons.cloud_off_outlined),
                        Text(_error!, textAlign: TextAlign.center),
                        if (_snapshot != null)
                          const Text(
                            'Showing the last loaded board; it may be stale.',
                          ),
                        TextButton(
                          onPressed: _loadBoards,
                          child: const Text('Retry'),
                        ),
                        if (_error!.contains('Dashboard sign-in'))
                          FilledButton(
                            onPressed: _signIn,
                            child: const Text('Open Dashboard sign-in'),
                          ),
                        if (_error!.contains('Native Hermes sign-in'))
                          FilledButton(
                            onPressed: () async {
                              await context.pushNamed<void>(
                                RouteNames.hermesSettings,
                              );
                              if (mounted) await _loadBoards();
                            },
                            child: const Text('Open Hermes sign-in'),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            Expanded(child: _boardBody()),
          ],
        ),
      ),
    );
  }

  Widget _boardBody() {
    final snapshot = _snapshot;
    if (snapshot == null || snapshot.boardSlug != _board) {
      if (_loading) return const Center(child: CircularProgressIndicator());
      if (_error != null) return const SizedBox.shrink();
      return const Center(child: Text('No Kanban boards available.'));
    }
    final tasks = snapshot.lanes[_lane] ?? const <KanbanTask>[];
    return RefreshIndicator(
      onRefresh: _refresh,
      child: tasks.isEmpty
          ? ListView(
              children: [
                const SizedBox(height: 100),
                Center(child: Text('No tasks in ${_label(_lane)}.')),
              ],
            )
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
              itemCount: tasks.length,
              itemBuilder: (context, index) => _KanbanTaskCard(
                task: tasks[index],
                onTap: () => _openTask(tasks[index]),
              ),
            ),
    );
  }
}

String _label(String value) =>
    value.isEmpty ? value : '${value[0].toUpperCase()}${value.substring(1)}';

class _KanbanTaskCard extends StatelessWidget {
  const _KanbanTaskCard({required this.task, required this.onTap});
  final KanbanTask task;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(bottom: 10),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(task.title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              _label(task.status),
              style: Theme.of(context).textTheme.labelMedium,
            ),
            if (task.summary != null) ...[
              const SizedBox(height: 8),
              Text(task.summary!, maxLines: 3, overflow: TextOverflow.ellipsis),
            ],
            const SizedBox(height: 8),
            Text(
              [
                if (task.assignee != null) task.assignee!,
                if (task.priority != null) 'Priority ${task.priority}',
                if (task.commentCount != null) '${task.commentCount} comments',
                if (task.childTotal != null)
                  '${task.childDone ?? 0}/${task.childTotal} children done',
              ].join(' · '),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    ),
  );
}

class _KanbanTaskSheet extends StatefulWidget {
  const _KanbanTaskSheet({
    required this.board,
    required this.task,
    required this.client,
    required this.onChanged,
  });
  final String board;
  final KanbanTask task;
  final HermesKanbanClient client;
  final Future<void> Function() onChanged;

  @override
  State<_KanbanTaskSheet> createState() => _KanbanTaskSheetState();
}

class _KanbanTaskSheetState extends State<_KanbanTaskSheet> {
  KanbanTaskDetail? _detail;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    Future<void>.microtask(_load);
  }

  Future<void> _load() async {
    try {
      final detail = await widget.client.task(widget.board, widget.task.id);
      if (mounted) {
        setState(() {
          _detail = detail;
          _error = null;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error is KanbanApiException
              ? error.message
              : 'Could not load task details.',
        );
      }
    }
  }

  Future<void> _write(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      await _load();
      await widget.onChanged();
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error is KanbanApiException
              ? error.message
              : 'Could not save this change.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<String?> _input(String title, {String? initial}) =>
      _kanbanTextDialog(context, title, initial: initial, maxLength: 1000);

  Future<void> _changeStatus(String status) async {
    if (status == 'running') return;
    var closing = false;
    final currentStatus = _detail?.task.status ?? widget.task.status;
    final consequential =
        status == 'done' ||
        status == 'blocked' ||
        status == 'archived' ||
        currentStatus == 'running';
    final confirmed = await _settledDialog<bool>(
      context,
      (dialogContext) => AlertDialog(
        title: Text('Move to ${_label(status)}?'),
        content: Text(
          consequential
              ? 'This may stop active work, hide the task, or affect dependencies. Hermes will validate the transition.'
              : 'Hermes will validate this transition.',
        ),
        actions: [
          TextButton(
            onPressed: () {
              if (closing) return;
              closing = true;
              Navigator.pop(dialogContext, false);
            },
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (closing) return;
              closing = true;
              Navigator.pop(dialogContext, true);
            },
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
    if (mounted && confirmed == true) {
      await _write(
        () => widget.client.patchTask(widget.board, widget.task.id, {
          'status': status,
        }),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final detail = _detail;
    final task = detail?.task ?? widget.task;
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(task.title, style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 8),
          Text(
            '${_label(task.status)} · ${task.assignee ?? 'Unassigned'} · Priority ${task.priority?.toString() ?? 'unknown'}',
          ),
          if (_busy) const LinearProgressIndicator(),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
            TextButton(onPressed: _load, child: const Text('Retry')),
          ],
          const SizedBox(height: 16),
          if (task.body != null) Text(task.body!),
          if (task.summary != null) ...[
            const SizedBox(height: 12),
            Text(
              'Latest summary',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            Text(task.summary!),
          ],
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton(
                onPressed: _busy
                    ? null
                    : () async {
                        final value = await _input(
                          'Edit title',
                          initial: task.title,
                        );
                        if (!mounted) return;
                        if (value != null && value.isNotEmpty) {
                          await _write(
                            () => widget.client.patchTask(
                              widget.board,
                              task.id,
                              {'title': value},
                            ),
                          );
                        }
                      },
                child: const Text('Edit title'),
              ),
              OutlinedButton(
                onPressed: _busy
                    ? null
                    : () async {
                        final value = await _input(
                          'Assign to',
                          initial: task.assignee,
                        );
                        if (!mounted) return;
                        if (value != null) {
                          await _write(
                            () => widget.client.patchTask(
                              widget.board,
                              task.id,
                              {'assignee': value},
                            ),
                          );
                        }
                      },
                child: const Text('Assignee'),
              ),
              OutlinedButton(
                onPressed: _busy
                    ? null
                    : () async {
                        final value = await _input(
                          'Priority',
                          initial: task.priority?.toString(),
                        );
                        if (!mounted) return;
                        final priority = int.tryParse(value ?? '');
                        if (priority != null) {
                          await _write(
                            () => widget.client.patchTask(
                              widget.board,
                              task.id,
                              {'priority': priority},
                            ),
                          );
                        }
                      },
                child: const Text('Priority'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text('Move task', style: Theme.of(context).textTheme.titleSmall),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final lane in kanbanLanes)
                if (lane != 'running' && lane != task.status)
                  ActionChip(
                    label: Text(_label(lane)),
                    onPressed: _busy ? null : () => _changeStatus(lane),
                  ),
              if (task.status != 'archived')
                ActionChip(
                  label: const Text('Archive'),
                  onPressed: _busy ? null : () => _changeStatus('archived'),
                ),
            ],
          ),
          if (detail != null) ...[
            const SizedBox(height: 16),
            Text('Activity', style: Theme.of(context).textTheme.titleMedium),
            Text(
              '${detail.runs.length} runs · ${detail.events.length} events · ${detail.comments.length} comments',
            ),
            for (final run in detail.runs.reversed.take(10))
              ListTile(
                leading: const Icon(Icons.play_circle_outline),
                title: Text(run['status']?.toString() ?? 'Run state unknown'),
                subtitle: Text(
                  run['summary']?.toString() ??
                      run['outcome']?.toString() ??
                      'No summary available',
                ),
              ),
            for (final event in detail.events.reversed.take(10))
              ListTile(
                leading: const Icon(Icons.history),
                title: Text(event['kind']?.toString() ?? 'Task event'),
                subtitle: Text(
                  event['created_at']?.toString() ?? 'Time unavailable',
                ),
              ),
            for (final comment in detail.comments.reversed.take(20))
              ListTile(
                title: Text(comment['body']?.toString() ?? ''),
                subtitle: Text(
                  comment['author']?.toString() ?? 'Unknown author',
                ),
              ),
            Text(
              'Dependencies: ${detail.links['parents'] is List ? (detail.links['parents'] as List).length : 'unknown'} parents',
            ),
            Text('Attachments: ${detail.attachments.length}'),
            for (final attachment in detail.attachments.take(20))
              ListTile(
                leading: const Icon(Icons.attach_file),
                title: Text(
                  attachment['filename']?.toString() ??
                      attachment['name']?.toString() ??
                      'Attachment',
                ),
                subtitle: const Text('Stored in Hermes'),
              ),
            for (final child in detail.childResults.take(20))
              ListTile(
                leading: const Icon(Icons.subdirectory_arrow_right),
                title: Text(child['title']?.toString() ?? 'Child task'),
                subtitle: Text(child['status']?.toString() ?? 'Status unknown'),
              ),
            for (final diagnostic in task.diagnostics.take(10))
              ListTile(
                leading: const Icon(Icons.info_outline),
                title: Text(
                  diagnostic['message']?.toString() ??
                      diagnostic['kind']?.toString() ??
                      'Diagnostic',
                ),
              ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _busy
                  ? null
                  : () async {
                      final value = await _input('Add comment');
                      if (!mounted) return;
                      if (value != null && value.isNotEmpty) {
                        await _write(
                          () => widget.client.comment(
                            widget.board,
                            task.id,
                            value,
                          ),
                        );
                      }
                    },
              icon: const Icon(Icons.comment_outlined),
              label: const Text('Add comment'),
            ),
          ],
        ],
      ),
    );
  }
}
