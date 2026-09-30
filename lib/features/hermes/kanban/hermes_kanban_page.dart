import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

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

/// The Hermes profiles a task can be assigned to: Bot Mode's bots, or the
/// Kanban plugin's roster on gateways without Bot Mode.
Future<List<KanbanProfile>> _kanbanProfiles(
  BuildContext context,
  HermesKanbanClient client,
) async {
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
}

/// The profile choices, drawn in place where they were asked for (they open
/// under the control and push the rest down). Choosing one reports its name;
/// "Unassign" reports an empty name, as the old picker did.
class _ProfileChoices extends StatefulWidget {
  const _ProfileChoices({
    required this.client,
    required this.current,
    required this.onSelected,
    this.enabled = true,
  });

  final HermesKanbanClient client;
  final String? current;
  final ValueChanged<String> onSelected;
  final bool enabled;

  @override
  State<_ProfileChoices> createState() => _ProfileChoicesState();
}

class _ProfileChoicesState extends State<_ProfileChoices> {
  late final Future<List<KanbanProfile>> _profiles = _kanbanProfiles(
    context,
    widget.client,
  );

  @override
  Widget build(BuildContext context) {
    final palette = HermezChatPalette.forBrightness(
      Theme.of(context).brightness,
    );
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: FutureBuilder<List<KanbanProfile>>(
        future: _profiles,
        builder: (context, snapshot) {
          if (!snapshot.hasData && !snapshot.hasError) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: LinearProgressIndicator(),
            );
          }
          if (snapshot.hasError) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'Could not load Hermes profiles. Retry the assignment.',
              ),
            );
          }
          final roster = snapshot.data!;
          if (roster.isEmpty) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text('No Hermes profiles available.'),
            );
          }
          final current = widget.current;
          return DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: palette.border),
            ),
            child: Material(
              type: MaterialType.transparency,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
                    child: Text(
                      'ASSIGNEE',
                      style: HermezType.technical(palette.muted),
                    ),
                  ),
                  for (final profile in roster)
                    ListTile(
                      enabled: widget.enabled,
                      minVerticalPadding: 10,
                      leading: Icon(
                        profile.name == current
                            ? Icons.radio_button_checked_rounded
                            : Icons.radio_button_off_rounded,
                        color: profile.name == current
                            ? palette.accent
                            : palette.muted,
                      ),
                      title: Text(profile.name),
                      subtitle: profile.description == null
                          ? null
                          : Text(
                              profile.description!,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                      onTap: () => widget.onSelected(profile.name),
                    ),
                  if (current != null && current.isNotEmpty)
                    ListTile(
                      enabled: widget.enabled,
                      leading: Icon(
                        Icons.person_off_outlined,
                        color: palette.muted,
                      ),
                      title: const Text('Unassign'),
                      subtitle: const Text('This pauses new agent work.'),
                      onTap: () => widget.onSelected(''),
                    ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
                    child: Text(
                      'Ready tasks start automatically once assigned.',
                      style: HermezType.meta(palette),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// A single field edited in place, with Cancel and Save under it.
class _InlineField extends StatefulWidget {
  const _InlineField({
    required this.label,
    required this.onCancel,
    required this.onSave,
    this.initial,
    this.maxLength = 1000,
    this.numeric = false,
    this.multiline = false,
  });

  final String label;
  final String? initial;
  final int maxLength;
  final bool numeric;
  final bool multiline;
  final VoidCallback onCancel;
  final ValueChanged<String> onSave;

  @override
  State<_InlineField> createState() => _InlineFieldState();
}

class _InlineFieldState extends State<_InlineField> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initial,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 10),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _controller,
          autofocus: true,
          maxLength: widget.maxLength,
          minLines: widget.multiline ? 2 : 1,
          maxLines: widget.multiline ? 6 : 1,
          keyboardType: widget.numeric ? TextInputType.number : null,
          decoration: InputDecoration(labelText: widget.label),
          onSubmitted: widget.multiline
              ? null
              : (_) => widget.onSave(_controller.text.trim()),
        ),
        OverflowBar(
          alignment: MainAxisAlignment.end,
          spacing: 8,
          children: [
            TextButton(
              style: TextButton.styleFrom(minimumSize: const Size(64, 44)),
              onPressed: widget.onCancel,
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size(64, 44)),
              onPressed: () => widget.onSave(_controller.text.trim()),
              child: const Text('Save'),
            ),
          ],
        ),
      ],
    ),
  );
}

/// A consequential choice held open for one more decision, drawn where it
/// was made.
class _GuardPanel extends StatelessWidget {
  const _GuardPanel({
    required this.title,
    required this.message,
    required this.keepLabel,
    required this.confirmLabel,
    required this.onKeep,
    required this.onConfirm,
  });

  final String title;
  final String message;
  final String keepLabel;
  final String confirmLabel;
  final VoidCallback onKeep;
  final VoidCallback? onConfirm;

  @override
  Widget build(BuildContext context) {
    final palette = HermezChatPalette.forBrightness(
      Theme.of(context).brightness,
    );
    final edge = palette.accent;
    return Semantics(
      container: true,
      liveRegion: true,
      label: '$title $message',
      child: Container(
        margin: const EdgeInsets.only(top: 10),
        padding: const EdgeInsets.fromLTRB(14, 12, 10, 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: edge.withValues(alpha: 0.6)),
          color: edge.withValues(alpha: 0.06),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ExcludeSemantics(
              child: Text(title, style: HermezType.technical(edge)),
            ),
            const SizedBox(height: 4),
            ExcludeSemantics(
              child: Text(message, style: HermezType.meta(palette)),
            ),
            OverflowBar(
              alignment: MainAxisAlignment.end,
              spacing: 8,
              children: [
                TextButton(
                  style: TextButton.styleFrom(minimumSize: const Size(64, 44)),
                  onPressed: onKeep,
                  child: Text(keepLabel),
                ),
                FilledButton(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(64, 44),
                  ),
                  onPressed: onConfirm,
                  child: Text(confirmLabel),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Which task field is being edited in place.
enum _TaskEdit { title, assignee, priority, comment }

/// The secondary choices of the new-task form as one physical compartment.
///
/// Title, details, warnings and the Create button stay in view. Status, bot
/// and priority sit one tap away, and their real values are on the header, so
/// nothing is hidden by being closed. Opening it only reveals controls that
/// already exist: no request is made and the created task is unchanged.
class _NewTaskOptions extends StatelessWidget {
  const _NewTaskOptions({
    required this.expanded,
    required this.onExpansionChanged,
    required this.enabled,
    required this.triage,
    required this.assignee,
    required this.priority,
    required this.onTriageChanged,
    required this.onPickAssignee,
    required this.onPriorityChanged,
    this.choosingBot = false,
    this.botChoices,
  });

  final bool expanded;
  final ValueChanged<bool> onExpansionChanged;
  final bool enabled;
  final bool triage;
  final String? assignee;
  final int priority;
  final ValueChanged<bool> onTriageChanged;
  final VoidCallback onPickAssignee;
  final ValueChanged<int> onPriorityChanged;

  /// The bot list is open inside the options, under the assign control.
  final bool choosingBot;
  final Widget? botChoices;

  @override
  Widget build(BuildContext context) {
    final palette = HermezChatPalette.forBrightness(
      Theme.of(context).brightness,
    );
    final bot = assignee != null && assignee!.isNotEmpty ? assignee : null;
    final status = triage ? 'Triage' : 'Ready';
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: HermezExpandableSection(
        expanded: expanded,
        onExpansionChanged: onExpansionChanged,
        semanticLabel:
            'Task options. $status, '
            '${bot == null ? 'no bot assigned' : 'assigned to $bot'}, '
            'priority $priority',
        openFeedback: HermezFeedbackCue.compartmentOpen,
        closeFeedback: HermezFeedbackCue.compartmentClose,
        padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
        childPadding: const EdgeInsets.fromLTRB(14, 4, 14, 14),
        header: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('OPTIONS', style: HermezType.technical(palette.muted)),
            const SizedBox(height: 2),
            Text(
              '$status · ${bot ?? 'No bot'} · Priority $priority',
              style: TextStyle(
                color: palette.ink,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SegmentedButton<bool>(
              expandedInsets: EdgeInsets.zero,
              segments: const [
                ButtonSegment(value: true, label: Text('Triage')),
                ButtonSegment(value: false, label: Text('Ready')),
              ],
              selected: {triage},
              onSelectionChanged: enabled
                  ? (value) => onTriageChanged(value.first)
                  : null,
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: enabled ? onPickAssignee : null,
              icon: const Icon(Icons.person_outline_rounded),
              label: Text(
                bot == null
                    ? 'Assign a Hermes bot (optional)'
                    : 'Assigned to $bot',
              ),
            ),
            HermezReveal(
              visible: choosingBot && botChoices != null,
              revealKey: const ValueKey('new-task-bot-choices'),
              child: botChoices ?? const SizedBox.shrink(),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<int>(
              initialValue: priority,
              // Takes the width it is given, so large text cannot push the
              // arrow out of the compartment.
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Priority'),
              items: [
                for (var value = 0; value <= 3; value++)
                  DropdownMenuItem(
                    value: value,
                    child: Text('Priority $value'),
                  ),
              ],
              onChanged: enabled
                  ? (value) => onPriorityChanged(value ?? 0)
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}

/// The theme the new-task panel and the pickers opened from it use: the
/// Hermez theme, with dialogs on the Hermez surface.
ThemeData _kanbanPanelTheme(BuildContext context) {
  final palette = HermezChatPalette.forBrightness(Theme.of(context).brightness);
  return hermezVisualTheme(Theme.of(context)).copyWith(
    dialogTheme: DialogThemeData(
      backgroundColor: palette.surface,
      surfaceTintColor: Colors.transparent,
    ),
  );
}

/// A button that opens the new-task panel by turning into it. While the panel
/// is up the panel's own copy of the button's face stands in for it, so the
/// real one is kept in place (it still takes up its space) but not drawn.
class _MorphTrigger extends StatelessWidget {
  const _MorphTrigger({
    required this.hidden,
    required this.radius,
    required this.color,
    required this.semanticLabel,
    required this.onOpen,
    required this.child,
  });

  final bool hidden;
  final double radius;
  final Color color;
  final String semanticLabel;
  final ValueChanged<HermezMorphOrigin?> onOpen;
  final Widget child;

  @override
  Widget build(BuildContext context) => Visibility(
    visible: !hidden,
    maintainState: true,
    maintainAnimation: true,
    maintainSize: true,
    child: HermezMotionSurface(
      weight: HermezMotionWeight.light,
      originRadius: radius,
      originColor: color,
      feedbackCue: HermezFeedbackCue.objectOpen,
      semanticLabel: semanticLabel,
      onOpen: onOpen,
      child: child,
    ),
  );
}

/// The plus, turning into a cross as the panel opens ([turn] 0 to 1): the
/// reference's `scale(0.97) rotate(45deg)`.
Widget _turningPlus(IconData icon, Color color, double turn) =>
    Transform.rotate(
      angle: turn * HermezPanelMotion.rotate,
      child: Transform.scale(
        scale: 1 - (1 - HermezPanelMotion.scale) * turn,
        child: Icon(icon, size: 24, color: color),
      ),
    );

/// The content of the New task button: a plus and its label. Used for the
/// resting button and for the face the panel grows out of, so the two are the
/// same picture.
class _NewTaskFaceBody extends StatelessWidget {
  const _NewTaskFaceBody({this.turn = 0});

  final double turn;

  @override
  Widget build(BuildContext context) {
    final palette = HermezChatPalette.forBrightness(
      Theme.of(context).brightness,
    );
    return Padding(
      padding: const EdgeInsetsDirectional.only(start: 16, end: 20),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _turningPlus(Icons.add, palette.onAccent, turn),
          const SizedBox(width: 8),
          Text(
            'New task',
            style: Theme.of(context).textTheme.labelLarge
                ?.copyWith(color: palette.onAccent),
          ),
        ],
      ),
    );
  }
}

/// The face the New task panel grows out of when there is no button to
/// measure: the same picture as the button.
class _NewTaskFace extends StatelessWidget {
  const _NewTaskFace({required this.turn});

  final double turn;

  @override
  Widget build(BuildContext context) => Align(
    alignment: AlignmentDirectional.centerStart,
    child: _NewTaskFaceBody(turn: turn),
  );
}

/// The floating New task button.
class _NewTaskPill extends StatelessWidget {
  const _NewTaskPill();

  @override
  Widget build(BuildContext context) {
    final palette = HermezChatPalette.forBrightness(
      Theme.of(context).brightness,
    );
    return Material(
      color: palette.accent,
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: const SizedBox(height: 56, child: _NewTaskFaceBody()),
    );
  }
}

/// The plus on a lane header, and the face the panel grows out of when it is
/// the button that was tapped.
class _LanePlus extends StatelessWidget {
  const _LanePlus({this.turn = 0});

  final double turn;

  @override
  Widget build(BuildContext context) {
    final palette = HermezChatPalette.forBrightness(
      Theme.of(context).brightness,
    );
    return SizedBox.square(
      dimension: 48,
      child: Center(
        child: _turningPlus(Icons.add_rounded, palette.accent, turn),
      ),
    );
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
  bool _showSearch = false;
  bool _showEmptyLanes = false;
  String _searchQuery = '';
  String? _error;
  bool _loading = true;
  final bool _busy = false;

  /// Which button the open new-task panel grew out of ('fab' or
  /// a lane's plus); that button is not drawn while the panel stands in for it.
  String? _creatingFrom;
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

  Future<void> _create({
    bool triage = true,
    HermezMorphOrigin? origin,
    HermezPanelFaceBuilder? face,
    String source = 'fab',
    double originRadius = 16,
    double originElevation = 0,
  }) async {
    final board = _board;
    if (board == null || _busy) return;
    final title = TextEditingController();
    final body = TextEditingController();
    var selectedTriage = triage;
    var priority = 0;
    String? assignee;
    var saving = false;
    var optionsOpen = false;
    var choosingBot = false;
    String? errorText;
    final palette = HermezChatPalette.forBrightness(
      Theme.of(context).brightness,
    );
    // The panel grows out of the button that was tapped, and goes home into
    // it. The rectangle is taken once, now: this screen makes room for the
    // keyboard, which lifts the button, and a start and end point that moved
    // with it would drift while the panel opens and closes. With no measured
    // button it grows out of a point at the middle of the screen.
    final from = origin == null
        ? HermezMorphOrigin.rect(
            Rect.fromCenter(
              center: MediaQuery.sizeOf(context).center(Offset.zero),
              width: 56,
              height: 56,
            ),
            radius: originRadius,
            color: palette.accent,
          )
        : HermezMorphOrigin.rect(
            origin.resolve(),
            radius: origin.radius,
            color: origin.color,
          );
    setState(() => _creatingFrom = source);
    try {
      final created = await pushHermezPanel<bool>(
        context,
        origin: from,
        originElevation: originElevation,
        surfaceColor: palette.surface,
        semanticLabel: 'New task',
        theme: _kanbanPanelTheme(context),
        faceBuilder: face ?? (context, turn) => _NewTaskFace(turn: turn),
        builder: (panelContext) => StatefulBuilder(
          builder: (panelContext, setModalState) => Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'New task',
                  style: Theme.of(panelContext).textTheme.headlineSmall,
                ),
                const SizedBox(height: 16),
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        TextField(
                          controller: title,
                          maxLength: 240,
                          decoration: const InputDecoration(
                            labelText: 'Title *',
                          ),
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
                        _NewTaskOptions(
                          expanded: optionsOpen,
                          enabled: !saving,
                          triage: selectedTriage,
                          assignee: assignee,
                          priority: priority,
                          onExpansionChanged: (open) {
                            // Opening the options means the typing is done;
                            // the keyboard would otherwise sit over what just
                            // opened.
                            if (open) {
                              FocusManager.instance.primaryFocus?.unfocus();
                            }
                            setModalState(() => optionsOpen = open);
                          },
                          onTriageChanged: (value) =>
                              setModalState(() => selectedTriage = value),
                          onPickAssignee: () =>
                              setModalState(() => choosingBot = !choosingBot),
                          choosingBot: choosingBot,
                          botChoices: _ProfileChoices(
                            client: _api(),
                            current: assignee,
                            enabled: !saving,
                            onSelected: (picked) => setModalState(() {
                              assignee = picked;
                              choosingBot = false;
                            }),
                          ),
                          onPriorityChanged: (value) =>
                              setModalState(() => priority = value),
                        ),
                        // Conditional lines unroll in place instead of
                        // popping in, and stay outside the compartment: a
                        // warning or an error is never hidden by a closed
                        // section.
                        HermezReveal(
                          visible:
                              !selectedTriage &&
                              assignee != null &&
                              assignee!.isNotEmpty,
                          revealKey: const ValueKey('new-task-agent-notice'),
                          child: const Padding(
                            padding: EdgeInsets.only(top: 12),
                            child: Text(
                              'Ready tasks assigned to a bot may start agent work immediately.',
                            ),
                          ),
                        ),
                        HermezReveal(
                          visible: errorText != null,
                          revealKey: const ValueKey('new-task-error'),
                          child: Padding(
                            padding: const EdgeInsets.only(top: 12),
                            child: Text(
                              errorText ?? '',
                              style: TextStyle(
                                color: Theme.of(panelContext).colorScheme.error,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                // Like a dialog's actions: side by side, stacked when large
                // text leaves no room for both.
                OverflowBar(
                  alignment: MainAxisAlignment.end,
                  spacing: 8,
                  overflowSpacing: 4,
                  overflowAlignment: OverflowBarAlignment.end,
                  children: [
                    TextButton(
                      onPressed: saving
                          ? null
                          : () => Navigator.pop(panelContext, false),
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
                                if (panelContext.mounted) {
                                  Navigator.pop(panelContext, true);
                                }
                              } catch (error) {
                                if (panelContext.mounted) {
                                  setModalState(
                                    () => errorText = _message(error),
                                  );
                                }
                              } finally {
                                if (panelContext.mounted) {
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
              ],
            ),
          ),
        ),
      );
      if (created == true && mounted && _board == board) {
        await _refresh();
      }
    } finally {
      // Only after the panel has finished contracting into its button.
      if (mounted) setState(() => _creatingFrom = null);
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
          // The board does not move for the keyboard: the floating button
          // would ride up on its own. The new-task panel lifts itself.
          resizeToAvoidBottomInset: false,
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
              : _MorphTrigger(
                  hidden: _creatingFrom == 'fab',
                  radius: 16,
                  color: palette.accent,
                  semanticLabel: 'New task',
                  onOpen: (origin) => _create(
                    origin: origin,
                    source: 'fab',
                    originRadius: 16,
                    originElevation: 2,
                  ),
                  child: const _NewTaskPill(),
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
            ? _MorphTrigger(
                hidden: _creatingFrom == 'lane:$lane',
                radius: 24,
                color: HermezChatPalette.forBrightness(
                  Theme.of(context).brightness,
                ).surface,
                semanticLabel: 'New ${_label(lane)} task',
                onOpen: (origin) => _create(
                  triage: lane == 'triage',
                  origin: origin,
                  source: 'lane:$lane',
                  originRadius: 24,
                  face: (context, turn) => _LanePlus(turn: turn),
                ),
                child: Tooltip(
                  message: 'New ${_label(lane)} task',
                  child: const _LanePlus(),
                ),
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

  /// The field being edited in place, if any.
  _TaskEdit? _editing;

  /// A status change held open for confirmation, if any.
  String? _pendingStatus;
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

  void _toggleEdit(_TaskEdit edit) => setState(() {
    _editing = _editing == edit ? null : edit;
    _pendingStatus = null;
  });

  Future<void> _saveEdit(Future<void> Function() action) async {
    setState(() => _editing = null);
    await _write(action);
  }

  /// A status control holds its choice open for one more decision, drawn
  /// under the controls.
  void _askStatus(String status) {
    if (status == 'running') return;
    setState(() {
      _pendingStatus = _pendingStatus == status ? null : status;
      _editing = null;
    });
  }

  Future<void> _changeStatus(String status) async {
    if (status == 'running') return;
    setState(() => _pendingStatus = null);
    await _write(
      () => widget.client.patchTask(widget.board, widget.task.id, {
        'status': status,
      }),
    );
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
                              : () => _toggleEdit(_TaskEdit.title),
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
                              : () => _toggleEdit(_TaskEdit.assignee),
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
                              : () => _toggleEdit(_TaskEdit.priority),
                          icon: const Icon(Icons.flag_outlined, size: 17),
                          label: const Text('Priority'),
                        ),
                      ),
                    ],
                  );
                },
              ),
              // The chosen field opens here, under its control, and pushes
              // the rest of the task down.
              HermezReveal(
                visible:
                    _editing == _TaskEdit.title ||
                    _editing == _TaskEdit.assignee ||
                    _editing == _TaskEdit.priority,
                weight: HermezMotionWeight.medium,
                revealKey: ValueKey('task-edit-$_editing'),
                child: switch (_editing) {
                  _TaskEdit.title => _InlineField(
                    label: 'Title',
                    initial: task.title,
                    maxLength: 1000,
                    onCancel: () => setState(() => _editing = null),
                    onSave: (value) {
                      if (value.isEmpty) return;
                      _saveEdit(
                        () => widget.client.patchTask(widget.board, task.id, {
                          'title': value,
                        }),
                      );
                    },
                  ),
                  _TaskEdit.priority => _InlineField(
                    label: 'Priority',
                    initial: task.priority?.toString(),
                    maxLength: 4,
                    numeric: true,
                    onCancel: () => setState(() => _editing = null),
                    onSave: (value) {
                      final priority = int.tryParse(value);
                      if (priority == null) return;
                      _saveEdit(
                        () => widget.client.patchTask(widget.board, task.id, {
                          'priority': priority,
                        }),
                      );
                    },
                  ),
                  _TaskEdit.assignee => _ProfileChoices(
                    client: widget.client,
                    current: task.assignee,
                    enabled: !_busy,
                    onSelected: (value) => _saveEdit(
                      () => widget.client.patchTask(widget.board, task.id, {
                        'assignee': value,
                      }),
                    ),
                  ),
                  _ => const SizedBox.shrink(),
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
                              side: _pendingStatus == lane
                                  ? BorderSide(
                                      color: HermezChatPalette.forBrightness(
                                        Theme.of(context).brightness,
                                      ).accent,
                                      width: 2,
                                    )
                                  : null,
                              onPressed: _busy ? null : () => _askStatus(lane),
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
                            side: _pendingStatus == 'archived'
                                ? BorderSide(
                                    color: HermezChatPalette.forBrightness(
                                      Theme.of(context).brightness,
                                    ).accent,
                                    width: 2,
                                  )
                                : null,
                            onPressed: _busy
                                ? null
                                : () => _askStatus('archived'),
                          ),
                        ),
                    ],
                  );
                },
              ),
              HermezReveal(
                visible: _pendingStatus != null,
                weight: HermezMotionWeight.medium,
                revealKey: ValueKey('task-status-$_pendingStatus'),
                child: _pendingStatus == null
                    ? const SizedBox.shrink()
                    : _GuardPanel(
                        title:
                            'MOVE TO ${_label(_pendingStatus!).toUpperCase()}?',
                        message:
                            _pendingStatus == 'done' ||
                                _pendingStatus == 'blocked' ||
                                _pendingStatus == 'archived' ||
                                task.status == 'running'
                            ? 'This may stop active work, hide the task, or affect dependencies. Hermes will validate the transition.'
                            : 'Hermes will validate this transition.',
                        keepLabel: 'Keep current',
                        confirmLabel: 'Move',
                        onKeep: () => setState(() => _pendingStatus = null),
                        onConfirm: _busy
                            ? null
                            : () => _changeStatus(_pendingStatus!),
                      ),
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
              onPressed: _busy ? null : () => _toggleEdit(_TaskEdit.comment),
              icon: const Icon(Icons.comment_outlined),
              label: const Text('Add comment'),
            ),
            HermezReveal(
              visible: _editing == _TaskEdit.comment,
              weight: HermezMotionWeight.medium,
              revealKey: const ValueKey('task-comment'),
              child: _InlineField(
                label: 'Comment',
                multiline: true,
                onCancel: () => setState(() => _editing = null),
                onSave: (value) {
                  if (value.isEmpty) return;
                  _saveEdit(
                    () => widget.client.comment(widget.board, task.id, value),
                  );
                },
              ),
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
