import 'dart:async';

import 'package:flutter/material.dart';

import '../../../shared/theme/theme_extensions.dart';
import '../motion/hermez_motion.dart';
import 'hermes_run_actions.dart';
import 'hermez_chat_palette.dart';

/// One pill in a row of run actions. A pill with [onSubmit] stretches into a
/// field across its row, the way Steer does; one with [onTap] simply acts.
@immutable
class HermezPillAction {
  const HermezPillAction({
    required this.label,
    required this.icon,
    this.onSubmit,
    this.onTap,
    this.hint,
    this.emphasized = false,
    this.quiet = false,
    this.busy = false,
    this.emptyText,
  });

  final String label;
  final IconData icon;

  /// Sends what was typed; the field folds away only when this returns true.
  final Future<bool> Function(String text)? onSubmit;
  final VoidCallback? onTap;
  final String? hint;
  final bool emphasized;
  final bool quiet;
  final bool busy;

  /// Sent from the keyboard's send key when the field is empty (for an
  /// action that means something on its own, such as Replan). Without it an
  /// empty field can only be closed.
  final String? emptyText;

  bool get opensField => onSubmit != null;
}

/// A row of [HermezRunPill]s where a field pill grows into a one-line field
/// spanning the row, exactly like the inline run's Steer: the pill's edge
/// and fill ride a travelling rectangle on the medium spring (the light
/// spring, mirrored, on the way back), the field is laid out once at its
/// final width and uncovered by that edge, and the send control grows in at
/// the moving edge once there is room. Back folds the field away first.
class HermezActionPills extends StatefulWidget {
  const HermezActionPills({super.key, required this.actions});

  final List<HermezPillAction> actions;

  @override
  State<HermezActionPills> createState() => _HermezActionPillsState();
}

class _HermezActionPillsState extends State<HermezActionPills>
    with SingleTickerProviderStateMixin {
  final GlobalKey _stackKey = GlobalKey();
  final List<GlobalKey> _pillKeys = [];
  final TextEditingController _text = TextEditingController();
  final FocusNode _focus = FocusNode(debugLabel: 'hermez-action-field');
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
  int? _openIndex;
  bool _open = false;
  bool _sending = false;

  @override
  void didUpdateWidget(covariant HermezActionPills oldWidget) {
    super.didUpdateWidget(oldWidget);
    final index = _openIndex;
    // The action went away (the step finished, the delegate ended).
    if (_open &&
        (index == null ||
            index >= widget.actions.length ||
            !widget.actions[index].opensField)) {
      _close();
    }
  }

  @override
  void dispose() {
    _morph.dispose();
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  GlobalKey _keyFor(int index) {
    while (_pillKeys.length <= index) {
      _pillKeys.add(GlobalKey());
    }
    return _pillKeys[index];
  }

  void _openField(int index) {
    if (_open) return;
    // Measured in a tap handler, after layout: never during a build.
    final pill = _keyFor(index).currentContext?.findRenderObject();
    final stack = _stackKey.currentContext?.findRenderObject();
    if (pill is! RenderBox || stack is! RenderBox || !pill.hasSize) return;
    final topLeft = pill.localToGlobal(Offset.zero, ancestor: stack);
    setState(() {
      _from = topLeft & pill.size;
      _openIndex = index;
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
      setState(() {
        _from = null;
        _openIndex = null;
      });
    }

    if (context.reduceMotion) {
      _morph.value = 0;
      clear();
      return;
    }
    unawaited(_morph.reverse().whenComplete(clear));
  }

  Future<void> _send({bool fromKeyboard = false}) async {
    final index = _openIndex;
    if (index == null || index >= widget.actions.length || _sending) return;
    final action = widget.actions[index];
    final submit = action.onSubmit;
    var text = _text.text.trim();
    if (text.isEmpty && fromKeyboard) text = action.emptyText ?? '';
    if (submit == null || text.isEmpty) return;
    setState(() => _sending = true);
    var accepted = false;
    try {
      accepted = await submit(text);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
    if (mounted && accepted) _close();
  }

  @override
  Widget build(BuildContext context) {
    final palette = HermezChatPalette.forBrightness(
      Theme.of(context).brightness,
    );
    final index = _openIndex;
    final open = index != null && index < widget.actions.length
        ? widget.actions[index]
        : null;
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
                  for (final (i, action) in widget.actions.indexed)
                    KeyedSubtree(
                      key: _keyFor(i),
                      child: HermezRunPill(
                        label: action.label,
                        icon: action.icon,
                        emphasized: action.emphasized,
                        quiet: action.quiet,
                        busy: action.busy,
                        onTap: action.opensField
                            ? () => _openField(i)
                            : action.onTap,
                      ),
                    ),
                ],
              ),
              if ((_from, open) case (final from?, final action?))
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
                      child: _PillField(
                        palette: palette,
                        action: action,
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

/// A pill at any point between pill and field. Its icon and label never
/// move; the field is uncovered by the travelling edge.
class _PillField extends StatelessWidget {
  const _PillField({
    required this.palette,
    required this.action,
    required this.width,
    required this.progress,
    required this.text,
    required this.focus,
    required this.sending,
    required this.onSend,
    required this.onClose,
  });

  final HermezChatPalette palette;
  final HermezPillAction action;
  final double width;
  final double progress;
  final TextEditingController text;
  final FocusNode focus;
  final bool sending;
  final Future<void> Function({bool fromKeyboard}) onSend;
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
                // Same insets as the pill, so the icon and label stay put.
                padding: EdgeInsetsDirectional.fromSTEB(
                  HermezRunPill.padding.left,
                  HermezRunPill.padding.top,
                  48,
                  HermezRunPill.padding.bottom,
                ),
                child: Row(
                  children: [
                    Icon(action.icon, size: 18, color: palette.ink),
                    const SizedBox(width: 7),
                    Text(
                      action.label,
                      style: HermezRunPill.labelStyle(palette.ink),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: text,
                        focusNode: focus,
                        maxLines: 1,
                        maxLength: 1000,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => onSend(fromKeyboard: true),
                        style: TextStyle(color: palette.ink, fontSize: 15),
                        cursorColor: palette.accent,
                        // The pill is the field's edge: the theme's focused
                        // border must not draw a second one inside.
                        decoration: InputDecoration(
                          isCollapsed: true,
                          filled: false,
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          disabledBorder: InputBorder.none,
                          counterText: '',
                          hintText: action.hint ?? 'Say more',
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
                    builder: (context, _) => _FieldControl(
                      palette: palette,
                      canSend: text.text.trim().isNotEmpty,
                      sending: sending,
                      onSend: () => onSend(),
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
/// glyph turns in place between the two, as on Steer.
class _FieldControl extends StatelessWidget {
  const _FieldControl({
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
      message: canSend ? 'Send to Hermes' : 'Close',
      child: HermezMotionSurface(
        weight: HermezMotionWeight.light,
        semanticLabel: canSend ? 'Send to Hermes' : 'Close',
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
