import 'package:flutter/material.dart';

import '../../../core/models/chat_message.dart';
import '../../chat/widgets/streaming_status_widget.dart';
import '../motion/hermez_motion.dart';
import '../services/hermes_activity_presenter.dart';
import 'hermes_activity_view.dart';

/// Retains the paired/grouped Desktop rows and the legacy disclosure's exact
/// result renderer. A matching status enriches its row, not a second timeline.
class HermesUnifiedActivityTimeline extends StatelessWidget {
  const HermesUnifiedActivityTimeline({
    super.key,
    required this.rows,
    required this.statuses,
    required this.running,
    this.onInspect,
  });
  final List<HermesActivityRow> rows;
  final List<ChatStatusUpdate> statuses;
  final bool running;
  final void Function(HermesActivityRow, HermezMorphOrigin?)? onInspect;

  @override
  Widget build(BuildContext context) {
    final remaining = [...statuses.where((status) => status.hidden != true)];
    final entries = <Widget>[];
    // One rail. A tool's matching status updates belong to its row; their raw
    // output stays folded under it until asked for, never a wall of results.
    for (final row in rows) {
      final details = <ChatStatusUpdate>[];
      for (var i = 0; i < row.count; i++) {
        final match = remaining.indexWhere(
          (status) => hermesStatusToolName(status) == row.toolName,
        );
        if (match < 0) break;
        details.add(remaining.removeAt(match));
      }
      entries.add(
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            HermesActivityRowView(
              row: row,
              onOpen: row.inspectable && onInspect != null
                  ? (origin) => onInspect!(row, origin)
                  : null,
            ),
            if (details.isNotEmpty)
              _FoldedOutput(updates: details, running: running),
          ],
        ),
      );
    }
    // Statuses with no tool row (web search, notes) only when nothing else ran.
    if (remaining.isNotEmpty && rows.isEmpty) {
      entries.add(
        StreamingStatusTimeline(updates: remaining, isStreaming: running),
      );
    }
    return Material(
      type: MaterialType.transparency,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: entries,
      ),
    );
  }
}

/// A tool's output, folded to one quiet line under its row until opened.
class _FoldedOutput extends StatefulWidget {
  const _FoldedOutput({required this.updates, required this.running});
  final List<ChatStatusUpdate> updates;
  final bool running;

  @override
  State<_FoldedOutput> createState() => _FoldedOutputState();
}

class _FoldedOutputState extends State<_FoldedOutput> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Padding(
      // Aligned with the row's text, inside the same rail.
      padding: const EdgeInsets.only(left: 42, bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => setState(() => _open = !_open),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      _open ? 'Hide output' : 'Show output',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: muted,
                      ),
                    ),
                  ),
                  Icon(
                    _open
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded,
                    size: 16,
                    color: muted,
                  ),
                ],
              ),
            ),
          ),
          // Inside the sheet's lazy list a size animation can't resize
          // mid-layout, so the fold opens in place.
          if (_open)
            StreamingStatusTimeline(
              updates: widget.updates,
              isStreaming: widget.running,
              showHeaders: false,
            ),
        ],
      ),
    );
  }
}
