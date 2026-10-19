import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A button that only fires after it has been pressed and held for
/// [holdDuration]. Used for Approve: a stray tap can never approve anything.
///
/// While held, a fill sweeps across the button and the label changes to
/// [holdingLabel]. Letting go early, or sliding the finger off the button,
/// drains the fill and nothing happens. [onConfirmed] fires at most once per
/// press. Screen-reader users get the standard "double-tap and hold" gesture,
/// which confirms directly (it is itself a deliberate, two-step gesture).
class HoldToConfirmButton extends StatefulWidget {
  const HoldToConfirmButton({
    super.key,
    required this.label,
    required this.onConfirmed,
    this.holdingLabel = 'Keep holding…',
    this.holdDuration = const Duration(milliseconds: 1400),
    this.enabled = true,
    this.busy = false,
    this.icon,
    this.color,
    this.foreground,
    this.trackColor,
  });

  final String label;
  final String holdingLabel;
  final VoidCallback onConfirmed;
  final Duration holdDuration;
  final bool enabled;

  /// True while the confirmed action is running; shows a spinner and ignores
  /// presses.
  final bool busy;
  final IconData? icon;
  final Color? color;
  final Color? foreground;
  final Color? trackColor;

  @override
  State<HoldToConfirmButton> createState() => _HoldToConfirmButtonState();
}

class _HoldToConfirmButtonState extends State<HoldToConfirmButton>
    with SingleTickerProviderStateMixin {
  static const double _height = 56;
  static const double _slop = 28;

  late final AnimationController _progress = AnimationController(
    vsync: this,
    duration: widget.holdDuration,
  )..addStatusListener(_onStatus);

  bool _fired = false;
  bool _pointerDown = false;

  bool get _active => widget.enabled && !widget.busy;

  @override
  void dispose() {
    _progress.dispose();
    super.dispose();
  }

  void _onStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed && _pointerDown && !_fired) {
      _fire();
    }
  }

  void _fire() {
    _fired = true;
    HapticFeedback.heavyImpact();
    widget.onConfirmed();
  }

  void _down(PointerDownEvent event) {
    if (!_active) return;
    _pointerDown = true;
    _fired = false;
    HapticFeedback.selectionClick();
    _progress.forward(from: 0);
  }

  void _move(PointerMoveEvent event) {
    if (!_pointerDown) return;
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return;
    final local = box.globalToLocal(event.position);
    final bounds = (Offset.zero & box.size).inflate(_slop);
    if (!bounds.contains(local)) _release();
  }

  void _up(PointerEvent event) => _release();

  void _release() {
    if (!_pointerDown) return;
    _pointerDown = false;
    if (_progress.status != AnimationStatus.completed) {
      _progress.animateBack(
        0,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    } else {
      _progress.value = 0;
    }
  }

  @override
  void didUpdateWidget(HoldToConfirmButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_active && _pointerDown) _release();
    if (oldWidget.holdDuration != widget.holdDuration) {
      _progress.duration = widget.holdDuration;
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = widget.color ?? scheme.primary;
    final foreground = widget.foreground ?? scheme.onPrimary;
    final track = widget.trackColor ?? color.withValues(alpha: 0.22);
    final active = _active;
    return Semantics(
      button: true,
      enabled: active,
      excludeSemantics: true,
      label: widget.label,
      hint: 'Press and hold to confirm',
      onLongPress: active ? _fire : null,
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: _down,
        onPointerMove: _move,
        onPointerUp: _up,
        onPointerCancel: _up,
        child: AnimatedBuilder(
          animation: _progress,
          builder: (context, _) {
            final value = _progress.value;
            final holding = _pointerDown && value > 0 && !widget.busy;
            return Opacity(
              opacity: active || widget.busy ? 1 : 0.45,
              child: Container(
                height: _height,
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: track,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: color.withValues(alpha: 0.6)),
                ),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: FractionallySizedBox(
                        widthFactor: value.clamp(0.0, 1.0),
                        heightFactor: 1,
                        child: ColoredBox(color: color),
                      ),
                    ),
                    Center(
                      child: widget.busy
                          ? SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.4,
                                color: foreground,
                              ),
                            )
                          : Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (widget.icon != null) ...[
                                  Icon(
                                    widget.icon,
                                    size: 20,
                                    color: value > 0.5 ? foreground : color,
                                  ),
                                  const SizedBox(width: 8),
                                ],
                                Text(
                                  holding ? widget.holdingLabel : widget.label,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 16,
                                    color: value > 0.5 ? foreground : color,
                                  ),
                                ),
                              ],
                            ),
                    ),
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
