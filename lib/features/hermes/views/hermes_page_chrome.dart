import 'package:flutter/material.dart';
import 'package:nib_motion/nib_motion.dart';

import '../../../shared/theme/theme_extensions.dart';
import '../feedback/hermez_feedback.dart';
import '../motion/hermez_motion.dart';
import '../widgets/hermez_chat_palette.dart';
import '../widgets/hermez_technical_background.dart';
import '../widgets/hermez_visual_theme.dart';

/// Shared native chrome for Hermes-owned destinations. Content is always real
/// Hermes data; this widget owns presentation only.
///
/// The large title scrolls away with the content; once it has gone under
/// the app bar a compact title takes its place over a hairline, the way a
/// large-title page settles on iOS.
class HermesPageChrome extends StatefulWidget {
  const HermesPageChrome({
    super.key,
    required this.title,
    required this.subtitle,
    required this.child,
    this.actions = const [],
    this.showHeader = true,
    this.titleMorphId,
    this.leading,
  });

  final String title;
  final String subtitle;
  final Widget child;
  final List<Widget> actions;

  /// False when the page draws its own header (for example a shared object
  /// that arrives from the previous screen).
  final bool showHeader;

  /// Lets the page title arrive as the title of the object that opened it.
  final String? titleMorphId;

  /// The app bar's leading control, such as Home's navigation button.
  final Widget? leading;

  static TextStyle titleStyle(HermezChatPalette palette) => TextStyle(
    color: palette.ink,
    fontSize: 34,
    fontWeight: FontWeight.w900,
    letterSpacing: -1.5,
    height: 1.05,
  );

  @override
  State<HermesPageChrome> createState() => _HermesPageChromeState();
}

class _HermesPageChromeState extends State<HermesPageChrome> {
  final ScrollController _outer = ScrollController();

  /// 0 while the large title shows, 1 once it is under the app bar.
  final ValueNotifier<double> _collapsed = ValueNotifier(0);

  @override
  void initState() {
    super.initState();
    _outer.addListener(_track);
  }

  void _track() {
    if (!_outer.hasClients) return;
    final offset = _outer.positions.isEmpty ? 0.0 : _outer.offset;
    _collapsed.value = ((offset - 28) / 34).clamp(0.0, 1.0);
  }

  @override
  void dispose() {
    _outer
      ..removeListener(_track)
      ..dispose();
    _collapsed.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = HermezChatPalette.forBrightness(
      Theme.of(context).brightness,
    );
    // Hermez is on screen: start interface audio in the background (once).
    HermezFeedback.instance.warmUp();
    final header = HermezPageHeader(
      title: widget.title,
      subtitle: widget.subtitle,
      titleMorphId: widget.titleMorphId,
      palette: palette,
    );
    return NibMotionConfig(
      reducedMotion: context.reduceMotion,
      entranceWarmup: Duration.zero,
      child: Theme(
        data: hermezVisualTheme(Theme.of(context)),
        child: HermezRouteCanvas(
          color: palette.canvas,
          child: Scaffold(
            backgroundColor: Colors.transparent,
            appBar: AppBar(
              backgroundColor: Colors.transparent,
              surfaceTintColor: Colors.transparent,
              scrolledUnderElevation: 0,
              leading: widget.leading,
              actions: widget.actions,
              centerTitle: true,
              flexibleSpace: widget.showHeader
                  ? ValueListenableBuilder<double>(
                      valueListenable: _collapsed,
                      builder: (context, t, _) => IgnorePointer(
                        child: ColoredBox(
                          color: Color.lerp(
                            palette.canvas.withValues(alpha: 0),
                            palette.canvas,
                            t,
                          )!,
                          child: Align(
                            alignment: Alignment.bottomCenter,
                            child: Transform.scale(
                              scaleX: t,
                              child: SizedBox(
                                height: 0.5,
                                width: double.infinity,
                                child: ColoredBox(color: palette.border),
                              ),
                            ),
                          ),
                        ),
                      ),
                    )
                  : null,
              title: widget.showHeader
                  ? ValueListenableBuilder<double>(
                      valueListenable: _collapsed,
                      builder: (context, t, _) => ExcludeSemantics(
                        excluding: t < 0.5,
                        child: ClipRect(
                          child: Transform.translate(
                            offset: Offset(0, 28 * (1 - t)),
                            child: Text(
                              widget.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: palette.ink,
                                fontSize: 17,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.3,
                              ),
                            ),
                          ),
                        ),
                      ),
                    )
                  : null,
            ),
            body: SafeArea(
              top: false,
              child: widget.showHeader
                  ? NestedScrollView(
                      controller: _outer,
                      headerSliverBuilder: (context, _) => [
                        SliverToBoxAdapter(child: header),
                      ],
                      body: widget.child,
                    )
                  : widget.child,
            ),
          ),
        ),
      ),
    );
  }
}

/// The Hermez page title block. The title can arrive from the card that
/// opened the page; the subtitle settles in behind it.
class HermezPageHeader extends StatelessWidget {
  const HermezPageHeader({
    super.key,
    required this.title,
    required this.subtitle,
    required this.palette,
    this.titleMorphId,
    this.motifMorphId,
  });

  final String title;
  final String subtitle;
  final HermezChatPalette palette;
  final String? titleMorphId;
  final String? motifMorphId;

  @override
  // Full width: the construction marks run to the edge of the section, not
  // to the end of the title.
  Widget build(BuildContext context) => SizedBox(
    width: double.infinity,
    child: HermezTechnicalBackground(
      variant: HermezBackgroundVariant.editorial,
      morphId: motifMorphId,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 2, 22, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            HermezMorphText(
              title,
              id: titleMorphId,
              maxLines: 2,
              style: HermesPageChrome.titleStyle(palette),
            ),
            const SizedBox(height: 4),
            HermezEntrance(
              order: 0,
              child: Text(
                subtitle,
                style: TextStyle(color: palette.muted, fontSize: 13),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// The page canvas. While the page grows out of a card it starts as that
/// card's surface color and settles to [color], so the growing aperture reads
/// as the same object. A color change, not an opacity change.
class HermezRouteCanvas extends StatelessWidget {
  const HermezRouteCanvas({
    super.key,
    required this.color,
    required this.child,
  });

  final Color color;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final route = ModalRoute.of(context);
    final animation = route?.animation;
    final originColor = route is HermezRouteTransitions
        ? route.origin?.color
        : null;
    if (animation == null ||
        originColor == null ||
        route is! HermezRouteTransitions ||
        route.effectiveMotion != HermezRouteMotion.expand) {
      return ColoredBox(color: color, child: child);
    }
    return AnimatedBuilder(
      animation: animation,
      child: child,
      builder: (context, child) => ColoredBox(
        color: Color.lerp(
          originColor,
          color,
          // Match the route: on Back the colour moves with the flipped spring,
          // so it starts changing immediately instead of lingering.
          (animation.status == AnimationStatus.reverse
                  ? HermezMotion.curveHeavy.flipped
                  : HermezMotion.curveHeavy)
              .transform(animation.value.clamp(0.0, 1.0)),
        )!,
        child: child,
      ),
    );
  }
}

class HermesPanel extends StatelessWidget {
  const HermesPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.onTap,
    this.backgroundVariant,
  });
  final Widget child;
  final EdgeInsets padding;
  final VoidCallback? onTap;
  final HermezBackgroundVariant? backgroundVariant;

  @override
  Widget build(BuildContext context) {
    final palette = HermezChatPalette.forBrightness(
      Theme.of(context).brightness,
    );
    return Material(
      color: palette.surface,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(19),
        side: BorderSide(color: palette.border),
      ),
      child: backgroundVariant == null
          ? _content()
          : HermezTechnicalBackground(
              variant: backgroundVariant!,
              child: _content(),
            ),
    );
  }

  Widget _content() => onTap == null
      ? Padding(padding: padding, child: child)
      : InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(19),
          child: Padding(padding: padding, child: child),
        );
}

class HermesSectionTitle extends StatelessWidget {
  const HermesSectionTitle(this.label, {super.key, this.trailing});
  final String label;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Wrap(
    alignment: WrapAlignment.spaceBetween,
    crossAxisAlignment: WrapCrossAlignment.center,
    spacing: 8,
    runSpacing: 4,
    children: [
      Text(
        label,
        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
      ),
      ?trailing,
    ],
  );
}
