import 'package:conduit/features/spaces/services/hermes_spaces_client.dart';

/// An in-memory stand-in for the Hermes Spaces plugin API with the same
/// revision contract: every write bumps the revision once, a stale write is
/// `409 {"error": "revision_conflict", "current_revision": n}`.
class FakeSpacesServer {
  final Map<String, Map<String, Object?>> pages = {};
  final List<String> requests = [];
  int _ids = 0;

  /// When set, the next request fails with this status (once).
  int? failNextWith;

  String _uuid() {
    final n = (++_ids).toRadixString(16).padLeft(12, '0');
    return '00000000-0000-4000-8000-$n';
  }

  Map<String, Object?> addPage({
    String spaceId = '00000000-0000-4000-8000-0000000000aa',
    String title = 'Doc',
    String content = '',
  }) {
    final id = _uuid();
    final page = {
      'id': id,
      'space_id': spaceId,
      'parent_id': null,
      'title': title,
      'content': content,
      'revision': 1,
      'updated_at': 0,
    };
    pages[id] = page;
    return page;
  }

  /// Someone else (Kai, another device) saves the Page.
  void editElsewhere(String id, String content) {
    final page = pages[id]!;
    page['content'] = content;
    page['revision'] = (page['revision']! as int) + 1;
  }

  late final SpacesTransport transport =
      (method, path, {query, body, cancelToken}) async {
        requests.add('$method $path');
        final fail = failNextWith;
        if (fail != null) {
          failNextWith = null;
          return (status: fail, json: {'error': 'boom', 'message': 'boom'});
        }
        if (path == '/health') {
          return (status: 200, json: {'ok': true, 'schema_version': 1});
        }
        final match = RegExp(r'^/pages/([^/]+)$').firstMatch(path);
        if (match != null) {
          final page = pages[match.group(1)];
          if (page == null) {
            return (
              status: 404,
              json: {'error': 'not_found', 'message': 'Page not found.'},
            );
          }
          if (method == 'GET')
            return (
              status: 200,
              json: {
                'page': {...page},
              },
            );
          if (method == 'PATCH') {
            final expected = body!['expected_revision'];
            if (expected != page['revision']) {
              return (
                status: 409,
                json: {
                  'error': 'revision_conflict',
                  'message': 'The page changed since this draft was loaded.',
                  'current_revision': page['revision'],
                },
              );
            }
            if (body.containsKey('title')) page['title'] = body['title'];
            if (body.containsKey('content')) page['content'] = body['content'];
            page['revision'] = (page['revision']! as int) + 1;
            return (
              status: 200,
              json: {
                'page': {...page},
              },
            );
          }
        }
        return (status: 404, json: {'error': 'not_found', 'message': 'nope'});
      };

  HermesSpacesClient client() => HermesSpacesClient(transport);
}
