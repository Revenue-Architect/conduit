import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/services/navigation_service.dart';
import '../motion/hermez_motion.dart';
import '../services/hermes_activity_presenter.dart';
import 'hermez_chat_palette.dart';
import 'hermez_live.dart';
import 'hermez_surfaces.dart';

IconData hermesActivityIcon(HermesActivityFamily family) => switch (family) {
  HermesActivityFamily.command => Icons.terminal_rounded,
  HermesActivityFamily.code => Icons.data_object_rounded,
  HermesActivityFamily.file => Icons.description_outlined,
  HermesActivityFamily.search => Icons.search_rounded,
  HermesActivityFamily.web => Icons.language_rounded,
  HermesActivityFamily.browser => Icons.travel_explore_rounded,
  HermesActivityFamily.plan => Icons.checklist_rounded,
  HermesActivityFamily.delegate => Icons.call_split_rounded,
  HermesActivityFamily.page => Icons.article_outlined,
  HermesActivityFamily.memory => Icons.bookmark_outline_rounded,
  HermesActivityFamily.ask => Icons.help_outline_rounded,
  HermesActivityFamily.image => Icons.image_outlined,
  HermesActivityFamily.schedule => Icons.schedule_rounded,
  HermesActivityFamily.message => Icons.send_rounded,
  HermesActivityFamily.tools => Icons.extension_outlined,
  HermesActivityFamily.review => Icons.rate_review_outlined,
  HermesActivityFamily.other => Icons.bolt_rounded,
};

/// A run's activity in words. The newest [visible] rows show; earlier ones
/// fold into "+N earlier" and open in place.
class HermesActivityList extends StatefulWidget {
  const HermesActivityList({
    super.key,
    required this.rows,
    this.visible = 5,
    this.onInspect,
    this.dense = false,
  });

  final List<HermesActivityRow> rows;
  final int visible;

  /// Opens a row's step up close, growing out of the row.
  final void Function(HermesActivityRow row, HermezMorphOrigin? origin)?
  onInspect;
  final bool dense;

  @override
  State<HermesActivityList> createState() => _HermesActivityListState();
}

class _HermesActivityListState extends State<HermesActivityList> {
  bool _all = false;

  @override
  Widget build(BuildContext context) {
    final palette = HermezChatPalette.forBrightness(
      Theme.of(context).brightness,
    );
    final recent = _all
        ? (rows: widget.rows, earlier: 0)
        : HermesActivityPresenter.recent(widget.rows, visible: widget.visible);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        HermezReveal(
          visible: recent.earlier > 0,
          revealKey: const ValueKey('activity-earlier'),
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: HermezMotionSurface(
              weight: HermezMotionWeight.light,
              semanticLabel: 'Show ${recent.earlier} earlier steps',
              onTap: () => setState(() => _all = true),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.unfold_more_rounded,
                      size: 16,
                      color: palette.muted,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '+${recent.earlier} earlier',
                      style: HermezType.meta(palette).copyWith(
                        fontWeight: FontWeight.w700,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        for (final row in recent.rows)
          HermesActivityRowView(
            key: ValueKey('activity-${row.key}'),
            row: row,
            dense: widget.dense,
            onOpen: row.inspectable && widget.onInspect != null
                ? (origin) => widget.onInspect!(row, origin)
                : null,
          ),
      ],
    );
  }
}

class HermesActivityRowView extends StatelessWidget {
  const HermesActivityRowView({
    super.key,
    required this.row,
    this.onOpen,
    this.dense = false,
  });

  final HermesActivityRow row;
  final ValueChanged<HermezMorphOrigin?>? onOpen;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final palette = HermezChatPalette.forBrightness(
      Theme.of(context).brightness,
    );
    final running = row.state == HermesActivityRowState.running;
    final failed = row.state == HermesActivityRowState.failed;
    final waiting = row.state == HermesActivityRowState.waiting;
    final verbStyle = HermezType.body(palette).copyWith(
      fontSize: dense ? 13.5 : 14,
      fontWeight: FontWeight.w700,
      height: 1.25,
    );
    final tile = dense ? 26.0 : 30.0;
    final duration = row.duration;
    final meta = <String>[
      if (row.object != null) row.object!,
      if (row.summary != null && row.object == null) row.summary!,
    ].join(' · ');
    final label = [
      row.verb,
      if (row.count > 1) '${row.count} times',
      if (row.object != null) row.object!,
      if (failed) 'failed',
      if (duration != null) HermesActivityPresenter.formatDuration(duration),
    ].join(', ');
    final body = Padding(
      padding: EdgeInsets.symmetric(vertical: dense ? 5 : 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          AnimatedContainer(
            duration: HermezMotion.settleFor(HermezMotionWeight.light),
            curve: HermezMotion.curveLight,
            width: tile,
            height: tile,
            decoration: BoxDecoration(
              color: failed || waiting
                  ? palette.accent.withValues(alpha: 0.12)
                  : palette.ink.withValues(alpha: running ? 0.07 : 0.05),
              borderRadius: BorderRadius.circular(tile * 0.32),
            ),
            child: Center(
              child: running
                  ? HermezLiveDot(state: HermezLiveState.working, size: 6)
                  : Icon(
                      failed
                          ? Icons.error_outline_rounded
                          : hermesActivityIcon(row.family),
                      size: dense ? 15 : 17,
                      color: failed || waiting ? palette.accent : palette.ink,
                    ),
            ),
          ),
          SizedBox(width: dense ? 10 : 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: HermezLiveText(
                        row.verb,
                        live: running,
                        style: verbStyle.copyWith(
                          color: failed ? palette.accent : palette.ink,
                        ),
                      ),
                    ),
                    if (row.count > 1) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: palette.ink.withValues(alpha: 0.07),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          '×${row.count}',
                          style: HermezType.meta(palette).copyWith(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: palette.ink,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                if (meta.isNotEmpty)
                  Text(
                    meta,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: HermezType.meta(palette).copyWith(fontSize: 12),
                  ),
              ],
            ),
          ),
          if (row.page != null) ...[
            const SizedBox(width: 8),
            _OpenPagePill(page: row.page!),
          ] else if (duration != null) ...[
            const SizedBox(width: 8),
            Text(
              HermesActivityPresenter.formatDuration(duration),
              style: HermezType.meta(palette).copyWith(
                fontSize: 12,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
          if (onOpen != null && row.page == null) ...[
            const SizedBox(width: 2),
            Icon(Icons.chevron_right_rounded, size: 18, color: palette.muted),
          ],
        ],
      ),
    );
    return Semantics(
      label: label,
      button: onOpen != null,
      excludeSemantics: true,
      child: onOpen == null
          ? body
          : HermezMotionSurface(
              weight: HermezMotionWeight.light,
              originRadius: 12,
              onOpen: onOpen,
              child: body,
            ),
    );
  }
}

class _OpenPagePill extends StatelessWidget {
  const _OpenPagePill({required this.page});

  final ({String pageId, String spaceId, String title}) page;

  @override
  Widget build(BuildContext context) {
    final palette = HermezChatPalette.forBrightness(
      Theme.of(context).brightness,
    );
    return HermezMotionSurface(
      weight: HermezMotionWeight.light,
      semanticLabel: 'Open Page ${page.title}',
      onTap: () =>
          context.push(Routes.spacePagePath(page.spaceId, page.pageId)),
      child: Container(
        constraints: const BoxConstraints(minHeight: 32),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: palette.ink,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          'Open',
          style: TextStyle(
            color: palette.surface,
            fontSize: 12.5,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}
