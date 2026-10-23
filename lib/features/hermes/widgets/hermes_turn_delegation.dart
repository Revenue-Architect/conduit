import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/chat_message.dart';
import '../../../l10n/app_localizations.dart';
import '../../../l10n/conduit_localizations.dart';
import '../models/hermes_subagent.dart';
import '../motion/hermez_motion.dart';
import '../providers/hermes_agentic_providers.dart';
import '../providers/hermes_providers.dart';
import '../services/hermes_desktop_api_service.dart';
import '../views/hermes_live_run_page.dart';
import '../kanban/hermes_kanban_page.dart';
import 'hermes_inline_delegation.dart';

/// No title matching or "latest assistant" fallback. Each origin resolves once
/// against actual recorded ids; absent origin information stays in Delegates.
bool hermesWorkerBelongsToMessage(
  HermesSubagentState worker,
  ChatMessage message,
) {
  if (worker.parentMessageId == message.id) return true;
  final metadata = message.metadata;
  if (worker.sourceToolCallId != null &&
      (metadata?['hermesToolCallIds'] as List?)?.contains(
            worker.sourceToolCallId,
          ) ==
          true) {
    return true;
  }
  return worker.parentTurnId != null &&
      worker.parentTurnId == metadata?['hermesTurnId'];
}

@immutable
class _TurnWorkers {
  const _TurnWorkers(this.value);
  final List<HermesSubagentState> value;
  @override
  bool operator ==(Object other) =>
      other is _TurnWorkers && listEquals(value, other.value);
  @override
  int get hashCode => Object.hashAll(value);
}

class HermesTurnDelegation extends ConsumerWidget {
  const HermesTurnDelegation({
    super.key,
    required this.sessionId,
    required this.message,
    required this.parentLabel,
    this.onLayoutChanged,
    this.turnMessages = const [],
  });
  final String sessionId, parentLabel;
  final ChatMessage message;
  final List<ChatMessage> turnMessages;
  final VoidCallback? onLayoutChanged;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(
      hermesAgenticStateProvider(sessionId).select(
        (state) => _TurnWorkers(
          state.value?.subagents
                  .where((w) {
                    final owner =
                        (turnMessages.isEmpty ? [message] : turnMessages)
                            .where((m) => hermesWorkerBelongsToMessage(w, m))
                            .firstOrNull;
                    return owner?.id == message.id;
                  })
                  .toList(growable: false) ??
              const [],
        ),
      ),
    );
    if (selected.value.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: HermesDelegationScope(
        parentSessionId: sessionId,
        parentLabel: parentLabel,
        workers: selected.value,
        builder: (load, open, artifact) => HermesInlineDelegation(
          key: PageStorageKey('delegated-turn:$sessionId:${message.id}'),
          turnKey: message.id,
          workers: selected.value,
          parentSessionId: sessionId,
          parentLabel: parentLabel,
          loadConversation: load,
          onOpenSession: open,
          loadArtifact: artifact,
          onLayoutChanged: onLayoutChanged,
        ),
      ),
    );
  }
}

typedef DelegatedConversationLoader = Future<List<ChatMessage>> Function(
  HermesSubagentState,
);
typedef DelegatedSessionOpener = Future<void> Function(
  HermesSubagentState,
  HermezMorphOrigin?,
);
typedef DelegatedArtifactLoader = Future<String> Function(
  HermesSubagentState,
  int,
);

/// Shares the authenticated read/navigation path between inline cards and the
/// existing Delegates sheet. Navigator.push keeps the parent route mounted.
class HermesDelegationScope extends ConsumerWidget {
  const HermesDelegationScope({
    super.key,
    required this.parentSessionId,
    required this.parentLabel,
    required this.workers,
    required this.builder,
  });
  final String parentSessionId, parentLabel;
  final List<HermesSubagentState> workers;
  final Widget Function(
    DelegatedConversationLoader,
    DelegatedSessionOpener,
    DelegatedArtifactLoader,
  )
  builder;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    HermesDesktopApiService service() {
      final value = ref.read(hermesApiServiceProvider);
      if (value is! HermesDesktopApiService) {
        throw StateError('Hermes unavailable');
      }
      return value;
    }

    return builder((worker) => service().readDelegatedConversation(worker), (
      worker,
      origin,
    ) async {
      if (worker.kind == HermesDelegationKind.kanban &&
          worker.taskId != null &&
          worker.boardSlug != null) {
        await openHermesDelegatedKanbanTask(
          context,
          service: service(),
          taskId: worker.taskId!,
          board: worker.boardSlug!,
          profile:
              worker.parentProfile ??
              service().profileForSession(parentSessionId),
          origin: origin,
        );
        return;
      }
      if (worker.childSessionId == null || worker.childProfile == null) return;
      // Verify profile-scoped access before exposing the full child session.
      await service().readDelegatedConversation(worker, maximum: 1);
      if (!context.mounted) return;
      await Navigator.of(context).push<void>(
        HermezRoute<void>(
          motion: HermezRouteMotion.expand,
          origin: origin,
          builder: (context) => Localizations.override(
            context: context,
            delegates: [
              ...conduitLocalizationsDelegates,
              ...AppLocalizations.localizationsDelegates,
            ],
            child: HermesLiveRunPage(
              sessionId: worker.childSessionId!,
              profile: worker.childProfile,
              embedded: true,
              delegation: worker,
              parentLabel: parentLabel,
            ),
          ),
        ),
      );
    }, (worker, index) => service().readDelegationArtifact(worker, index));
  }
}
