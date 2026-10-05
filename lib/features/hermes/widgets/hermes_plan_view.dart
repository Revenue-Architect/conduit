import 'package:flutter/material.dart';

import '../models/hermes_todo.dart';
import '../motion/hermez_motion.dart';
import 'hermez_chat_palette.dart';
import 'hermez_live.dart';
import 'hermez_surfaces.dart';

/// "3 of 7", or "Plan paused · 3 of 7" when the run stopped with steps left.
String hermesPlanStatus(HermesTodoSnapshot plan, {required bool running}) {
  final count = '${plan.completed} of ${plan.total}';
  if (plan.isFinished) return 'Plan done · $count';
  if (!running && plan.hasActiveWork) return 'Plan paused · $count';
  return 'Plan · $count';
}

/// The plan at a glance inside the run surface: the progress bar and at most
/// three steps, the current one first. Tapping it opens the whole plan.
class HermesPlanPreview extends StatelessWidget {
  const HermesPlanPreview({
    super.key,
    required this.plan,
    required this.running,
    this.onOpen,
  });

  final HermesTodoSnapshot plan;
  final bool running;

  /// Opens the whole plan, growing out of this preview.
  final ValueChanged<HermezMorphOrigin?>? onOpen;

  @override
  Widget build(BuildContext context) {
    final palette = HermezChatPalette.forBrightness(
      Theme.of(context).brightness,
    );
    final preview = plan.preview();
    final current = plan.current;
    final paused = !running && plan.hasActiveWork;
    return HermezMotionSurface(
      weight: HermezMotionWeight.light,
      semanticLabel: '${hermesPlanStatus(plan, running: running)}. Open plan',
      originRadius: 14,
      onOpen: onOpen,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Flexible(
                  child: Text(
                    paused
                        ? 'PLAN PAUSED'
                        : plan.isFinished
                        ? 'PLAN DONE'
                        : 'PLAN',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: HermezType.technical(
                      paused ? palette.accent : palette.muted,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                HermezRollingCount(
                  value: '${plan.completed}',
                  style: HermezType.technical(palette.ink),
                ),
                Text(
                  ' OF ${plan.total}',
                  style: HermezType.technical(palette.ink),
                ),
                const Spacer(),
                if (onOpen != null)
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 18,
                    color: palette.muted,
                  ),
              ],
            ),
            const SizedBox(height: 8),
            HermezPlanBar(snapshot: plan, paused: paused),
            const SizedBox(height: 6),
            for (final item in preview)
              HermesPlanRow(
                key: ValueKey('plan-preview-${item.id}'),
                item: item,
                live:
                    running &&
                    item.id == current?.id &&
                    item.status == HermesTodoStatus.inProgress,
                dense: true,
              ),
          ],
        ),
      ),
    );
  }
}

/// One step: its glyph and its words. A finished step steps back; the step
/// being worked on shimmers while the run is live.
class HermesPlanRow extends StatelessWidget {
  const HermesPlanRow({
    super.key,
    required this.item,
    this.depth = 0,
    this.live = false,
    this.dense = false,
    this.selected = false,
    this.onTap,
  });

  final HermesTodoItem item;
  final int depth;
  final bool live;
  final bool dense;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = HermezChatPalette.forBrightness(
      Theme.of(context).brightness,
    );
    final finished =
        item.status == HermesTodoStatus.completed ||
        item.status == HermesTodoStatus.cancelled;
    final style = HermezType.body(palette).copyWith(
      fontSize: dense ? 13.5 : 15,
      height: 1.32,
      color: finished ? palette.muted : palette.ink,
      fontWeight: item.status == HermesTodoStatus.inProgress
          ? FontWeight.w700
          : FontWeight.w500,
      decoration: item.status == HermesTodoStatus.cancelled
          ? TextDecoration.lineThrough
          : null,
      decorationColor: palette.muted,
    );
    final text = live
        ? HermezLiveText(item.content, style: style, maxLines: dense ? 1 : 4)
        : Text(
            item.content,
            maxLines: dense ? 1 : null,
            overflow: dense ? TextOverflow.ellipsis : null,
            style: style,
          );
    final label = switch (item.status) {
      HermesTodoStatus.pending => 'To do',
      HermesTodoStatus.inProgress => 'In progress',
      HermesTodoStatus.completed => 'Done',
      HermesTodoStatus.cancelled => 'Cancelled',
    };
    final row = Padding(
      padding: EdgeInsetsDirectional.only(
        start: depth * 20.0,
        top: dense ? 5 : 9,
        bottom: dense ? 5 : 9,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.only(top: dense ? 0.5 : 1.5),
            child: HermezTodoGlyph(status: item.status, size: dense ? 16 : 18),
          ),
          SizedBox(width: dense ? 10 : 12),
          Expanded(child: text),
        ],
      ),
    );
    return Semantics(
      label: '$label: ${item.content}',
      selected: selected,
      button: onTap != null,
      excludeSemantics: true,
      child: onTap == null
          ? row
          : HermezMotionSurface(
              weight: HermezMotionWeight.light,
              onTap: onTap,
              child: AnimatedContainer(
                duration: HermezMotion.settleFor(HermezMotionWeight.light),
                curve: HermezMotion.curveLight,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  color: selected
                      ? palette.ink.withValues(alpha: 0.05)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: row,
              ),
            ),
    );
  }
}
