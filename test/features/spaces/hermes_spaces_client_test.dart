import 'package:conduit/features/spaces/models/spaces_models.dart';
import 'package:conduit/features/spaces/services/hermes_spaces_client.dart';
import 'package:conduit/features/spaces/utils/page_document_codec.dart';
import 'package:conduit/features/spaces/widgets/save_as_page_sheet.dart';
import 'package:flutter_test/flutter_test.dart';

HermesSpacesClient _client(SpacesResponse Function(String, String) reply) =>
    HermesSpacesClient(
      (method, path, {query, body, cancelToken}) async => reply(method, path),
    );

void main() {
  group('client', () {
    test('health: ok, missing plugin, older Hermes', () async {
      expect(
        await _client((_, _) => (status: 200, json: {'ok': true})).available(),
        isTrue,
      );
      expect(
        await _client((_, _) => (status: 404, json: null)).available(),
        isFalse,
      );
      expect(
        await _client((_, _) => (status: 405, json: null)).available(),
        isFalse,
      );
    });

    test('a 409 revision_conflict is typed, other errors are not', () async {
      final conflicted = _client(
        (_, _) => (
          status: 409,
          json: {'error': 'revision_conflict', 'current_revision': 16},
        ),
      );
      await expectLater(
        conflicted.updatePage(
          '00000000-0000-4000-8000-000000000001',
          expectedRevision: 14,
          content: 'x',
        ),
        throwsA(
          isA<SpacesRevisionConflict>().having(
            (e) => e.currentRevision,
            'currentRevision',
            16,
          ),
        ),
      );
      final notEmpty = _client(
        (_, _) => (
          status: 409,
          json: {'error': 'space_not_empty', 'message': 'Has pages.'},
        ),
      );
      await expectLater(
        notEmpty.deleteSpace('00000000-0000-4000-8000-000000000001'),
        throwsA(
          isA<SpacesApiException>()
              .having((e) => e.code, 'code', 'space_not_empty')
              .having((e) => e is SpacesRevisionConflict, 'conflict', isFalse),
        ),
      );
    });

    test('malformed ids never reach a request', () async {
      var requests = 0;
      final client = HermesSpacesClient((
        method,
        path, {
        query,
        body,
        cancelToken,
      }) async {
        requests++;
        return (status: 200, json: {});
      });
      for (final bad in [
        '../etc',
        '',
        'abc',
        '00000000-0000-4000-8000-00000000000G',
      ]) {
        await expectLater(client.page(bad), throwsA(isA<SpacesApiException>()));
      }
      expect(requests, 0);
    });

    test('list decoding drops malformed rows', () async {
      final client = _client(
        (_, _) => (
          status: 200,
          json: {
            'pages': [
              {
                'id': '00000000-0000-4000-8000-000000000001',
                'space_id': 's',
                'title': 'Good',
                'revision': 2,
                'excerpt': 'hi',
              },
              {'id': 'bad', 'title': 'Bad', 'revision': 1, 'space_id': 's'},
              'junk',
            ],
          },
        ),
      );
      final pages = await client.pages('00000000-0000-4000-8000-0000000000aa');
      expect(pages.map((p) => p.title), ['Good']);
      expect(isSpacesId(pages.single.id), isTrue);
    });
  });

  group('source mode', () {
    test('plain supported Markdown stays visual', () {
      const supported =
          '# Title\n\nSome **bold**, *italic*, ~~gone~~ and `code`.\n\n'
          '- one\n- two\n\n1. first\n2. second\n\n- [ ] todo\n- [x] done\n\n'
          '> quote\n\n```\ncode block\n```\n\n[link](https://example.com)\n\n---\n';
      expect(sourceModeReason(supported), isNull);
      expect(sourceModeReason(''), isNull);
    });

    test('constructs the visual editor would lose force source mode', () {
      expect(sourceModeReason('<div>hi</div>'), 'raw HTML');
      expect(sourceModeReason('<script>x</script>'), 'raw HTML');
      expect(sourceModeReason('![alt](x.png)'), 'images');
      expect(sourceModeReason('Note[^1]\n\n[^1]: here'), 'footnotes');
      expect(sourceModeReason('---\ntitle: x\n---\nbody'), 'front matter');
      expect(sourceModeReason('::: warning\nhi\n:::'), 'directives');
      expect(sourceModeReason(r'$$x^2$$'), 'display math');
      expect(sourceModeReason('| a | b |\n|---|---|\n| 1 | 2 |'), 'tables');
      expect(sourceModeReason('- a\n  - nested'), 'nested lists');
      expect(sourceModeReason('Title\n====='), 'setext headings');
    });
  });

  group('save as page', () {
    test('suggests the first heading, else the first line, clipped', () {
      expect(
        suggestPageTitle('Intro\n\n## Local **models** compared\n'),
        'Local models compared',
      );
      expect(
        suggestPageTitle('Plain first line.\nSecond'),
        'Plain first line.',
      );
      expect(suggestPageTitle(''), 'Saved reply');
      final long = suggestPageTitle('word ' * 40);
      expect(long.length, lessThanOrEqualTo(73));
      expect(long.endsWith('…'), isTrue);
    });
  });
}
