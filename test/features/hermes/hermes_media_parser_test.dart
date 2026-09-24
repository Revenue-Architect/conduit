import 'package:conduit/features/hermes/services/hermes_media_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parseHermesMedia', () {
    test('keeps ordinary filesystem paths as ordinary prose', () {
      const text = 'The report is at /opt/data/artifacts/report.pdf.';

      final result = parseHermesMedia(text);

      expect(result.cleanText, text);
      expect(result.artifacts, isEmpty);
    });

    test('parses unquoted paths with spaces through a known extension', () {
      const text = 'Done.\nMEDIA:/opt/data/artifacts/My Report 2026.pdf\nNext.';

      final result = parseHermesMedia(text);

      expect(result.cleanText, 'Done.\nNext.');
      expect(result.artifacts, hasLength(1));
      expect(
        result.artifacts.single.path,
        '/opt/data/artifacts/My Report 2026.pdf',
      );
      expect(result.artifacts.single.filename, 'My Report 2026.pdf');
      expect(result.artifacts.single.kind, HermesMediaKind.file);
    });

    test('accepts double quotes, single quotes, and backticks', () {
      final result = parseHermesMedia('''
MEDIA:"/opt/data/My Image.png"
MEDIA:'/opt/data/My audio.m4a'
MEDIA:`/opt/data/My Clip.mp4`
''');

      expect(result.artifacts.map((item) => item.path), [
        '/opt/data/My Image.png',
        '/opt/data/My audio.m4a',
        '/opt/data/My Clip.mp4',
      ]);
      expect(result.artifacts.map((item) => item.kind), [
        HermesMediaKind.image,
        HermesMediaKind.audio,
        HermesMediaKind.video,
      ]);
    });

    test('parses multiple inline directives and preserves surrounding prose', () {
      const text =
          'Created MEDIA:/opt/data/first.png and MEDIA:"/opt/data/My PDF.pdf".';

      final result = parseHermesMedia(text);

      expect(result.cleanText, 'Created  and .');
      expect(result.artifacts.map((item) => item.filename), [
        'first.png',
        'My PDF.pdf',
      ]);
    });

    test('parses explicit unknown extensions as generic files', () {
      final result = parseHermesMedia('MEDIA:/opt/data/archive.custom');

      expect(result.cleanText, '');
      expect(result.artifacts.single.path, '/opt/data/archive.custom');
      expect(result.artifacts.single.kind, HermesMediaKind.file);
    });

    test('recognizes uppercase extensions without changing the path', () {
      final result = parseHermesMedia('MEDIA:/opt/data/PHOTO.WEBP');

      expect(result.artifacts.single.path, '/opt/data/PHOTO.WEBP');
      expect(result.artifacts.single.kind, HermesMediaKind.image);
    });

    test('does not include trailing sentence punctuation in a file path', () {
      final result = parseHermesMedia('MEDIA:/opt/data/My Report.pdf.\n');

      expect(result.cleanText, '');
      expect(result.artifacts.single.path, '/opt/data/My Report.pdf');
      expect(result.artifacts.single.filename, 'My Report.pdf');
    });

    test('keeps compound archive extensions together', () {
      final result = parseHermesMedia('MEDIA:/opt/data/My Archive.tar.gz');

      expect(result.artifacts.single.path, '/opt/data/My Archive.tar.gz');
      expect(result.artifacts.single.filename, 'My Archive.tar.gz');
      expect(result.artifacts.single.kind, HermesMediaKind.file);
      expect(result.cleanText, '');
    });

    test('preserves MEDIA examples inside fenced and inline code', () {
      const text = '''
Example:
```text
MEDIA:/opt/data/example.pdf
```
Use `MEDIA:/opt/data/inline-example.pdf` and MEDIA:/opt/data/real.pdf
''';

      final result = parseHermesMedia(text);

      expect(result.artifacts.map((item) => item.path), ['/opt/data/real.pdf']);
      expect(
        result.cleanText,
        contains('```text\nMEDIA:/opt/data/example.pdf\n```'),
      );
      expect(
        result.cleanText,
        contains('`MEDIA:/opt/data/inline-example.pdf`'),
      );
    });

    test('preserves directives inside blockquotes', () {
      const text = '''
> MEDIA:/opt/data/quoted-example.pdf
MEDIA:/opt/data/real.pdf
''';

      final result = parseHermesMedia(text);

      expect(result.artifacts.single.path, '/opt/data/real.pdf');
      expect(
        result.cleanText,
        contains('> MEDIA:/opt/data/quoted-example.pdf'),
      );
    });

    test('accepts emphasis-wrapped tags and CJK path terminators', () {
      const text = '**MEDIA:/opt/data/Report.pdf**\nMEDIA:/opt/data/报告.pdf。\n';

      final result = parseHermesMedia(text);

      expect(result.artifacts.map((item) => item.path), [
        '/opt/data/Report.pdf',
        '/opt/data/报告.pdf',
      ]);
      expect(result.cleanText, '');
    });

    test('does not parse a partial MEDIA token', () {
      const text = 'MEDIA-like prose: /opt/data/report.pdf';

      final result = parseHermesMedia(text);

      expect(result.cleanText, text);
      expect(result.artifacts, isEmpty);
    });

    test('does not match MEDIA inside a longer word', () {
      const text = 'MULTIMEDIA: /opt/data/report.pdf';

      final result = parseHermesMedia(text);

      expect(result.cleanText, text);
      expect(result.artifacts, isEmpty);
    });

    test('does not consume content on the next line after a bare tag', () {
      const text = 'MEDIA:\nThe file is ready.\n';

      final result = parseHermesMedia(text);

      expect(result.cleanText, text);
      expect(result.artifacts, isEmpty);
    });
  });
}
