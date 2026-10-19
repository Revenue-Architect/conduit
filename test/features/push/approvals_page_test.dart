import 'package:checks/checks.dart';
import 'package:conduit/core/services/navigation_service.dart';
import 'package:conduit/core/services/secure_credential_storage.dart';
import 'package:conduit/features/push/models/approval.dart';
import 'package:conduit/features/push/platform/conduit_push_api.g.dart';
import 'package:conduit/features/push/providers/push_providers.dart';
import 'package:conduit/features/push/services/push_gateway_client.dart';
import 'package:conduit/features/push/services/push_registration_service.dart';
import 'package:conduit/features/push/views/approval_detail_page.dart';
import 'package:conduit/features/push/views/approvals_page.dart';
import 'package:conduit/features/push/views/hold_to_confirm_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

class _MockClient extends Mock implements PushGatewayClient {}

Approval _approval({
  String id = 'a-1',
  String status = 'pending',
  String description = 'Restart the changedetection container',
  String? digest = 'dg-1',
  Duration expiresIn = const Duration(minutes: 30),
}) {
  final now = DateTime.now();
  return Approval.fromJson({
    'id': id,
    'action_type': 'restart_container',
    'description': description,
    'status': status,
    'created_at': now.subtract(const Duration(minutes: 5)).toIso8601String(),
    'expires_at': now.add(expiresIn).toIso8601String(),
    'requested_by': 'chief',
    'payload_digest': ?digest,
    'payload': {'container': 'changedetection'},
    if (status != 'pending')
      'resolved_at': now.subtract(const Duration(minutes: 1)).toIso8601String(),
    if (status == 'approved') 'resolved_by': 'conduit:dev-1',
    if (status == 'approved') 'decided_via': 'conduit',
  })!;
}

void main() {
  late _MockClient client;

  setUpAll(() {
    registerFallbackValue(ApprovalDecision.approve);
  });

  setUp(() {
    client = _MockClient();
  });

  List<Override> overrides({bool paired = true}) => [
    if (paired)
    pushPairingProvider.overrideWith(
      (ref) async => const PushDeviceSecrets(
        token: 'hpd_t',
        gateway: 'https://h:8450',
        deviceId: 'dev-1',
      ),
    ),
    if (paired) pushGatewayClientProvider.overrideWith((ref) => client),
    pushRegistrationServiceProvider.overrideWithValue(
      PushRegistrationService(
        host: ConduitPushHostApi(),
        secure: SecureCredentialStorage(instance: const FlutterSecureStorage()),
        isAndroid: false,
      ),
    ),
  ];

  Future<void> pumpPage(
    WidgetTester tester, {
    List<Override>? extra,
    bool paired = true,
    Widget page = const ApprovalsPage(),
  }) async {
    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final router = GoRouter(
      initialLocation: Routes.hermesApprovals,
      routes: [
        GoRoute(path: Routes.hermesApprovals, builder: (_, _) => page),
        GoRoute(
          path: Routes.hermesApproval,
          builder: (_, state) =>
              ApprovalDetailPage(approvalId: state.pathParameters['approvalId']!),
        ),
        GoRoute(
          path: Routes.hermesPushPairing,
          builder: (_, _) => const Scaffold(body: Text('PAIRING PAGE')),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [...overrides(paired: paired), ...?extra],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }

  void stubLists({
    List<Approval> pending = const [],
    List<Approval> history = const [],
    String? nextBefore,
  }) {
    when(
      () => client.listApprovals(
        status: 'pending',
        limit: any(named: 'limit'),
        before: any(named: 'before'),
      ),
    ).thenAnswer((_) async => ApprovalPage(items: pending));
    when(
      () => client.listApprovals(
        status: 'all',
        limit: any(named: 'limit'),
        before: any(named: 'before'),
      ),
    ).thenAnswer(
      (_) async => ApprovalPage(items: history, nextBefore: nextBefore),
    );
  }

  testWidgets('empty states for both sections', (tester) async {
    stubLists();
    await pumpPage(tester);
    await tester.pumpAndSettle();
    expect(find.text('Nothing is waiting on you.'), findsOneWidget);
    expect(find.text('No decided requests yet.'), findsOneWidget);
    expect(find.text('All clear'), findsOneWidget);
  });

  testWidgets('a pending request shows details and both decisions', (
    tester,
  ) async {
    stubLists(pending: [_approval()]);
    await pumpPage(tester);
    await tester.pumpAndSettle();
    expect(find.text('restart_container'), findsOneWidget);
    expect(find.text('Restart the changedetection container'), findsOneWidget);
    expect(find.text('1 request needs you'), findsOneWidget);
    expect(find.byType(HoldToConfirmButton), findsOneWidget);
    expect(find.text('Deny'), findsOneWidget);
    expect(find.textContaining('min left'), findsOneWidget);
  });

  testWidgets('a tap on Approve does nothing; holding sends the decision', (
    tester,
  ) async {
    stubLists(pending: [_approval()]);
    when(
      () => client.decide(
        id: 'a-1',
        decision: ApprovalDecision.approve,
        digest: 'dg-1',
        deviceId: 'dev-1',
      ),
    ).thenAnswer((_) async => ApprovalStatus.approved);
    await pumpPage(tester);
    await tester.pumpAndSettle();

    await tester.tap(find.byType(HoldToConfirmButton));
    await tester.pump(const Duration(milliseconds: 300));
    verifyNever(
      () => client.decide(
        id: any(named: 'id'),
        decision: any(named: 'decision'),
        digest: any(named: 'digest'),
        deviceId: any(named: 'deviceId'),
      ),
    );

    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(HoldToConfirmButton)),
    );
    await tester.pump(); // first frame starts the hold ticker
    await tester.pump(const Duration(milliseconds: 1500));
    await gesture.up();
    await tester.pump();
    verify(
      () => client.decide(
        id: 'a-1',
        decision: ApprovalDecision.approve,
        digest: 'dg-1',
        deviceId: 'dev-1',
      ),
    ).called(1);
    await tester.pumpAndSettle();
    expect(find.text('Approved.'), findsOneWidget);
  });

  testWidgets('Deny asks first, then sends', (tester) async {
    stubLists(pending: [_approval()]);
    when(
      () => client.decide(
        id: 'a-1',
        decision: ApprovalDecision.deny,
        digest: 'dg-1',
        deviceId: 'dev-1',
      ),
    ).thenAnswer((_) async => ApprovalStatus.denied);
    await pumpPage(tester);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Deny'));
    await tester.pumpAndSettle();
    expect(find.text('Deny this request?'), findsOneWidget);
    // Cancel leaves it alone.
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    verifyNever(
      () => client.decide(
        id: any(named: 'id'),
        decision: any(named: 'decision'),
        digest: any(named: 'digest'),
        deviceId: any(named: 'deviceId'),
      ),
    );

    await tester.tap(find.text('Deny'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Deny'));
    await tester.pumpAndSettle();
    verify(
      () => client.decide(
        id: 'a-1',
        decision: ApprovalDecision.deny,
        digest: 'dg-1',
        deviceId: 'dev-1',
      ),
    ).called(1);
    expect(find.text('Denied.'), findsOneWidget);
  });

  testWidgets('a conflict is explained, not hidden', (tester) async {
    stubLists(pending: [_approval()]);
    when(
      () => client.decide(
        id: any(named: 'id'),
        decision: any(named: 'decision'),
        digest: any(named: 'digest'),
        deviceId: any(named: 'deviceId'),
      ),
    ).thenThrow(
      const PushGatewayException(
        message: 'This request was already decided.',
        statusCode: 409,
        currentStatus: ApprovalStatus.denied,
      ),
    );
    await pumpPage(tester);
    await tester.pumpAndSettle();
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(HoldToConfirmButton)),
    );
    await tester.pump(); // first frame starts the hold ticker
    await tester.pump(const Duration(milliseconds: 1500));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(find.text('Already denied.'), findsOneWidget);
  });

  testWidgets('a request without a verification code cannot be decided', (
    tester,
  ) async {
    stubLists(pending: [_approval(digest: null)]);
    await pumpPage(tester);
    await tester.pumpAndSettle();
    expect(find.byType(HoldToConfirmButton), findsNothing);
    expect(find.textContaining('Open the request to review'), findsOneWidget);
  });

  testWidgets('history shows results and loads older pages', (tester) async {
    final first = [
      _approval(id: 'h-1', status: 'approved'),
      _approval(id: 'h-2', status: 'expired', description: 'Old thing'),
    ];
    stubLists(history: first, nextBefore: '2026-10-01T00:00:00+00:00');
    await pumpPage(tester);
    await tester.pumpAndSettle();
    expect(find.textContaining('Approved by you in Hermez'), findsOneWidget);
    expect(find.text('Old thing'), findsOneWidget);
    expect(find.text('Load older'), findsOneWidget);

    when(
      () => client.listApprovals(
        status: 'all',
        limit: any(named: 'limit'),
        before: '2026-10-01T00:00:00+00:00',
      ),
    ).thenAnswer(
      (_) async => ApprovalPage(
        items: [_approval(id: 'h-3', status: 'denied', description: 'Older still')],
      ),
    );
    await tester.scrollUntilVisible(
      find.text('Load older'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Load older'));
    await tester.pumpAndSettle();
    expect(find.text('Older still'), findsOneWidget);
    expect(find.text('Load older'), findsNothing);
  });

  testWidgets('an unreachable gateway shows a retry', (tester) async {
    when(
      () => client.listApprovals(
        status: any(named: 'status'),
        limit: any(named: 'limit'),
        before: any(named: 'before'),
      ),
    ).thenThrow(const PushGatewayException(message: 'Could not reach Hermes.'));
    await pumpPage(tester);
    await tester.pumpAndSettle();
    expect(find.text('Could not reach Hermes.'), findsWidgets);
    expect(find.text('Try again'), findsOneWidget);
  });

  testWidgets('not paired offers the pairing page', (tester) async {
    await pumpPage(
      tester,
      paired: false,
      extra: [
        pushPairingProvider.overrideWith((ref) async => null),
        pushGatewayClientProvider.overrideWith((ref) => null),
      ],
    );
    await tester.pumpAndSettle();
    expect(find.text('Pair this phone'), findsOneWidget);
    await tester.tap(find.text('Enter pairing code'));
    await tester.pumpAndSettle();
    expect(find.text('PAIRING PAGE'), findsOneWidget);
  });

  testWidgets('detail page shows parameters and decides with hold', (
    tester,
  ) async {
    when(() => client.getApproval('a-1')).thenAnswer((_) async => _approval());
    when(
      () => client.decide(
        id: 'a-1',
        decision: ApprovalDecision.approve,
        digest: 'dg-1',
        deviceId: 'dev-1',
      ),
    ).thenAnswer((_) async => ApprovalStatus.approved);
    stubLists();
    await pumpPage(tester, page: const ApprovalDetailPage(approvalId: 'a-1'));
    await tester.pumpAndSettle();
    expect(find.textContaining('"container": "changedetection"'), findsOneWidget);
    expect(find.text('Registered parameters'), findsOneWidget);
    await tester.ensureVisible(find.byType(HoldToConfirmButton));
    await tester.pumpAndSettle();
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(HoldToConfirmButton)),
    );
    await tester.pump(); // first frame starts the hold ticker
    await tester.pump(const Duration(milliseconds: 1500));
    await gesture.up();
    await tester.pumpAndSettle();
    verify(
      () => client.decide(
        id: 'a-1',
        decision: ApprovalDecision.approve,
        digest: 'dg-1',
        deviceId: 'dev-1',
      ),
    ).called(1);
  });

  testWidgets('detail page for a decided request has no decision controls', (
    tester,
  ) async {
    when(
      () => client.getApproval('a-1'),
    ).thenAnswer((_) async => _approval(status: 'approved'));
    await pumpPage(tester, page: const ApprovalDetailPage(approvalId: 'a-1'));
    await tester.pumpAndSettle();
    expect(find.byType(HoldToConfirmButton), findsNothing);
    expect(find.textContaining('Approved by you in Hermez'), findsOneWidget);
  });

  testWidgets('the Deny confirmation text carries the request', (tester) async {
    stubLists(pending: [_approval(description: 'Wipe the cache')]);
    await pumpPage(tester);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Deny'));
    await tester.pumpAndSettle();
    check(find.textContaining('Wipe the cache').evaluate()).isNotEmpty();
  });
}
