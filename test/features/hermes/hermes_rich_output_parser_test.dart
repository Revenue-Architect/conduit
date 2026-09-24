import 'package:conduit/features/hermes/services/hermes_rich_output_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parseHermesRichOutput', () {
    test(
      'splits an explicit A2UI fence and preserves surrounding Markdown',
      () {
        const text =
            'Current status:\n```a2ui\n{"version":"v0.9"}\n```\nMore details.';

        final segments = parseHermesRichOutput(text);

        expect(segments, hasLength(3));
        expect((segments[0] as MarkdownSegment).content, 'Current status:\n');
        expect((segments[1] as A2uiSegment).content, '{"version":"v0.9"}\n');
        expect((segments[2] as MarkdownSegment).content, 'More details.');
      },
    );

    test('supports multiple surfaces and CRLF without rewriting payloads', () {
      const text =
          'One\r\n```a2ui\r\n{"version":"v0.9","surface":"one"}\r\n```'
          '\r\nTwo\r\n```a2ui\r\n{"version":"v0.9","surface":"two"}'
          '\r\n```\r\nThree';

      final segments = parseHermesRichOutput(text);

      expect(segments, hasLength(5));
      expect((segments[0] as MarkdownSegment).content, 'One\r\n');
      expect(
        (segments[1] as A2uiSegment).content,
        '{"version":"v0.9","surface":"one"}\r\n',
      );
      expect((segments[2] as MarkdownSegment).content, 'Two\r\n');
      expect(
        (segments[3] as A2uiSegment).content,
        '{"version":"v0.9","surface":"two"}\r\n',
      );
      expect((segments[4] as MarkdownSegment).content, 'Three');
    });

    test('does not reinterpret JSON, other code, or nested examples', () {
      const text = '''
```json
{"version":"v0.9"}
```

```dart
final example = ''';

      final segments = parseHermesRichOutput(text);

      expect(segments, hasLength(1));
      expect(segments.single, isA<MarkdownSegment>());
      expect(segments.single.content, text);
    });

    test(
      'does not extract an A2UI-looking fence nested in another code fence',
      () {
        const text = '```json\n```a2ui\n{}\n```\n```';

        final segments = parseHermesRichOutput(text);

        expect(segments, hasLength(1));
        expect(segments.single, isA<MarkdownSegment>());
        expect(segments.single.content, text);
      },
    );

    test('leaves incomplete and non-exact A2UI fences as Markdown', () {
      for (final text in <String>[
        '```a2ui\n{"version":"v0.9"}',
        '```a2ui-extra\n{}\n```',
        '~~~a2ui data\n{}\n~~~',
      ]) {
        final segments = parseHermesRichOutput(text);

        expect(segments, hasLength(1));
        expect(segments.single, isA<MarkdownSegment>());
        expect(segments.single.content, text);
      }
    });

    test('keeps tilde A2UI fences and ordinary text-only responses', () {
      const fenced = '~~~a2ui\n{"version":"v0.9"}\n~~~';
      final fencedSegments = parseHermesRichOutput(fenced);
      final textSegments = parseHermesRichOutput('Plain answer.');

      expect(fencedSegments, hasLength(1));
      expect(fencedSegments.single, isA<A2uiSegment>());
      expect(textSegments, hasLength(1));
      expect(textSegments.single, isA<MarkdownSegment>());
      expect(textSegments.single.content, 'Plain answer.');
    });
  });
}
