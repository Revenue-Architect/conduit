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

class HermezCardStackState extends State<HermezCardStack> {
  late final List<HermezCardView> _views = [widget.root];

  int get depth => _views.length - 1;

  void push(HermezCardView view) => setState(() => _views.add(view));

  void pop() {
    if (_views.length > 1) setState(_views.removeLast);
  }

  void _close() => widget.onClose != null
      ? widget.onClose!()
      : Navigator.of(context).maybePop();

  @override
  Widget build(BuildContext context) {
    final palette = HermezChatPalette.forBrightness(
      Theme.of(context).brightness,
    );
    final top = _views.last;
    final reduce = MediaQuery.of(context).disableAnimations;
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
                  child: Text(
                    top.title,
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
            duration: reduce
                ? Duration.zero
                : const Duration(milliseconds: 320),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: Stack(
              children: [
                for (var i = 0; i < _views.length; i++)
                  Offstage(
                    offstage: i != _views.length - 1,
                    child: TickerMode(
                      enabled: i == _views.length - 1,
                      child: _SlideIn(
                        active: i == _views.length - 1,
                        reduce: reduce,
                        child: KeyedSubtree(
                          key: _views[i].key,
                          child: Builder(builder: _views[i].builder),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Slides a step 8 dp into place and fades it in each time it becomes the
/// one on top. Its structure never changes, so the step keeps its state.
class _SlideIn extends StatefulWidget {
  const _SlideIn({
    required this.active,
    required this.reduce,
    required this.child,
  });

  final bool active;
  final bool reduce;
  final Widget child;

  @override
  State<_SlideIn> createState() => _SlideInState();
}

class _SlideInState extends State<_SlideIn>
    with SingleTickerProviderStateMixin {
  late final AnimationController _t = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
    value: 1,
  );

  @override
  void didUpdateWidget(_SlideIn old) {
    super.didUpdateWidget(old);
    if (widget.active && !old.active && !widget.reduce) _t.forward(from: 0);
  }

  @override
  void dispose() {
    _t.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _t,
    builder: (context, child) {
      final v = Curves.easeOutCubic.transform(_t.value);
      return Opacity(
        opacity: v,
        child: Transform.translate(
          offset: Offset(8 * (1 - v), 0),
          child: child,
        ),
      );
    },
    child: widget.child,
  );
}

/// A yes/no question as a one card: it grows out of the control in [from]
/// (the button that asked) and folds back into it. Returns true only when
/// the owner picks [confirmLabel]; closing the card never confirms.
Future<bool> confirmHermezCard(
  BuildContext from, {
  required String title,
  required String body,
  required String confirmLabel,
  String cancelLabel = 'Cancel',
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
                        backgroundColor: palette.accent,
                        foregroundColor: palette.onAccent,
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
    from: from,
    builder: content,
    semanticLabel: title,
  );
  return answer ?? false;
}
