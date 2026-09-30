import 'package:checks/checks.dart';
import 'package:conduit/features/hermes/widgets/hermes_approval_card.dart';
import 'package:conduit/l10n/app_localizations.dart';
import 'package:conduit/l10n/conduit_localizations.dart';
import 'package:conduit/shared/theme/app_theme.dart';
import 'package:conduit/shared/theme/tweakcn_themes.dart';
import 'package:conduit/features/hermes/widgets/hermez_decision_frame.dart';
import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget host(Widget card) => ProviderScope(
    child: MaterialApp(
      theme: AppTheme.light(TweakcnThemes.t3Chat),
      localizationsDelegates: conduitLocalizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: SingleChildScrollView(child: card)),
    ),
  );

  testWidgets('while resolving, the options are held and the card says so', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        HermesApprovalCard(
          state: HermesApprovalState.resolving,
          onDecision: (_) {},
        ),
      ),
    );
    final options = tester
        .widgetList<HermezDecisionOption>(find.byType(HermezDecisionOption))
        .toList();
    check(options).has((items) => items.length, 'length').equals(2);
    check(options.every((option) => !option.enabled)).isTrue();
    expect(find.text('SENDING'), findsOneWidget);
  });

  testWidgets('primary options first; other policies Hermes sent sit in '
      'More options', (tester) async {
    final sent = <String>[];
    await tester.pumpWidget(
      host(
        HermesApprovalCard(
          state: HermesApprovalState.pending,
          summary: 'docker compose restart nvr',
          choices: const ['once', 'session', 'always', 'deny'],
          onChoice: sent.add,
          onDecision: (_) {},
        ),
      ),
    );
    expect(find.text('> docker compose restart nvr'), findsOneWidget);
    expect(find.text('Hermes is paused until you decide.'), findsOneWidget);
    expect(find.text('Allow once'), findsOneWidget);
    expect(find.text('Deny'), findsOneWidget);
    // Folded away until asked for.
    expect(find.text('Allow for session'), findsNothing);
    await tester.tap(find.text('More options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Allow for session'));
    expect(sent, ['session']);
  });

  testWidgets('only the choices Hermes sent are offered', (tester) async {
    await tester.pumpWidget(
      host(
        HermesApprovalCard(
          state: HermesApprovalState.pending,
          choices: const ['once', 'deny'],
          onChoice: (_) {},
          onDecision: (_) {},
        ),
      ),
    );
    expect(find.text('More options'), findsNothing);
    expect(find.text('Always allow'), findsNothing);
    expect(find.text('Allow for session'), findsNothing);
  });

  testWidgets('an answer is sent exactly once per pending request', (
    tester,
  ) async {
    final sent = <String>[];
    await tester.pumpWidget(
      host(
        HermesApprovalCard(
          state: HermesApprovalState.pending,
          choices: const ['once', 'deny'],
          onChoice: sent.add,
          onDecision: (_) {},
        ),
      ),
    );
    await tester.tap(find.text('Allow once'));
    await tester.pump();
    await tester.tap(find.text('Allow once'), warnIfMissed: false);
    await tester.tap(find.text('Deny'), warnIfMissed: false);
    await tester.pump();
    expect(sent, ['once']);

    // A failed request puts it back to pending: it can be answered again.
    await tester.pumpWidget(
      host(
        HermesApprovalCard(
          state: HermesApprovalState.resolving,
          choices: const ['once', 'deny'],
          onChoice: sent.add,
          onDecision: (_) {},
        ),
      ),
    );
    await tester.pumpWidget(
      host(
        HermesApprovalCard(
          state: HermesApprovalState.pending,
          choices: const ['once', 'deny'],
          onChoice: sent.add,
          onDecision: (_) {},
        ),
      ),
    );
    await tester.tap(find.text('Deny'));
    await tester.pump();
    expect(sent, ['once', 'deny']);
  });

  testWidgets('legacy approve and deny still report the decision', (
    tester,
  ) async {
    final decisions = <bool>[];
    await tester.pumpWidget(
      host(
        HermesApprovalCard(
          state: HermesApprovalState.pending,
          onDecision: decisions.add,
        ),
      ),
    );
    await tester.tap(find.text('Deny'));
    await tester.pump();
    expect(decisions, [false]);
  });

  testWidgets('renders in a Cupertino tree', (tester) async {
    await tester.pumpWidget(
      CupertinoApp(
        localizationsDelegates: conduitLocalizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Theme(
          data: AppTheme.light(TweakcnThemes.t3Chat),
          child: HermesApprovalCard(
            state: HermesApprovalState.pending,
            onDecision: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('APPROVAL REQUIRED'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
