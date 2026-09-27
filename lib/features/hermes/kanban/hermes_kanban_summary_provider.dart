import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/hermes_providers.dart';
import '../services/hermes_desktop_api_service.dart';
import 'hermes_kanban_client.dart';

/// Read-only projection of the first Hermes board. Counts are derived from the
/// server snapshot, never maintained as a second local task store.
final class HermesKanbanSummary {
  const HermesKanbanSummary(this.board, this.snapshot);

  final KanbanBoardRef board;
  final KanbanSnapshot snapshot;

  int count(String lane) => snapshot.lanes[lane]?.length ?? 0;
  int get total =>
      snapshot.lanes.values.fold(0, (sum, tasks) => sum + tasks.length);
}

final hermesKanbanSummaryProvider =
    FutureProvider.autoDispose<HermesKanbanSummary?>((ref) async {
      final config = ref.watch(hermesConfigProvider);
      final service = ref.watch(hermesApiServiceProvider);
      final client = HermesKanbanClient(
        config,
        nativeRequest: service is HermesDesktopApiService
            ? service.requestKanbanJson
            : null,
      );
      ref.onDispose(() => unawaited(client.close()));
      final boards = await client.boards();
      if (boards.isEmpty) return null;
      final board = boards.firstWhere(
        (candidate) => candidate.slug == 'default',
        orElse: () => boards.first,
      );
      return HermesKanbanSummary(board, await client.board(board.slug));
    });
