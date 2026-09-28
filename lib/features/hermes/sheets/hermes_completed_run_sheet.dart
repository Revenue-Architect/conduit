import 'package:flutter/material.dart';

import '../models/hermes_completed_run_snapshot.dart';
import '../motion/hermez_motion.dart';
import '../services/hermes_live_activity.dart';
import '../widgets/hermes_artifact_view.dart';
import '../widgets/hermez_bot_mark.dart';
import '../widgets/hermez_chat_palette.dart';
import '../widgets/hermez_relative_time.dart';
import '../widgets/hermez_sheet_parts.dart';
import '../widgets/hermez_surfaces.dart';
import 'hermez_modal_sheet.dart';

enum HermesCompletedRunAction { conversation, artifacts }

Future<HermesCompletedRunAction?> showHermesCompletedRunSheet(
  BuildContext context,
  HermesCompletedRunSnapshot snapshot, {
  HermezMorphOrigin? origin,
}) => pushHermezSheetRoute<HermesCompletedRunAction>(
  context,
  origin: origin,
  builder: (sheetContext) => _CompletedRunSheet(snapshot: snapshot),
);

class _CompletedRunSheet extends StatelessWidget {
  const _CompletedRunSheet({required this.snapshot});
  final HermesCompletedRunSnapshot snapshot;

  String _duration(Duration value) {
    if (value.inHours > 0) {
      return '${value.inHours}h ${value.inMinutes.remainder(60)}m';
    }
    if (value.inMinutes > 0) {
      return '${value.inMinutes}m ${value.inSeconds.remainder(60)}s';
    }
    return '${value.inSeconds}s';
  }

  @override
  Widget build(BuildContext context) {
    final palette = HermezChatPalette.forBrightness(
      Theme.of(context).brightness,
    );
    final profile = snapshot.profile;
    final started = snapshot.startedAt;
    final steps = snapshot.activity
        .where(
          (event) =>
              event.kind == HermesLiveActivityKind.toolCompleted ||
              event.kind == HermesLiveActivityKind.subagentCompleted,
        )
        .take(8)
        .toList(growable: false);
    final divider = Container(
      width: 1,
      height: 36,
      margin: const EdgeInsets.symmetric(horizontal: 10),
      color: palette.border,
    );
    return HermezModalSheet(
      title: 'Run complete',
      subtitle: Text(
        '${profile ?? 'Hermes'} finished'.toUpperCase(),
        style: HermezType.technical(palette.ink).copyWith(letterSpacing: 3),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 0,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _Fact(
                leading: HermezBotMark(
                  identity: hermezIdentityForName(profile),
                  size: 40,
                  label: profile ?? 'Hermes',
                ),
                label: 'Bot',
                value: profile ?? 'Hermes',
              ),
              if (started != null) ...[
                divider,
                _Fact(
                  leading: Icon(Icons.schedule_rounded, color: palette.ink),
                  label: 'Duration',
                  value: _duration(snapshot.completedAt.difference(started)),
                ),
              ],
              divider,
              _Fact(
                leading: Icon(
                  Icons.event_available_outlined,
                  color: palette.ink,
                ),
                label: 'Completed',
                value: hermezRelativeLabel(snapshot.completedAt),
              ),
            ],
          ),
          const SizedBox(height: 16),
          HermezSurface(
            kind: HermezSurfaceKind.utility,
            motif: HermezMotif.etched,
            border: Border.all(color: palette.border.withValues(alpha: 0.75)),
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: const Color(0xFF17181C),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(
                    Icons.notes_rounded,
                    color: Color(0xFFF6F5F2),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'RUN SUMMARY',
                        style: HermezType.technical(palette.muted)
                            .copyWith(letterSpacing: 2),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        snapshot.title,
                        style: HermezType.section(palette)
                            .copyWith(fontSize: 18, height: 1.2),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        snapshot.finalText.isEmpty
                            ? 'The run ended. Open its conversation to see the latest transcript.'
                            : snapshot.finalText,
                        style: HermezType.body(palette)
                            .copyWith(color: palette.muted),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (steps.isNotEmpty) ...[
            const SizedBox(height: 12),
            HermezSurface(
              kind: HermezSurfaceKind.utility,
              border: Border.all(color: palette.border.withValues(alpha: 0.75)),
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  HermezSectionLabel(
                    'Completed steps',
                    trailing: Text(
                      '${steps.length} STEPS',
                      style: HermezType.technical(palette.muted),
                    ),
                  ),
                  const SizedBox(height: 8),
                  for (var index = 0; index < steps.length; index++)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 7),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 28,
                            height: 28,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: index == 0
                                  ? palette.accent
                                  : palette.canvas,
                              shape: BoxShape.circle,
                            ),
                            child: Text(
                              '${index + 1}',
                              style: TextStyle(
                                color: index == 0 ? Colors.white : palette.ink,
                                fontWeight: FontWeight.w700,
                                fontSize: 12,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                steps[index].title,
                                style: HermezType.body(palette),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
          if (snapshot.artifacts.isNotEmpty) ...[
            const SizedBox(height: 12),
            HermezSectionLabel(
              'Generated files',
              trailing: Text(
                '${snapshot.artifacts.length} FILES',
                style: HermezType.technical(palette.muted),
              ),
            ),
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
      footer: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          HermezActionTile(
            primary: true,
            icon: Icons.chat_bubble_outline_rounded,
            title: 'Open conversation',
            subtitle: 'Continue with these results',
            onTap: () =>
                Navigator.pop(context, HermesCompletedRunAction.conversation),
          ),
          if (snapshot.artifacts.isNotEmpty) ...[
            const SizedBox(height: 8),
            HermezActionTile(
              icon: Icons.folder_outlined,
              title: 'View files',
              subtitle: 'See all artifacts',
              onTap: () =>
                  Navigator.pop(context, HermesCompletedRunAction.artifacts),
            ),
          ],
        ],
      ),
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact({
    required this.leading,
    required this.label,
    required this.value,
  });

  final Widget leading;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final palette = HermezChatPalette.forBrightness(
      Theme.of(context).brightness,
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        leading,
        const SizedBox(width: 10),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label.toUpperCase(),
                style: HermezType.technical(palette.muted)
                    .copyWith(fontSize: 9.5, letterSpacing: 1.8),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: HermezType.body(palette)
                    .copyWith(fontWeight: FontWeight.w600, fontSize: 15),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
