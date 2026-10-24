import 'package:flutter/material.dart';

import '../../../core/models/chat_message.dart';
import '../../../shared/theme/theme_extensions.dart';
import '../models/hermes_subagent.dart';
import '../motion/hermez_motion.dart';
import 'hermes_delegated_worker_card.dart';
import 'hermez_bot_mark.dart';
import 'hermez_chat_palette.dart';
import 'hermez_live.dart';
import 'hermez_surfaces.dart';

/// Delegated work as part of the conversation: each worker is a branch that
/// hangs off the turn on a thin rail, not a card of its own. One worker is
/// just its branch; several share one line with their avatars and a progress
/// bar that only counts what Hermes reported finished. Identity includes the
/// turn, so expansions survive row recycling and child-route navigation.
class HermesInlineDelegation extends StatefulWidget {
  const HermesInlineDelegation({
    super.key,
    required this.workers,
    required this.parentSessionId,
    required this.parentLabel,
    required this.turnKey,
    this.onLayoutChanged,
    this.loadConversation,
    this.onOpenSession,
    this.loadArtifact,
  });
  final List<HermesSubagentState> workers;
  final String parentSessionId, parentLabel, turnKey;
  final VoidCallback? onLayoutChanged;
  final Future<List<ChatMessage>> Function(HermesSubagentState)?
  loadConversation;
  final Future<void> Function(HermesSubagentState, HermezMorphOrigin?)?
  onOpenSession;
  final Future<String> Function(HermesSubagentState, int)? loadArtifact;
  @override
  State<HermesInlineDelegation> createState() => _InlineState();
}

class _InlineState extends State<HermesInlineDelegation> {
  final Set<String> _expanded = {};
  bool _open = false, _restored = false;
  String get _storage =>
      'delegation:${widget.parentSessionId}:${widget.turnKey}';
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_restored) return;
    _restored = true;
    final stored = PageStorage.maybeOf(context)
        ?.readState(context, identifier: _storage);
    if (stored is Map) {
      _open = stored['open'] == true;
      _expanded.addAll(
        (stored['workers'] as List?)?.whereType<String>() ?? const [],
      );
    }
  }

  void _change(VoidCallback action) {
    widget.onLayoutChanged?.call();
    setState(action);
    PageStorage.maybeOf(context)?.writeState(context, {
      'open': _open,
      'workers': _expanded.toList(),
    }, identifier: _storage);
  }

  Widget _branch(HermesSubagentState worker) => HermesDelegatedWorkerCard(
    key: PageStorageKey('$_storage:${worker.id}'),
    worker: worker,
    parentSessionId: widget.parentSessionId,
    parentLabel: widget.parentLabel,
    branch: true,
    expanded: _expanded.contains(worker.id),
    onToggle: () => _change(() {
      if (!_expanded.add(worker.id)) _expanded.remove(worker.id);
    }),
    onLayoutChanged: widget.onLayoutChanged,
    loadConversation: widget.loadConversation,
    onOpenSession: widget.onOpenSession,
    loadArtifact: widget.loadArtifact,
  );

  @override
  Widget build(BuildContext context) {
    final workers = widget.workers;
    if (workers.isEmpty) return const SizedBox.shrink();
    final p = HermezChatPalette.forBrightness(Theme.of(context).brightness);
    if (workers.length == 1) {
      return _ThreadRail(
        color: p.accent,
        last: true,
        child: _branch(workers.single),
      );
    }
    final working = workers.live;
    final finished = workers.where((w) => w.status.isTerminal).length;
    final problems = workers.problems;
    final summary = [
      '${workers.length} agents',
      if (working > 0) '$working working',
      if (working == 0 && problems == 0) 'all replied',
      if (problems > 0) '$problems failed',
    ].join(' · ');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ThreadRail(
          color: p.accent,
          last: !_open,
          child: HermezMotionSurface(
            key: const ValueKey('delegation-group'),
            weight: HermezMotionWeight.light,
            semanticLabel:
                '$summary. $finished of ${workers.length} finished. ${_open ? 'Collapse' : 'Expand'}',
            semanticsExpanded: _open,
            onTap: () => _change(() => _open = !_open),
            originRadius: 12,
            originColor: p.canvas,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 48),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    _AvatarStack(workers: workers),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            children: [
                              if (working > 0) ...[
                                const HermezLiveDot(
                                  state: HermezLiveState.working,
                                  size: 6,
                                ),
                                const SizedBox(width: 5),
                              ],
                              Flexible(
                                child: Text(
                                  summary,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: HermezType.meta(p).copyWith(
                                    color: p.ink,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13.5,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                '$finished of ${workers.length}',
                                style: HermezType.meta(p).copyWith(
                                  fontFeatures: const [
                                    FontFeature.tabularFigures(),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 7),
                          HermesDelegationProgress(
                            value: finished / workers.length,
                            problem: problems > 0,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 4),
                    AnimatedRotation(
                      turns: _open ? 0.25 : 0,
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeOutCubic,
                      child: Icon(
                        Icons.chevron_right_rounded,
                        color: p.accent,
                        size: 20,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        HermezReveal(
          visible: _open,
          revealKey: ValueKey(_storage),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < workers.length; i++)
                _ThreadRail(
                  color: p.accent,
                  last: i == workers.length - 1,
                  child: _branch(workers[i]),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// How much of a delegation batch has finished, as Hermes reported it. A thin
/// track with the accent filling it; it moves only when a worker finishes.
class HermesDelegationProgress extends StatelessWidget {
  const HermesDelegationProgress({
    super.key,
    required this.value,
    this.problem = false,
  });

  final double value;
  final bool problem;

  @override
  Widget build(BuildContext context) {
    final p = HermezChatPalette.forBrightness(Theme.of(context).brightness);
    final fill = problem ? Theme.of(context).colorScheme.error : p.accent;
    return Semantics(
      value: '${(value * 100).round()}%',
      child: TweenAnimationBuilder<double>(
        tween: Tween(end: value.clamp(0.0, 1.0)),
        duration: context.reduceMotion
            ? Duration.zero
            : const Duration(milliseconds: 520),
        curve: Curves.easeOutCubic,
        builder: (context, v, _) => ClipRRect(
          borderRadius: BorderRadius.circular(2),
          child: SizedBox(
            height: 3,
            child: Stack(
              children: [
                Positioned.fill(
                  child: ColoredBox(color: p.border.withValues(alpha: 0.6)),
                ),
                FractionallySizedBox(
                  widthFactor: v,
                  heightFactor: 1,
                  child: ColoredBox(color: fill),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Up to three worker avatars, overlapping.
class _AvatarStack extends StatelessWidget {
  const _AvatarStack({required this.workers});

  final List<HermesSubagentState> workers;

  @override
  Widget build(BuildContext context) {
    final p = HermezChatPalette.forBrightness(Theme.of(context).brightness);
    final shown = workers.take(3).toList(growable: false);
    const size = 22.0, overlap = 9.0;
    return SizedBox(
      width: size + (shown.length - 1) * (size - overlap),
      height: size,
      child: Stack(
        children: [
          for (var i = shown.length - 1; i >= 0; i--)
            Positioned(
              left: i * (size - overlap),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: p.canvas, width: 1.5),
                ),
                child: HermezBotMark(
                  botName: shown[i].displayName,
                  identity: hermezIdentityForName(shown[i].displayName),
                  size: size - 3,
                  label: shown[i].displayName,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The thread line a branch hangs from: down from the turn above, then an
/// elbow into the branch's avatar. It continues past a branch that has
/// siblings below it. A thin connector in a light wash of the accent.
class _ThreadRail extends StatelessWidget {
  const _ThreadRail({
    required this.color,
    required this.last,
    required this.child,
  });

  final Color color;
  final bool last;
  final Widget child;

  static const double indent = 22;

  @override
  Widget build(BuildContext context) => CustomPaint(
    painter: _RailPainter(color: color.withValues(alpha: 0.45), last: last),
    child: Padding(
      padding: const EdgeInsets.only(left: indent),
      child: child,
    ),
  );
}

class _RailPainter extends CustomPainter {
  const _RailPainter({required this.color, required this.last});

  final Color color;
  final bool last;

  // The elbow meets the branch's avatar centre (its header is 48dp tall).
  static const double _x = 7, _elbowY = 30, _radius = 8;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    final path = Path()
      ..moveTo(_x, 0)
      ..lineTo(_x, _elbowY - _radius)
      ..quadraticBezierTo(_x, _elbowY, _x + _radius, _elbowY)
      ..lineTo(_ThreadRail.indent - 3, _elbowY);
    canvas.drawPath(path, paint);
    if (!last) canvas.drawLine(Offset(_x, 0), Offset(_x, size.height), paint);
  }

  @override
  bool shouldRepaint(_RailPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.last != last;
}
