import 'package:flutter/material.dart';

import '../../../core/models/chat_message.dart';
import '../models/hermes_subagent.dart';
import '../motion/hermez_motion.dart';
import 'hermes_delegated_worker_card.dart';
import 'hermez_chat_palette.dart';
import 'hermez_surfaces.dart';

/// A physical part of one assistant turn. Identity includes the turn, so
/// independent expansions survive row recycling and child-route navigation.
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

  @override
  Widget build(BuildContext context) {
    if (widget.workers.isEmpty) return const SizedBox.shrink();
    final p = HermezChatPalette.forBrightness(Theme.of(context).brightness);
    final working = widget.workers
        .where((w) => w.status == HermesSubagentStatus.running)
        .length;
    final done = widget.workers
        .where((w) => w.status == HermesSubagentStatus.completed)
        .length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            color: p.surface,
            border: Border.all(color: p.border),
            borderRadius: BorderRadius.circular(14),
          ),
          child: HermezMotionSurface(
            weight: HermezMotionWeight.light,
            semanticLabel:
                'Delegated work. ${widget.workers.length} workers. ${_open ? 'Collapse' : 'Expand'}',
            semanticsExpanded: _open,
            onTap: () => _change(() => _open = !_open),
            child: Padding(
              padding: const EdgeInsets.all(13),
              child: Row(
                children: [
                  const Icon(Icons.account_tree_outlined, size: 18),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Delegated work', style: HermezType.section(p)),
                        const SizedBox(height: 4),
                        Text(
                          '${widget.workers.length} workers · $working working · $done complete',
                          style: HermezType.meta(p),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    _open
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded,
                    color: p.muted,
                  ),
                ],
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
              for (final worker in widget.workers)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: HermesDelegatedWorkerCard(
                    key: PageStorageKey('$_storage:${worker.id}'),
                    worker: worker,
                    parentSessionId: widget.parentSessionId,
                    parentLabel: widget.parentLabel,
                    expanded: _expanded.contains(worker.id),
                    onToggle: () => _change(() {
                      if (!_expanded.add(worker.id)) {
                        _expanded.remove(worker.id);
                      }
                    }),
                    onLayoutChanged: widget.onLayoutChanged,
                    loadConversation: widget.loadConversation,
                    onOpenSession: widget.onOpenSession,
                    loadArtifact: widget.loadArtifact,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
