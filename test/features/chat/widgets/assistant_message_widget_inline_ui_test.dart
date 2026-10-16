import 'dart:convert';

import 'package:conduit/core/models/chat_message.dart';
import 'package:conduit/features/chat/providers/chat_providers.dart';
import 'package:conduit/features/chat/providers/text_to_speech_provider.dart';
import 'package:conduit/features/chat/widgets/assistant_message_widget.dart';
import 'package:conduit/features/hermes/models/hermes_config.dart';
import 'package:conduit/features/hermes/providers/hermes_providers.dart'
    show HermesConfigController, hermesConfigProvider;
import 'package:conduit/features/hermes/services/hermes_run_transport.dart'
    show kHermesTransport;
import 'package:conduit/features/hermes/widgets/hermes_openui_surface.dart';
import 'package:conduit/core/services/settings_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _Tts extends TextToSpeechController {
  @override
  TextToSpeechState build() => const TextToSpeechState();
}

class _Config extends HermesConfigController {
  @override
  HermesConfig build() => const HermesConfig(
    enabled: true,
    baseUrl: 'https://hermes.example/v1',
    mode: HermesBackendMode.desktopGateway,
    desktopAuthKind: HermesDesktopAuthKind.dashboardCookie,
  );
}

class _Messages extends ChatMessagesNotifier {
  _Messages(this.initial);
  final List<ChatMessage> initial;
  @override
  List<ChatMessage> build() => initial;
  void replace(List<ChatMessage> messages) => state = messages;
}

// Tabs and a form are local; only the Button sends.
const _program =
    'root = Stack([Tabs([Tab("Plan",[Text("Plan body")]),'
    'Tab("Notes",[Text("Notes body")])]),'
    'Form("trip",[Select("activity","Activity",["Reading","Museum"],"Reading"),'
    'Checkbox("quiet","Keep it quiet",false),'
    'Button("Plan this weekend","Plan it")])])';

ChatMessage _assistant(String id) => ChatMessage(
  id: id,
  role: 'assistant',
  content: '```openui\n$_program\n```',
  timestamp: DateTime(2026),
  metadata: const {'transport': kHermesTransport, 'responseDone': true},
);

ChatMessage _user(String id) => ChatMessage(
  id: id,
  role: 'user',
  content: '[A2UI_INTERACTION]\n{}',
  timestamp: DateTime(2026),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<_Messages> pumpChat(
    WidgetTester tester, {
    required List<ChatMessage> messages,
    required List<String> sent,
  }) async {
    final notifier = _Messages(messages);
    await tester.binding.setSurfaceSize(const Size(400, 2600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          textToSpeechControllerProvider.overrideWith(_Tts.new),
          streamingHapticsEnabledProvider.overrideWithValue(false),
          hermesConfigProvider.overrideWith(_Config.new),
          chatMessagesProvider.overrideWith(() => notifier),
        ],
        // No Scaffold, as in the real chat.
        child: MaterialApp(
          home: SingleChildScrollView(
            child: Column(
              children: [
                for (final m in messages.where((m) => m.role == 'assistant'))
                  AssistantMessageWidget(
                    key: ValueKey(m.id),
                    message: m,
                    showFollowUps: false,
                    showActionBar: false,
                    animateOnMount: false,
                    onDelete: () {},
                    onFollowUpSelected: sent.add,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return notifier;
  }

  bool buttonEnabled(WidgetTester tester, Finder surface) {
    final button = find.descendant(
      of: surface,
      matching: find.byType(FilledButton),
    );
    return tester.widget<FilledButton>(button).onPressed != null;
  }

  Finder surfaceOf(String id) => find.byWidgetPredicate(
    (w) =>
        w is HermesOpenuiSurface &&
        w.surfaceId.startsWith('openui-$id-'),
  );

  testWidgets('older surface cannot send; local controls still work', (
    tester,
  ) async {
    final sent = <String>[];
    await pumpChat(
      tester,
      messages: [_assistant('old'), _user('answer'), _assistant('new')],
      sent: sent,
    );
    final old = surfaceOf('old');
    expect(old, findsOneWidget);
    expect(buttonEnabled(tester, old), isFalse);
    expect(buttonEnabled(tester, surfaceOf('new')), isTrue);

    // Local edits on the old surface still work and send nothing.
    final oldTabs = find.descendant(of: old, matching: find.text('Notes'));
    await tester.tap(oldTabs);
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: old, matching: find.text('Notes body')),
      findsOneWidget,
    );
    await tester.tap(
      find.descendant(of: old, matching: find.text('Keep it quiet')),
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<CheckboxListTile>(
            find.descendant(
              of: old,
              matching: find.byType(CheckboxListTile),
            ),
          )
          .value,
      isTrue,
    );
    await tester.tap(
      find.descendant(of: old, matching: find.text('Plan this weekend')),
      warnIfMissed: false,
    );
    await tester.pump();
    expect(sent, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the latest surface sends exactly once', (tester) async {
    final sent = <String>[];
    await pumpChat(
      tester,
      messages: [_assistant('old'), _user('answer'), _assistant('new')],
      sent: sent,
    );
    final latest = surfaceOf('new');
    await tester.tap(
      find.descendant(of: latest, matching: find.text('Plan this weekend')),
    );
    await tester.pump();
    expect(sent, hasLength(1));
    final context = jsonDecode(
      sent.single.split('\n').skip(1).join('\n'),
    )['action']['context'];
    expect(context['renderer'], 'openui');
    expect(context['values'], {'activity': 'Reading', 'quiet': false});
    expect(tester.takeException(), isNull);
  });

  testWidgets('a surface locks once a user turn follows it', (tester) async {
    final sent = <String>[];
    final only = [_assistant('only')];
    final notifier = await pumpChat(tester, messages: only, sent: sent);
    final surface = surfaceOf('only');
    expect(buttonEnabled(tester, surface), isTrue);

    notifier.replace([...only, _user('answer')]);
    await tester.pumpAndSettle();
    expect(buttonEnabled(tester, surface), isFalse);
    await tester.tap(
      find.descendant(of: surface, matching: find.text('Plan this weekend')),
      warnIfMissed: false,
    );
    await tester.pump();
    expect(sent, isEmpty);

    // Removing the later turn makes the reply actionable again.
    notifier.replace(only);
    await tester.pumpAndSettle();
    expect(buttonEnabled(tester, surface), isTrue);
  });
}
