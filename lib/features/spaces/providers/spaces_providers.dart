import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../hermes/providers/hermes_providers.dart';
import '../models/spaces_models.dart';
import '../services/hermes_spaces_client.dart';

/// The Spaces client for the connected Hermes, or null when its sign-in
/// cannot reach plugin routes.
final hermesSpacesClientProvider = Provider<HermesSpacesClient?>((ref) {
  final service = ref.watch(hermesApiServiceProvider);
  final config = ref.watch(hermesConfigProvider);
  return HermesSpacesClient.forService(service, config);
});

/// Whether this Hermes has the Spaces plugin. Any failure is "no": an older
/// Hermes simply does not show Spaces.
final spacesAvailableProvider = FutureProvider<bool>((ref) async {
  final client = ref.watch(hermesSpacesClientProvider);
  var available = false;
  if (client != null) {
    try {
      available = await client.available();
    } catch (_) {
      available = false;
    }
  }
  ref.read(spacesConfirmedProvider.notifier).set(available);
  return available;
});

/// The last answer of [spacesAvailableProvider], without starting it. For
/// UI that appears many times (every assistant reply) and must not open a
/// Hermes connection or probe on its own.
final spacesConfirmedProvider = NotifierProvider<SpacesConfirmed, bool>(
  SpacesConfirmed.new,
);

class SpacesConfirmed extends Notifier<bool> {
  @override
  bool build() => false;

  void set(bool value) => state = value;
}

final spacesListProvider = FutureProvider.autoDispose<List<HermesSpace>>((
  ref,
) async {
  final client = ref.watch(hermesSpacesClientProvider);
  if (client == null) throw const SpacesUnavailable();
  return client.spaces();
});

typedef SpacePagesQuery = ({String spaceId, String query, bool byName});

final spacePagesProvider = FutureProvider.autoDispose
    .family<List<HermesPageSummary>, SpacePagesQuery>((ref, args) async {
      final client = ref.watch(hermesSpacesClientProvider);
      if (client == null) throw const SpacesUnavailable();
      return client.pages(args.spaceId, query: args.query, byName: args.byName);
    });

/// The Hermes profile a Page's "Ask" opens by default: kai when it exists,
/// otherwise the first bot.
const spacesDefaultProfile = 'kai';

/// The Page a Hermes conversation belongs to, or null (also when Spaces is
/// unavailable or the lookup fails: this only decorates the chat).
final pageForSessionProvider = FutureProvider.autoDispose
    .family<HermesPageSummary?, String>((ref, sessionId) async {
      if (ref.watch(spacesAvailableProvider).value != true) return null;
      final client = ref.watch(hermesSpacesClientProvider);
      if (client == null) return null;
      try {
        return await client.pageForSession(sessionId);
      } catch (_) {
        return null;
      }
    });
