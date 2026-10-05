import 'package:flutter/material.dart';

import '../../../shared/theme/theme_extensions.dart';
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
/// The line joining one plan step to the next in an outline.
enum HermesPlanRail {
  /// Not reached yet: a faint line.
  pending,

  /// The step before it finished: the line draws itself down.
  done,

  /// The step before it was cancelled: the trail stops, dashed.
  stopped,
}

/// Which line joins [from] to the step right after it, at the same depth.
HermesPlanRail? hermesPlanRailBetween(HermesTodoRow from, HermesTodoRow? to) {
  if (to == null || to.depth != from.depth) return null;
  return switch (from.item.status) {
    HermesTodoStatus.completed => HermesPlanRail.done,
    HermesTodoStatus.cancelled => HermesPlanRail.stopped,
    _ => HermesPlanRail.pending,
  };
}

class HermesPlanRow extends StatelessWidget {
  const HermesPlanRow({
    super.key,
    required this.item,
    this.depth = 0,
    this.live = false,
    this.dense = false,
    this.selected = false,
    this.onTap,
    this.railAbove,
    this.railBelow,
  });

  final HermesTodoItem item;
  final int depth;
  final bool live;
  final bool dense;
  final bool selected;
  final VoidCallback? onTap;

  /// The line from the previous step down to this one's mark, and from
  /// this one's mark down to the next (a timeline in the plan sheet).
  final HermesPlanRail? railAbove;
  final HermesPlanRail? railBelow;

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
    final glyphSize = dense ? 16.0 : 18.0;
    final padTop = dense ? 5.0 : 9.0;
    final glyphTop = padTop + (dense ? 0.5 : 1.5);
    final railX = depth * 20.0 + glyphSize / 2 - 1;
    final content = Padding(
      padding: EdgeInsetsDirectional.only(
        start: depth * 20.0,
        top: padTop,
        bottom: dense ? 5 : 9,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.only(top: dense ? 0.5 : 1.5),
            child: HermezTodoGlyph(status: item.status, size: glyphSize),
          ),
          SizedBox(width: dense ? 10 : 12),
          Expanded(child: text),
        ],
      ),
    );
    final row = railAbove == null && railBelow == null
        ? content
        : Stack(
            children: [
              content,
              if (railAbove case final rail?)
                PositionedDirectional(
                  start: railX,
                  top: 0,
                  height: glyphTop - 3,
                  width: 2,
                  child: _PlanRailLine(rail: rail),
                ),
              if (railBelow case final rail?)
                PositionedDirectional(
                  start: railX,
                  top: glyphTop + glyphSize + 3,
                  bottom: 0,
                  width: 2,
                  child: _PlanRailLine(rail: rail),
                ),
            ],
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

/// One stretch of the plan timeline. A finished step's line draws itself
/// down (a stroke, not a fade); a cancelled step's trail stops, dashed.
/// Adapted from SwiftPieces' Status Timeline.
class _PlanRailLine extends StatefulWidget {
  const _PlanRailLine({required this.rail});

  final HermesPlanRail rail;

  @override
  State<_PlanRailLine> createState() => _PlanRailLineState();
}

class _PlanRailLineState extends State<_PlanRailLine>
    with SingleTickerProviderStateMixin {
  late final AnimationController _draw = AnimationController(
    vsync: this,
    duration: HermezMotion.settleFor(HermezMotionWeight.medium),
    // A line that is already drawn when it appears is not news.
    value: 1,
  );

  @override
  void didUpdateWidget(covariant _PlanRailLine oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.rail == HermesPlanRail.done &&
        oldWidget.rail != HermesPlanRail.done) {
      if (context.reduceMotion) {
        _draw.value = 1;
      } else {
        _draw.forward(from: 0);
      }
    }
  }

  @override
  void dispose() {
    _draw.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = HermezChatPalette.forBrightness(
      Theme.of(context).brightness,
    );
    return AnimatedBuilder(
      animation: _draw,
      builder: (context, _) => CustomPaint(
        painter: _PlanRailPainter(
          rail: widget.rail,
          drawn: HermezMotion.curveMedium.transform(_draw.value),
          faint: palette.ink.withValues(alpha: 0.13),
          solid: palette.ink.withValues(alpha: 0.5),
        ),
      ),
    );
  }
}

class _PlanRailPainter extends CustomPainter {
  const _PlanRailPainter({
    required this.rail,
    required this.drawn,
    required this.faint,
    required this.solid,
  });

  final HermesPlanRail rail;
  final double drawn;
  final Color faint;
  final Color solid;

  @override
  void paint(Canvas canvas, Size size) {
    final x = size.width / 2;
    final line = Paint()
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    switch (rail) {
      case HermesPlanRail.pending:
        canvas.drawLine(
          Offset(x, 0),
          Offset(x, size.height),
          line..color = faint,
        );
      case HermesPlanRail.done:
        // The faint line underneath; the solid one drawing down over it.
        canvas.drawLine(
          Offset(x, 0),
          Offset(x, size.height),
          line..color = faint,
        );
        canvas.drawLine(
          Offset(x, 0),
          Offset(x, size.height * drawn),
          Paint()
            ..strokeWidth = 2
            ..strokeCap = StrokeCap.round
            ..color = solid,
        );
      case HermesPlanRail.stopped:
        line.color = faint;
        for (var y = 0.0; y < size.height; y += 7) {
          canvas.drawLine(
            Offset(x, y),
            Offset(x, (y + 2.5).clamp(0, size.height)),
            line,
          );
        }
    }
  }

  @override
  bool shouldRepaint(_PlanRailPainter old) =>
      old.rail != rail ||
      old.drawn != drawn ||
      old.faint != faint ||
      old.solid != solid;
}
