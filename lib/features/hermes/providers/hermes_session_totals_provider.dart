import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'hermes_providers.dart';
import '../services/hermes_desktop_api_service.dart';

/// Total conversations per profile, not just the visible recent-session page.
final hermesSessionTotalsProvider =
    FutureProvider.autoDispose<Map<String, int>>((ref) async {
      final service = ref.watch(hermesApiServiceProvider);
      if (service is! HermesDesktopApiService) return const {};
      return service.sessionTotalsByProfile();
    });
