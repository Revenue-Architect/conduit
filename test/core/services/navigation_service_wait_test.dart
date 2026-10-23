import 'package:conduit/core/services/navigation_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

GoRouter _router(String initial) => GoRouter(
  initialLocation: initial,
  routes: [
    GoRoute(path: '/splash', builder: (_, _) => const SizedBox()),
    GoRoute(path: '/home', builder: (_, _) => const SizedBox()),
  ],
);

void main() {
  test('completes immediately when already past the splash screen', () async {
    NavigationService.attachRouter(_router('/home'));
    await NavigationService.waitUntilLeft('/splash');
  });

  test('completes when the router leaves the splash screen', () async {
    final router = _router('/splash');
    NavigationService.attachRouter(router);
    var done = false;
    final wait = NavigationService.waitUntilLeft(
      '/splash',
    ).then((_) => done = true);
    await Future<void>.delayed(Duration.zero);
    expect(done, isFalse);
    router.go('/home');
    await wait;
    expect(done, isTrue);
  });

  test('gives up after the timeout instead of waiting forever', () async {
    NavigationService.attachRouter(_router('/splash'));
    await NavigationService.waitUntilLeft(
      '/splash',
      timeout: const Duration(milliseconds: 50),
    );
  });
}
