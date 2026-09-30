import 'package:flutter/material.dart';

import '../feedback/hermez_feedback.dart';
import '../motion/hermez_motion.dart';
import 'hermez_chat_palette.dart';
import 'hermez_surfaces.dart';

/// Stop, held open for one more decision in the run's own controls.
///
/// Tapping Stop does not interrupt at once: it opens this guard in place,
/// under the controls, pushing what follows down. Keep running folds it
/// away; Stop calls [onStop] once and folds it away. Never a centered
/// dialog.
class HermesStopGuard extends StatefulWidget {
  const HermesStopGuard({
    super.key,
    required this.open,
    required this.onKeepRunning,
    required this.onStop,
  });

  final bool open;
  final VoidCallback onKeepRunning;

  /// Interrupts the run. Called at most once per opening.
  final VoidCallback onStop;

  @override
  State<HermesStopGuard> createState() => _HermesStopGuardState();
}

class _HermesStopGuardState extends State<HermesStopGuard> {
  bool _sent = false;

  @override
  void didUpdateWidget(HermesStopGuard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A fresh opening may stop again.
    if (widget.open && !oldWidget.open) _sent = false;
  }

  void _stop() {
    if (_sent) return;
    _sent = true;
    widget.onStop();
  }

  @override
  Widget build(BuildContext context) {
    final palette = HermezChatPalette.forBrightness(
      Theme.of(context).brightness,
    );
    final danger = Theme.of(context).colorScheme.error;
    return HermezReveal(
      visible: widget.open,
      weight: HermezMotionWeight.medium,
      revealKey: const ValueKey('hermes-stop-guard'),
      child: Semantics(
        container: true,
        liveRegion: true,
        label: 'Stop this run? Hermes will interrupt the active turn.',
        child: Container(
          margin: const EdgeInsets.only(top: 10),
          padding: const EdgeInsets.fromLTRB(14, 12, 10, 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: danger.withValues(alpha: 0.55)),
            color: danger.withValues(alpha: 0.06),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ExcludeSemantics(
                child: Text(
                  'STOP THIS RUN?',
                  style: HermezType.technical(danger),
                ),
              ),
              const SizedBox(height: 4),
              ExcludeSemantics(
                child: Text(
                  'Hermes will interrupt the active turn.',
                  style: HermezType.meta(palette),
                ),
              ),
              OverflowBar(
                alignment: MainAxisAlignment.end,
                spacing: 8,
                children: [
                  TextButton(
                    style: TextButton.styleFrom(
                      minimumSize: const Size(64, 44),
                    ),
                    onPressed: () {
                      HermezFeedback.play(HermezFeedbackCue.compartmentClose);
                      widget.onKeepRunning();
                    },
                    child: const Text('Keep running'),
                  ),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: danger,
                      foregroundColor: Theme.of(context).colorScheme.onError,
                      minimumSize: const Size(64, 44),
                    ),
                    onPressed: _stop,
                    child: const Text('Stop'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
