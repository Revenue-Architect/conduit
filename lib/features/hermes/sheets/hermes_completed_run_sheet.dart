import 'package:flutter/material.dart';

import '../models/hermes_completed_run_snapshot.dart';
import '../services/hermes_live_activity.dart';
import '../views/hermes_page_chrome.dart';
import '../widgets/hermes_artifact_view.dart';
import 'hermez_modal_sheet.dart';

enum HermesCompletedRunAction { conversation, artifacts }

Future<HermesCompletedRunAction?> showHermesCompletedRunSheet(
  BuildContext context,
  HermesCompletedRunSnapshot snapshot,
) => showHermezSheet<HermesCompletedRunAction>(
  context,
  title: 'Run complete',
  eyebrow: snapshot.profile == null ? 'Hermes' : snapshot.profile,
  body: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      HermesPanel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              snapshot.title,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),
            if (snapshot.startedAt != null)
              Text(
                'Duration: ${snapshot.completedAt.difference(snapshot.startedAt!).inSeconds}s',
              ),
          ],
        ),
      ),
      const SizedBox(height: 14),
      const HermesSectionTitle('Result'),
      const SizedBox(height: 8),
      HermesPanel(
        child: Text(
          snapshot.finalText.isEmpty
              ? 'The run ended. Open its conversation to see the latest transcript.'
              : snapshot.finalText,
        ),
      ),
      if (snapshot.activity.isNotEmpty) ...[
        const SizedBox(height: 14),
        const HermesSectionTitle('Activity'),
        HermesPanel(
          child: Column(
            children: [
              for (final event
                  in snapshot.activity
                      .where(
                        (event) =>
                            event.kind ==
                                HermesLiveActivityKind.toolCompleted ||
                            event.kind ==
                                HermesLiveActivityKind.subagentCompleted,
                      )
                      .take(8))
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.check_circle_outline_rounded),
                  title: Text(event.title),
                ),
            ],
          ),
        ),
      ],
      if (snapshot.artifacts.isNotEmpty) ...[
        const SizedBox(height: 14),
        const HermesSectionTitle('Generated files'),
        const SizedBox(height: 8),
        for (final artifact in snapshot.artifacts)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: HermesArtifactView(
              artifact: artifact,
              sessionId: snapshot.sessionId,
            ),
          ),
      ],
    ],
  ),
  footer: Row(
    children: [
      Expanded(
        child: FilledButton.icon(
          onPressed: () =>
              Navigator.pop(context, HermesCompletedRunAction.conversation),
          icon: const Icon(Icons.chat_bubble_outline_rounded),
          label: const Text('Open conversation'),
        ),
      ),
      if (snapshot.artifacts.isNotEmpty) ...[
        const SizedBox(width: 8),
        OutlinedButton(
          onPressed: () =>
              Navigator.pop(context, HermesCompletedRunAction.artifacts),
          child: const Text('View files'),
        ),
      ],
    ],
  ),
);
