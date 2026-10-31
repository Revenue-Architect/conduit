import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../motion/hermez_motion.dart';
import '../providers/hermes_agentic_providers.dart';
import '../widgets/hermes_inline_delegation.dart';
import '../widgets/hermes_turn_delegation.dart';
import 'hermez_modal_sheet.dart';
export '../widgets/hermes_delegated_worker_card.dart'
    show
        hermesWorkerLiveState,
        hermesWorkerStatusLabel,
        hermesWorkerElapsed,
        hermesDelegatesSummary;

Future<void> showHermesDelegatesSheet(
  BuildContext context, {
  required String sessionId,
  HermezMorphOrigin? origin,
}) => pushHermezSheetRoute<void>(
  context,
  fit: true,
  origin: origin,
  heightFactor: .88,
  builder: (_) => Consumer(
    builder: (context, ref, _) {
      final workers =
          ref.watch(hermesAgenticStateProvider(sessionId)).value?.subagents ??
          const [];
      return HermezModalSheet(
        eyebrow: 'DELEGATES',
        title: 'Delegates',
        body: workers.isEmpty
            ? const Padding(
                padding: EdgeInsets.all(24),
                child: Text('No delegates reported.'),
              )
            : HermesDelegationScope(
                parentSessionId: sessionId,
                parentLabel: 'Parent',
                workers: workers,
                builder: (load, open, artifact) => HermesInlineDelegation(
                  workers: workers,
                  parentSessionId: sessionId,
                  parentLabel: 'Parent',
                  turnKey: 'sheet',
                  loadConversation: load,
                  onOpenSession: open,
                  loadArtifact: artifact,
                ),
              ),
      );
    },
  ),
);
