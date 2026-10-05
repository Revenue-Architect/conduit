import 'dart:async';

import 'package:flutter/material.dart';

import '../../../shared/theme/theme_extensions.dart';
import '../feedback/hermez_feedback.dart';
import '../motion/hermez_motion.dart';
import 'hermez_chat_palette.dart';
import 'hermez_status_morph.dart';

/// A button for an action that takes a moment and either works or doesn't.
/// On tap the capsule draws in around a ring that spins while the action
/// runs; success closes the ring into a check and the button says so for a
/// beat before returning; failure says what went wrong, nudges, and taps
/// again to retry. The same object the whole way through. Adapted from
/// SwiftPieces' Commit Button.
class HermezCommitButton extends StatefulWidget {
  const HermezCommitButton({
    super.key,
    required this.label,
    required this.onCommit,
    this.icon,
    this.successLabel,
    this.failureLabel = 'Try again',
    this.hold = const Duration(milliseconds: 900),
    this.height = 40,
    this.enabled = true,
    this.onCommitted,
  });

  final String label;
  final IconData? icon;

  /// Runs the action: true when it worked. A throw counts as failure.
  final Future<bool> Function() onCommit;

  /// What the button says once it worked; just a check when null.
  final String? successLabel;
  final String failureLabel;

  /// How long success shows before the button is itself again.
  final Duration hold;
  final double height;
  final bool enabled;

  /// Called once success has shown for [hold] (to close a panel, say); the
  /// button then stays as it is instead of returning.
  final VoidCallback? onCommitted;

  @override
  State<HermezCommitButton> createState() => _HermezCommitButtonState();
}

enum _Phase { idle, working, done, failed }

class _HermezCommitButtonState extends State<HermezCommitButton> {
  _Phase _phase = _Phase.idle;
  Timer? _back;

  Future<void> _commit() async {
    if (_phase == _Phase.working || !widget.enabled) return;
    _back?.cancel();
    // The surface gives the press its own feedback.
    setState(() => _phase = _Phase.working);
    var ok = false;
    try {
      ok = await widget.onCommit();
    } catch (_) {
      ok = false;
    }
    if (!mounted) return;
    HermezFeedback.play(
      ok ? HermezFeedbackCue.approvalAccepted : HermezFeedbackCue.runFailed,
    );
    setState(() => _phase = ok ? _Phase.done : _Phase.failed);
    if (ok) {
      _back = Timer(widget.hold, () {
        if (!mounted) return;
        final then = widget.onCommitted;
        if (then != null) {
          then();
        } else {
          setState(() => _phase = _Phase.idle);
        }
      });
    }
  }

  @override
  void dispose() {
    _back?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = HermezChatPalette.forBrightness(
      Theme.of(context).brightness,
    );
    final reduce = context.reduceMotion;
    final ring = _phase == _Phase.working;
    final morphState = switch (_phase) {
      _Phase.idle => HermezMorphState.idle,
      _Phase.working => HermezMorphState.working,
      _Phase.done => HermezMorphState.done,
      _Phase.failed => HermezMorphState.failed,
    };
    final label = switch (_phase) {
      _Phase.idle || _Phase.working => widget.label,
      _Phase.done => widget.successLabel,
      _Phase.failed => widget.failureLabel,
    };
    final fill = _phase == _Phase.failed ? palette.accent : palette.ink;
    final onFill = _phase == _Phase.failed ? palette.onAccent : palette.canvas;
    final mark = _phase == _Phase.idle
        ? (widget.icon == null
              ? null
              : Icon(widget.icon, size: 18, color: onFill))
        : HermezStatusMorph(
            state: morphState,
            size: 18,
            // On the dark capsule the ring and its disc read in the
            // capsule's own ink.
            tint: _phase == _Phase.failed ? palette.onAccent : onFill,
            ink: onFill,
            onInk: fill,
            onTint: fill,
          );
    return Semantics(
      button: true,
      enabled: widget.enabled,
      label: _phase == _Phase.working
          ? '${widget.label}, working'
          : _phase == _Phase.failed
          ? '${widget.failureLabel}. Double tap to try again'
          : label ?? widget.label,
      excludeSemantics: true,
      child: HermezMotionSurface(
        weight: HermezMotionWeight.light,
        onTap: widget.enabled && !ring ? _commit : null,
        child: LayoutBuilder(
          builder: (context, constraints) {
            // A long label at large text sizes wraps instead of running
            // out of the capsule.
            final labelMax = constraints.maxWidth.isFinite
                ? (constraints.maxWidth - 32 - (mark == null ? 0 : 26)).clamp(
                    0.0,
                    double.infinity,
                  )
                : double.infinity;
            return AnimatedSize(
              // The capsule draws in around the ring and opens back out.
              duration: reduce
                  ? Duration.zero
                  : HermezMotion.settleFor(HermezMotionWeight.medium),
              curve: HermezMotion.curveMedium,
              alignment: Alignment.center,
              child: Container(
                constraints: BoxConstraints(minHeight: widget.height),
                padding: EdgeInsets.symmetric(
                  horizontal: ring ? (widget.height - 18) / 2 : 16,
                  vertical: ring ? (widget.height - 18) / 2 : 8,
                ),
                decoration: BoxDecoration(
                  color: widget.enabled
                      ? fill
                      : palette.ink.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(widget.height / 2),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ?mark,
                    if (!ring && label != null) ...[
                      if (mark != null) const SizedBox(width: 8),
                      ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: labelMax),
                        child: Text(
                          label,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: onFill,
                            fontWeight: FontWeight.w800,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
