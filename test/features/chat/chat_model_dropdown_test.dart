import 'package:conduit/shared/widgets/adaptive_toolbar_components.dart';
import 'package:checks/checks.dart';
import 'package:conduit/core/models/chat_message.dart';
import 'package:conduit/core/models/conversation.dart';
import 'package:conduit/core/models/model.dart';
import 'package:conduit/features/chat/views/chat_page.dart';
import 'package:conduit/features/hermes/models/hermes_model.dart';
import 'package:conduit/features/hermes/models/hermes_bot.dart';
import 'package:conduit/features/hermes/services/hermes_session_provenance.dart';
import 'package:conduit/shared/theme/app_theme.dart';
import 'package:conduit/shared/theme/tweakcn_themes.dart';
import 'package:conduit/features/hermes/widgets/hermez_bot_mark.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  group('shouldShowChatModelDropdown', () {
    test('keeps switching available for Hermes in a mixed setup', () {
      check(
        shouldShowChatModelDropdown(
          selectedModel: hermesSyntheticModel(),
          isHermesOnly: false,
        ),
      ).isTrue();
    });

    test('hides switching for the single-agent Hermes-only setup', () {
      check(
        shouldShowChatModelDropdown(
          selectedModel: hermesSyntheticModel(),
          isHermesOnly: true,
        ),
      ).isFalse();
    });

    test('hides switching for a bot in a mixed setup', () {
      check(
        shouldShowChatModelDropdown(
          selectedModel: hermesSyntheticModel(),
          isHermesOnly: false,
          isHermesBot: true,
        ),
      ).isFalse();
    });

    test('shows switching for OpenWebUI or an empty selection', () {
      const openWebUiModel = Model(id: 'gpt', name: 'GPT');

      check(
        shouldShowChatModelDropdown(
          selectedModel: openWebUiModel,
          isHermesOnly: true,
        ),
      ).isTrue();
      check(
        shouldShowChatModelDropdown(selectedModel: null, isHermesOnly: true),
      ).isTrue();
    });
  });

  test('temporary chat action is hidden for Hermes', () {
    check(
      shouldShowTemporaryChatAction(isHermes: true, activeConversation: null),
    ).isFalse();
    check(
      shouldShowTemporaryChatAction(isHermes: false, activeConversation: null),
    ).isTrue();
  });

  test('bot chat uses its bot title in the model pill', () {
    const avatar = 'data:image/png;base64,YQ==';
    final now = DateTime(2026);
    final conversation = markNativeHermesConversation(
      Conversation(
        id: 'local:hermes_bot',
        title: 'Bot Chat',
        createdAt: now,
        updatedAt: now,
        metadata: const {
          kHermesBotTitleMetadataKey: 'Research',
          kHermesBotAvatarMetadataKey: avatar,
        },
      ),
    );

    check(chatHermesBotTitle(conversation)).equals('Research');
    check(chatHermesBotPresentation(conversation)?.avatar).equals(avatar);
    check(
      chatHermesBotTitle(
        conversation.copyWith(metadata: conversation.metadata),
      ),
    ).isNull();
  });

  test('bot chat uses the bot identity for assistant headers', () {
    const avatar = 'data:image/png;base64,YQ==';
    final summary = debugBuildChatListLayoutSummaryForTesting(
      [
        ChatMessage(
          id: 'assistant-1',
          role: 'assistant',
          content: 'Hello',
          timestamp: DateTime(2026),
          model: kHermesDefaultModelId,
        ),
      ],
      models: [hermesSyntheticModel()],
      hermesBot: (
        title: 'Research',
        avatar: avatar,
        shape: 'squircle',
        color: '#8b5cf6',
        imageKind: 'photo',
      ),
    );

    check(summary.single.displayModelName).equals('Research');
    check(summary.single.modelIconUrl).equals(avatar);
  });

  testWidgets('bot chat toolbar shows its avatar, name, and activity', (
    tester,
  ) async {
    const avatar =
        'data:image/png;base64,'
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=';
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(TweakcnThemes.t3Chat),
        home: Scaffold(
          body: MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: debugBuildHermesBotToolbarTitleForTesting(
              bot: (
                title: 'Research',
                avatar: avatar,
                shape: 'squircle',
                color: '#8b5cf6',
                imageKind: 'shape',
              ),
              maxWidth: 240,
              active: true,
            ),
          ),
        ),
      ),
    );

    check(find.text('Research').evaluate().length).equals(1);
    // Hermez draws every bot with its own mark, not the synced image.
    final mark = tester.widget<HermezBotMark>(
      find.descendant(
        of: find.byKey(const ValueKey('hermes-bot-toolbar-avatar')),
        matching: find.byType(HermezBotMark),
      ),
    );
    check(mark.label).equals('Research');
    check(
      find.byKey(const ValueKey('hermes-bot-activity-dot')).evaluate().length,
    ).equals(1);
    // The activity dot breathes by size, never by opacity.
    check(find.byType(FadeTransition).evaluate()).isEmpty();
    check(
      tester
          .widgetList<ScaleTransition>(
            find.ancestor(
              of: find.byKey(const ValueKey('hermes-bot-activity-dot')),
              matching: find.byType(ScaleTransition),
            ),
          )
          .first
          .scale
          .value,
    ).equals(1);
  });

  testWidgets(
    'bot identity shrinks and hides the name without losing its label',
    (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        Widget header(bool compact, {bool reduced = false}) => MaterialApp(
          theme: AppTheme.light(TweakcnThemes.t3Chat),
          home: Scaffold(
            body: MediaQuery(
              data: MediaQueryData(disableAnimations: reduced),
              child: debugBuildHermesBotToolbarTitleForTesting(
                bot: (
                  title: 'Chief',
                  avatar: null,
                  shape: 'squircle',
                  color: '#8b5cf6',
                  imageKind: null,
                ),
                maxWidth: 200,
                compact: compact,
              ),
            ),
          ),
        );
        double avatarSize() => tester
            .getSize(find.byKey(const ValueKey('hermes-bot-toolbar-avatar')))
            .width;
        Opacity nameOpacity() => tester.widget<Opacity>(
          find
              .ancestor(
                of: find.byKey(const ValueKey('hermes-bot-toolbar-title')),
                matching: find.byType(Opacity),
              )
              .first,
        );
        await tester.pumpWidget(header(false));
        expect(avatarSize(), kHermesBotHeaderAvatar);
        await tester.pumpWidget(header(true));
        await tester.pump(const Duration(milliseconds: 110));
        expect(
          avatarSize(),
          allOf(
            greaterThan(kHermesBotHeaderAvatarFolded),
            lessThan(kHermesBotHeaderAvatar),
          ),
        );
        expect(nameOpacity().opacity, allOf(greaterThan(0), lessThan(1)));
        await tester.pumpAndSettle();
        expect(avatarSize(), kHermesBotHeaderAvatarFolded);
        expect(nameOpacity().opacity, 0);
        expect(find.bySemanticsLabel('Chief'), findsOneWidget);
        await tester.pumpWidget(header(false, reduced: true));
        await tester.pump();
        expect(avatarSize(), kHermesBotHeaderAvatar);
        expect(nameOpacity().opacity, 1);
        expect(tester.takeException(), isNull);
      } finally {
        semantics.dispose();
      }
    },
  );

  testWidgets('larger bot icon fits the centered toolbar without clipping', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(TweakcnThemes.t3Chat),
        home: Builder(
          builder: (context) => Scaffold(
            appBar: buildConduitCenteredAdaptiveAppBar(
              context: context,
              tintColor: Colors.black,
              toolbarHeight: kHermesBotHeaderHeight,
              leading: const SizedBox.square(dimension: 44),
              actions: const [],
              title: debugBuildHermesBotToolbarTitleForTesting(
                bot: (
                  title: 'Chief',
                  avatar: null,
                  shape: 'squircle',
                  color: '#8b5cf6',
                  imageKind: null,
                ),
                maxWidth: 400,
              ),
            ).appBar,
          ),
        ),
      ),
    );
    final bar = tester.widget<AppBar>(find.byType(AppBar));
    expect(bar.toolbarHeight, kHermesBotHeaderHeight);
    final avatar = tester.getRect(
      find.byKey(const ValueKey('hermes-bot-toolbar-avatar')),
    );
    final bounds = tester.getRect(find.byType(AppBar));
    expect(avatar.size, const Size.square(kHermesBotHeaderAvatar));
    expect(avatar.top, greaterThanOrEqualTo(bounds.top));
    expect(avatar.bottom, lessThanOrEqualTo(bounds.bottom));
    // The avatar, not the avatar-and-name group, is the toolbar's center.
    expect(avatar.center.dx, closeTo(400, 0.5));
    expect(tester.takeException(), isNull);
    const cupertino = ConduitAdaptiveCupertinoNavigationBar(
      textScaler: TextScaler.noScaling,
      toolbarHeight: 64,
      leading: SizedBox.square(dimension: 44),
    );
    expect(cupertino.preferredSize.height, 64);
  });

  group('chatLocalFilePickerExtensions', () {
    test('filters Hermes to supported local documents without PDF', () {
      final extensions = chatLocalFilePickerExtensions(hermesSyntheticModel())!;

      check(extensions).contains('txt');
      check(extensions).contains('docx');
      check(extensions).not((it) => it.contains('pdf'));
    });

    test('offers PDF when Hermes advertises Responses file input', () {
      final extensions = chatLocalFilePickerExtensions(
        hermesSyntheticModel(),
        hermesResponsesFiles: true,
      )!;

      check(extensions).contains('pdf');
    });

    test('leaves Desktop Hermes picker unrestricted', () {
      check(
        chatLocalFilePickerExtensions(
          hermesSyntheticModel(),
          desktopHermes: true,
        ),
      ).isNull();
    });

    test('leaves the OpenWebUI picker unrestricted', () {
      const openWebUiModel = Model(id: 'gpt', name: 'GPT');

      check(chatLocalFilePickerExtensions(openWebUiModel)).isNull();
      check(chatLocalFilePickerExtensions(null)).isNull();
    });
  });
}
