import 'package:flutter/material.dart';

import '../models/hermes_config.dart';
import '../services/hermes_desktop_api_service.dart';
import '../services/hermes_live_activity.dart';
import 'hermez_chat_palette.dart';

/// A compact, session-scoped live timeline that stays inside the conversation.
/// It shares the existing Desktop event subscription; opening it never starts
/// another gateway connection or invents a progress percentage.
class HermesLiveActivityDisclosure extends StatefulWidget {
  const HermesLiveActivityDisclosure({
    super.key,
    required this.service,
    required this.sessionId,
    required this.expanded,
    required this.onToggle,
  });

  static const collapsedHeight = 72.0;
  static const expandedHeight = 292.0;

  final HermesDesktopApiService service;
  final String sessionId;
  final bool expanded;
  final VoidCallback onToggle;

  @override
  State<HermesLiveActivityDisclosure> createState() =>
      _HermesLiveActivityDisclosureState();
}

class _HermesLiveActivityDisclosureState
    extends State<HermesLiveActivityDisclosure> {
  late Stream<List<HermesLiveActivityEvent>> _activity;
  late Stream<HermesDesktopTurnState> _turns;

  @override
  void initState() {
    super.initState();
    _subscribe();
  }

  @override
  void didUpdateWidget(covariant HermesLiveActivityDisclosure oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.service, widget.service) ||
        oldWidget.sessionId != widget.sessionId) {
      _subscribe();
    }
  }

  void _subscribe() {
    _activity = widget.service.activityFor(widget.sessionId);
    _turns = widget.service.turnStatesFor(widget.sessionId);
  }

  @override
  Widget build(BuildContext context) {
    final palette = HermezChatPalette.forBrightness(
      Theme.of(context).brightness,
    );
    return StreamBuilder<HermesDesktopTurnState>(
      stream: _turns,
      initialData: widget.service.turnStateFor(widget.sessionId),
      builder: (context, turn) => StreamBuilder<List<HermesLiveActivityEvent>>(
        stream: _activity,
        initialData: widget.service.activitySnapshotFor(widget.sessionId),
        builder: (context, activity) {
          final events = activity.data ?? const <HermesLiveActivityEvent>[];
          final running = turn.data == HermesDesktopTurnState.running;
          final latest = events.isEmpty ? null : events.last;
          return AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            height: widget.expanded
                ? HermesLiveActivityDisclosure.expandedHeight
                : HermesLiveActivityDisclosure.collapsedHeight,
            decoration: BoxDecoration(
              color: palette.surface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: palette.border),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: widget.onToggle,
                    child: SizedBox(
                      height: HermesLiveActivityDisclosure.collapsedHeight - 2,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Row(
                          children: [
                            Icon(
                              running
                                  ? Icons.radio_button_checked_rounded
                                  : Icons.timeline_rounded,
                              color: running ? palette.accent : palette.muted,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    running ? 'Live activity' : 'Run activity',
                                    style: TextStyle(
                                      color: palette.ink,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  Text(
                                    latest?.title ??
                                        (running
                                            ? 'Hermes is working'
                                            : 'No active run'),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: palette.muted,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (events.isNotEmpty)
                              Text(
                                '${events.length}',
                                style: TextStyle(color: palette.muted),
                              ),
                            const SizedBox(width: 6),
                            Icon(
                              widget.expanded
                                  ? Icons.expand_more_rounded
                                  : Icons.expand_less_rounded,
                              color: palette.ink,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                if (widget.expanded)
                  Expanded(
                    child: events.isEmpty
                        ? Center(
                            child: Text(
                              running
                                  ? 'Waiting for the first tool update…'
                                  : 'No activity in this session yet.',
                              style: TextStyle(color: palette.muted),
                            ),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                            itemCount: events.length.clamp(0, 20),
                            itemBuilder: (context, index) {
                              final event = events[events.length - 1 - index];
                              final time = TimeOfDay.fromDateTime(
                                event.timestamp.toLocal(),
                              ).format(context);
                              return ListTile(
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                                leading: Icon(
                                  Icons.circle,
                                  size: 8,
                                  color: index == 0 && running
                                      ? palette.accent
                                      : palette.muted,
                                ),
                                title: Text(event.title, maxLines: 2),
                                trailing: Text(
                                  time,
                                  style: TextStyle(
                                    color: palette.muted,
                                    fontSize: 11,
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}
