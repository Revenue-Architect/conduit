import 'package:flutter/material.dart';
import 'package:nib_motion/nib_motion.dart';

import '../../../shared/theme/theme_extensions.dart';
import '../widgets/hermez_chat_palette.dart';
import '../widgets/hermez_technical_background.dart';
import '../widgets/hermez_visual_theme.dart';

/// Shared native chrome for Hermes-owned destinations. Content is always real
/// Hermes data; this widget owns presentation only.
class HermesPageChrome extends StatelessWidget {
  const HermesPageChrome({
    super.key,
    required this.title,
    required this.subtitle,
    required this.child,
    this.actions = const [],
  });

  final String title;
  final String subtitle;
  final Widget child;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final palette = HermezChatPalette.forBrightness(
      Theme.of(context).brightness,
    );
    return NibMotionConfig(
      reducedMotion: context.reduceMotion,
      entranceWarmup: Duration.zero,
      child: Theme(
      data: hermezVisualTheme(Theme.of(context)),
      child: Scaffold(
        backgroundColor: palette.canvas,
        appBar: AppBar(
          backgroundColor: palette.canvas,
          surfaceTintColor: Colors.transparent,
          scrolledUnderElevation: 0,
          actions: actions,
        ),
        body: SafeArea(
          top: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              HermezTechnicalBackground(
                variant: HermezBackgroundVariant.editorial,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(22, 2, 22, 18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          color: palette.ink,
                          fontSize: 34,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -1.5,
                          height: 1.05,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: TextStyle(color: palette.muted, fontSize: 13),
                      ),
                    ],
                  ),
                ),
              ),
              Expanded(child: child),
            ],
          ),
        ),
      ),
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
