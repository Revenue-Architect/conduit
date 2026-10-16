import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:conduit/features/hermes/services/hermes_openui_parser.dart';
import 'package:conduit/features/hermes/services/hermes_inline_ui_capability.dart';
import 'package:conduit/features/hermes/services/hermes_openui_schema.dart';
import 'package:conduit/features/hermes/services/hermes_rich_output_parser.dart';
import 'package:conduit/features/hermes/widgets/hermes_openui_surface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('bare tabs and forms work in a custom chat without Material', (
    tester,
  ) async {
    final sent = <String>[];
    const code =
        'root = Stack(['
        'Tabs([Tab("Overview",[Text("Ready")]),Tab("Details",[Text("More")])]),'
        'Form("trip",[Select("destination","Destination",["A","B"],"A"),'
        'MultiSelect("interests","Interests",["Food","Outdoors"],["Food"]),'
        'Button("Compare","Compare my choices")])])';
    await tester.pumpWidget(
      MaterialApp(
        home: SingleChildScrollView(
          child: HermesOpenuiSurface(
            payload: code,
            surfaceId: 'custom-chat',
            onInteraction: sent.add,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Details'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Outdoors'));
    await tester.pumpAndSettle();
    expect(sent, isEmpty);
    await tester.tap(find.text('Compare'));
    await tester.pumpAndSettle();
    final values = jsonDecode(
      sent.single.split('\n').skip(1).join('\n'),
    )['action']['context']['values'];
    expect(values, {'destination': 'A', 'interests': ['Food', 'Outdoors']});
    expect(tester.takeException(), isNull);
  });
  testWidgets('integer schema accepts 2.0 without a native cast failure', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: HermesOpenuiSurface(
            payload: 'root = Stack([Grid([Text("Two columns")], 2.0)])',
            surfaceId: 'numeric-grid',
          ),
        ),
      ),
    );
    expect(find.text('Two columns'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  final directory = Directory('docs/hermes-openui/references');
  final examples = directory
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.openui'))
      .toList();
  test('capability is per turn, retry idempotent and actions remain exact JSON', () {
    const message = 'Compare these example prices';
    final wire = hermesInlineUiTurnText(message);
    expect(wire, contains('[Client capability: Conduit OpenUI v1]'));
    expect(hermesInlineUiTurnText(wire), wire);
    expect(hermesInlineUiVisibleText(wire), message);
    const interaction =
        '[A2UI_INTERACTION]\n{"version":"v0.9","action":{"context":{"renderer":"openui"}}}';
    expect(hermesInlineUiTurnText(interaction), interaction);
    expect(
      jsonDecode(
        hermesInlineUiTurnText(interaction).split('\n').last,
      )['version'],
      'v0.9',
    );
  });
  test('exact Desktop schemas, 70 components and complete shared fixtures', () {
    final schema = jsonDecode(
      File('${directory.path}/catalog.schema.json').readAsStringSync(),
    );
    expect(jsonDecode(hermesOpenuiSchemaJson), schema[r'$defs']);
    expect(hermesOpenuiComponentNames, hasLength(70));
    final covered = <String>{};
    void walk(HermesOpenuiNode n) {
      covered.add(n.type);
      for (final child in n.children) {
        walk(child);
      }
    }

    for (final example in examples) {
      walk(parseHermesOpenui(example.readAsStringSync()));
    }
    expect(covered, hermesOpenuiComponentNames);
  });
  test('mixed explicit fences stay independent; examples and partial fences are prose', () {
    final result = parseHermesRichOutput(
      'Before\n```openui\nroot = Stack([])\n```\n```a2ui\n{}\n```\nAfter',
    );
    expect(result.whereType<OpenuiSegment>(), hasLength(1));
    expect(result.whereType<A2uiSegment>(), hasLength(1));
    for (final text in [
      '```openui\nroot = Stack([])',
      '```json\n~~~openui\nroot = Stack([])\n~~~\n```',
    ]) {
      expect(parseHermesRichOutput(text).whereType<OpenuiSegment>(), isEmpty);
    }
  });
  test(
    'rejects execution, unsafe fields, invalid semantics and bounded resources',
    () {
      for (final code in [
        'root = Stack([Query("network")])',
        'root = Stack([Text("x")]); other = Stack([])',
        'root = Stack([Text("x".trim())])',
        'root = Stack([Input("n","N","","")])',
        'root = Stack([Form("f",[Input("constructor","N","","")])])',
        'root = Stack([Form("f",[Input("x","N","",""),Checkbox("x","N",false)])])',
        'root = Stack([Form("f",[Form("nested",[])])])',
        'root = Stack([Select("x","X",["A"],"B")])',
        'root = Stack([Table(["a","b"],[["one"]])])',
        'root = Stack([BarChart("T",["A"],[1,2],"CAD")])',
        'root = Stack([Progress("P",11,10)])',
        'root = Stack([Form("f",[Slider("s","S",10,1,5)])])',
        'root = Stack([Tabs([Text("bad")])])',
        'root = Stack([Tab("bad",[])])',
        'root = Stack([Heatmap("H",["a"],["b"],[[1,2]])])',
        'root = Stack([DefinitionList(["a"],[])])',
        'root = Stack([Text("${'x' * 65536}")])',
        'root = Stack([${List.filled(201, 'Text("x")').join(',')}])',
      ]) {
        expect(
          () => parseHermesOpenui(code),
          throwsFormatException,
          reason: code.substring(0, code.length > 100 ? 100 : code.length),
        );
      }
    },
  );
  for (final brightness in Brightness.values) {
    for (final example in examples) {
      testWidgets(
        'native ${example.uri.pathSegments.last} at 360px $brightness',
        (tester) async {
          await tester.binding.setSurfaceSize(const Size(360, 800));
          addTearDown(() => tester.binding.setSurfaceSize(null));
          await tester.pumpWidget(
            MaterialApp(
              theme: ThemeData(brightness: brightness),
              home: SingleChildScrollView(
                child: HermesOpenuiSurface(
                  payload: example.readAsStringSync(),
                  surfaceId: 'gallery',
                  onInteraction: (_) {},
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(
            find.text(
              'This OpenUI could not be displayed. Ask Hermes to regenerate it.',
            ),
            findsNothing,
          );
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
  testWidgets('edits stay local; explicit button sends defaults and edits once', (
    tester,
  ) async {
    final messages = <String>[];
    final pending = Completer<void>();
    const code =
        'root = Stack([Form("plan",[Input("note","Note","","Keep relaxed"),Select("activity","Activity",["Reading","Museum"],"Reading"),Button("Plan this","Suggest a plan.")])])';
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: HermesOpenuiSurface(
              payload: code,
              surfaceId: 'origin-message',
              onInteraction: (p) {
                messages.add(p);
                return pending.future;
              },
            ),
          ),
        ),
      ),
    );
    await tester.enterText(find.byType(TextFormField), 'Changed note');
    expect(messages, isEmpty);
    await tester.tap(find.text('Plan this'));
    await tester.pump();
    await tester.tap(find.text('Plan this'));
    expect(messages, hasLength(1));
    final action = jsonDecode(
      messages.single.split('\n').skip(1).join('\n'),
    )['action'];
    expect(action['surfaceId'], 'origin-message');
    expect(action['name'], 'openui.continue');
    expect(action['context'], {
      'renderer': 'openui',
      'message': 'Suggest a plan.',
      'form': 'plan',
      'values': {'note': 'Changed note', 'activity': 'Reading'},
    });
    pending.complete();
    await tester.pumpAndSettle();
  });
  testWidgets('invalid and busy or read-only surfaces cannot send', (
    tester,
  ) async {
    var sent = 0;
    for (final busy in [true, false]) {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HermesOpenuiSurface(
              payload: 'root = Stack([Button("Go","Request")])',
              surfaceId: 'locked',
              isBusy: busy,
              onInteraction: busy
                  ? (_) {
                      sent++;
                    }
                  : null,
            ),
          ),
        ),
      );
      await tester.tap(find.text('Go'));
      await tester.pump();
    }
    expect(sent, 0);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HermesOpenuiSurface(
            payload: 'root = Stack([Button("Go","Request")]) extra',
            surfaceId: 'invalid',
            onInteraction: (_) {
              sent++;
            },
          ),
        ),
      ),
    );
    expect(find.text('Go'), findsNothing);
    expect(find.text('View source'), findsOneWidget);
  });
}
