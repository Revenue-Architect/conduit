import 'package:flutter/material.dart';

import '../../hermes/widgets/hermez_chat_palette.dart';
import '../../hermes/widgets/hermez_surfaces.dart';
import '../services/hermes_spaces_client.dart';
import '../../hermes/widgets/hermez_skeleton.dart';

HermezChatPalette _palette(BuildContext context) =>
    HermezChatPalette.forBrightness(Theme.of(context).brightness);

class SpacesLoadingState extends StatelessWidget {
  const SpacesLoadingState({super.key});

  @override
  Widget build(BuildContext context) => ListView(
    physics: const AlwaysScrollableScrollPhysics(),
    padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
    children: [HermezSkeleton.rows(count: 5)],
  );
}

class SpacesEmptyState extends StatelessWidget {
  const SpacesEmptyState({
    super.key,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final palette = _palette(context);
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(28, 72, 28, 28),
      children: [
        Icon(Icons.article_outlined, size: 40, color: palette.muted),
        const SizedBox(height: 14),
        Text(
          title,
          textAlign: TextAlign.center,
          style: HermezType.body(palette)
              .copyWith(fontWeight: FontWeight.w800, fontSize: 17),
        ),
        const SizedBox(height: 6),
        Text(
          message,
          textAlign: TextAlign.center,
          style: HermezType.meta(palette),
        ),
        if (actionLabel != null && onAction != null) ...[
          const SizedBox(height: 18),
          Center(
            child: FilledButton.icon(
              onPressed: onAction,
              icon: const Icon(Icons.add_rounded),
              label: Text(actionLabel!),
            ),
          ),
        ],
      ],
    );
  }
}

class SpacesErrorState extends StatelessWidget {
  const SpacesErrorState({
    super.key,
    required this.error,
    required this.onRetry,
  });

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final palette = _palette(context);
    final message = switch (error) {
      SpacesUnavailable() =>
        'Spaces is not installed on this Hermes. Ask your admin to enable '
            'the spaces plugin.',
      SpacesApiException(:final message) => message,
      _ => 'Could not load Spaces. Check your connection and retry.',
    };
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(28, 72, 28, 28),
      children: [
        Icon(Icons.cloud_off_rounded, size: 40, color: palette.muted),
        const SizedBox(height: 14),
        Text(
          message,
          textAlign: TextAlign.center,
          style: HermezType.body(palette),
        ),
        const SizedBox(height: 16),
        Center(
          child: OutlinedButton(onPressed: onRetry, child: const Text('Retry')),
        ),
      ],
    );
  }
}

void showSpacesError(BuildContext context, String message) {
  ScaffoldMessenger.maybeOf(context)
    ?..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}
