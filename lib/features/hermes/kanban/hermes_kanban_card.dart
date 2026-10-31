part of 'hermes_kanban_page.dart';

/// Kanban as a card (docs/app-design-2026-10-30, you-kanban.html k01): it
/// grows out of Today's Kanban link, shows the board grouped by what it asks
/// of the owner, and every next step reshapes the same card: a task becomes
/// its detail, New task becomes the form. The full board stays one tap away.
Future<void> showHermesKanbanCard(
  BuildContext context, {
  @visibleForTesting HermesKanbanClient? client,
}) async {
  final selection = await pushHermezFullCard<_KanbanCardExit>(
    context,
    semanticLabel: 'Kanban',
    builder: (_) => _KanbanCard(client: client),
  );
  if (!context.mounted || selection == null) return;
  switch (selection) {
    case _KanbanCardOpenBoard():
      await context.pushNamed<void>(RouteNames.hermesKanban);
    case _KanbanCardFollow(:final selection, :final board):
      switch (selection) {
        case _KanbanLinkedTask():
          // A linked task: the board, where its detail opens in place.
          await context.pushNamed<void>(RouteNames.hermesKanban);
        case _KanbanLinkedAttachment(:final target):
          await context.pushNamed<void>(
            RouteNames.hermesArtifacts,
            extra: target,
          );
      }
      // Keep the analyzer honest about the board the link came from.
      assert(board.isNotEmpty);
  }
}

sealed class _KanbanCardExit {
  const _KanbanCardExit();
}

final class _KanbanCardOpenBoard extends _KanbanCardExit {
  const _KanbanCardOpenBoard();
}

final class _KanbanCardFollow extends _KanbanCardExit {
  const _KanbanCardFollow(this.selection, this.board);
  final _KanbanLinkedSelection selection;
  final String board;
}

/// The card's groups, in the order they ask for attention.
enum _KanbanGroup {
  needsYou('Needs you', {'review', 'blocked'}),
  running('Running', {'running'}),
  upNext('Up next', {'triage', 'todo', 'scheduled', 'ready'}),
  done('Done', {'done'});

  const _KanbanGroup(this.label, this.statuses);
  final String label;
  final Set<String> statuses;
}

enum _KanbanCardView { list, task, create }

class _KanbanCard extends ConsumerStatefulWidget {
  const _KanbanCard({this.client});

  final HermesKanbanClient? client;

  @override
  ConsumerState<_KanbanCard> createState() => _KanbanCardState();
}

class _KanbanCardState extends ConsumerState<_KanbanCard> {
  HermesKanbanClient? _client;
  String? _board;
  KanbanSnapshot? _snapshot;
  Object? _error;
  _KanbanGroup? _group;
  _KanbanCardView _view = _KanbanCardView.list;
  KanbanTask? _task;

  HermesKanbanClient get _api {
    if (widget.client != null) return widget.client!;
    final service = ref.read(hermesApiServiceProvider);
    return _client ??= HermesKanbanClient(
      ref.read(hermesConfigProvider),
      nativeRequest: service is HermesDesktopApiService
          ? service.requestKanbanJson
          : null,
    );
  }

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    unawaited(_client?.close());
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final board = _board ?? (await _api.boards()).firstOrNull?.slug;
      if (board == null) {
        if (mounted) setState(() => _error = 'No Kanban boards yet.');
        return;
      }
      final snapshot = await _api.board(board);
      if (!mounted) return;
      setState(() {
        _board = board;
        _snapshot = snapshot;
        _error = null;
        // Open on the first group that has something in it.
        _group ??= _KanbanGroup.values.firstWhere(
          (g) => _tasks(g).isNotEmpty,
          orElse: () => _KanbanGroup.needsYou,
        );
      });
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error is KanbanApiException
              ? error.message
              : 'Kanban is unavailable. Check Hermes sign-in and retry.',
        );
      }
    }
  }

  List<KanbanTask> _tasks(_KanbanGroup group) => [
    for (final entry in (_snapshot?.lanes ?? const {}).entries)
      if (group.statuses.contains(entry.key)) ...entry.value,
  ];

  void _show(_KanbanCardView view, [KanbanTask? task]) => setState(() {
    _view = view;
    _task = task;
  });

  @override
  Widget build(BuildContext context) {
    final palette = HermezChatPalette.forBrightness(
      Theme.of(context).brightness,
    );
    final board = _board;
    final task = _task;
    final Widget body = switch (_view) {
      _KanbanCardView.task when task != null && board != null => Material(
        key: ValueKey('task:${task.id}'),
        color: palette.raised,
        child: _KanbanTaskSheet(
          board: board,
          task: task,
          client: _api,
          onChanged: _load,
          onBack: () => _show(_KanbanCardView.list),
        ),
      ),
      _KanbanCardView.create when board != null => _KanbanCardCreate(
        key: const ValueKey('create'),
        board: board,
        client: _api,
        onBack: () => _show(_KanbanCardView.list),
        onCreated: () async {
          _show(_KanbanCardView.list);
          setState(() => _group = _KanbanGroup.upNext);
          await _load();
        },
      ),
      _ => _list(context, palette),
    };
    // The pressed row grows into the next step and the card springs to
    // its height; back folds the step into the row it came from.
    return HermezCardMorph(
      depth: _view == _KanbanCardView.list ? 0 : 1,
      raised: _view != _KanbanCardView.list,
      child: body,
    );
  }

  Widget _list(BuildContext context, HermezChatPalette palette) {
    final snapshot = _snapshot;
    final group = _group ?? _KanbanGroup.needsYou;
    final tasks = snapshot == null ? const <KanbanTask>[] : _tasks(group);
    return Column(
      key: const ValueKey('list'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _CardGrabber(),
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 6, 10, 10),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Kanban',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.3,
                    color: palette.ink,
                  ),
                ),
              ),
              TextButton(
                onPressed: () =>
                    Navigator.pop(context, const _KanbanCardOpenBoard()),
                child: const Text('Board'),
              ),
              IconButton(
                tooltip: 'Close',
                onPressed: () => Navigator.pop(context),
                icon: Icon(Icons.close_rounded, color: palette.ink),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 40,
          // Four pills: a plain row that scrolls, all of them built.
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: Row(
              children: [
                for (final g in _KanbanGroup.values)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(
                        snapshot == null
                            ? g.label
                            : '${g.label} ${_tasks(g).length}',
                      ),
                      selected: g == group,
                      showCheckmark: false,
                      onSelected: (_) => setState(() => _group = g),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 6),
        Expanded(child: _rows(context, palette, snapshot, tasks)),
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 16),
          child: FilledButton(
            onPressed: _board == null
                ? null
                : () => _show(_KanbanCardView.create),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
            ),
            child: const Text('New task'),
          ),
        ),
      ],
    );
  }

  Widget _rows(
    BuildContext context,
    HermezChatPalette palette,
    KanbanSnapshot? snapshot,
    List<KanbanTask> tasks,
  ) {
    final error = _error;
    if (error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '$error',
                textAlign: TextAlign.center,
                style: TextStyle(color: palette.muted, fontSize: 15),
              ),
              const SizedBox(height: 12),
              TextButton(onPressed: _load, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }
    if (snapshot == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final bots = {
      for (final bot in ref.watch(hermesBotsProvider).value ?? const [])
        bot.name: bot,
    };
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      children: [
        if (tasks.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 20, 14, 8),
            child: Text(
              'Nothing here.',
              style: TextStyle(color: palette.muted, fontSize: 15),
            ),
          ),
        for (final task in tasks)
          _KanbanCardRow(
            task: task,
            bot: bots[task.assignee],
            palette: palette,
            onOpen: () => _show(_KanbanCardView.task, task),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
          child: Text(
            'Needs you is review and blocked; Up next is triage, to do, '
            'scheduled and ready. Tap a task and the card becomes it.',
            style: TextStyle(color: palette.muted, fontSize: 12, height: 1.35),
          ),
        ),
      ],
    );
  }
}

class _CardGrabber extends StatelessWidget {
  const _CardGrabber();

  @override
  Widget build(BuildContext context) => Center(
    child: Container(
      margin: const EdgeInsets.only(top: 8, bottom: 2),
      width: 36,
      height: 4,
      decoration: BoxDecoration(
        color: HermezChatPalette.forBrightness(Theme.of(context).brightness)
            .border,
        borderRadius: BorderRadius.circular(2),
      ),
    ),
  );
}

/// A task: who has it, its title, where it stands and how old it is, and the
/// one thing to do with it.
class _KanbanCardRow extends StatelessWidget {
  const _KanbanCardRow({
    required this.task,
    required this.bot,
    required this.palette,
    required this.onOpen,
  });

  final KanbanTask task;
  final HermesBot? bot;
  final HermezChatPalette palette;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final bot = this.bot;
    final created = _kanbanDate(task.createdAt);
    final meta = [
      task.assignee ?? 'No bot',
      _label(task.status),
      if (created != null) hermezRelativeLabel(created),
    ].join(' · ');
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onOpen,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 60),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Row(
            children: [
              ClipOval(
                child: SizedBox.square(
                  dimension: 36,
                  child: bot == null
                      ? ColoredBox(
                          color: palette.canvas,
                          child: Icon(
                            Icons.person_outline_rounded,
                            size: 18,
                            color: palette.muted,
                          ),
                        )
                      : HermezBotMark(
                          identity: hermezIdentityForBot(bot),
                          botName: bot.name,
                          size: 36,
                          label: bot.title,
                        ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      task.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        color: palette.ink,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      meta,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: palette.muted),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              task.status == 'review'
                  ? FilledButton(
                      onPressed: onOpen,
                      style: FilledButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                      ),
                      child: const Text('Review'),
                    )
                  : OutlinedButton(
                      onPressed: onOpen,
                      style: OutlinedButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                      ),
                      child: const Text('Open'),
                    ),
            ],
          ),
        ),
      ),
    );
  }
}

DateTime? _kanbanDate(Object? raw) {
  final seconds = raw is num ? raw.toInt() : int.tryParse('${raw ?? ''}');
  if (seconds == null || seconds <= 0) return null;
  return DateTime.fromMillisecondsSinceEpoch(
    seconds > 100000000000 ? seconds : seconds * 1000,
  );
}

/// New task, in the same card: what, details, who, and whether it starts
/// now or waits in triage.
class _KanbanCardCreate extends StatefulWidget {
  const _KanbanCardCreate({
    super.key,
    required this.board,
    required this.client,
    required this.onBack,
    required this.onCreated,
  });

  final String board;
  final HermesKanbanClient client;
  final VoidCallback onBack;
  final Future<void> Function() onCreated;

  @override
  State<_KanbanCardCreate> createState() => _KanbanCardCreateState();
}

class _KanbanCardCreateState extends State<_KanbanCardCreate> {
  final _title = TextEditingController();
  final _body = TextEditingController();
  List<KanbanProfile>? _profiles;
  String? _assignee;
  bool _ready = false;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(
      _kanbanProfiles(context, widget.client)
          .then((p) {
            if (mounted) setState(() => _profiles = p);
          })
          .catchError((_) {
            if (mounted) setState(() => _profiles = const []);
          }),
    );
  }

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final title = _title.text.trim();
    if (title.isEmpty) {
      setState(() => _error = 'Give the task a title.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.client.create(
        widget.board,
        title,
        triage: !_ready,
        assignee: _assignee,
        body: _body.text,
      );
      await widget.onCreated();
    } catch (error) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = error is KanbanApiException
              ? error.message
              : 'Could not create the task.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = HermezChatPalette.forBrightness(
      Theme.of(context).brightness,
    );
    final profiles = _profiles;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _CardGrabber(),
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 4, 10, 6),
          child: Row(
            children: [
              IconButton(
                tooltip: 'Back',
                onPressed: _saving ? null : widget.onBack,
                icon: Icon(Icons.chevron_left_rounded, color: palette.ink),
              ),
              Expanded(
                child: Text(
                  'New task',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.3,
                    color: palette.ink,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Close',
                onPressed: () => Navigator.pop(context),
                icon: Icon(Icons.close_rounded, color: palette.ink),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(22, 0, 22, 12),
            children: [
              TextField(
                controller: _title,
                autofocus: true,
                enabled: !_saving,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(labelText: 'What'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _body,
                enabled: !_saving,
                minLines: 2,
                maxLines: 5,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(labelText: 'Details'),
              ),
              const SizedBox(height: 18),
              Text('Who', style: TextStyle(fontSize: 12, color: palette.muted)),
              const SizedBox(height: 6),
              if (profiles == null)
                const LinearProgressIndicator()
              else
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ChoiceChip(
                      label: const Text('No bot'),
                      selected: _assignee == null,
                      showCheckmark: false,
                      onSelected: _saving
                          ? null
                          : (_) => setState(() => _assignee = null),
                    ),
                    for (final p in profiles)
                      ChoiceChip(
                        label: Text(p.name),
                        selected: _assignee == p.name,
                        showCheckmark: false,
                        onSelected: _saving
                            ? null
                            : (_) => setState(() => _assignee = p.name),
                      ),
                  ],
                ),
              const SizedBox(height: 18),
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: false, label: Text('Triage')),
                  ButtonSegment(value: true, label: Text('Ready')),
                ],
                selected: {_ready},
                onSelectionChanged: _saving
                    ? null
                    : (value) => setState(() => _ready = value.single),
              ),
              if (_ready && _assignee != null) ...[
                const SizedBox(height: 10),
                Text(
                  'Ready tasks assigned to a bot may start agent work '
                  'immediately.',
                  style: TextStyle(fontSize: 13, color: palette.muted),
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(
                  _error!,
                  style: TextStyle(fontSize: 13, color: palette.failed),
                ),
              ],
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 4, 18, 16),
          child: FilledButton(
            onPressed: _saving ? null : _save,
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
            ),
            child: Text(_saving ? 'Creating…' : 'Create task'),
          ),
        ),
      ],
    );
  }
}
