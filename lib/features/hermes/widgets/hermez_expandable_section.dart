import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

import '../../../shared/theme/theme_extensions.dart';
import '../feedback/hermez_feedback.dart';
import '../motion/hermez_motion.dart';
import 'hermez_chat_palette.dart';
import 'hermez_surfaces.dart';

/// A physical compartment: more of the same object, opened in place.
///
/// The section occupies real layout space, so as it opens everything after it
/// is pushed down, and as it closes everything comes back up. That is a
/// layout animation, not a translated overlay.
///
/// - The parent owns [expanded]; a header tap only reports the wish through
///   [onExpansionChanged]. The section follows [expanded], including changes
///   the parent makes without a tap.
/// - One spring (the Hermez spring for [weight]) owns the height, through
///   [HermezUnroll]: the top stays anchored, the bottom edge travels, and the
///   content moves with the edge. A second tap mid-flight reverses from the
///   current position with the current velocity.
/// - The chevron turns on the same spring, so panel and indicator are one
///   mechanism. Nothing fades.
/// - While closed the content takes no input and is hidden from
///   accessibility; once fully closed it is unmounted unless
///   [maintainState].
/// - Reduced motion changes the layout at once.
/// - [openFeedback] / [closeFeedback] play only for a real header tap, never
///   for a build, rebuild, or a parent-driven change.
///
/// It knows nothing about bots, jobs, Kanban, or Hermes, and calls nothing.
class HermezExpandableSection extends StatefulWidget {
  const HermezExpandableSection({
    super.key,
    required this.expanded,
    required this.onExpansionChanged,
    required this.header,
    required this.child,
    this.weight = HermezMotionWeight.medium,
    this.semanticLabel,
    this.openFeedback,
    this.closeFeedback,
    this.maintainState = false,
    this.padding = const EdgeInsets.fromLTRB(16, 12, 12, 12),
    this.childPadding = const EdgeInsets.fromLTRB(16, 12, 16, 14),
    this.framed = true,
  });

  final bool expanded;
  final ValueChanged<bool> onExpansionChanged;

  /// The header content; the section adds the turning indicator after it.
  final Widget header;
  final Widget child;

  final HermezMotionWeight weight;
  final String? semanticLabel;

  final HermezFeedbackCue? openFeedback;
  final HermezFeedbackCue? closeFeedback;

  /// Keep [child] mounted while closed (for real local state such as a
  /// half-typed field). Off by default: hidden read-only content is dropped.
  final bool maintainState;

  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry childPadding;

  /// Draw the compartment's own utility frame. Off when the section lives
  /// inside a surface that already is the frame (a hero card).
  final bool framed;

  @override
  State<HermezExpandableSection> createState() =>
      _HermezExpandableSectionState();
}

class _HermezExpandableSectionState extends State<HermezExpandableSection>
    with SingleTickerProviderStateMixin {
  late final AnimationController _open = AnimationController(
    vsync: this,
    value: widget.expanded ? 1 : 0,
  );

  @override
  void didUpdateWidget(HermezExpandableSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.expanded != widget.expanded) _settle();
  }

  @override
  void dispose() {
    _open.dispose();
    super.dispose();
  }

  void _settle() {
    final target = widget.expanded ? 1.0 : 0.0;
    if (context.reduceMotion) {
      _open.value = target;
      return;
    }
    // From wherever it is, carrying its velocity: a reversal mid-flight
    // turns around instead of restarting.
    _open.animateWith(
      _ClampedSpring(
        SpringSimulation(
          HermezMotion.springFor(widget.weight).toFlutter(),
          _open.value,
          target,
          _open.velocity,
        ),
        target,
      ),
    );
  }

  void _toggle() {
    final next = !widget.expanded;
    final cue = next ? widget.openFeedback : widget.closeFeedback;
    if (cue != null) HermezFeedback.play(cue);
    widget.onExpansionChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    final palette = HermezChatPalette.forBrightness(
      Theme.of(context).brightness,
    );
    final radius = BorderRadius.circular(
      HermezSurface.radiusFor(HermezSurfaceKind.utility),
    );
    final header = HermezMotionSurface(
      weight: HermezMotionWeight.light,
      semanticLabel: widget.semanticLabel,
      semanticsExpanded: widget.expanded,
      // The optional cue belongs to the toggle, not a generic tick.
      haptic: widget.openFeedback == null && widget.closeFeedback == null,
      onTap: _toggle,
      child: Padding(
        padding: widget.padding,
        child: Row(
          children: [
            Expanded(child: widget.header),
            const SizedBox(width: 8),
            AnimatedBuilder(
              animation: _open,
              builder: (context, _) => Transform.rotate(
                angle: math.pi * _open.value.clamp(0.0, 1.0),
                child: Icon(
                  Icons.keyboard_arrow_down_rounded,
                  color: palette.muted,
                  size: 22,
                ),
              ),
            ),
          ],
        ),
      ),
    );
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // The seam: the header's lower boundary opening, travelling with
        // the content rather than drawn as a second border.
        Container(
          height: 1,
          margin: EdgeInsets.symmetric(horizontal: widget.framed ? 16 : 0),
          color: palette.border.withValues(alpha: 0.7),
        ),
        Padding(padding: widget.childPadding, child: widget.child),
      ],
    );
    final body = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        header,
        AnimatedBuilder(
          animation: _open,
          child: content,
          builder: (context, content) {
            final closed = _open.value <= 0 && !_open.isAnimating;
            if (closed && !widget.maintainState) {
              return const SizedBox.shrink();
            }
            return IgnorePointer(
              ignoring: !widget.expanded,
              child: ExcludeSemantics(
                excluding: !widget.expanded,
                child: HermezUnroll(animation: _open, child: content!),
              ),
            );
          },
        ),
      ],
    );
    if (!widget.framed) return body;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: radius,
        border: Border.all(color: palette.border.withValues(alpha: 0.8)),
      ),
      child: ClipRRect(borderRadius: radius, child: body),
    );
  }
}

/// The Hermez springs are critically damped; this guards the size factor
/// against floating-point excursions outside [0, 1] and lands exactly on the
/// target when the spring is at rest (a closed section is truly closed).
class _ClampedSpring extends Simulation {
  _ClampedSpring(this._spring, this._target);

  final SpringSimulation _spring;
  final double _target;

  @override
  double x(double time) =>
      _spring.isDone(time) ? _target : _spring.x(time).clamp(0.0, 1.0);

  @override
  double dx(double time) => _spring.dx(time);

  @override
  bool isDone(double time) => _spring.isDone(time);
}
