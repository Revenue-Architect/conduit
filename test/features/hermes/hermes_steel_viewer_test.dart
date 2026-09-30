import 'package:conduit/features/hermes/services/hermes_steel_viewer.dart';
import 'package:conduit/features/hermes/widgets/hermes_steel_live_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a build define with a trailing comment still yields the viewer', () {
    const raw =
        'http://steel.example:8300/v1/sessions/debug  # private; never commit';
    final url = sanitizeSteelViewerDefine(raw);
    expect(url, 'http://steel.example:8300/v1/sessions/debug');
    expect(parseSteelViewerUrl(url), isNotNull);
    // Unsanitized, the comment parses as a fragment and hides the viewer.
    expect(parseSteelViewerUrl(raw), isNull);
    expect(sanitizeSteelViewerDefine(''), '');
    expect(sanitizeSteelViewerDefine('  '), '');
  });

  test('watch/control parameter preserves existing query', () {
    const source =
        'http://steel.example/v1/sessions/debug?session=abc&interactive=true';
    final watch = steelViewerUri(source, interactive: false);
    final control = steelViewerUri(source, interactive: true);
    expect(watch.queryParameters, {'session': 'abc', 'interactive': 'false'});
    expect(control.queryParameters, {'session': 'abc', 'interactive': 'true'});
  });

  test('rejects unsafe and malformed viewer URLs', () {
    for (final source in [
      '',
      'file:///tmp/viewer',
      'javascript:alert(1)',
      'http://user:secret@steel.example/debug',
      'https://steel.example/debug#fragment',
      'not a url',
    ]) {
      expect(parseSteelViewerUrl(source), isNull, reason: source);
      expect(
        () => steelViewerUri(source, interactive: false),
        throwsFormatException,
      );
    }
  });

  testWidgets('embedded viewer starts in watch-only mode', (tester) async {
    Uri? loaded;
    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          height: 280,
          child: HermesSteelLiveView(
            viewerUrl: 'http://steel.example/v1/sessions/debug?session=abc',
            viewerBuilder: (uri) {
              loaded = uri;
              return const Text('Steel player');
            },
          ),
        ),
      ),
    );
    expect(find.text('Steel player'), findsOneWidget);
    expect(loaded?.queryParameters['session'], 'abc');
    expect(loaded?.queryParameters['interactive'], 'false');
  });
}
