import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/services/haptic_service.dart';
import '../../../shared/theme/theme_extensions.dart';
import '../motion/hermez_motion.dart';
import 'hermez_chat_palette.dart';

/// A run control. The surface stays put and compresses; its label changes
/// in place while the action runs.
class HermezRunPill extends StatelessWidget {
  const HermezRunPill({
    super.key,
    required this.label,
    required this.icon,
    this.onTap,
    this.emphasized = false,
    this.quiet = false,
    this.busy = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onTap;
  final bool emphasized;
  final bool quiet;
  final bool busy;

  static const padding = EdgeInsets.symmetric(horizontal: 14, vertical: 9);
  static const minHeight = 42.0;

  static TextStyle labelStyle(Color color) =>
      TextStyle(color: color, fontWeight: FontWeight.w700);

  static BoxDecoration surface(HermezChatPalette palette) => BoxDecoration(
    color: palette.canvas,
    borderRadius: BorderRadius.circular(999),
    border: Border.all(color: palette.border.withValues(alpha: 0.8)),
  );

  @override
  Widget build(BuildContext context) {
    final palette = HermezChatPalette.forBrightness(
      Theme.of(context).brightness,
    );
    final enabled = onTap != null && !busy;
    final dark = emphasized;
    final foreground = dark
        ? const Color(0xFFF6F5F2)
        : enabled || busy
        ? palette.ink
        : palette.muted;
    return HermezMotionSurface(
      weight: HermezMotionWeight.light,
      semanticLabel: label,
      enabled: enabled,
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: minHeight),
        padding: padding,
        decoration: dark
            ? BoxDecoration(
                color: const Color(0xFF17181C),
                borderRadius: BorderRadius.circular(999),
              )
            : quiet
            ? null
            : surface(palette),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (busy)
              SizedBox.square(
                dimension: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: foreground,
                ),
              )
            else
              Icon(icon, size: 18, color: foreground),
            const SizedBox(width: 7),
            Flexible(child: Text(label, style: labelStyle(foreground))),
          ],
        ),
      ),
    );
  }
}

/// Run actions whose Steer pill grows into an inline field.
///
/// Steer is not a dialog. The pill itself stretches across its row into a
/// text field: its icon and label stay exactly where they were, the field
/// unrolls to the right, and the send control grows in at the moving edge.
/// Sending or closing contracts the field back into the pill.
class HermesRunActions extends StatefulWidget {
  const HermesRunActions({
    super.key,
    required this.onSteer,
    this.leading = const [],
    this.trailing = const [],
    this.showSteer = true,
  });

  /// Sends a steer. Returns whether Hermes accepted it; the field closes only
  /// then. Null when the run cannot be steered.
  final Future<bool> Function(String text)? onSteer;
  final List<Widget> leading;
  final List<Widget> trailing;

  /// Whether the Steer pill is shown at all, for runs that have ended.
  final bool showSteer;

  @override
  State<HermesRunActions> createState() => _HermesRunActionsState();
}

class _HermesRunActionsState extends State<HermesRunActions>
    with SingleTickerProviderStateMixin {
  final GlobalKey _stackKey = GlobalKey();
  final GlobalKey _pillKey = GlobalKey();
  final TextEditingController _text = TextEditingController();
  final FocusNode _focus = FocusNode(debugLabel: 'hermes-steer');
  late final AnimationController _morph = AnimationController(
    vsync: this,
    duration: HermezMotion.settleFor(HermezMotionWeight.medium),
    reverseDuration: HermezMotion.settleFor(HermezMotionWeight.light),
  );
  late final Animation<double> _progress = CurvedAnimation(
    parent: _morph,
    curve: HermezMotion.curveMedium,
    reverseCurve: HermezMotion.curveLight.flipped,
  );

  Rect? _from;
  bool _open = false;
  bool _sending = false;

  @override
  void didUpdateWidget(covariant HermesRunActions oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The run ended or can no longer be steered: fold the field away.
    if ((widget.onSteer == null || !widget.showSteer) && _open) _close();
  }

  @override
  void dispose() {
    _morph.dispose();
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _openField() {
    if (_open || widget.onSteer == null) return;
    // Measured in a tap handler, after layout: never during a build.
    final pill = _pillKey.currentContext?.findRenderObject();
    final stack = _stackKey.currentContext?.findRenderObject();
    if (pill is! RenderBox || stack is! RenderBox || !pill.hasSize) return;
    final topLeft = pill.localToGlobal(Offset.zero, ancestor: stack);
    setState(() {
      _from = topLeft & pill.size;
      _open = true;
    });
    // The field mounts this frame; focus it once it exists so the keyboard
    // rises together with the morph.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _open) _focus.requestFocus();
    });
    if (context.reduceMotion) {
      _morph.value = 1;
    } else {
      unawaited(_morph.forward());
    }
  }

  void _close() {
    if (!_open) return;
    _focus.unfocus();
    setState(() => _open = false);
    void clear() {
      if (!mounted || _open) return;
      _text.clear();
      setState(() => _from = null);
    }

    if (context.reduceMotion) {
      _morph.value = 0;
      clear();
      return;
    }
    unawaited(_morph.reverse().whenComplete(clear));
  }

  Future<void> _send() async {
    final steer = widget.onSteer;
    final text = _text.text.trim();
    if (steer == null || text.isEmpty || _sending) return;
    setState(() => _sending = true);
    var accepted = false;
    try {
      accepted = await steer(text);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
    if (!mounted || !accepted) return;
    unawaited(ConduitHaptics.success());
    _close();
  }

  @override
  Widget build(BuildContext context) {
    final palette = HermezChatPalette.forBrightness(
      Theme.of(context).brightness,
    );
    return PopScope(
      canPop: !_open,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _close();
      },
      child: LayoutBuilder(
        builder: (context, constraints) => SizedBox(
          width: constraints.maxWidth,
          child: Stack(
            key: _stackKey,
            clipBehavior: Clip.none,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ...widget.leading,
                  if (widget.showSteer)
                    KeyedSubtree(
                      key: _pillKey,
                      child: HermezRunPill(
                        label: 'Steer',
                        icon: Icons.edit_outlined,
                        onTap: widget.onSteer == null ? null : _openField,
                      ),
                    ),
                  ...widget.trailing,
                ],
              ),
              if (_from case final from? when widget.showSteer)
                AnimatedBuilder(
                  animation: _progress,
                  builder: (context, _) {
                    final t = _progress.value;
                    final to = Rect.fromLTWH(
                      0,
                      from.top,
                      constraints.maxWidth,
                      from.height,
                    );
                    return Positioned.fromRect(
                      rect: Rect.lerp(from, to, t)!,
                      child: _SteerField(
                        palette: palette,
                        width: to.width,
                        progress: t,
                        text: _text,
                        focus: _focus,
                        sending: _sending,
                        onSend: _send,
                        onClose: _close,
                      ),
                    );
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The Steer pill at any point between pill and field. The pill's edge and
/// fill ride the travelling rectangle; the field is laid out once at its
/// final width and uncovered by that edge, so nothing inside it reflows.
class _SteerField extends StatelessWidget {
  const _SteerField({
    required this.palette,
    required this.width,
    required this.progress,
    required this.text,
    required this.focus,
    required this.sending,
    required this.onSend,
    required this.onClose,
  });

  final HermezChatPalette palette;
  final double width;
  final double progress;
  final TextEditingController text;
  final FocusNode focus;
  final bool sending;
  final Future<void> Function() onSend;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    // The send control grows in once the field has room for it.
    final control = Curves.easeOut.transform(
      ((progress - 0.35) / 0.65).clamp(0.0, 1.0),
    );
    return DecoratedBox(
      decoration: HermezRunPill.surface(palette),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(999),
        child: Stack(
          fit: StackFit.expand,
          children: [
            OverflowBox(
              alignment: AlignmentDirectional.centerStart,
              minWidth: width,
              maxWidth: width,
              child: Padding(
                // Same insets as the pill, so the icon and label do not move.
                padding: EdgeInsetsDirectional.fromSTEB(
                  HermezRunPill.padding.left,
                  HermezRunPill.padding.top,
                  48,
                  HermezRunPill.padding.bottom,
                ),
                child: Row(
                  children: [
                    Icon(Icons.edit_outlined, size: 18, color: palette.ink),
                    const SizedBox(width: 7),
                    Text('Steer', style: HermezRunPill.labelStyle(palette.ink)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: text,
                        focusNode: focus,
                        maxLines: 1,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => onSend(),
                        style: TextStyle(color: palette.ink, fontSize: 15),
                        cursorColor: palette.accent,
                        decoration: InputDecoration.collapsed(
                          hintText: 'What should change?',
                          hintStyle: TextStyle(
                            color: palette.muted,
                            fontSize: 15,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            PositionedDirectional(
              end: 4,
              top: 0,
              bottom: 0,
              child: Center(
                child: Transform.scale(
                  scale: control,
                  child: ListenableBuilder(
                    listenable: text,
                    builder: (context, _) => _SteerControl(
                      palette: palette,
                      canSend: text.text.trim().isNotEmpty,
                      sending: sending,
                      onSend: onSend,
                      onClose: onClose,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Close while the field is empty; send once there is something to say. The
/// glyph turns in place between the two.
class _SteerControl extends StatelessWidget {
  const _SteerControl({
    required this.palette,
    required this.canSend,
    required this.sending,
    required this.onSend,
    required this.onClose,
  });

  final HermezChatPalette palette;
  final bool canSend;
  final bool sending;
  final Future<void> Function() onSend;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final filled = canSend || sending;
    return Tooltip(
      message: canSend ? 'Send to Hermes' : 'Close steer',
      child: HermezMotionSurface(
        weight: HermezMotionWeight.light,
        semanticLabel: canSend ? 'Send to Hermes' : 'Close steer',
        enabled: !sending,
        onTap: canSend ? () => unawaited(onSend()) : onClose,
        child: TweenAnimationBuilder<Color?>(
          tween: ColorTween(end: filled ? palette.accent : palette.canvas),
          duration: context.reduceMotion
              ? Duration.zero
              : HermezMotion.settleFor(HermezMotionWeight.light),
          curve: HermezMotion.curveLight,
          builder: (context, fill, child) => DecoratedBox(
            decoration: BoxDecoration(color: fill, shape: BoxShape.circle),
            child: child,
          ),
          child: SizedBox.square(
            dimension: 34,
            child: Center(
              child: sending
                  ? SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: palette.onAccent,
                      ),
                    )
                  : HermezIconSwap(
                      icon: canSend
                          ? Icons.arrow_upward_rounded
                          : Icons.close_rounded,
                      color: canSend ? palette.onAccent : palette.ink,
                      size: 18,
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
