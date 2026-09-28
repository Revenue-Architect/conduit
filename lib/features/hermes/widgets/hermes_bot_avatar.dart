import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../../../shared/theme/theme_extensions.dart';
import 'hermez_bot_mark.dart';

/// Renders Hermes' synced shape face, or its uploaded/photo avatar.
class HermesBotAvatar extends StatefulWidget {
  const HermesBotAvatar({
    required this.size,
    required this.label,
    required this.shape,
    required this.color,
    this.imageUrl,
    this.imageKind,
    this.active = false,
    super.key,
  });

  final double size;
  final String label;
  final String shape;
  final String color;
  final String? imageUrl;
  final String? imageKind;
  final bool active;

  @override
  State<HermesBotAvatar> createState() => _HermesBotAvatarState();
}

class _HermesBotAvatarState extends State<HermesBotAvatar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: AnimationDuration.extended,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncMotion();
  }

  @override
  void didUpdateWidget(HermesBotAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncMotion();
  }

  void _syncMotion() {
    if (!widget.active || context.reduceMotion) {
      _controller
        ..stop()
        ..value = 0;
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Hermez draws every bot with its own mark (the reference bot family),
    // derived from the profile name, so chats, lists, and Home agree.
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) => Transform.translate(
        offset: Offset(
          0,
          widget.active && !context.reduceMotion
              ? -widget.size *
                    0.03 *
                    (1 - math.cos(2 * math.pi * _controller.value))
              : 0,
        ),
        child: child,
      ),
      child: RepaintBoundary(
        child: HermezBotMark(
          identity: hermezIdentityForName(widget.label),
          size: widget.size,
          label: widget.label,
        ),
      ),
    );
  }
}
