import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/services/navigation_service.dart';
import '../../../shared/theme/theme_extensions.dart';
import '../../../shared/widgets/platform_ui/platform_ui.dart';
import '../models/hermes_bot.dart';
import '../models/hermes_team.dart';
import '../models/hermes_team_timeline.dart';
import '../motion/hermez_motion.dart';
import '../providers/hermes_providers.dart';
import '../services/hermes_activity_presenter.dart';
import '../services/hermes_desktop_api_service.dart';
import '../sheets/hermez_modal_sheet.dart';
import '../widgets/hermes_activity_view.dart';
import '../widgets/hermez_bot_mark.dart';
import '../widgets/hermez_chat_palette.dart';
import '../widgets/hermez_live.dart';
import '../widgets/hermez_surfaces.dart';
import 'hermes_page_chrome.dart';
import '../widgets/hermez_skeleton.dart';

/// Teams on this Hermes server, most recently active first. An error means
/// the server does not offer Group Chat (or it is not running).
final hermesTeamsProvider = FutureProvider.autoDispose<List<HermesTeam>>((
  ref,
) async {
  final service = ref.watch(hermesApiServiceProvider);
  if (service is! HermesDesktopApiService) return const [];
  return service.listTeams();
});

/// Opens a team room, growing it out of [origin] when there is one.
void openHermesTeam(
  BuildContext context,
  HermesTeam team, [
  HermezMorphOrigin? origin,
]) => context.pushNamed<void>(
  RouteNames.hermesTeamRoom,
  pathParameters: {'roomId': team.roomId},
  extra: origin,
);

/// Asks for 2–6 bots and a name, creates the room on Hermes, and opens it.
Future<void> startHermesTeam(
  BuildContext context,
  WidgetRef ref, [
  HermezMorphOrigin? origin,
]) async {
  final team = await showHermezSheet<HermesTeam>(
    context,
    origin: origin,
    title: 'New team',
    subtitle: Text(
      'Put 2 to 6 bots in one room to work on something together.',
      style: HermezType.meta(
        HermezChatPalette.forBrightness(Theme.of(context).brightness),
      ),
    ),
    body: const _NewTeamForm(),
  );
  if (team == null || !context.mounted) return;
  ref.invalidate(hermesTeamsProvider);
  openHermesTeam(context, team);
}

/// Overlapping marks for a team's bots.
class HermesTeamMarks extends StatelessWidget {
  const HermesTeamMarks({super.key, required this.team, this.size = 30});

  final HermesTeam team;
  final double size;

  @override
  Widget build(BuildContext context) {
    final shown = team.members.take(4).toList(growable: false);
    final step = size * 0.62;
    return SizedBox(
      width: shown.isEmpty ? size : size + step * (shown.length - 1),
      height: size,
      child: Stack(
        children: [
          for (var i = shown.length - 1; i >= 0; i--)
            Positioned(
              left: step * i,
              child: HermezBotMark(
                identity: hermezIdentityForName(shown[i].profile),
                size: size,
                label: shown[i].label,
              ),
            ),
        ],
      ),
    );
  }
}

/// One team in a list: its bots, its name, who is in it.
class HermesTeamTile extends StatelessWidget {
  const HermesTeamTile({super.key, required this.team, required this.onOpen});

  final HermesTeam team;
  final ValueChanged<HermezMorphOrigin?> onOpen;

  @override
  Widget build(BuildContext context) {
    final palette = HermezChatPalette.forBrightness(
      Theme.of(context).brightness,
    );
    return HermezMotionSurface(
      weight: HermezMotionWeight.light,
      semanticLabel: 'Team ${team.name}',
      originRadius: 18,
      originColor: palette.surface,
      onOpen: onOpen,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            HermesTeamMarks(team: team),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    team.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: HermezType.section(palette).copyWith(fontSize: 15),
                  ),
                  Text(
                    team.members.map((member) => member.label).join(', '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: HermezType.meta(palette),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: palette.muted),
          ],
        ),
      ),
    );
  }
}

/// All teams.
class HermesTeamsPage extends ConsumerWidget {
  const HermesTeamsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = HermezChatPalette.forBrightness(
      Theme.of(context).brightness,
    );
    final teams = ref.watch(hermesTeamsProvider);
    return HermesPageChrome(
      title: 'Teams',
      subtitle: 'Bots working together',
      child: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(hermesTeamsProvider);
          await ref.read(hermesTeamsProvider.future);
        },
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 36),
          children: [
            Builder(
              builder: (context) => HermezMotionSurface(
                semanticLabel: 'New team',
                originRadius: 999,
                originColor: palette.ink,
                onOpen: (origin) => startHermesTeam(context, ref, origin),
                child: Container(
                  constraints: const BoxConstraints(minHeight: 52),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: palette.ink,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.group_add_outlined, color: palette.surface),
                      const SizedBox(width: 8),
                      Text(
                        'New team',
                        style: TextStyle(
                          color: palette.surface,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 18),
            ...teams.when(
              loading: () => const [LinearProgressIndicator()],
              error: (_, _) => [
                Text(
                  'Teams are not available on this Hermes server. Group Chat '
                  'needs Hermes 2026.9 or later with its room worker running.',
                  style: HermezType.meta(palette),
                ),
              ],
              data: (list) => list.isEmpty
                  ? [
                      Text(
                        'No teams yet. Start one to have your bots work a '
                        'problem together: they reply in turn, can pass, and '
                        'answer @mentions.',
                        style: HermezType.meta(palette),
                      ),
                    ]
                  : [
                      for (final team in list)
                        HermesTeamTile(
                          team: team,
                          onOpen: (origin) =>
                              openHermesTeam(context, team, origin),
                        ),
                    ],
            ),
          ],
        ),
      ),
    );
  }
}

class _NewTeamForm extends ConsumerStatefulWidget {
  const _NewTeamForm();

  @override
  ConsumerState<_NewTeamForm> createState() => _NewTeamFormState();
}

class _NewTeamFormState extends ConsumerState<_NewTeamForm> {
  static const _min = 2;
  static const _max = 6;

  final List<HermesBot> _picked = [];
  final TextEditingController _name = TextEditingController();
  bool _nameEdited = false;
  bool _creating = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _toggle(HermesBot bot) {
    setState(() {
      if (!_picked.remove(bot) && _picked.length < _max) _picked.add(bot);
      if (!_nameEdited) {
        _name.text = _picked.map((bot) => bot.title).join(', ');
      }
    });
  }

  Future<void> _create() async {
    final service = ref.read(hermesApiServiceProvider);
    if (service is! HermesDesktopApiService || _picked.length < _min) return;
    final name = _name.text.trim().isEmpty
        ? _picked.map((bot) => bot.title).join(', ')
        : _name.text.trim();
    setState(() {
      _creating = true;
      _error = null;
    });
    try {
      final team = await service.createTeam(
        name: name.length > 200 ? name.substring(0, 200) : name,
        members: [
          for (final bot in _picked)
            HermesTeamMember.rosterFor(bot.name, title: bot.title),
        ],
      );
      if (mounted) Navigator.of(context).pop(team);
    } catch (error) {
      if (mounted) {
        setState(() {
          _creating = false;
          _error = 'Could not create the team. $error';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = HermezChatPalette.forBrightness(
      Theme.of(context).brightness,
    );
    final bots = ref.watch(hermesBotsProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('BOTS', style: HermezType.technical(palette.muted)),
        const SizedBox(height: 6),
        ...bots.when(
          loading: () => const [LinearProgressIndicator()],
          error: (_, _) => [
            Text('Could not load your bots.', style: HermezType.meta(palette)),
          ],
          data: (list) => [
            for (final bot in list)
              _BotChoice(
                bot: bot,
                picked: _picked.contains(bot),
                enabled: _picked.contains(bot) || _picked.length < _max,
                onTap: () => _toggle(bot),
              ),
          ],
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _name,
          maxLength: 200,
          onChanged: (_) => _nameEdited = true,
          decoration: const InputDecoration(
            labelText: 'Team name',
            counterText: '',
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(_error!, style: TextStyle(color: palette.accent)),
        ],
        const SizedBox(height: 16),
        FilledButton(
          onPressed: _picked.length >= _min && !_creating ? _create : null,
          child: Text(
            _creating
                ? 'Creating…'
                : _picked.length < _min
                ? 'Pick at least $_min bots'
                : 'Create team with ${_picked.length} bots',
          ),
        ),
      ],
    );
  }
}

class _BotChoice extends StatelessWidget {
  const _BotChoice({
    required this.bot,
    required this.picked,
    required this.enabled,
    required this.onTap,
  });

  final HermesBot bot;
  final bool picked;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = HermezChatPalette.forBrightness(
      Theme.of(context).brightness,
    );
    return HermezMotionSurface(
      weight: HermezMotionWeight.light,
      enabled: enabled,
      semanticLabel: '${bot.title}${picked ? ', in the team' : ''}',
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            HermezBotMark(
              identity: hermezIdentityForName(bot.name),
              size: 34,
              label: bot.title,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    bot.title,
                    style: HermezType.section(palette).copyWith(fontSize: 15),
                  ),
                  if (bot.description case final description?)
                    Text(
                      description,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: HermezType.meta(palette),
                    ),
                ],
              ),
            ),
            HermezIconSwap(
              icon: picked
                  ? Icons.check_circle_rounded
                  : Icons.radio_button_unchecked_rounded,
              color: picked ? palette.accent : palette.muted,
            ),
          ],
        ),
      ),
    );
  }
}

/// A team room: the bots' discussion, what they are doing now, anything
/// waiting on the user, and a composer. Hermes runs the discussion; this
/// page reads the room log while it is open.
class HermesTeamRoomPage extends ConsumerStatefulWidget {
  const HermesTeamRoomPage({super.key, required this.roomId});

  final String roomId;

  @override
  ConsumerState<HermesTeamRoomPage> createState() => _HermesTeamRoomPageState();
}

class _HermesTeamRoomPageState extends ConsumerState<HermesTeamRoomPage> {
  HermesTeam? _team;
  HermesTeamStatus _status = HermesTeamStatus.idle;
  List<HermesTeamEvent> _events = const [];
  int _cursor = 0;
  bool _loading = true;
  Object? _error;
  bool _sending = false;

  /// The Team options tray is open under the room header.
  bool _optionsOpen = false;

  /// Delete team is held open for one more decision inside the tray.
  bool _confirmingDelete = false;
  DateTime? _sentAt;
  bool _refreshing = false;
  Timer? _poll;

  /// What each member is doing in its own room session, by profile.
  Map<String, HermesTeamMemberLive> _live = const {};
  Timer? _livePoll;
  bool _liveLoading = false;

  /// Lines that were already there when the room opened do not animate in.
  Set<String>? _initialKeys;

  final TextEditingController _input = TextEditingController();
  final FocusNode _focus = FocusNode(debugLabel: 'hermes-team-composer');

  @override
  void initState() {
    super.initState();
    unawaited(_refresh());
  }

  @override
  void dispose() {
    _poll?.cancel();
    _livePoll?.cancel();
    _input.dispose();
    _focus.dispose();
    super.dispose();
  }

  HermesDesktopApiService? get _service {
    final service = ref.read(hermesApiServiceProvider);
    return service is HermesDesktopApiService ? service : null;
  }

  Future<void> _refresh() async {
    if (_refreshing || !mounted) return;
    final service = _service;
    if (service == null || !isValidHermesTeamId(widget.roomId)) {
      setState(() {
        _loading = false;
        _error = StateError('Teams need the Hermes Desktop connection.');
      });
      return;
    }
    // Poll only while the app is in front.
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    if (lifecycle != null && lifecycle != AppLifecycleState.resumed) {
      _schedule();
      return;
    }
    _refreshing = true;
    try {
      final state = await service.teamState(widget.roomId);
      var events = _events;
      var cursor = _cursor;
      for (var page = 0; page < 10; page++) {
        final log = await service.teamLog(widget.roomId, sinceSeq: cursor);
        events = mergeHermesTeamEvents(events, log.events);
        cursor = log.cursor;
        if (!log.hasMore) break;
      }
      if (!mounted) return;
      setState(() {
        _team = state.team;
        _status = state.status;
        _events = events;
        _cursor = cursor;
        _loading = false;
        _error = null;
        _initialKeys ??= {for (final event in events) event.eventId};
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = error;
        });
      }
    } finally {
      _refreshing = false;
      _schedule();
      _scheduleLive(immediately: _livePoll == null && _teamBusy);
    }
  }

  bool get _teamBusy {
    final sent = _sentAt;
    return _status.working ||
        _status.blocked ||
        _live.values.any((member) => member.working) ||
        (sent != null &&
            DateTime.now().difference(sent) < const Duration(seconds: 20));
  }

  /// Reads each member's room session while the team works: read only,
  /// never resumed or steered from here.
  void _scheduleLive({bool immediately = false}) {
    if (!mounted || _livePoll?.isActive == true) return;
    if (!_teamBusy) {
      if (_live.values.any((member) => member.working)) {
        setState(() => _live = const {});
      }
      return;
    }
    _livePoll = Timer(
      immediately ? Duration.zero : const Duration(milliseconds: 1200),
      () => unawaited(_pollLive()),
    );
  }

  Future<void> _pollLive() async {
    _livePoll = null;
    final team = _team;
    final service = _service;
    if (!mounted || team == null || service == null || _liveLoading) return;
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    if (lifecycle != null && lifecycle != AppLifecycleState.resumed) {
      _scheduleLive();
      return;
    }
    _liveLoading = true;
    try {
      final live = await service.teamMembersLive(team.roomId, team.members);
      if (mounted) setState(() => _live = live);
    } catch (_) {
      // Live detail is optional: the room log still shows every reply.
    } finally {
      _liveLoading = false;
      _scheduleLive();
    }
  }

  void _schedule() {
    _poll?.cancel();
    if (!mounted) return;
    final sent = _sentAt;
    final busy =
        _status.working ||
        _status.blocked ||
        (sent != null &&
            DateTime.now().difference(sent) < const Duration(seconds: 20));
    _poll = Timer(
      _error != null
          ? const Duration(seconds: 8)
          : busy
          ? const Duration(milliseconds: 1500)
          : const Duration(seconds: 6),
      _refresh,
    );
  }

  Future<void> _act(
    Future<void> Function(HermesDesktopApiService) action,
    String failure,
  ) async {
    final service = _service;
    if (service == null) return;
    try {
      await action(service);
    } catch (error) {
      if (mounted) {
        AdaptiveSnackBar.show(
          context,
          message: failure,
          type: AdaptiveSnackBarType.error,
        );
      }
    }
    unawaited(_refresh());
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    final service = _service;
    try {
      if (service == null) throw StateError('No Hermes connection.');
      await service.sendToTeam(widget.roomId, text);
      _input.clear();
      _sentAt = DateTime.now();
      _scheduleLive(immediately: true);
    } catch (_) {
      if (mounted) {
        AdaptiveSnackBar.show(
          context,
          message: 'Could not send to the team.',
          type: AdaptiveSnackBarType.error,
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
    unawaited(_refresh());
  }

  void _mention(HermesTeamMember member) {
    final text = _input.text;
    final selection = _input.selection;
    final at = selection.isValid ? selection.start : text.length;
    final end = selection.isValid ? selection.end : text.length;
    final before = text.substring(0, at);
    final insert =
        '${before.isEmpty || before.endsWith(' ') ? '' : ' '}@${member.handle} ';
    _input.value = TextEditingValue(
      text: before + insert + text.substring(end),
      selection: TextSelection.collapsed(offset: at + insert.length),
    );
    _focus.requestFocus();
  }

  Future<void> _disband() async {
    final team = _team;
    if (team == null) return;
    setState(() => _confirmingDelete = false);
    final service = _service;
    if (service == null) return;
    try {
      await service.disbandTeam(team.roomId);
      ref.invalidate(hermesTeamsProvider);
      if (mounted) Navigator.of(context).maybePop();
    } catch (_) {
      if (mounted) {
        AdaptiveSnackBar.show(
          context,
          message: 'Could not delete the team.',
          type: AdaptiveSnackBarType.error,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = HermezChatPalette.forBrightness(
      Theme.of(context).brightness,
    );
    final team = _team;
    final timeline = team == null
        ? const HermesTeamTimeline(lines: [], thinking: [])
        : HermesTeamTimeline.from(_events, team);
    final working =
        _status.working ||
        timeline.thinking.isNotEmpty ||
        _live.values.any((member) => member.working);
    return HermesPageChrome(
      title: team?.name ?? 'Team',
      subtitle: '',
      showHeader: false,
      actions: [
        if (team != null)
          IconButton(
            tooltip: 'Team options',
            isSelected: _optionsOpen,
            onPressed: () => setState(() {
              _optionsOpen = !_optionsOpen;
              if (!_optionsOpen) _confirmingDelete = false;
            }),
            icon: const Icon(Icons.tune_rounded),
          ),
      ],
      child: Column(
        children: [
          if (team != null) _RoomHeader(team: team, working: working),
          // Team options open in place under the header and push the room
          // down; nothing floats over it.
          if (team != null)
            HermezReveal(
              visible: _optionsOpen,
              weight: HermezMotionWeight.medium,
              revealKey: const ValueKey('team-options'),
              child: _TeamOptions(
                team: team,
                confirmingDelete: _confirmingDelete,
                onAskDelete: () =>
                    setState(() => _confirmingDelete = !_confirmingDelete),
                onKeep: () => setState(() => _confirmingDelete = false),
                onDelete: () => unawaited(_disband()),
              ),
            ),
          if (_error != null && team != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 6),
              child: Text(
                'Reconnecting to the team…',
                style: HermezType.meta(palette),
              ),
            ),
          Expanded(
            child: _loading
                ? Align(
                    alignment: Alignment.topCenter,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: HermezSkeleton.rows(count: 4),
                    ),
                  )
                : team == null
                ? Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      'This team could not be opened. It may have been '
                      'deleted, or Group Chat is not running on Hermes.',
                      style: HermezType.meta(palette),
                    ),
                  )
                : _RoomLog(
                    team: team,
                    timeline: timeline,
                    live: _live,
                    initialKeys: _initialKeys ?? const {},
                  ),
          ),
          if (team != null) ...[
            for (final approval in _status.approvals)
              _ApprovalBar(
                approval: approval,
                member: team.memberById(approval.memberId),
                onAnswer: (allow) => _act(
                  (service) => service.answerTeamApproval(
                    team.roomId,
                    approval,
                    allow: allow,
                  ),
                  'Could not answer the request.',
                ),
              ),
            if (_status.retries.isNotEmpty)
              _NoticeBar(
                text: "A reply didn't finish.",
                action: 'Retry',
                onAction: () => _act(
                  (service) =>
                      service.retryTeamTask(team.roomId, _status.retries.first),
                  'Could not retry.',
                ),
              ),
            _Composer(
              team: team,
              controller: _input,
              focus: _focus,
              sending: _sending,
              working: working,
              onSend: _send,
              onStop: () => _act(
                (service) => service.stopTeam(team.roomId),
                'Could not stop the team.',
              ),
              onMention: _mention,
            ),
          ],
        ],
      ),
    );
  }
}

class _RoomHeader extends StatelessWidget {
  const _RoomHeader({required this.team, required this.working});

  final HermesTeam team;
  final bool working;

  @override
  Widget build(BuildContext context) {
    final palette = HermezChatPalette.forBrightness(
      Theme.of(context).brightness,
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 0, 18, 10),
      child: Row(
        children: [
          HermesTeamMarks(team: team, size: 36),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  team.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: HermezType.display(palette).copyWith(fontSize: 22),
                ),
                Text(
                  [
                    team.members.map((member) => member.label).join(', '),
                    if (working) 'working',
                  ].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: HermezType.meta(palette),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RoomLog extends StatelessWidget {
  const _RoomLog({
    required this.team,
    required this.timeline,
    required this.live,
    required this.initialKeys,
  });

  final HermesTeam team;
  final HermesTeamTimeline timeline;
  final Map<String, HermesTeamMemberLive> live;
  final Set<String> initialKeys;

  @override
  Widget build(BuildContext context) {
    final palette = HermezChatPalette.forBrightness(
      Theme.of(context).brightness,
    );
    final lines = timeline.lines;
    // A member whose session is visibly working gets a live card instead
    // of a bare "is thinking" row.
    final working = [
      for (final member in team.members)
        if (live[member.profile] case final state? when state.working)
          (member: member, state: state),
    ];
    final busy = {for (final entry in working) entry.member.memberId};
    final thinking = [
      for (final member in timeline.thinking)
        if (!busy.contains(member.memberId)) member,
    ];
    if (lines.isEmpty && thinking.isEmpty && working.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Align(
          alignment: Alignment.topLeft,
          child: Text(
            'Say what you want the team to work on. Every bot sees it, they '
            'reply in turn, and a bot can pass. Use @ to ask one bot.',
            style: HermezType.meta(palette),
          ),
        ),
      );
    }
    // Newest at the bottom, anchored there as the discussion grows.
    final count = working.length + lines.length + thinking.length;
    return ListView.builder(
      reverse: true,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      itemCount: count,
      itemBuilder: (context, index) {
        if (index < working.length) {
          final entry = working[working.length - 1 - index];
          return _Arrival(
            key: ValueKey('live-${entry.member.memberId}'),
            animate: true,
            child: _MemberLiveCard(member: entry.member, live: entry.state),
          );
        }
        index -= working.length;
        if (index < thinking.length) {
          final member = thinking[thinking.length - 1 - index];
          return _Arrival(
            key: ValueKey('thinking-${member.memberId}'),
            animate: true,
            child: _ThinkingRow(member: member),
          );
        }
        final line = lines[lines.length - 1 - (index - thinking.length)];
        return _Arrival(
          key: ValueKey(line.key),
          animate: !initialKeys.contains(line.key),
          child: switch (line.kind) {
            HermesTeamLineKind.user => _UserLine(line: line),
            HermesTeamLineKind.member => _MemberLine(line: line),
            HermesTeamLineKind.note ||
            HermesTeamLineKind.problem => _NoteLine(line: line),
          },
        );
      },
    );
  }
}

/// A new line slides out from under the one above it once; lines that were
/// there when the room opened stay still.
class _Arrival extends StatefulWidget {
  const _Arrival({super.key, required this.animate, required this.child});

  final bool animate;
  final Widget child;

  @override
  State<_Arrival> createState() => _ArrivalState();
}

class _ArrivalState extends State<_Arrival>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: HermezMotion.settleFor(HermezMotionWeight.medium),
    value: widget.animate ? 0 : 1,
  );
  late final Animation<double> _curve = CurvedAnimation(
    parent: _controller,
    curve: HermezMotion.curveMedium,
  );

  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Inherited settings are readable here, not in initState.
    if (_started || !widget.animate) return;
    _started = true;
    if (context.reduceMotion) {
      _controller.value = 1;
    } else {
      unawaited(_controller.forward());
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      HermezUnroll(animation: _curve, child: widget.child);
}

class _UserLine extends StatelessWidget {
  const _UserLine({required this.line});

  final HermesTeamLine line;

  @override
  Widget build(BuildContext context) {
    final palette = HermezChatPalette.forBrightness(
      Theme.of(context).brightness,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Align(
        alignment: AlignmentDirectional.centerEnd,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.sizeOf(context).width * 0.8,
          ),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: palette.userBubble,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: SelectableText(
                line.text,
                style: TextStyle(color: palette.onUserBubble, height: 1.35),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MemberLine extends StatelessWidget {
  const _MemberLine({required this.line});

  final HermesTeamLine line;

  @override
  Widget build(BuildContext context) {
    final palette = HermezChatPalette.forBrightness(
      Theme.of(context).brightness,
    );
    final member = line.member;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          HermezBotMark(
            identity: hermezIdentityForName(member?.profile),
            size: 30,
            label: member?.label,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  member?.label ?? 'Bot',
                  style: HermezType.section(palette).copyWith(fontSize: 14),
                ),
                const SizedBox(height: 3),
                SelectableText(
                  line.text,
                  style: TextStyle(color: palette.ink, height: 1.4),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _NoteLine extends StatelessWidget {
  const _NoteLine({required this.line});

  final HermesTeamLine line;

  @override
  Widget build(BuildContext context) {
    final palette = HermezChatPalette.forBrightness(
      Theme.of(context).brightness,
    );
    final problem = line.kind == HermesTeamLineKind.problem;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(child: Divider(color: palette.border)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.sizeOf(context).width * 0.7,
              ),
              child: Text(
                line.text,
                textAlign: TextAlign.center,
                style: HermezType.meta(palette)
                    .copyWith(color: problem ? palette.accent : palette.muted),
              ),
            ),
          ),
          Expanded(child: Divider(color: palette.border)),
        ],
      ),
    );
  }
}

class _ThinkingRow extends StatelessWidget {
  const _ThinkingRow({required this.member});

  final HermesTeamMember member;

  @override
  Widget build(BuildContext context) {
    final palette = HermezChatPalette.forBrightness(
      Theme.of(context).brightness,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          HermezBotMark(
            identity: hermezIdentityForName(member.profile),
            size: 30,
            label: member.label,
          ),
          const SizedBox(width: 10),
          Text('${member.label} is thinking', style: HermezType.meta(palette)),
          const SizedBox(width: 8),
          SizedBox.square(
            dimension: 12,
            child: CircularProgressIndicator(
              strokeWidth: 1.6,
              color: palette.accent,
            ),
          ),
        ],
      ),
    );
  }
}

/// One member at work in its own session: what it is doing now, the steps
/// it just took, its plan, what it is thinking, and its reply as it is
/// written. Tap for every step of this turn.
class _MemberLiveCard extends StatefulWidget {
  const _MemberLiveCard({required this.member, required this.live});

  final HermesTeamMember member;
  final HermesTeamMemberLive live;

  @override
  State<_MemberLiveCard> createState() => _MemberLiveCardState();
}

class _MemberLiveCardState extends State<_MemberLiveCard> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final palette = HermezChatPalette.forBrightness(
      Theme.of(context).brightness,
    );
    final live = widget.live;
    final rows = HermesActivityPresenter.rows(
      live.activity,
      running: live.working,
    );
    final now = HermesActivityPresenter.now(rows);
    final done = rows
        .where((row) => row.state != HermesActivityRowState.running)
        .toList();
    final recent = done.length > 2 ? done.sublist(done.length - 2) : done;
    final status = switch (live.status) {
      'waiting' => 'needs you',
      'starting' => 'starting',
      _ => 'working',
    };
    final todo = live.todo;
    // A model's interim words can arrive as both reasoning and reply: show
    // them once.
    String squash(String value) =>
        value.replaceAll(RegExp(r'\s+'), '').toLowerCase();
    final thinking = live.thinking;
    final preview = live.preview;
    final showThinking =
        thinking != null &&
        (preview == null ||
            !(squash(preview).contains(squash(thinking)) ||
                squash(thinking).contains(squash(preview))));
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          HermezBotMark(
            identity: hermezIdentityForName(widget.member.profile),
            size: 30,
            label: widget.member.label,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: HermezMotionSurface(
              weight: HermezMotionWeight.light,
              semanticsExpanded: _open,
              semanticLabel:
                  '${widget.member.label} is $status${now == null ? '' : ': $now'}',
              onTap: () => setState(() => _open = !_open),
              child: Container(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                decoration: BoxDecoration(
                  color: palette.surface,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: live.status == 'waiting'
                        ? palette.accent.withValues(alpha: 0.6)
                        : palette.border.withValues(alpha: 0.9),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            widget.member.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: HermezType.section(palette)
                                .copyWith(fontSize: 14),
                          ),
                        ),
                        const SizedBox(width: 6),
                        HermezLiveDot(
                          state: live.status == 'waiting'
                              ? HermezLiveState.attention
                              : HermezLiveState.working,
                          size: 6,
                        ),
                        const SizedBox(width: 2),
                        Text(status, style: HermezType.meta(palette)),
                        const Spacer(),
                        AnimatedRotation(
                          turns: _open ? 0.5 : 0,
                          duration: HermezMotion.settleFor(
                            HermezMotionWeight.light,
                          ),
                          curve: HermezMotion.curveLight,
                          child: Icon(
                            Icons.expand_more_rounded,
                            size: 18,
                            color: palette.muted,
                          ),
                        ),
                      ],
                    ),
                    if (todo != null && !todo.isEmpty) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Text(
                            'PLAN ${todo.completed}/${todo.total}',
                            style: HermezType.technical(palette.muted),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: HermezPlanBar(snapshot: todo, height: 3),
                          ),
                        ],
                      ),
                    ],
                    if (now != null) ...[
                      const SizedBox(height: 8),
                      HermezLiveText(
                        now,
                        style: HermezType.body(
                          palette,
                        ).copyWith(fontSize: 13.5, fontWeight: FontWeight.w700),
                      ),
                    ],
                    if (!_open)
                      for (final row in recent)
                        HermesActivityRowView(row: row, dense: true)
                    else if (rows.isNotEmpty)
                      HermesActivityList(rows: rows, visible: 40, dense: true),
                    if (showThinking) ...[
                      const SizedBox(height: 6),
                      Text(
                        thinking,
                        maxLines: _open ? 12 : 2,
                        overflow: TextOverflow.ellipsis,
                        style: HermezType.meta(palette)
                            .copyWith(fontStyle: FontStyle.italic),
                      ),
                    ],
                    if (live.preview != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        live.preview!,
                        maxLines: _open ? 8 : 3,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: palette.ink, height: 1.4),
                      ),
                    ],
                    if (now == null &&
                        recent.isEmpty &&
                        live.preview == null &&
                        live.thinking == null) ...[
                      const SizedBox(height: 6),
                      HermezLiveText(
                        'Thinking…',
                        style: HermezType.meta(palette),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ApprovalBar extends StatelessWidget {
  const _ApprovalBar({
    required this.approval,
    required this.member,
    required this.onAnswer,
  });

  final HermesTeamApproval approval;
  final HermesTeamMember? member;
  final ValueChanged<bool> onAnswer;

  @override
  Widget build(BuildContext context) {
    final palette = HermezChatPalette.forBrightness(
      Theme.of(context).brightness,
    );
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 6),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: palette.accent.withValues(alpha: 0.55)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '${member?.label ?? 'A bot'} needs your approval',
            style: HermezType.section(palette).copyWith(fontSize: 15),
          ),
          const SizedBox(height: 4),
          Text(
            approval.description,
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
            style: HermezType.meta(palette),
          ),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: Wrap(
              spacing: 4,
              children: [
                TextButton(
                  onPressed: () => onAnswer(false),
                  child: const Text('Deny'),
                ),
                TextButton(
                  onPressed: () => onAnswer(true),
                  child: const Text('Allow once'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _NoticeBar extends StatelessWidget {
  const _NoticeBar({
    required this.text,
    required this.action,
    required this.onAction,
  });

  final String text;
  final String action;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final palette = HermezChatPalette.forBrightness(
      Theme.of(context).brightness,
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 0, 10, 4),
      child: Row(
        children: [
          Expanded(child: Text(text, style: HermezType.meta(palette))),
          TextButton(onPressed: onAction, child: Text(action)),
        ],
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.team,
    required this.controller,
    required this.focus,
    required this.sending,
    required this.working,
    required this.onSend,
    required this.onStop,
    required this.onMention,
  });

  final HermesTeam team;
  final TextEditingController controller;
  final FocusNode focus;
  final bool sending;
  final bool working;
  final VoidCallback onSend;
  final VoidCallback onStop;
  final ValueChanged<HermesTeamMember> onMention;

  @override
  Widget build(BuildContext context) {
    final palette = HermezChatPalette.forBrightness(
      Theme.of(context).brightness,
    );
    // Clear the gesture bar. Android can report no bottom inset while the
    // bar is still drawn over the app, so keep at least a handle's height.
    // While the keyboard is up it covers the bar, so only the gap remains.
    final media = MediaQuery.of(context);
    final systemBottom = media.viewInsets.bottom > 0
        ? 0.0
        : math.max(media.viewPadding.bottom, 14.0);
    return Padding(
      padding: EdgeInsets.fromLTRB(12, 4, 12, 12 + systemBottom),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 36,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (final member in team.members)
                  Padding(
                    padding: const EdgeInsetsDirectional.only(end: 6),
                    child: HermezMotionSurface(
                      weight: HermezMotionWeight.light,
                      semanticLabel: 'Mention ${member.label}',
                      onTap: () => onMention(member),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: palette.canvas,
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: palette.border),
                        ),
                        child: Text(
                          '@${member.handle}',
                          style: TextStyle(
                            color: palette.ink,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          DecoratedBox(
            decoration: BoxDecoration(
              color: palette.surface,
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: palette.border),
            ),
            child: ConstrainedBox(
              // A roomy field: two lines at rest, growing to eight.
              constraints: const BoxConstraints(minHeight: 88),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(18, 14, 8, 14),
                      child: TextField(
                        controller: controller,
                        focusNode: focus,
                        minLines: 2,
                        maxLines: 8,
                        keyboardType: TextInputType.multiline,
                        textInputAction: TextInputAction.newline,
                        textCapitalization: TextCapitalization.sentences,
                        style: TextStyle(
                          color: palette.ink,
                          fontSize: 16,
                          height: 1.35,
                        ),
                        // The pill is the field's outline; the app theme's
                        // focused border must not draw a second one inside.
                        decoration: InputDecoration(
                          isCollapsed: true,
                          filled: false,
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          disabledBorder: InputBorder.none,
                          hintText: 'Message the team',
                          hintStyle: TextStyle(
                            color: palette.muted,
                            fontSize: 16,
                            height: 1.35,
                          ),
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(8),
                    child: ListenableBuilder(
                      listenable: controller,
                      builder: (context, _) {
                        final hasText = controller.text.trim().isNotEmpty;
                        final stop = working && !hasText;
                        return Tooltip(
                          message: stop ? 'Stop the team' : 'Send',
                          child: HermezMotionSurface(
                            weight: HermezMotionWeight.light,
                            semanticLabel: stop ? 'Stop the team' : 'Send',
                            enabled: !sending && (stop || hasText),
                            onTap: stop ? onStop : onSend,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: stop || hasText
                                    ? palette.accent
                                    : palette.canvas,
                                shape: BoxShape.circle,
                              ),
                              child: SizedBox.square(
                                dimension: 44,
                                child: Center(
                                  child: sending
                                      ? SizedBox.square(
                                          dimension: 16,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: palette.onAccent,
                                          ),
                                        )
                                      : HermezIconSwap(
                                          icon: stop
                                              ? Icons.stop_rounded
                                              : Icons.arrow_upward_rounded,
                                          color: stop || hasText
                                              ? palette.onAccent
                                              : palette.muted,
                                          size: 22,
                                        ),
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Home's Teams section: the latest teams, or an invitation to start one.
/// Hidden entirely when the Hermes server does not offer Group Chat.
class HermesTeamsSection extends ConsumerWidget {
  const HermesTeamsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = HermezChatPalette.forBrightness(
      Theme.of(context).brightness,
    );
    final teams = ref.watch(hermesTeamsProvider);
    if (teams.hasError) return const SizedBox.shrink();
    final list = teams.asData?.value;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      // The Teams block is one object: All teams grows it into the Teams
      // page, and Back returns it here.
      child: Builder(
        builder: (blockContext) => RepaintBoundary(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              HermezSectionBar(
                label: 'TEAMS  ${list?.length ?? '—'}',
                actionLabel: 'All teams',
                onAction: () => context.pushNamed(
                  RouteNames.hermesTeams,
                  extra: HermezMorphOrigin.of(
                    blockContext,
                    radius: 18,
                    color: palette.canvas,
                    snapshot: HermezMorphOrigin.capture(blockContext),
                  ),
                ),
              ),
              HermezSurface(
                kind: HermezSurfaceKind.list,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 2,
                ),
                child: list == null
                    ? const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: LinearProgressIndicator(),
                      )
                    : list.isEmpty
                    ? HermezMotionSurface(
                        weight: HermezMotionWeight.light,
                        semanticLabel: 'Start a team',
                        originRadius: 18,
                        originColor: palette.surface,
                        onOpen: (origin) =>
                            startHermesTeam(context, ref, origin),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Row(
                            children: [
                              Icon(
                                Icons.group_add_outlined,
                                color: palette.ink,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Start a team',
                                      style: HermezType.section(palette)
                                          .copyWith(fontSize: 15),
                                    ),
                                    Text(
                                      'Put 2 to 6 bots in one room to work '
                                      'something out together.',
                                      style: HermezType.meta(palette),
                                    ),
                                  ],
                                ),
                              ),
                              Icon(
                                Icons.chevron_right_rounded,
                                color: palette.muted,
                              ),
                            ],
                          ),
                        ),
                      )
                    : Column(
                        children: [
                          for (var i = 0; i < list.take(3).length; i++) ...[
                            if (i > 0)
                              Divider(
                                height: 1,
                                color: palette.border.withValues(alpha: 0.7),
                              ),
                            HermesTeamTile(
                              team: list[i],
                              onOpen: (origin) =>
                                  openHermesTeam(context, list[i], origin),
                            ),
                          ],
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The Team options tray: its actions, and Delete held open for one more
/// decision where it was asked for.
class _TeamOptions extends StatelessWidget {
  const _TeamOptions({
    required this.team,
    required this.confirmingDelete,
    required this.onAskDelete,
    required this.onKeep,
    required this.onDelete,
  });

  final HermesTeam team;
  final bool confirmingDelete;
  final VoidCallback onAskDelete;
  final VoidCallback onKeep;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final palette = HermezChatPalette.forBrightness(
      Theme.of(context).brightness,
    );
    final danger = Theme.of(context).colorScheme.error;
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 4, 18, 8),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: palette.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: palette.border),
        ),
        child: Material(
          type: MaterialType.transparency,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 2),
                child: Text(
                  'TEAM OPTIONS',
                  style: HermezType.technical(palette.muted),
                ),
              ),
              ListTile(
                leading: Icon(Icons.delete_outline_rounded, color: danger),
                title: Text('Delete team', style: TextStyle(color: danger)),
                onTap: onAskDelete,
              ),
              HermezReveal(
                visible: confirmingDelete,
                weight: HermezMotionWeight.medium,
                revealKey: const ValueKey('team-delete-guard'),
                child: Semantics(
                  container: true,
                  liveRegion: true,
                  label:
                      'Delete this team? ${team.name} and its discussion are '
                      'removed from Hermes.',
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
                            'DELETE THIS TEAM?',
                            style: HermezType.technical(danger),
                          ),
                        ),
                        const SizedBox(height: 4),
                        ExcludeSemantics(
                          child: Text(
                            '${team.name} and its discussion are removed '
                            'from Hermes. This cannot be undone. Your bots '
                            'are not affected.',
                            style: HermezType.meta(palette),
                          ),
                        ),
                        OverflowBar(
                          alignment: MainAxisAlignment.end,
                          spacing: 8,
                          children: [
                            TextButton(
                              style: TextButton.styleFrom(
                                minimumSize: const Size(64, 44),
                              ),
                              onPressed: onKeep,
                              child: const Text('Cancel'),
                            ),
                            FilledButton(
                              style: FilledButton.styleFrom(
                                backgroundColor: danger,
                                foregroundColor: Theme.of(context)
                                    .colorScheme
                                    .onError,
                                minimumSize: const Size(64, 44),
                              ),
                              onPressed: onDelete,
                              child: const Text('Delete'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
