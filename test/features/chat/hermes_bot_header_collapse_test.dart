import 'package:conduit/features/chat/views/chat_page.dart';
import 'package:conduit/features/chat/views/hermes_bot_header_collapse.dart';
import 'package:conduit/shared/theme/app_theme.dart';
import 'package:conduit/shared/theme/tweakcn_themes.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

const _settle = Duration(milliseconds: 700);

/// A user drag from [from] to [to] (distances from the latest messages), in
/// small steps like a finger delivers them.
void _drag(HermesBotHeaderCollapse header, double from, double to) {
  header.userDragStarted(from);
  const steps = 8;
  for (var i = 1; i <= steps; i++) {
    final d = from + (to - from) * i / steps;
    header.userScrolled(d, atLatest: d <= 24);
  }
  header.userDragEnded(atLatest: to <= 24);
}

void main() {
  group('HermesBotHeaderCollapse', () {
    test('jitter and short drags never collapse the header', () {
      fakeAsync((async) {
        final header = HermesBotHeaderCollapse();
        header.userDragStarted(0);
        for (final d in [3.0, 0.0, 6.0, 1.0, 12.0, 4.0, 0.0]) {
          header.userScrolled(d, atLatest: true);
        }
        header.userDragEnded(atLatest: true);
        _drag(header, 0, 40);
        async.elapse(const Duration(seconds: 2));
        expect(header.compact.value, isFalse);
        header.dispose();
      });
    });

    test('collapses after about 48 dp of deliberate scrolling', () {
      fakeAsync((async) {
        final header = HermesBotHeaderCollapse();
        header.userDragStarted(0);
        header.userScrolled(47, atLatest: false);
        expect(header.compact.value, isFalse);
        header.userScrolled(49, atLatest: false);
        expect(header.compact.value, isTrue);
        header.dispose();
      });
    });

    test('overscroll bounce past the latest edge does not count as travel', () {
      fakeAsync((async) {
        final header = HermesBotHeaderCollapse();
        header.userDragStarted(0);
        header.userScrolled(-80, atLatest: true);
        header.userScrolled(-20, atLatest: true);
        header.userDragEnded(atLatest: true);
        expect(header.compact.value, isFalse);
        header.dispose();
      });
    });

    test('stays compact through pauses while reading older messages', () {
      fakeAsync((async) {
        final header = HermesBotHeaderCollapse();
        _drag(header, 0, 600);
        expect(header.compact.value, isTrue);
        async.elapse(const Duration(seconds: 5));
        _drag(header, 600, 900);
        async.elapse(const Duration(seconds: 10));
        expect(header.compact.value, isTrue);
        header.dispose();
      });
    });

    test('expands only after settling at the latest messages for 700 ms', () {
      fakeAsync((async) {
        final header = HermesBotHeaderCollapse();
        _drag(header, 0, 600);
        _drag(header, 600, 0);
        expect(header.compact.value, isTrue);
        async.elapse(const Duration(milliseconds: 650));
        expect(header.compact.value, isTrue);
        async.elapse(const Duration(milliseconds: 60));
        expect(header.compact.value, isFalse);
        header.dispose();
      });
    });

    test('resuming a scroll cancels a pending expansion', () {
      fakeAsync((async) {
        final header = HermesBotHeaderCollapse();
        _drag(header, 0, 600);
        _drag(header, 600, 0);
        async.elapse(const Duration(milliseconds: 400));
        expect(header.expansionPending, isTrue);
        header.userDragStarted(0);
        expect(header.expansionPending, isFalse);
        async.elapse(_settle * 2);
        expect(header.compact.value, isTrue);
        header.userDragEnded(atLatest: true);
        async.elapse(_settle);
        expect(header.compact.value, isFalse);
        header.dispose();
      });
    });

    test('a fling that leaves the latest messages cancels the expansion', () {
      fakeAsync((async) {
        final header = HermesBotHeaderCollapse();
        _drag(header, 0, 600);
        header.userDragStarted(600);
        header.userScrolled(10, atLatest: true);
        header.userDragEnded(atLatest: true);
        header.userScrolled(200, atLatest: false);
        async.elapse(_settle * 2);
        expect(header.compact.value, isTrue);
        header.dispose();
      });
    });

    test('programmatic scrolling and streaming never change the header', () {
      fakeAsync((async) {
        final header = HermesBotHeaderCollapse();
        // Auto-follow and streamed text move the viewport with no user drag:
        // the page only forwards changes while tracksUserMotion is true.
        expect(header.tracksUserMotion, isFalse);
        header.userScrolled(500, atLatest: false);
        header.userScrolled(0, atLatest: true);
        async.elapse(_settle * 2);
        expect(header.compact.value, isFalse);

        _drag(header, 0, 600);
        async.elapse(const Duration(seconds: 2));
        expect(header.tracksUserMotion, isFalse);
        // An auto-scroll back to the latest messages, long after the user
        // stopped, is ignored too.
        header.userScrolled(0, atLatest: true);
        async.elapse(_settle * 2);
        expect(header.compact.value, isTrue);
        header.dispose();
      });
    });

    test('a streaming reply cannot hold the motion window open', () {
      fakeAsync((async) {
        final header = HermesBotHeaderCollapse();
        _drag(header, 0, 600);
        header.userDragStarted(600);
        header.userDragEnded(atLatest: false);
        for (var i = 0; i < 40; i++) {
          async.elapse(const Duration(milliseconds: 100));
          if (header.tracksUserMotion)
            header.userScrolled(600, atLatest: false);
        }
        expect(header.tracksUserMotion, isFalse);
        header.dispose();
      });
    });

    test('jump to latest expands once the view arrives and stays', () {
      fakeAsync((async) {
        final header = HermesBotHeaderCollapse();
        _drag(header, 0, 900);
        header.userRequestedLatest();
        header.userScrolled(500, atLatest: false);
        header.userScrolled(100, atLatest: false);
        header.userScrolled(0, atLatest: true);
        async.elapse(const Duration(milliseconds: 650));
        expect(header.compact.value, isTrue);
        async.elapse(const Duration(milliseconds: 100));
        expect(header.compact.value, isFalse);
        header.dispose();
      });
    });

    test('a new conversation starts expanded with no pending timers', () {
      fakeAsync((async) {
        final header = HermesBotHeaderCollapse();
        _drag(header, 0, 600);
        _drag(header, 600, 0);
        header.reset();
        expect(header.compact.value, isFalse);
        expect(header.expansionPending, isFalse);
        expect(header.tracksUserMotion, isFalse);
        header.dispose();
        expect(async.pendingTimers, isEmpty);
      });
    });
  });

  testWidgets(
    'the avatar keeps its horizontal center as the header collapses',
    (tester) async {
      Widget header(bool compact) => MaterialApp(
        theme: AppTheme.light(TweakcnThemes.t3Chat),
        home: Scaffold(
          body: Center(
            child: debugBuildHermesBotToolbarTitleForTesting(
              bot: (
                title: 'Chief',
                avatar: null,
                shape: 'squircle',
                color: '#8b5cf6',
                imageKind: null,
              ),
              maxWidth: 320,
              compact: compact,
            ),
          ),
        ),
      );
      final avatar = find.byKey(const ValueKey('hermes-bot-toolbar-avatar'));
      await tester.pumpWidget(header(false));
      final expanded = tester.getCenter(avatar).dx;
      await tester.pumpWidget(header(true));
      await tester.pump(kHermesBotHeaderTransition ~/ 2);
      expect(tester.getCenter(avatar).dx, closeTo(expanded, 0.5));
      await tester.pumpAndSettle();
      expect(tester.getSize(avatar).width, 33);
      expect(tester.getCenter(avatar).dx, closeTo(expanded, 0.5));
      // The avatar, not the avatar-and-name group, is the title's center.
      expect(expanded, closeTo(400, 0.5));
      expect(
        kHermesBotHeaderTransition.inMilliseconds,
        inInclusiveRange(280, 320),
      );
    },
  );
}
