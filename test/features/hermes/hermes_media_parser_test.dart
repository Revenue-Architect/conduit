import 'package:conduit/features/hermes/services/hermes_media_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parseHermesMedia', () {
    test('keeps ordinary filesystem paths outside /opt/data as prose', () {
      const text =
          'The report is at /home/user/report.pdf and ~/notes.md and '
          'C:\\Users\\me\\a.pdf and artifacts/report.pdf.';

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
      const text = 'MEDIA-like prose: /home/user/report.pdf';

      final result = parseHermesMedia(text);

      expect(result.cleanText, text);
      expect(result.artifacts, isEmpty);
    });

    test('does not match MEDIA inside a longer word', () {
      const text = 'MULTIMEDIA: /home/user/report.pdf';

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

  group('bare /opt/data server paths', () {
    const handoff =
        '/opt/data/specialist-handoffs/2026-10-18/kai-20261018_231519_20db93.md';

    test("message 9747: a bare handoff path becomes a card", () {
      const text =
          "Kai's handoff is ready: $handoff \u2014 open it for the full plan.";

      final result = parseHermesMedia(text);

      expect(result.artifacts, hasLength(1));
      expect(result.artifacts.single.path, handoff);
      expect(result.artifacts.single.filename, 'kai-20261018_231519_20db93.md');
      expect(result.artifacts.single.kind, HermesMediaKind.file);
      expect(
        result.cleanText,
        "Kai's handoff is ready: kai-20261018_231519_20db93.md \u2014 open it "
        'for the full plan.',
      );
    });

    test('a trailing sentence period is not part of the path', () {
      final result = parseHermesMedia('Saved to $handoff.');

      expect(result.artifacts.single.path, handoff);
      expect(result.cleanText, 'Saved to kai-20261018_231519_20db93.md.');
    });

    test('a span that is exactly the path in single backticks is a path', () {
      final result = parseHermesMedia('Read `$handoff` next.');

      expect(result.artifacts, hasLength(1));
      expect(result.artifacts.single.path, handoff);
      expect(result.cleanText, 'Read `kai-20261018_231519_20db93.md` next.');
    });

    test('inline code with anything else around the path stays text', () {
      final text = 'Run `cat $handoff` to see it.';

      final result = parseHermesMedia(text);

      expect(result.artifacts, isEmpty);
      expect(result.cleanText, text);
    });

    test('a path inside a code fence stays text', () {
      final text = 'Output:\n```\n$handoff\n```\nDone.';

      final result = parseHermesMedia(text);

      expect(result.artifacts, isEmpty);
      expect(result.cleanText, text);
    });

    test('a backticked path inside a code fence stays text', () {
      final text = 'Output:\n```text\n`$handoff`\n```\n';

      expect(parseHermesMedia(text).artifacts, isEmpty);
    });

    test('a path in a blockquote stays text', () {
      final text = '> earlier I wrote $handoff\nOK.';

      final result = parseHermesMedia(text);

      expect(result.artifacts, isEmpty);
      expect(result.cleanText, text);
    });

    test('secrets, env files, auth, config and .. never become cards', () {
      for (final path in const [
        '/opt/data/.secrets/hermes-v2-ingest-key.txt',
        '/opt/data/.env.json',
        '/opt/data/profiles/kai/.env.txt',
        '/opt/data/auth.json',
        '/opt/data/profiles/kai/auth.json',
        '/opt/data/config.yaml',
        '/opt/data/profiles/ops/config.yaml',
        '/opt/data/specialist-handoffs/../.secrets/key.txt',
        '/opt/data/x/../../etc/passwd.txt',
      ]) {
        final text = 'See $path now.';
        final result = parseHermesMedia(text);
        expect(result.artifacts, isEmpty, reason: path);
        expect(result.cleanText, text, reason: path);
      }
    });

    test('a denied path is also refused in backticks and after MEDIA:', () {
      expect(
        parseHermesMedia('Key `/opt/data/.secrets/k.txt` here').artifacts,
        isEmpty,
      );
    });

    test('other roots, schemes and relative paths are not widened', () {
      for (final text in const [
        'See /opt/other/report.pdf now.',
        'See /opt/database/report.pdf now.',
        'See file:///opt/data/report.pdf now.',
        'See https://example.com/opt/data/report.pdf now.',
        'See opt/data/report.pdf now.',
        'See ./opt/data/report.pdf now.',
        'See /opt/data/ now.',
        'See /opt/data/notes.unknownext now.',
      ]) {
        final result = parseHermesMedia(text);
        expect(result.artifacts, isEmpty, reason: text);
        expect(result.cleanText, text, reason: text);
      }
    });

    test('a real MEDIA line plus the same bare path gives one card', () {
      final result = parseHermesMedia(
        'Handoff written to $handoff\nMEDIA:$handoff\n',
      );

      expect(result.artifacts, hasLength(1));
      expect(result.artifacts.single.path, handoff);
      expect(result.cleanText, 'Handoff written to kai-20261018_231519_20db93.md\n');
    });

    test('a MEDIA line and a different bare path give two cards', () {
      final result = parseHermesMedia(
        'Also see /opt/data/artifacts/b.pdf\nMEDIA:$handoff\n',
      );

      expect(result.artifacts.map((a) => a.path), [
        handoff,
        '/opt/data/artifacts/b.pdf',
      ]);
    });

    test('the same bare path twice gives one card but both mentions read well', () {
      final result = parseHermesMedia('Open $handoff, then reread $handoff.');

      expect(result.artifacts, hasLength(1));
      expect(
        result.cleanText,
        'Open kai-20261018_231519_20db93.md, then reread '
        'kai-20261018_231519_20db93.md.',
      );
    });

    test('MEDIA: used mid-sentence is still a directive', () {
      final result = parseHermesMedia('Here you go MEDIA:$handoff please.');

      expect(result.artifacts.single.path, handoff);
      expect(result.cleanText, 'Here you go  please.');
    });

    test('image and audio paths get their kinds', () {
      final result = parseHermesMedia(
        'Chart /opt/data/out/c.png and /opt/data/out/v.m4a ready',
      );

      expect(result.artifacts.map((a) => a.kind), [
        HermesMediaKind.image,
        HermesMediaKind.audio,
      ]);
    });
  });
}
