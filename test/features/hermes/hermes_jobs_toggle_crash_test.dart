import 'package:conduit/features/hermes/models/hermes_capabilities.dart';
import 'package:conduit/features/hermes/models/hermes_job.dart';
import 'package:conduit/features/hermes/motion/hermez_motion.dart';
import 'package:conduit/features/hermes/providers/hermes_providers.dart';
import 'package:conduit/features/hermes/views/hermes_jobs_page.dart';
import 'package:conduit/features/hermes/models/hermes_config.dart';
import 'package:conduit/features/hermes/services/hermes_api_service.dart';
import 'package:conduit/shared/widgets/platform_ui/platform_ui.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

// Scheduled agents kept a closed sheet's disposed drag notifier and threw
// on the next rebuild (on device: `_dependents.isEmpty`).
var _enabled = true;

class _C extends HermesJobsController {
  @override
  Future<List<HermesJob>> build() async {
    await Future<void>.delayed(const Duration(milliseconds: 200));
    return [
      HermesJob(
        id: 'job-1',
        name: 'Daily',
        prompt: 'p',
        schedule: '0 9 * * *',
        enabled: _enabled,
      ),
    ];
  }

  @override
  Future<void> setEnabled(String id, bool enabled) async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    _enabled = enabled;
    ref.invalidateSelf();
  }
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 100; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('toggling a job after a sheet closed, then Back, never throws', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final router = GoRouter(
      initialLocation: '/home',
      routes: [
        GoRoute(
          path: '/home',
          builder: (context, state) => Scaffold(
            body: Center(
              child: Builder(
                builder: (context) => HermezMotionSurface(
                  onOpen: (origin) => context.push('/jobs', extra: origin),
                  child: const SizedBox(
                    width: 200,
                    height: 100,
                    child: Text('Card'),
                  ),
                ),
              ),
            ),
          ),
        ),
        GoRoute(
          path: '/jobs',
          pageBuilder: (context, state) => buildHermezMotionPage(
            pageKey: state.pageKey,
            child: const HermesJobsPage(),
            motion: HermezRouteMotion.expand,
            origin: state.extra as HermezMorphOrigin?,
          ),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          hermesJobsProvider.overrideWith(_C.new),
          hermesCapabilitiesProvider.overrideWith(
            (ref) async => const HermesCapabilities(),
          ),
          hermesApiServiceProvider.overrideWithValue(
            HermesApiService(
              config: const HermesConfig(
                enabled: true,
                baseUrl: 'https://h.example',
                apiKey: 'k',
              ),
            ),
          ),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await _settle(tester);
    await tester.tap(find.text('Card'));
    await _settle(tester);
    // Open the job's edit sheet and close it.
    await tester.tap(find.byIcon(Icons.edit_outlined));
    await _settle(tester);
    await tester.binding.handlePopRoute();
    await _settle(tester);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byType(AdaptiveSwitch).first);
    await _settle(tester);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byType(AdaptiveSwitch).first);
    await _settle(tester);
    expect(tester.takeException(), isNull);
    await tester.binding.handlePopRoute();
    await _settle(tester);
    expect(tester.takeException(), isNull);
  });
}
