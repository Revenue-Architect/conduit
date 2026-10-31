import 'package:flutter/material.dart';

import '../../../shared/theme/theme_extensions.dart';
import '../widgets/hermez_chat_palette.dart';
import 'hermez_card_route.dart';

/// One step inside a card: its title and its content.
@immutable
class HermezCardView {
  HermezCardView({required this.title, required this.builder})
    : key = GlobalKey();

  final String title;
  final WidgetBuilder builder;

  /// Keeps the step's state (typed text, scroll) while a deeper step is on
  /// top, so going back finds it as it was.
  final GlobalKey key;
}

/// The inside of a one-card surface (docs/app-design-2026-10-30, "One
/// card"): nothing opened from a card opens anything new. A nested step
/// pushes onto this stack and the same card reshapes to it: its height
/// springs, the new content slides 8 dp and fades in, and the header gains
/// ‹ back. Lower steps stay mounted and hidden, so their input survives.
/// × closes the whole card, which folds back into the control it came from.
class HermezCardStack extends StatefulWidget {
  const HermezCardStack({super.key, required this.root, this.onClose});

  final HermezCardView root;

  /// Closes the card; defaults to popping the route it lives in.
  final VoidCallback? onClose;

  static HermezCardStackState of(BuildContext context) =>
      context.findAncestorStateOfType<HermezCardStackState>()!;

  @override
  State<HermezCardStack> createState() => HermezCardStackState();
}

class HermezCardStackState extends State<HermezCardStack>
    with SingleTickerProviderStateMixin {
  late final List<HermezCardView> _views = [widget.root];

  /// The step leaving the card while the next one arrives: the one pushed
  /// over, or the one popped.
  HermezCardView? _leaving;

  /// 0 to 1 as one step cross-fades into the next (the reference's ~200 ms).
  late final AnimationController _swap =
      AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 280),
        value: 1,
      )..addStatusListener((status) {
        if (status == AnimationStatus.completed && _leaving != null) {
          setState(() => _leaving = null);
        }
      });

  int get depth => _views.length - 1;

  void push(HermezCardView view) {
    setState(() {
      _leaving = _views.last;
      _views.add(view);
    });
    _start();
  }

  void pop() {
    if (_views.length < 2) return;
    setState(() => _leaving = _views.removeLast());
    _start();
  }

  void _start() {
    if (MediaQuery.of(context).disableAnimations) {
      _swap.value = 1;
      _leaving = null;
    } else {
      _swap.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _swap.dispose();
    super.dispose();
  }

  void _close() => widget.onClose != null
      ? widget.onClose!()
      : Navigator.of(context).maybePop();

  // Opacity only: a blur per frame on a whole step dropped frames on the
  // phone.
  static Widget _fade(double opacity, Widget child) =>
      Opacity(opacity: opacity.clamp(0.0, 1.0), child: child);

  Widget _step(HermezCardView view) => KeyedSubtree(
    key: view.key,
    child: Builder(builder: view.builder),
  );

  @override
  Widget build(BuildContext context) {
    final palette = HermezChatPalette.forBrightness(
      Theme.of(context).brightness,
    );
    final top = _views.last;
    final reduce = MediaQuery.of(context).disableAnimations;
    final leaving = _leaving;
    return PopScope(
      // System Back pops a step before it closes the card.
      canPop: _views.length == 1,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) pop();
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(_views.length > 1 ? 2 : 18, 4, 4, 8),
            child: Row(
              children: [
                if (_views.length > 1)
                  IconButton(
                    tooltip: 'Back',
                    onPressed: pop,
                    icon: Icon(Icons.chevron_left_rounded, color: palette.ink),
                  ),
                Expanded(
                  // The title cross-fades with its step.
                  child: AnimatedSwitcher(
                    duration: reduce
                        ? Duration.zero
                        : const Duration(milliseconds: 200),
                    layoutBuilder: (current, previous) => Stack(
                      alignment: Alignment.centerLeft,
                      children: [...previous, ?current],
                    ),
                    transitionBuilder: (child, animation) => AnimatedBuilder(
                      animation: animation,
                      builder: (context, c) => _fade(animation.value, c!),
                      child: child,
                    ),
                    child: Text(
                      top.title,
                      key: ValueKey(top.key),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: AppTypography.fontFamily,
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.3,
                        color: palette.ink,
                      ),
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Close',
                  onPressed: _close,
                  style: IconButton.styleFrom(backgroundColor: palette.surface),
                  icon: Icon(
                    Icons.close_rounded,
                    size: 18,
                    color: palette.muted,
                  ),
                ),
              ],
            ),
          ),
          AnimatedSize(
            // The same card reshapes with the reference's springy settle.
            duration: reduce
                ? Duration.zero
                : const Duration(milliseconds: 330),
            curve: const Cubic(0.34, 1.28, 0.64, 1),
            alignment: Alignment.topCenter,
            child: AnimatedBuilder(
              animation: _swap,
              builder: (context, _) {
                final v = Curves.easeOut.transform(_swap.value);
                return Stack(
                  clipBehavior: Clip.hardEdge,
                  children: [
                    // Lower steps stay mounted (and keep their input) unseen.
                    for (final view in _views)
                      if (view != top && view != leaving)
                        Offstage(
                          child: TickerMode(enabled: false, child: _step(view)),
                        ),
                    _fade(leaving == null ? 1 : v, _step(top)),
                    if (leaving != null)
                      Positioned(
                        top: 0,
                        left: 0,
                        right: 0,
                        child: IgnorePointer(
                          child: _fade(1 - v, _step(leaving)),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// A yes/no question as a one card: it grows out of the control in [from]
/// (the button that asked) and folds back into it. With [fromIsControl]
/// false, [from] is only where to push and the card grows out of the last
/// pressed control instead. Returns true only when the owner picks
/// [confirmLabel]; closing the card never confirms. [destructive] paints the
/// confirm in the failure red.
Future<bool> confirmHermezCard(
  BuildContext from, {
  required String title,
  required String body,
  required String confirmLabel,
  String cancelLabel = 'Cancel',
  bool destructive = false,
  bool fromIsControl = true,
}) async {
  final palette = HermezChatPalette.forBrightness(Theme.of(from).brightness);
  Widget content(BuildContext panelContext) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 10, 4, 14),
    child: HermezCardStack(
      root: HermezCardView(
        title: title,
        builder: (context) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                body,
                style: TextStyle(
                  fontFamily: AppTypography.fontFamily,
                  fontSize: 15,
                  height: 1.45,
                  color: palette.muted,
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.tonal(
                      onPressed: () => Navigator.pop(panelContext, false),
                      child: Text(cancelLabel),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: destructive
                            ? palette.failed
                            : palette.accent,
                        foregroundColor: destructive
                            ? palette.raised
                            : palette.onAccent,
                      ),
                      onPressed: () => Navigator.pop(panelContext, true),
                      child: Text(confirmLabel),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );
  final answer = await pushHermezCard<bool>(
    from,
    from: fromIsControl ? from : null,
    builder: content,
    semanticLabel: title,
  );
  return answer ?? false;
}

/// Asks for one line of text as a one card (rename, create). Returns the
/// trimmed text, or null when closed, empty or unchanged.
Future<String?> promptHermezCard(
  BuildContext context, {
  required String title,
  required String hintText,
  String? initialValue,
  required String confirmLabel,
  String cancelLabel = 'Cancel',
  TextInputType? keyboardType,
  TextCapitalization textCapitalization = TextCapitalization.sentences,
  int? maxLength,
}) async {
  final value = await pushHermezCard<String>(
    context,
    semanticLabel: title,
    builder: (cardContext) => Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 14),
      child: HermezCardStack(
        root: HermezCardView(
          title: title,
          builder: (_) => _PromptField(
            hintText: hintText,
            initialValue: initialValue,
            confirmLabel: confirmLabel,
            cancelLabel: cancelLabel,
            keyboardType: keyboardType,
            textCapitalization: textCapitalization,
            maxLength: maxLength,
            onDone: (text) => Navigator.pop(cardContext, text),
          ),
        ),
      ),
    ),
  );
  final trimmed = value?.trim();
  if (trimmed == null || trimmed.isEmpty) return null;
  if (initialValue != null && trimmed == initialValue.trim()) return null;
  return trimmed;
}

class _PromptField extends StatefulWidget {
  const _PromptField({
    required this.hintText,
    required this.initialValue,
    required this.confirmLabel,
    required this.cancelLabel,
    required this.keyboardType,
    required this.textCapitalization,
    required this.maxLength,
    required this.onDone,
  });

  final String hintText;
  final String? initialValue;
  final String confirmLabel;
  final String cancelLabel;
  final TextInputType? keyboardType;
  final TextCapitalization textCapitalization;
  final int? maxLength;
  final ValueChanged<String?> onDone;

  @override
  State<_PromptField> createState() => _PromptFieldState();
}

class _PromptFieldState extends State<_PromptField> {
  late final _controller = TextEditingController(text: widget.initialValue);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = HermezChatPalette.forBrightness(
      Theme.of(context).brightness,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _controller,
            autofocus: true,
            keyboardType: widget.keyboardType,
            textCapitalization: widget.textCapitalization,
            maxLength: widget.maxLength,
            onSubmitted: widget.onDone,
            style: TextStyle(
              fontFamily: AppTypography.fontFamily,
              fontSize: 15,
              color: palette.ink,
            ),
            decoration: InputDecoration(
              hintText: widget.hintText,
              enabledBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: palette.border),
              ),
              focusedBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: palette.ink, width: 2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: FilledButton.tonal(
                  onPressed: () => widget.onDone(null),
                  child: Text(widget.cancelLabel),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: palette.accent,
                    foregroundColor: palette.onAccent,
                  ),
                  onPressed: () => widget.onDone(_controller.text),
                  child: Text(widget.confirmLabel),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
