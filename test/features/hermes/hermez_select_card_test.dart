import 'package:conduit/features/hermes/motion/hermez_card_route.dart';
import 'package:conduit/features/hermes/motion/hermez_select_card.dart';
import 'package:conduit/shared/widgets/adaptive_selection_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // The rule: a picker is the select card. The pressed field grows into
  // the options, and picking one returns it and folds the card back.
  testWidgets('a select card grows from its field and returns the pick', (
    tester,
  ) async {
    String? picked;
    String? adaptive;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(platform: TargetPlatform.android),
        home: Scaffold(
          body: Column(
            children: [
              Builder(
                builder: (context) => TextButton(
                  key: const Key('field'),
                  onPressed: () async =>
                      picked = await showHermezSelectCard<String>(
                        context,
                        from: context,
                        title: 'Alerts from Chief',
                        selected: 'needs',
                        options: const [
                          HermezSelectOption('all', 'Everything'),
                          HermezSelectOption('needs', 'Only what needs me'),
                          HermezSelectOption('none', 'Nothing'),
                        ],
                      ),
                  child: const Text('Only what needs me'),
                ),
              ),
              Builder(
                builder: (context) => TextButton(
                  onPressed: () async =>
                      adaptive = await showAdaptiveSelectionSheet<String>(
                        context: context,
                        builder: (sheetContext) => AdaptiveSelectionSheet(
                          title: 'Thinking',
                          itemCount: 2,
                          itemBuilder: (_, index) => AdaptiveSelectionTile(
                            title: ['On', 'Off'][index],
                            selected: index == 0,
                            onTap: () =>
                                Navigator.of(sheetContext)
                                    .pop(['on', 'off'][index]),
                          ),
                        ),
                      ),
                  child: const Text('Thinking'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    final field = tester.getRect(find.byKey(const Key('field')));

    await tester.tap(find.byKey(const Key('field')));
    await tester.pumpAndSettle();
    expect(hermezCardOriginOf(tester.element(find.text('Nothing'))), field);
    await tester.tap(find.text('Nothing'));
    await tester.pumpAndSettle();
    expect(picked, 'none');
    expect(find.text('Alerts from Chief'), findsNothing);

    await tester.tap(find.text('Thinking'));
    await tester.pumpAndSettle();
    expect(find.byType(HermezSelectRow), findsNWidgets(2));
    await tester.tap(find.text('Off'));
    await tester.pumpAndSettle();
    expect(adaptive, 'off');
  });
}
