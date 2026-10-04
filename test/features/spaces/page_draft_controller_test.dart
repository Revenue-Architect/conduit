import 'package:conduit/features/spaces/models/spaces_models.dart';
import 'package:conduit/features/spaces/services/page_draft_controller.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_spaces_server.dart';

void main() {
  late FakeSpacesServer server;
  late String body;
  late String title;

  Future<PageDraftController> open(FakeSpacesServer server) async {
    final pageJson = server.addPage(title: 'Plan', content: 'v1');
    final page = await server.client().page(pageJson['id']! as String);
    body = page.content;
    title = page.title;
    return PageDraftController(
      client: server.client(),
      page: page,
      readMarkdown: () => body,
      readTitle: () => title,
    );
  }

  setUp(() => server = FakeSpacesServer());

  test(
    'autosaves 800 ms after the last edit, once, with the loaded revision',
    () {
      fakeAsync((async) {
        late PageDraftController draft;
        open(server).then((value) => draft = value);
        async.flushMicrotasks();

        body = 'v2';
        draft.markEdited();
        async.elapse(const Duration(milliseconds: 500));
        body = 'v3';
        draft.markEdited();
        async.elapse(const Duration(milliseconds: 799));
        expect(server.requests.where((r) => r.startsWith('PATCH')), isEmpty);
        expect(draft.status, PageSaveStatus.dirty);

        async.elapse(const Duration(milliseconds: 2));
        async.flushMicrotasks();
        expect(
          server.requests.where((r) => r.startsWith('PATCH')),
          hasLength(1),
        );
        expect(draft.status, PageSaveStatus.saved);
        expect(draft.savedRevision, 2);
        expect(server.pages.values.single['content'], 'v3');
      });
    },
  );

  test(
    'a stale save keeps the draft, stops retrying, and loads the remote',
    () async {
      final draft = await open(server);
      server.editElsewhere(draft.page.id, 'kai edit');
      body = 'my edit';
      expect(await draft.save(), isFalse);
      expect(draft.status, PageSaveStatus.conflict);
      expect(draft.remote?.content, 'kai edit');
      expect(draft.remote?.revision, 2);
      // The draft is untouched and nothing retries on its own.
      expect(body, 'my edit');
      final patches = server.requests
          .where((r) => r.startsWith('PATCH'))
          .length;
      draft.markEdited();
      expect(await draft.save(), isFalse);
      expect(
        server.requests.where((r) => r.startsWith('PATCH')).length,
        patches,
      );
      expect(server.pages.values.single['content'], 'kai edit');
    },
  );

  test('keep my draft saves over the newest revision', () async {
    final draft = await open(server);
    server.editElsewhere(draft.page.id, 'kai edit');
    body = 'my edit';
    await draft.save();
    expect(await draft.keepMine(), isTrue);
    expect(draft.status, PageSaveStatus.saved);
    expect(server.pages.values.single['content'], 'my edit');
    expect(server.pages.values.single['revision'], 3);
  });

  test('use latest adopts the remote copy', () async {
    final draft = await open(server);
    server.editElsewhere(draft.page.id, 'kai edit');
    body = 'my edit';
    await draft.save();
    final latest = await draft.useLatest();
    expect(latest?.content, 'kai edit');
    expect(draft.status, PageSaveStatus.saved);
    expect(draft.savedRevision, 2);
  });

  test('returning to a clean Page shows newer server content; a dirty one '
      'goes to conflict instead', () async {
    final draft = await open(server);
    server.editElsewhere(draft.page.id, 'kai edit');
    final replaced = await draft.refreshFromServer();
    expect(replaced?.content, 'kai edit');
    expect(draft.savedRevision, 2);

    server.editElsewhere(draft.page.id, 'kai again');
    body = 'local change';
    draft.markEdited();
    expect(await draft.refreshFromServer(), isNull);
    expect(draft.status, PageSaveStatus.conflict);
    expect(body, 'local change');
  });

  test('flush reports failure so navigation can stay on the Page', () async {
    final draft = await open(server);
    body = 'unsaved';
    server.failNextWith = 500;
    expect(await draft.flush(), isFalse);
    expect(draft.status, PageSaveStatus.error);
    expect(draft.hasUnsavedChanges, isTrue);
    expect(await draft.flush(), isTrue);
    expect(draft.status, PageSaveStatus.saved);
  });

  test('a clean Page needs no save and an empty title is refused', () async {
    final draft = await open(server);
    expect(await draft.flush(), isTrue);
    expect(server.requests.where((r) => r.startsWith('PATCH')), isEmpty);
    title = '   ';
    expect(await draft.save(), isFalse);
    expect(draft.status, PageSaveStatus.error);
    title = 'x' * (SpacesLimits.pageTitle + 1);
    expect(await draft.save(), isFalse);
  });
}
