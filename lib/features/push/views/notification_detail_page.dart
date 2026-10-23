import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../hermes/views/hermes_page_chrome.dart';
import '../providers/push_providers.dart';
import '../services/push_gateway_client.dart';

final notificationDetailProvider = FutureProvider.autoDispose
    .family<PushNotificationDetail, ({String reference, String? kind})>((
      ref,
      key,
    ) async {
      // Pairing hydrates asynchronously during a cold notification launch.
      await ref.watch(pushPairingProvider.future);
      final client = ref.watch(pushGatewayClientProvider);
      if (client == null) {
        throw const PushGatewayException(
          message: 'Pair this phone in Notifications to read the update.',
        );
      }
      return client.getNotification(key.reference, kind: key.kind);
    }, retry: (retryCount, error) => null);

/// A notification without a conversation still opens its actual saved content.
/// Never substitute a new chat or infer an origin from its title/category.
class NotificationDetailPage extends ConsumerWidget {
  const NotificationDetailPage({
    super.key,
    required this.reference,
    this.referenceKind,
  });
  final String reference;
  final String? referenceKind;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = notificationDetailProvider((
      reference: reference,
      kind: referenceKind,
    ));
    final detail = ref.watch(provider);
    return HermesPageChrome(
      title: 'Notification',
      subtitle: 'Saved update',
      actions: [
        IconButton(
          tooltip: 'Refresh',
          onPressed: () => ref.invalidate(provider),
          icon: const Icon(Icons.refresh_rounded),
        ),
      ],
      child: detail.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  error is PushGatewayException
                      ? error.message
                      : 'Could not load this update.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: () => ref.invalidate(provider),
                  child: const Text('Try again'),
                ),
              ],
            ),
          ),
        ),
        data: (item) => ListView(
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 32),
          children: [
            SelectableText(
              item.title,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            SelectableText(item.body),
            if (item.sourceUrl != null) ...[
              const SizedBox(height: 16),
              TextButton.icon(
                onPressed: () async {
                  var opened = false;
                  try {
                    opened = await launchUrl(
                      Uri.parse(item.sourceUrl!),
                      mode: LaunchMode.externalApplication,
                    );
                  } catch (_) {}
                  if (!opened && context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Could not open the source.'),
                      ),
                    );
                  }
                },
                icon: const Icon(Icons.open_in_new_rounded),
                label: const Text('Open full source'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
