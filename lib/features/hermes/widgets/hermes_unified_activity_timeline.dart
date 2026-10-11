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
              Padding(
                padding: const EdgeInsets.only(left: 42),
                child: StreamingStatusTimeline(
                  updates: details,
                  isStreaming: running,
                  showHeaders: false,
                ),
              ),
          ],
        ),
      );
    }
    if (remaining.isNotEmpty) {
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
