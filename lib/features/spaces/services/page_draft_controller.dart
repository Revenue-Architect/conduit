import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/spaces_models.dart';
import 'hermes_spaces_client.dart';

/// Where a Page draft is relative to the server.
enum PageSaveStatus { saved, dirty, saving, error, conflict }

/// The autosave and revision-conflict state machine of one open Page.
///
/// Edits mark the draft dirty; 800 ms later it is saved against the revision
/// it was loaded at. A stale save never overwrites: the draft is kept, saving
/// stops, and the newest server copy is fetched for the user to resolve.
/// Nothing here ever discards local text without an explicit call.
class PageDraftController extends ChangeNotifier {
  PageDraftController({
    required HermesSpacesClient client,
    required HermesPage page,
    required String Function() readMarkdown,
    required String Function() readTitle,
    this.debounce = const Duration(milliseconds: 800),
  }) : _client = client,
       _readMarkdown = readMarkdown,
       _readTitle = readTitle,
       _page = page,
       _savedRevision = page.revision,
       _savedTitle = page.title,
       _savedMarkdown = page.content;

  final HermesSpacesClient _client;
  final String Function() _readMarkdown;
  final String Function() _readTitle;
  final Duration debounce;

  HermesPage _page;
  int _savedRevision;
  String _savedTitle;
  String _savedMarkdown;
  PageSaveStatus _status = PageSaveStatus.saved;
  String? _errorMessage;
  HermesPage? _remote;
  Timer? _timer;
  Future<bool>? _inFlight;
  bool _editedDuringSave = false;
  bool _disposed = false;

  HermesPage get page => _page;
  int get savedRevision => _savedRevision;
  PageSaveStatus get status => _status;
  String? get errorMessage => _errorMessage;

  /// The newer server copy while in [PageSaveStatus.conflict].
  HermesPage? get remote => _remote;

  bool get hasUnsavedChanges =>
      _status != PageSaveStatus.saved ||
      _readTitle().trim() != _savedTitle ||
      _readMarkdown() != _savedMarkdown;

  /// Call on every edit of the title or the body.
  void markEdited() {
    if (_status == PageSaveStatus.conflict) return; // resolved explicitly
    if (_status == PageSaveStatus.saving) {
      _editedDuringSave = true;
      return;
    }
    _set(PageSaveStatus.dirty);
    _timer?.cancel();
    _timer = Timer(debounce, () => unawaited(save()));
  }

  /// Saves now. True when the server holds exactly what is on screen.
  Future<bool> save() {
    _timer?.cancel();
    final running = _inFlight;
    if (running != null) {
      return running.then(
        (_) => _status == PageSaveStatus.saved ? true : save(),
      );
    }
    if (_status == PageSaveStatus.conflict) return Future.value(false);
    final title = _readTitle().trim();
    final markdown = _readMarkdown();
    if (title == _savedTitle && markdown == _savedMarkdown) {
      if (_status != PageSaveStatus.saved) _set(PageSaveStatus.saved);
      return Future.value(true);
    }
    if (title.isEmpty || title.length > SpacesLimits.pageTitle) {
      _fail(
        'Give the Page a title of up to ${SpacesLimits.pageTitle} characters.',
      );
      return Future.value(false);
    }
    if (markdown.length > SpacesLimits.pageContent) {
      _fail('This Page is longer than ${SpacesLimits.pageContent} characters.');
      return Future.value(false);
    }
    final future = _send(title, markdown, _savedRevision);
    _inFlight = future;
    return future.whenComplete(() => _inFlight = null);
  }

  /// Saves pending edits before leaving. True when it is safe to leave.
  Future<bool> flush() async {
    if (!hasUnsavedChanges) return true;
    return save();
  }

  Future<bool> _send(String title, String markdown, int expected) async {
    _editedDuringSave = false;
    _set(PageSaveStatus.saving);
    try {
      final saved = await _client.updatePage(
        _page.id,
        expectedRevision: expected,
        title: title == _savedTitle ? null : title,
        content: markdown == _savedMarkdown ? null : markdown,
      );
      _page = saved;
      _savedRevision = saved.revision;
      _savedTitle = saved.title;
      _savedMarkdown = markdown;
      _errorMessage = null;
      if (_editedDuringSave) {
        _editedDuringSave = false;
        _set(PageSaveStatus.dirty);
        _timer?.cancel();
        _timer = Timer(debounce, () => unawaited(save()));
        return false;
      }
      _set(PageSaveStatus.saved);
      return true;
    } on SpacesRevisionConflict {
      await _enterConflict();
      return false;
    } on SpacesApiException catch (error) {
      _fail(error.message);
      return false;
    } catch (_) {
      _fail('Could not save. Your changes are still here.');
      return false;
    }
  }

  Future<void> _enterConflict() async {
    _timer?.cancel();
    _errorMessage = null;
    _set(PageSaveStatus.conflict);
    try {
      _remote = await _client.page(_page.id);
    } catch (_) {
      _remote = null;
    }
    _notify();
  }

  void _fail(String message) {
    _errorMessage = message;
    _set(PageSaveStatus.error);
  }

  /// Fetches the server copy. A newer revision replaces a clean draft
  /// (returned so the editor can show it) and puts a dirty one in conflict.
  Future<HermesPage?> refreshFromServer() async {
    if (_inFlight != null || _status == PageSaveStatus.conflict) return null;
    final HermesPage latest;
    try {
      latest = await _client.page(_page.id);
    } catch (_) {
      return null;
    }
    if (latest.revision <= _savedRevision) return null;
    if (hasUnsavedChanges) {
      _remote = latest;
      _timer?.cancel();
      _set(PageSaveStatus.conflict);
      return null;
    }
    _adopt(latest);
    return latest;
  }

  /// Conflict resolution: keep this draft. Saves it over the newest server
  /// revision (after the user has confirmed and seen the remote copy).
  Future<bool> keepMine() async {
    final remote = _remote ?? await _latestOrNull();
    if (remote == null) {
      _fail('Could not load the latest version. Try again.');
      return false;
    }
    _savedRevision = remote.revision;
    _savedTitle = remote.title;
    _savedMarkdown = remote.content;
    _remote = null;
    _set(PageSaveStatus.dirty);
    final title = _readTitle().trim();
    final markdown = _readMarkdown();
    final future = _send(title, markdown, remote.revision);
    _inFlight = future;
    return future.whenComplete(() => _inFlight = null);
  }

  /// Conflict resolution: discard this draft for the newest server copy.
  /// Returns it so the editor can load it.
  Future<HermesPage?> useLatest() async {
    final remote = _remote ?? await _latestOrNull();
    if (remote == null) {
      _fail('Could not load the latest version. Try again.');
      return null;
    }
    _adopt(remote);
    return remote;
  }

  Future<HermesPage?> _latestOrNull() async {
    try {
      return await _client.page(_page.id);
    } catch (_) {
      return null;
    }
  }

  void _adopt(HermesPage latest) {
    _timer?.cancel();
    _page = latest;
    _savedRevision = latest.revision;
    _savedTitle = latest.title;
    _savedMarkdown = latest.content;
    _remote = null;
    _errorMessage = null;
    _set(PageSaveStatus.saved);
  }

  /// After a move or another metadata change made elsewhere in the UI.
  void adoptSaved(HermesPage saved) {
    _page = saved;
    _savedRevision = saved.revision;
    _savedTitle = saved.title;
    _notify();
  }

  void _set(PageSaveStatus status) {
    _status = status;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    super.dispose();
  }
}
