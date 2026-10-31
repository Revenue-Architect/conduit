import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/services/navigation_service.dart';
import '../models/hermes_bot.dart';
import '../models/hermes_job.dart';
import '../models/hermes_session.dart';
import '../motion/hermez_card_morph.dart';
import '../motion/hermez_card_route.dart';
import '../providers/hermes_providers.dart';
import '../services/hermes_desktop_api_service.dart';
import '../utils/hermes_schedule_format.dart';
import '../widgets/hermes_session_tile.dart' show openHermesSession;
import '../widgets/hermez_bot_mark.dart';
import '../widgets/hermez_chat_palette.dart';
import 'hermes_scheduled_agent_sheet.dart';

/// Scheduled as a card (docs/app-design-2026-10-30, m13): it grows out of
/// Today's Scheduled link and lists every bot's routines with where each
/// stands. A routine opens in the same card, and "Schedule something"
/// reshapes it into New routine (m14), which saves paused.
Future<void> showHermesScheduledCard(
  BuildContext context,
  WidgetRef ref,
) async {
  final exit = await pushHermezFullCard<Object>(
    context,
    semanticLabel: 'Scheduled',
    builder: (_) => const HermesScheduledCard(),
  );
  if (!context.mounted || exit == null) return;
  if (exit is HermesSessionSummary) {
    await openHermesSession(context, ref, exit);
  } else if (exit == _openPage) {
    await context.pushNamed<void>(RouteNames.hermesJobs);
  }
}

const _openPage = 'page';

enum _ScheduledView { list, routine, create }

/// The routine's standing, in the order the card sorts by.
enum _Standing {
  failed('Failed'),
  running('Running'),
  on('On'),
  paused('Paused');

  const _Standing(this.label);
  final String label;

  static _Standing of(HermesJob job) {
    if (job.isFailing) return failed;
    if (job.state == 'running') return running;
    return job.enabled ? on : paused;
  }
}

@visibleForTesting
class HermesScheduledCard extends ConsumerStatefulWidget {
  const HermesScheduledCard({super.key});

  @override
  ConsumerState<HermesScheduledCard> createState() =>
      _HermesScheduledCardState();
}

class _HermesScheduledCardState extends ConsumerState<HermesScheduledCard> {
  _ScheduledView _view = _ScheduledView.list;
  (String, HermesJob)? _open;

  void _show(_ScheduledView view, [(String, HermesJob)? open]) => setState(() {
    _view = view;
    _open = open;
  });

  @override
  Widget build(BuildContext context) {
    final open = _open;
    final Widget body = switch (_view) {
      _ScheduledView.routine when open != null => HermesScheduledAgentView(
        key: ValueKey('routine:${open.$2.id}'),
        job: open.$2,
        profile: open.$1,
        onBack: () => _show(_ScheduledView.list),
      ),
      _ScheduledView.create => _NewRoutine(
        key: const ValueKey('create'),
        onBack: () => _show(_ScheduledView.list),
        onSaved: () {
          ref.invalidate(hermesHomeProfileJobsProvider);
          ref.invalidate(hermesJobsProvider);
          _show(_ScheduledView.list);
        },
      ),
      _ => _list(context),
    };
    // The pressed row grows into the next step and the card springs to
    // its height; back folds the step into the row it came from.
    return HermezCardMorph(
      depth: _view == _ScheduledView.list ? 0 : 1,
      // Forms stay put: the keyboard already reshapes the card for them.
      raised: _view == _ScheduledView.routine,
      child: body,
    );
  }

  Widget _list(BuildContext context) {
    final palette = HermezChatPalette.forBrightness(
      Theme.of(context).brightness,
    );
    final all = ref.watch(hermesHomeProfileJobsProvider);
    final bots = {
      for (final bot in ref.watch(hermesBotsProvider).value ?? const [])
        bot.name: bot,
    };
    final entries = [...?all.value]
      ..sort((a, b) {
        final byStanding = _Standing.of(a.$2).index
            .compareTo(_Standing.of(b.$2).index);
        return byStanding != 0
            ? byStanding
            : a.$2.displayName.compareTo(b.$2.displayName);
      });
    final counts = {
      for (final s in _Standing.values)
        s: entries.where((e) => _Standing.of(e.$2) == s).length,
    };
    final summary = [
      '${counts[_Standing.on]! + counts[_Standing.running]!} on',
      if (counts[_Standing.failed]! > 0) '${counts[_Standing.failed]} failed',
      if (counts[_Standing.paused]! > 0) '${counts[_Standing.paused]} paused',
    ].join(' · ');
    return Column(
      key: const ValueKey('list'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: Container(
            margin: const EdgeInsets.only(top: 8, bottom: 2),
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: palette.border,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 6, 10, 0),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Scheduled',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.3,
                    color: palette.ink,
                  ),
                ),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, _openPage),
                child: const Text('All'),
              ),
              IconButton(
                tooltip: 'Close',
                onPressed: () => Navigator.pop(context),
                icon: Icon(Icons.close_rounded, color: palette.ink),
              ),
            ],
          ),
        ),
        if (all.hasValue)
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 0, 22, 8),
            child: Text(
              summary,
              style: TextStyle(fontSize: 13, color: palette.muted),
            ),
          ),
        Expanded(
          child: all.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (_, _) => Center(
              child: TextButton(
                onPressed: () => ref.invalidate(hermesHomeProfileJobsProvider),
                child: const Text('Couldn’t load routines. Retry'),
              ),
            ),
            data: (_) => ListView(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              children: [
                for (final entry in entries)
                  _RoutineRow(
                    job: entry.$2,
                    bot: bots[entry.$1],
                    profile: entry.$1,
                    palette: palette,
                    onOpen: () => _show(_ScheduledView.routine, entry),
                  ),
                const Divider(height: 17, indent: 14, endIndent: 14),
                ListTile(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                  leading: CircleAvatar(
                    backgroundColor: palette.canvas,
                    child: Icon(Icons.add_rounded, color: palette.ink),
                  ),
                  title: const Text('Schedule something'),
                  subtitle: const Text('New routines start paused'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => _show(_ScheduledView.create),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _RoutineRow extends StatelessWidget {
  const _RoutineRow({
    required this.job,
    required this.bot,
    required this.profile,
    required this.palette,
    required this.onOpen,
  });

  final HermesJob job;
  final HermesBot? bot;
  final String profile;
  final HermezChatPalette palette;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final bot = this.bot;
    final standing = _Standing.of(job);
    final who = bot?.title ?? profile;
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
                            Icons.schedule_rounded,
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
                      job.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        color: palette.ink,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${describeHermesCronSchedule(job.schedule)} · $who',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: palette.muted),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _StandingPill(standing: standing, palette: palette),
            ],
          ),
        ),
      ),
    );
  }
}

class _StandingPill extends StatelessWidget {
  const _StandingPill({required this.standing, required this.palette});

  final _Standing standing;
  final HermezChatPalette palette;

  @override
  Widget build(BuildContext context) {
    final label = Text(
      standing.label,
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: switch (standing) {
          _Standing.failed => palette.failed,
          _Standing.running => palette.liveText,
          _ => palette.ink,
        },
      ),
    );
    if (standing == _Standing.running) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: palette.live,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          label,
        ],
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: standing == _Standing.on ? palette.canvas : null,
        borderRadius: BorderRadius.circular(999),
        border: standing == _Standing.on
            ? null
            : Border.all(
                color: standing == _Standing.failed
                    ? palette.failed
                    : palette.border,
              ),
      ),
      child: label,
    );
  }
}

/// When a routine runs: the common choices, or the owner's own schedule.
const _whens = <(String, String)>[
  ('Every hour', '0 * * * *'),
  ('Daily 8:00', '0 8 * * *'),
  ('Weekdays 8:00', '0 8 * * 1-5'),
  ('Mondays 9:00', '0 9 * * 1'),
];

/// The tools a routine may use, as Hermes names its toolsets.
const _tools = <(String, String)>[
  ('Web', 'web'),
  ('Browser', 'browser'),
  ('Files', 'file'),
  ('Terminal', 'terminal'),
];

/// New routine (m14), in the same card: what, who, when and which tools.
/// It saves paused; nothing runs until the owner turns it on.
class _NewRoutine extends ConsumerStatefulWidget {
  const _NewRoutine({super.key, required this.onBack, required this.onSaved});

  final VoidCallback onBack;
  final VoidCallback onSaved;

  @override
  ConsumerState<_NewRoutine> createState() => _NewRoutineState();
}

class _NewRoutineState extends ConsumerState<_NewRoutine> {
  final _what = TextEditingController();
  final _custom = TextEditingController();
  final _whatFocus = FocusNode();
  String? _who;
  String _when = _whens[2].$2;
  bool _customWhen = false;
  final _toolsets = <String>{};
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // The keyboard comes up once the form has landed.
    Future<void>.delayed(kHermezCardMorphDuration, () {
      if (mounted) _whatFocus.requestFocus();
    });
  }

  @override
  void dispose() {
    _whatFocus.dispose();
    _what.dispose();
    _custom.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final what = _what.text.trim();
    final schedule = _customWhen ? _custom.text.trim() : _when;
    if (what.isEmpty || schedule.isEmpty) {
      setState(() => _error = what.isEmpty ? 'Say what to do.' : 'Say when.');
      return;
    }
    final service = ref.read(hermesApiServiceProvider);
    if (service is! HermesDesktopApiService) {
      setState(() => _error = 'Routines need the Hermes desktop gateway.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final words = what.split(RegExp(r'\s+'));
      await service.createRoutine(
        name: words.take(6).join(' '),
        prompt: what,
        schedule: schedule,
        profile: _who,
        enabledToolsets: _toolsets.isEmpty ? null : _toolsets.toList(),
      );
      if (mounted) widget.onSaved();
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = 'Couldn’t save the routine. Check the schedule and retry.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = HermezChatPalette.forBrightness(
      Theme.of(context).brightness,
    );
    final bots = ref.watch(hermesBotsProvider).value ?? const <HermesBot>[];
    Widget label(String text) => Padding(
      padding: const EdgeInsets.only(top: 18, bottom: 6),
      child: Text(text, style: TextStyle(fontSize: 12, color: palette.muted)),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 12, 10, 4),
          child: Row(
            children: [
              IconButton(
                tooltip: 'Back',
                onPressed: _saving ? null : widget.onBack,
                icon: Icon(Icons.chevron_left_rounded, color: palette.ink),
              ),
              Expanded(
                child: Text(
                  'New routine',
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
                controller: _what,
                focusNode: _whatFocus,
                enabled: !_saving,
                minLines: 1,
                maxLines: 4,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(labelText: 'What'),
              ),
              label('Who'),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final bot in bots)
                    ChoiceChip(
                      label: Text(bot.title),
                      selected: _who == bot.name,
                      showCheckmark: false,
                      onSelected: _saving
                          ? null
                          : (_) => setState(() => _who = bot.name),
                    ),
                ],
              ),
              label('When'),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final (name, cron) in _whens)
                    ChoiceChip(
                      label: Text(name),
                      selected: !_customWhen && _when == cron,
                      showCheckmark: false,
                      onSelected: _saving
                          ? null
                          : (_) => setState(() {
                              _when = cron;
                              _customWhen = false;
                            }),
                    ),
                  ChoiceChip(
                    label: const Text('Other'),
                    selected: _customWhen,
                    showCheckmark: false,
                    onSelected: _saving
                        ? null
                        : (_) => setState(() => _customWhen = true),
                  ),
                ],
              ),
              if (_customWhen)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: TextField(
                    controller: _custom,
                    enabled: !_saving,
                    decoration: const InputDecoration(
                      labelText: 'Schedule',
                      hintText: 'e.g. 30 7 * * * or every 2h',
                    ),
                  ),
                ),
              label(_who == null ? 'Tools it may use' : 'Tools $_who may use'),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final (name, toolset) in _tools)
                    FilterChip(
                      label: Text(name),
                      selected: _toolsets.contains(toolset),
                      onSelected: _saving
                          ? null
                          : (on) => setState(
                              () => on
                                  ? _toolsets.add(toolset)
                                  : _toolsets.remove(toolset),
                            ),
                    ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(
                  'None ticked keeps the bot’s usual tools. It starts paused '
                  'until you turn it on.',
                  style: TextStyle(fontSize: 13, color: palette.muted),
                ),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(
                    _error!,
                    style: TextStyle(fontSize: 13, color: palette.failed),
                  ),
                ),
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
            child: Text(_saving ? 'Saving…' : 'Save, paused'),
          ),
        ),
      ],
    );
  }
}
