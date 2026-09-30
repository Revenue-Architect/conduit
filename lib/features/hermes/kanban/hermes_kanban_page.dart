import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../shared/widgets/conduit_dialog_route.dart';
import '../../../core/services/navigation_service.dart';
import '../providers/hermes_providers.dart';
import '../services/hermes_desktop_api_service.dart';
import '../services/hermes_identifier.dart';
import '../views/hermes_dashboard_auth_page.dart';
import '../views/hermes_artifacts_page.dart';
import '../views/hermes_page_chrome.dart';
import '../widgets/hermez_visual_theme.dart';
import '../feedback/hermez_feedback.dart';
import '../widgets/hermez_chat_palette.dart';
import '../widgets/hermez_expandable_section.dart';
import '../widgets/hermez_surfaces.dart';
import '../widgets/hermez_technical_background.dart';
import '../motion/hermez_motion.dart';
import '../sheets/hermez_modal_sheet.dart';
import 'hermes_kanban_client.dart';

sealed class _KanbanLinkedSelection {
  const _KanbanLinkedSelection();
}

final class _KanbanLinkedTask extends _KanbanLinkedSelection {
  const _KanbanLinkedTask(this.id);
  final String id;
}

final class _KanbanLinkedAttachment extends _KanbanLinkedSelection {
  const _KanbanLinkedAttachment(this.target);
  final HermesKanbanArtifactTarget target;
}

/// The pop Future resolves before Material's dialog exit animation. Wait for
/// the overlay to be removed before rebuilding Kanban or disposing its fields.
Future<T?> _settledDialog<T>(
  BuildContext context,
  WidgetBuilder builder,
) async {
  final palette = HermezChatPalette.forBrightness(Theme.of(context).brightness);
  final theme = hermezVisualTheme(Theme.of(context)).copyWith(
    dialogTheme: DialogThemeData(
      backgroundColor: palette.surface,
      surfaceTintColor: Colors.transparent,
    ),
  );
  final route = ConduitDialogRoute<T>(
    context: context,
    builder: (dialogContext) =>
        Theme(data: theme, child: builder(dialogContext)),
  );
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

Future<String?> _pickKanbanProfile(
  BuildContext context,
  HermesKanbanClient client, {
  String? current,
}) {
  final profiles = () async {
    try {
      final bots = await ProviderScope.containerOf(
        context,
        listen: false,
      ).read(hermesBotsProvider.future);
      if (bots.isNotEmpty) {
        return bots
            .map((bot) => KanbanProfile(bot.name, bot.description))
            .toList(growable: false);
      }
    } catch (_) {
      // Older gateways may not advertise Bot Mode; the Kanban plugin remains
      // a compatible fallback for their profile roster.
    }
    return client.profiles();
  }();
  return _settledDialog<String>(
    context,
    (dialogContext) => AlertDialog(
      title: const Text('Assign Hermes profile'),
      content: SizedBox(
        width: 320,
        height: MediaQuery.sizeOf(dialogContext).height * 0.5,
        child: FutureBuilder<List<KanbanProfile>>(
          future: profiles,
          builder: (context, snapshot) {
            if (!snapshot.hasData && !snapshot.hasError) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return const Center(
                child: Text(
                  'Could not load Hermes profiles. Retry the assignment.',
                ),
              );
            }
            final roster = snapshot.data!;
            if (roster.isEmpty) {
              return const Center(child: Text('No Hermes profiles available.'));
            }
            return ListView(
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Text('Ready tasks start automatically once assigned.'),
                ),
                for (final profile in roster)
                  ListTile(
                    title: Text(profile.name),
                    subtitle: profile.description == null
                        ? null
                        : Text(
                            profile.description!,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                    trailing: profile.name == current
                        ? const Icon(Icons.check_rounded)
                        : null,
                    onTap: () => Navigator.pop(dialogContext, profile.name),
                  ),
                if (current != null)
                  ListTile(
                    title: const Text('Unassign'),
                    subtitle: const Text('This pauses new agent work.'),
                    onTap: () => Navigator.pop(dialogContext, ''),
                  ),
              ],
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('Cancel'),
        ),
      ],
    ),
  );
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
  bool _showSearch = false;
  bool _showEmptyLanes = false;
  String _searchQuery = '';
  String? _error;
  bool _loading = true;
  final bool _busy = false;
  bool _foreground = true;
  bool _pollInFlight = false;
  Timer? _refreshTimer;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    Future<void>.microtask(_loadBoards);
    _refreshTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (!_foreground ||
          !mounted ||
          _board == null ||
          _loading ||
          _busy ||
          _pollInFlight) {
        return;
      }
      _pollInFlight = true;
      unawaited(
        _refresh(quiet: true).whenComplete(() => _pollInFlight = false),
      );
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground) unawaited(_refresh());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _refreshTimer?.cancel();
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

  Future<void> _refresh({bool quiet = false}) async {
    final board = _board;
    if (board == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    final generation = ++_generation;
    if (!quiet || _error != null) {
      setState(() {
        if (!quiet) _loading = true;
        _error = null;
      });
    }
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
      _searchQuery = '';
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

  Future<void> _create({bool triage = true}) async {
    final board = _board;
    if (board == null || _busy) return;
    final title = TextEditingController();
    final body = TextEditingController();
    var selectedTriage = triage;
    var priority = 0;
    String? assignee;
    var saving = false;
    String? errorText;
    try {
      final created = await _settledDialog<bool>(
        context,
        (dialogContext) => StatefulBuilder(
          builder: (dialogContext, setModalState) => AlertDialog(
            title: const Text('New task'),
            content: SizedBox(
              width: 420,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: title,
                      autofocus: true,
                      maxLength: 240,
                      decoration: const InputDecoration(labelText: 'Title *'),
                    ),
                    TextField(
                      controller: body,
                      minLines: 3,
                      maxLines: 7,
                      decoration: const InputDecoration(
                        labelText: 'Details / instructions',
                        hintText: 'Describe the outcome and useful context',
                      ),
                    ),
                    const SizedBox(height: 12),
                    SegmentedButton<bool>(
                      segments: const [
                        ButtonSegment(value: true, label: Text('Triage')),
                        ButtonSegment(value: false, label: Text('Ready')),
                      ],
                      selected: {selectedTriage},
                      onSelectionChanged: saving
                          ? null
                          : (value) => setModalState(
                              () => selectedTriage = value.first,
                            ),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: saving
                          ? null
                          : () async {
                              final picked = await _pickKanbanProfile(
                                dialogContext,
                                _api(),
                                current: assignee,
                              );
                              if (dialogContext.mounted && picked != null) {
                                setModalState(() => assignee = picked);
                              }
                            },
                      icon: const Icon(Icons.person_outline_rounded),
                      label: Text(
                        assignee == null || assignee!.isEmpty
                            ? 'Assign a Hermes bot (optional)'
                            : 'Assigned to $assignee',
                      ),
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<int>(
                      initialValue: priority,
                      decoration: const InputDecoration(labelText: 'Priority'),
                      items: [
                        for (var value = 0; value <= 3; value++)
                          DropdownMenuItem(
                            value: value,
                            child: Text('Priority $value'),
                          ),
                      ],
                      onChanged: saving
                          ? null
                          : (value) =>
                                setModalState(() => priority = value ?? 0),
                    ),
                    if (!selectedTriage &&
                        assignee != null &&
                        assignee!.isNotEmpty)
                      const Padding(
                        padding: EdgeInsets.only(top: 12),
                        child: Text(
                          'Ready tasks assigned to a bot may start agent work immediately.',
                        ),
                      ),
                    if (errorText != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Text(
                          errorText!,
                          style: TextStyle(
                            color: Theme.of(dialogContext).colorScheme.error,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: saving
                    ? null
                    : () => Navigator.pop(dialogContext, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: saving
                    ? null
                    : () async {
                        if (title.text.trim().isEmpty) {
                          setModalState(
                            () => errorText = 'Enter a task title.',
                          );
                          return;
                        }
                        setModalState(() {
                          saving = true;
                          errorText = null;
                        });
                        try {
                          await _api().create(
                            board,
                            title.text.trim(),
                            body: body.text,
                            triage: selectedTriage,
                            assignee: assignee,
                            priority: priority,
                          );
                          if (dialogContext.mounted) {
                            Navigator.pop(dialogContext, true);
                          }
                        } catch (error) {
                          if (dialogContext.mounted) {
                            setModalState(() => errorText = _message(error));
                          }
                        } finally {
                          if (dialogContext.mounted) {
                            setModalState(() => saving = false);
                          }
                        }
                      },
                child: saving
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Create task'),
              ),
            ],
          ),
        ),
      );
      if (created == true && mounted && _board == board) {
        await _refresh();
      }
    } finally {
      title.dispose();
      body.dispose();
    }
  }

  Future<void> _openTask(KanbanTask task, [HermezMorphOrigin? origin]) async {
    final board = _board;
    if (board == null) return;
    final selected = await pushHermezSheetRoute<_KanbanLinkedSelection>(
      context,
      origin: origin,
      heightFactor: 0.86,
      builder: (context) => Material(
        color: HermezChatPalette.forBrightness(Theme.of(context).brightness)
            .surface,
        clipBehavior: Clip.antiAlias,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
        ),
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
    if (!mounted || _board != board) return;
    switch (selected) {
      case _KanbanLinkedTask(:final id):
        try {
          final linked = await _api().task(board, id);
          if (mounted && _board == board) await _openTask(linked.task);
        } catch (_) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Linked task is unavailable.')),
            );
          }
        }
      case _KanbanLinkedAttachment(:final target):
        await context.pushNamed<void>(
          RouteNames.hermesArtifacts,
          extra: target,
        );
      case null:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = HermezChatPalette.forBrightness(
      Theme.of(context).brightness,
    );
    return Theme(
      data: hermezVisualTheme(Theme.of(context)),
      child: HermezRouteCanvas(
        color: palette.canvas,
        child: Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            surfaceTintColor: Colors.transparent,
            scrolledUnderElevation: 0,
            title: Row(
              children: [
                Text(
                  'H',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                    letterSpacing: -3,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(left: 3, top: 13),
                  child: CircleAvatar(
                    radius: 4,
                    backgroundColor: HermezChatPalette.forBrightness(
                      Theme.of(context).brightness,
                    ).accent,
                  ),
                ),
              ],
            ),
            actions: [
              IconButton(
                tooltip: 'Search tasks',
                onPressed: () => setState(() => _showSearch = !_showSearch),
                icon: const Icon(Icons.search_rounded),
              ),
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
                  onPressed: _busy ? null : () => _create(),
                  icon: const Icon(Icons.add),
                  label: const Text('New task'),
                ),
          body: Column(
            children: [
              HermezTechnicalBackground(
                variant: HermezBackgroundVariant.editorial,
                morphId: hermezMorphPart(hermezBoardMorphId, 'motif'),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        HermezMorphText(
                          'Kanban',
                          id: hermezMorphPart(hermezBoardMorphId, 'title'),
                          style:
                              (Theme.of(context).textTheme.displaySmall ??
                                      const TextStyle())
                                  .copyWith(
                                    fontSize: 36,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: -1.8,
                                  ),
                        ),
                        Text(
                          'TURN IDEAS INTO ACTION',
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(
                                letterSpacing: 3.0,
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              if (_boards.isNotEmpty)
                SizedBox(
                  height: 58,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    children: [
                      for (final board in _boards)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            label: Text(board.name),
                            selected: board.slug == _board,
                            selectedColor: palette.ink,
                            backgroundColor: palette.surface,
                            labelStyle: TextStyle(
                              color: board.slug == _board
                                  ? palette.surface
                                  : palette.ink,
                              fontWeight: FontWeight.w700,
                            ),
                            side: BorderSide(
                              color: board.slug == _board
                                  ? palette.ink
                                  : palette.border,
                            ),
                            onSelected: (_) => _selectBoard(board.slug),
                          ),
                        ),
                    ],
                  ),
                ),
              if (_showSearch)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: TextField(
                    autofocus: true,
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search_rounded),
                      hintText: 'Search this board',
                    ),
                    onChanged: (value) => setState(() => _searchQuery = value),
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
    final query = _searchQuery.trim().toLowerCase();
    final visibleByLane = <String, List<KanbanTask>>{
      for (final lane in kanbanLanes)
        lane: query.isEmpty
            ? snapshot.lanes[lane] ?? const []
            : (snapshot.lanes[lane] ?? const <KanbanTask>[])
                  .where(
                    (task) =>
                        task.title.toLowerCase().contains(query) ||
                        (task.body?.toLowerCase().contains(query) ?? false) ||
                        (task.assignee?.toLowerCase().contains(query) ?? false),
                  )
                  .toList(growable: false),
    };
    final occupied = kanbanLanes
        .where((lane) => visibleByLane[lane]!.isNotEmpty)
        .toList(growable: false);
    final empty = kanbanLanes
        .where((lane) => visibleByLane[lane]!.isEmpty)
        .toList(growable: false);
    final entryLanes = empty
        .where((lane) => lane == 'triage' || lane == 'ready')
        .toList(growable: false);
    final otherEmpty = empty
        .where((lane) => lane != 'triage' && lane != 'ready')
        .toList(growable: false);
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 110),
        children: [
          if (occupied.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 32),
              child: Text(
                query.isEmpty
                    ? 'No tasks yet. Create one to start the board.'
                    : 'No tasks match this search.',
                textAlign: TextAlign.center,
              ),
            ),
          for (final lane in occupied) _laneSection(lane, visibleByLane[lane]!),
          if (query.isEmpty)
            for (final lane in entryLanes) _laneSection(lane, const []),
          if (query.isEmpty && otherEmpty.isNotEmpty) ...[
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () =>
                    setState(() => _showEmptyLanes = !_showEmptyLanes),
                icon: AnimatedRotation(
                  turns: _showEmptyLanes ? 0.5 : 0,
                  duration: HermezMotion.settleFor(HermezMotionWeight.medium),
                  curve: HermezMotion.curveMedium,
                  child: const Icon(Icons.keyboard_arrow_down_rounded),
                ),
                label: Text(
                  _showEmptyLanes
                      ? 'Hide empty stages'
                      : 'Show ${otherEmpty.length} empty stages',
                ),
              ),
            ),
            HermezReveal(
              visible: _showEmptyLanes,
              weight: HermezMotionWeight.medium,
              revealKey: const ValueKey('hermes-kanban-empty-lanes'),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final lane in otherEmpty) _laneSection(lane, const []),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _laneSection(String lane, List<KanbanTask> tasks) {
    final visible = tasks;
    final color = switch (lane) {
      'ready' || 'triage' => Theme.of(context).colorScheme.primary,
      'running' => const Color(0xFF2776D2),
      'done' => const Color(0xFF18704B),
      _ => Theme.of(context).colorScheme.onSurfaceVariant,
    };
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ExpansionTile(
        key: PageStorageKey<String>('hermes-lane-$lane'),
        initiallyExpanded:
            visible.isNotEmpty || lane == 'triage' || lane == 'ready',
        dense: true,
        tilePadding: const EdgeInsets.symmetric(horizontal: 12),
        childrenPadding: const EdgeInsets.only(bottom: 2),
        // Collapse runs the mirrored spring: an ease-out curve played in
        // reverse starts slowly and slams into the closed state.
        expansionAnimationStyle: AnimationStyle(
          duration: HermezMotion.settleFor(HermezMotionWeight.medium),
          reverseDuration: HermezMotion.settleFor(HermezMotionWeight.light),
          curve: HermezMotion.curveMedium,
          reverseCurve: HermezMotion.curveLight.flipped,
        ),
        shape: const Border(),
        collapsedShape: const Border(),
        leading: CircleAvatar(radius: 5, backgroundColor: color),
        title: Row(
          children: [
            Flexible(
              child: Text(
                _label(lane),
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 17,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(30),
              ),
              child: Text(
                '${visible.length}',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
        trailing: lane == 'triage' || lane == 'ready'
            ? IconButton(
                tooltip: 'New ${_label(lane)} task',
                onPressed: _busy
                    ? null
                    : () => _create(triage: lane == 'triage'),
                icon: const Icon(Icons.add_rounded),
              )
            : null,
        children: [
          if (visible.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: Text('No tasks in ${_label(lane)}.'),
            ),
          if (visible.isNotEmpty)
            HermezMotionGroup(
              children: [
                for (final task in visible)
                  KeyedSubtree(
                    key: ValueKey<String>('task:${task.id}'),
                    child: _KanbanTaskCard(
                      task: task,
                      board: _board,
                      onOpen: (origin) => _openTask(task, origin),
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

String _label(String value) =>
    value.isEmpty ? value : '${value[0].toUpperCase()}${value.substring(1)}';

String _kanbanTime(Object? raw) {
  final seconds = raw is num
      ? raw.toInt()
      : int.tryParse(raw?.toString() ?? '');
  if (seconds == null || seconds <= 0) return 'Time unavailable';
  final millis = seconds > 100000000000 ? seconds : seconds * 1000;
  try {
    return DateFormat.yMMMd().add_jm().format(
      DateTime.fromMillisecondsSinceEpoch(millis),
    );
  } catch (_) {
    return 'Time unavailable';
  }
}

class _KanbanTaskCard extends StatelessWidget {
  const _KanbanTaskCard({
    required this.task,
    required this.board,
    required this.onOpen,
  });
  final KanbanTask task;
  final String? board;
  final ValueChanged<HermezMorphOrigin?> onOpen;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
    child: HermezMotionSurface(
      semanticLabel: task.title,
      originRadius: 14,
      originColor: Theme.of(context).colorScheme.surface,
      onOpen: onOpen,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 11),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              task.status == 'done'
                  ? Icons.check_circle_rounded
                  : Icons.radio_button_unchecked_rounded,
              size: 20,
              color: task.status == 'done'
                  ? const Color(0xFF17A46A)
                  : Theme.of(context).colorScheme.outline,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 4,
                        backgroundColor: task.status == 'done'
                            ? const Color(0xFF18704B)
                            : HermezChatPalette.forBrightness(
                                Theme.of(context).brightness,
                              ).accent,
                      ),
                      const SizedBox(width: 7),
                      Expanded(
                        child: HermezMorphText(
                          task.title,
                          id: hermezMorphPart(
                            hermezKanbanTaskMorphId(board, task.id),
                            'title',
                          ),
                          maxLines: 3,
                          style:
                              (Theme.of(context).textTheme.titleSmall ??
                                      const TextStyle(fontSize: 14))
                                  .copyWith(fontWeight: FontWeight.w800),
                        ),
                      ),
                    ],
                  ),
                  if (task.body != null || task.summary != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      task.summary ?? task.body!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 10,
                    runSpacing: 4,
                    children: [
                      if (task.assignee != null)
                        _TaskMeta(Icons.person_outline_rounded, task.assignee!),
                      if (task.priority != null)
                        _TaskMeta(Icons.flag_outlined, '${task.priority}'),
                      if (task.commentCount != null && task.commentCount! > 0)
                        _TaskMeta(
                          Icons.mode_comment_outlined,
                          '${task.commentCount}',
                        ),
                    ],
                  ),
                  if (task.status == 'ready' && task.assignee == null)
                    const Text('Assign a Hermes profile to start agent work.'),
                  if (task.childTotal != null && task.childTotal! > 0) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: LinearProgressIndicator(
                            value: ((task.childDone ?? 0) / task.childTotal!)
                                .clamp(0.0, 1.0),
                            minHeight: 5,
                            borderRadius: BorderRadius.circular(6),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '${task.childDone ?? 0}/${task.childTotal}',
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.chevron_right_rounded, size: 20),
          ],
        ),
      ),
    ),
  );
}

class _TaskMeta extends StatelessWidget {
  const _TaskMeta(this.icon, this.label);
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(
        icon,
        size: 14,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
      const SizedBox(width: 3),
      Text(label, style: Theme.of(context).textTheme.labelSmall),
    ],
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

class _KanbanTaskSheetState extends State<_KanbanTaskSheet>
    with WidgetsBindingObserver {
  KanbanTaskDetail? _detail;
  String? _error;
  bool _busy = false;
  bool _activityExpanded = false;
  bool _filesExpanded = false;
  bool _depsExpanded = false;
  bool _diagnosticsExpanded = false;
  bool _descriptionExpanded = false;
  bool _foreground = true;
  bool _pollInFlight = false;
  Timer? _refreshTimer;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    Future<void>.microtask(_load);
    _refreshTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (!mounted || !_foreground || _busy || _pollInFlight) return;
      _pollInFlight = true;
      unawaited(_load().whenComplete(() => _pollInFlight = false));
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground) unawaited(_load());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final generation = ++_generation;
    try {
      final detail = await widget.client.task(widget.board, widget.task.id);
      if (mounted && generation == _generation) {
        setState(() {
          _detail = detail;
          _error = null;
        });
      }
    } catch (error) {
      if (mounted && generation == _generation) {
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

  Widget _compartment({
    required String title,
    required int count,
    required bool expanded,
    required ValueChanged<bool> onChanged,
    required List<Widget> children,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: HermezExpandableSection(
      expanded: expanded,
      onExpansionChanged: onChanged,
      semanticLabel: '$title, $count',
      openFeedback: HermezFeedbackCue.compartmentOpen,
      closeFeedback: HermezFeedbackCue.compartmentClose,
      padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
      childPadding: const EdgeInsets.fromLTRB(4, 4, 4, 6),
      header: Text(
        '${title.toUpperCase()} / $count',
        style: HermezType.technical(
          HermezChatPalette.forBrightness(Theme.of(context).brightness).muted,
        ),
      ),
      // The frame paints a background; tiles need their own Material so
      // their press ink shows above it.
      child: Material(
        type: MaterialType.transparency,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
      ),
    ),
  );

  Widget _section(
    String title,
    String subtitle,
    IconData icon,
    List<Widget> children, {
    VoidCallback? onTap,
    bool expanded = true,
  }) => Card(
    margin: const EdgeInsets.only(bottom: 12),
    child: Padding(
      padding: const EdgeInsets.all(17),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(12),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor: Theme.of(context)
                      .colorScheme
                      .surfaceContainerLow,
                  child: Icon(
                    icon,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      Text(
                        subtitle,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                if (onTap != null)
                  Icon(
                    expanded
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded,
                  ),
              ],
            ),
          ),
          if (onTap == null || expanded) ...[
            const SizedBox(height: 12),
            ...children,
          ],
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final detail = _detail;
    final task = detail?.task ?? widget.task;
    final parents = detail?.links['parents'];
    final parentCount = parents is List ? parents.length : 0;
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(18, 10, 18, 30),
        children: [
          Center(
            child: Container(
              width: 40,
              height: 5,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.outline,
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
          Row(
            children: [
              Expanded(
                child: Text(
                  task.id,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelMedium,
                ),
              ),
              IconButton(
                tooltip: 'Close task details',
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close_rounded),
              ),
            ],
          ),
          HermezMorphText(
            task.title,
            id: hermezMorphPart(
              hermezKanbanTaskMorphId(widget.board, task.id),
              'title',
            ),
            maxLines: 4,
            style:
                (Theme.of(context).textTheme.headlineMedium ??
                        const TextStyle())
                    .copyWith(
                      fontSize: 28,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -1,
                      height: 1.12,
                    ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              Chip(
                avatar: const CircleAvatar(
                  radius: 5,
                  backgroundColor: Color(0xFF666765),
                ),
                label: Text(_label(task.status)),
              ),
              Chip(
                avatar: const Icon(Icons.person_outline, size: 17),
                label: Text(task.assignee ?? 'Unassigned'),
              ),
              Chip(
                avatar: const Icon(Icons.flag_outlined, size: 17),
                label: Text('Priority ${task.priority?.toString() ?? '—'}'),
              ),
            ],
          ),
          if (task.childTotal != null && task.childTotal! > 0) ...[
            const SizedBox(height: 12),
            LinearProgressIndicator(
              value: ((task.childDone ?? 0) / task.childTotal!)
                  .clamp(0.0, 1.0)
                  .toDouble(),
              minHeight: 6,
              borderRadius: BorderRadius.circular(10),
            ),
            const SizedBox(height: 4),
            Text('${task.childDone ?? 0}/${task.childTotal} children done'),
          ],
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
          if (task.status == 'ready' && task.assignee == null)
            const Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: Text(
                'This task needs a Hermes profile before an agent can start.',
              ),
            ),
          _section(
            'Actions',
            'Edit key details for this task.',
            Icons.edit_outlined,
            [
              LayoutBuilder(
                builder: (context, constraints) {
                  final scale = MediaQuery.textScalerOf(context).scale(1);
                  final columns = scale > 1.5
                      ? 1
                      : scale > 1.1 || constraints.maxWidth < 315
                      ? 2
                      : 3;
                  final width =
                      (constraints.maxWidth - (columns - 1) * 8) / columns;
                  return Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      SizedBox(
                        width: width,
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            minimumSize: const Size(0, 46),
                          ),
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
                          icon: const Icon(Icons.edit_outlined, size: 17),
                          label: const Text('Edit title'),
                        ),
                      ),
                      SizedBox(
                        width: width,
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            minimumSize: const Size(0, 46),
                          ),
                          onPressed: _busy
                              ? null
                              : () async {
                                  final value = await _pickKanbanProfile(
                                    context,
                                    widget.client,
                                    current: task.assignee,
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
                          icon: const Icon(Icons.person_outline, size: 17),
                          label: const Text('Assignee'),
                        ),
                      ),
                      SizedBox(
                        width: width,
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            minimumSize: const Size(0, 46),
                          ),
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
                          icon: const Icon(Icons.flag_outlined, size: 17),
                          label: const Text('Priority'),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
          _section(
            'Move task',
            'Change the status of this task.',
            Icons.swap_horiz_rounded,
            [
              LayoutBuilder(
                builder: (context, constraints) {
                  final scale = MediaQuery.textScalerOf(context).scale(1);
                  final columns = scale > 1.5
                      ? 1
                      : scale > 1.1 || constraints.maxWidth < 315
                      ? 2
                      : 3;
                  final width =
                      (constraints.maxWidth - (columns - 1) * 8) / columns;
                  return Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final lane in kanbanLanes)
                        if (lane != 'running' && lane != task.status)
                          SizedBox(
                            width: width,
                            child: ActionChip(
                              label: SizedBox(
                                width: double.infinity,
                                child: Text(
                                  _label(lane),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                              onPressed: _busy
                                  ? null
                                  : () => _changeStatus(lane),
                            ),
                          ),
                      if (task.status != 'archived')
                        SizedBox(
                          width: width,
                          child: ActionChip(
                            label: const SizedBox(
                              width: double.infinity,
                              child: Text(
                                'Archive',
                                textAlign: TextAlign.center,
                              ),
                            ),
                            onPressed: _busy
                                ? null
                                : () => _changeStatus('archived'),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ],
          ),
          if (detail != null) ...[
            _section(
              'Live activity',
              '${detail.runs.length} runs · ${detail.events.length} events · ${detail.comments.length} comments · refreshes while open',
              Icons.schedule_rounded,
              [
                if (detail.runs.isEmpty &&
                    detail.events.isEmpty &&
                    detail.comments.isEmpty)
                  const Text(
                    'No agent runs yet. Ready, assigned tasks start automatically.',
                  ),
                if (!_activityExpanded &&
                    detail.runs.length +
                            detail.events.length +
                            detail.comments.length >
                        3)
                  Text(
                    detail.events.isNotEmpty
                        ? 'Latest: ${(detail.events.last['kind']?.toString() ?? 'Task event').replaceAll('_', ' ')} · ${_kanbanTime(detail.events.last['created_at'])}'
                        : detail.runs.isNotEmpty
                        ? 'Latest agent run: ${detail.runs.last['status'] ?? 'unknown'}'
                        : 'Latest comment: ${detail.comments.last['author'] ?? 'Unknown author'}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                if (_activityExpanded ||
                    detail.runs.length +
                            detail.events.length +
                            detail.comments.length <=
                        3)
                  for (final run in detail.runs.reversed.take(10))
                    ListTile(
                      leading: const Icon(Icons.play_circle_outline),
                      title: Text(
                        run['status']?.toString() ?? 'Run state unknown',
                      ),
                      subtitle: Text(
                        run['summary']?.toString() ??
                            run['outcome']?.toString() ??
                            'No summary available',
                        // Run summaries can contain the entire assistant
                        // answer. Keep the timeline scannable; the full
                        // result remains in the task's Details section.
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                if (_activityExpanded ||
                    detail.runs.length +
                            detail.events.length +
                            detail.comments.length <=
                        3)
                  for (final event in detail.events.reversed.take(10))
                    ListTile(
                      leading: const Icon(Icons.history),
                      title: Text(
                        (event['kind']?.toString() ?? 'Task event').replaceAll(
                          '_',
                          ' ',
                        ),
                      ),
                      subtitle: Text(_kanbanTime(event['created_at'])),
                    ),
                if (_activityExpanded ||
                    detail.runs.length +
                            detail.events.length +
                            detail.comments.length <=
                        3)
                  for (final comment in detail.comments.reversed.take(20))
                    ListTile(
                      title: Text(
                        comment['body']?.toString() ?? '',
                        maxLines: _activityExpanded ? null : 2,
                        overflow: _activityExpanded
                            ? null
                            : TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        comment['author']?.toString() ?? 'Unknown author',
                      ),
                    ),
                if (detail.runs.length +
                        detail.events.length +
                        detail.comments.length >
                    3)
                  TextButton(
                    onPressed: () =>
                        setState(() => _activityExpanded = !_activityExpanded),
                    child: Text(
                      _activityExpanded
                          ? 'Show less activity'
                          : 'View full activity',
                    ),
                  ),
              ],
              onTap: () =>
                  setState(() => _activityExpanded = !_activityExpanded),
              expanded: _activityExpanded,
            ),
            _section(
              'Dependencies & files',
              '$parentCount parents · ${detail.attachments.length} attachments',
              Icons.attach_file_rounded,
              [
                // Physical compartments: already-loaded data opens in place
                // and pushes the task controls down. No fetch on open.
                if (parentCount + detail.childResults.length > 0)
                  _compartment(
                    title: 'Dependencies',
                    count: parentCount + detail.childResults.length,
                    expanded: _depsExpanded,
                    onChanged: (open) => setState(() => _depsExpanded = open),
                    children: [
                      if (detail.links['parents'] is List)
                        for (final parent
                            in (detail.links['parents'] as List).take(20))
                          Builder(
                            builder: (context) {
                              final id = validateHermesOpaqueIdentifier(parent);
                              return ListTile(
                                leading: const Icon(
                                  Icons.account_tree_outlined,
                                ),
                                title: Text(
                                  'Parent task · ${id ?? 'Unavailable'}',
                                ),
                                trailing: id == null
                                    ? null
                                    : const Icon(Icons.chevron_right_rounded),
                                onTap: id == null
                                    ? null
                                    : () => Navigator.pop(
                                        context,
                                        _KanbanLinkedTask(id),
                                      ),
                              );
                            },
                          ),
                      for (final child in detail.childResults.take(20))
                        Builder(
                          builder: (context) {
                            final id = validateHermesOpaqueIdentifier(
                              child['id'],
                            );
                            return ListTile(
                              leading: const Icon(
                                Icons.subdirectory_arrow_right,
                              ),
                              title: Text(
                                child['title']?.toString() ?? 'Child task',
                              ),
                              subtitle: Text(
                                child['status']?.toString() ?? 'Status unknown',
                              ),
                              trailing: id == null
                                  ? null
                                  : const Icon(Icons.chevron_right_rounded),
                              onTap: id == null
                                  ? null
                                  : () => Navigator.pop(
                                      context,
                                      _KanbanLinkedTask(id),
                                    ),
                            );
                          },
                        ),
                    ],
                  ),
                if (detail.attachments.isNotEmpty)
                  _compartment(
                    title: 'Files',
                    count: detail.attachments.length,
                    expanded: _filesExpanded,
                    onChanged: (open) => setState(() => _filesExpanded = open),
                    children: [
                      for (final attachment in detail.attachments.take(20))
                        Builder(
                          builder: (context) {
                            final target =
                                HermesKanbanArtifactTarget.fromAttachment(
                                  board: widget.board,
                                  taskId: task.id,
                                  attachment: attachment,
                                );
                            return ListTile(
                              leading: const Icon(Icons.attach_file),
                              title: Text(
                                attachment['filename']?.toString() ??
                                    'Attachment',
                              ),
                              subtitle: Text(
                                target == null
                                    ? 'Attachment unavailable'
                                    : 'Open in Artifacts',
                              ),
                              trailing: target == null
                                  ? null
                                  : const Icon(Icons.chevron_right_rounded),
                              onTap: target == null
                                  ? null
                                  : () => Navigator.pop(
                                      context,
                                      _KanbanLinkedAttachment(target),
                                    ),
                            );
                          },
                        ),
                    ],
                  ),
                if (task.diagnostics.isNotEmpty)
                  _compartment(
                    title: 'Diagnostics',
                    count: task.diagnostics.length,
                    expanded: _diagnosticsExpanded,
                    onChanged: (open) =>
                        setState(() => _diagnosticsExpanded = open),
                    children: [
                      for (final diagnostic in task.diagnostics.take(10))
                        ListTile(
                          leading: const Icon(Icons.info_outline),
                          title: Text(
                            diagnostic['message']?.toString() ??
                                diagnostic['kind']?.toString() ??
                                'Diagnostic',
                          ),
                        ),
                    ],
                  ),
              ],
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                minimumSize: const Size(double.infinity, 54),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(28),
                ),
              ),
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
          if (task.body != null || task.summary != null) ...[
            const SizedBox(height: 16),
            _section(
              'Details',
              'Task description and latest agent summary',
              Icons.notes_rounded,
              [
                if (task.body != null) ...[
                  Text(
                    'Description',
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                  Text(
                    task.body!,
                    maxLines: _descriptionExpanded ? null : 2,
                    overflow: _descriptionExpanded
                        ? null
                        : TextOverflow.ellipsis,
                  ),
                ],
                if (task.summary != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    'Latest summary',
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                  Text(
                    task.summary!,
                    maxLines: _descriptionExpanded ? null : 2,
                    overflow: _descriptionExpanded
                        ? null
                        : TextOverflow.ellipsis,
                  ),
                ],
                TextButton(
                  onPressed: () => setState(
                    () => _descriptionExpanded = !_descriptionExpanded,
                  ),
                  child: Text(
                    _descriptionExpanded ? 'Show less' : 'Read full details',
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
