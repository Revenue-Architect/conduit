import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../shared/theme/theme_extensions.dart';
import '../../../desktop/hermez_desktop.dart';
import '../../admin/hermes_admin_client.dart';
import '../../admin/hermes_admin_models.dart';
import '../../admin/hermes_admin_providers.dart';
import '../../admin/hermes_config_backups.dart';
import '../../admin/hermes_config_document.dart';
import '../../admin/hermes_secret_redaction.dart';
import '../../sheets/hermez_modal_sheet.dart';
import '../../widgets/hermez_chat_palette.dart';
import '../../widgets/hermez_skeleton.dart';
import '../../widgets/hermez_surfaces.dart';
import '../../widgets/hermez_visual_theme.dart';

/// Edits a bot's config, or the server's root config, as YAML (KTD9, R20).
///
/// [scope] is the bot's name; null edits the root config. Secrets show as
/// placeholders (see [HermesConfigDocument]) and are put back from a fresh
/// read on save, so no key is ever shown, diffed or kept on the device.
/// Save checks the document, then always opens a diff review; nothing is
/// written until it is confirmed. The page needs a bounded height.
///
/// Unsaved edits live in this page's state, so they survive the window being
/// hidden to the tray and a reconnect. [onDirtyChanged] reports whether there
/// are any, for a shell that must ask before navigating away; leaving by Back
/// asks here.
class HermesAdvancedConfigPage extends ConsumerStatefulWidget {
  const HermesAdvancedConfigPage({
    super.key,
    this.scope,
    this.botTitle,
    this.onDirtyChanged,
  });

  /// The bot's name, or null for the server's root config.
  final String? scope;

  /// What to call the bot, when it has a title besides its name.
  final String? botTitle;

  final ValueChanged<bool>? onDirtyChanged;

  @override
  ConsumerState<HermesAdvancedConfigPage> createState() =>
      _HermesAdvancedConfigPageState();
}

enum _Load { loading, ready, failed, unavailable }

/// What the owner chose in the save review.
enum _ReviewDecision { write, reload }

class _HermesAdvancedConfigPageState
    extends ConsumerState<HermesAdvancedConfigPage> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focus = FocusNode(debugLabel: 'advanced config editor');

  _Load _load = _Load.loading;
  String _loadError = '';

  /// The file as the server last gave it. Holds secrets: kept in memory only,
  /// to tell whether the server's copy changed. Never shown.
  String _loadedRaw = '';

  /// What the editor showed on load; the baseline for "unsaved edits".
  String _loadedMasked = '';
  HermesAdminConfigSchema? _schema;
  Set<String>? _roots;
  int _commentsScrubbed = 0;

  HermesConfigValidation _live = const HermesConfigValidation([]);
  List<HermesConfigIssue> _blockers = const [];
  String? _saveError;
  String? _status;

  /// A save is under way, from the press of Save to the end, review included.
  bool _busy = false;

  /// The page is waiting on Hermes (not on the owner): drives the spinner.
  bool _working = false;
  bool _dirty = false;
  bool _settingText = false;
  Timer? _liveTimer;
  int _loadSerial = 0;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onTextChanged);
    unawaited(_loadConfig());
  }

  @override
  void dispose() {
    _liveTimer?.cancel();
    _controller
      ..removeListener(_onTextChanged)
      ..dispose();
    _focus.dispose();
    super.dispose();
  }

  // -------------------------------------------------------------------------
  // Loading
  // -------------------------------------------------------------------------

  Future<void> _loadConfig() async {
    final client = ref.read(hermesAdminClientProvider);
    final serial = ++_loadSerial;
    if (client == null) {
      setState(() => _load = _Load.unavailable);
      return;
    }
    setState(() {
      _load = _Load.loading;
      _loadError = '';
    });
    final scope = widget.scope;
    try {
      // Started together; the schema and the known roots are optional.
      final results = await Future.wait<Object?>([
        client.rawConfig(scope),
        HermesAdminClient.ifAvailable(() => client.configSchema(scope)),
        HermesAdminClient.ifAvailable(client.knownConfigRootKeys),
      ]);
      if (!mounted || serial != _loadSerial) return;
      _showLoaded(
        results[0]! as HermesAdminRawConfig,
        schema: results[1] as HermesAdminConfigSchema?,
        roots: results[2] as Set<String>?,
      );
    } on HermesAdminUnavailable {
      if (mounted && serial == _loadSerial) {
        setState(() => _load = _Load.unavailable);
      }
    } on ArgumentError {
      if (mounted && serial == _loadSerial) {
        setState(() => _load = _Load.unavailable);
      }
    } catch (error) {
      if (!mounted || serial != _loadSerial) return;
      setState(() {
        _load = _Load.failed;
        _loadError = _describe(error, "Couldn't load the config.");
      });
    }
  }

  void _showLoaded(
    HermesAdminRawConfig raw, {
    HermesAdminConfigSchema? schema,
    Set<String>? roots,
    String? status,
  }) {
    final masked = HermesConfigDocument.mask(raw.yaml);
    _settingText = true;
    _controller.value = TextEditingValue(
      text: masked.text,
      selection: const TextSelection.collapsed(offset: 0),
    );
    _settingText = false;
    _liveTimer?.cancel();
    setState(() {
      _load = _Load.ready;
      _loadedRaw = raw.yaml;
      _loadedMasked = masked.text;
      _commentsScrubbed = masked.commentsScrubbed;
      _schema = schema ?? _schema;
      _roots = roots ?? _roots;
      _blockers = const [];
      _saveError = null;
      _status = status;
      _live = const HermesConfigValidation([]);
    });
    _setDirty(false);
  }

  /// Server text made safe to show.
  String _describe(Object error, String fallback) {
    if (error is HermesAdminException) {
      return HermesSecretRedaction.redactText(error.message);
    }
    return fallback;
  }

  // -------------------------------------------------------------------------
  // Editing
  // -------------------------------------------------------------------------

  void _onTextChanged() {
    if (_settingText || _load != _Load.ready) return;
    _setDirty(_controller.text != _loadedMasked);
    _liveTimer?.cancel();
    _liveTimer = Timer(const Duration(milliseconds: 350), () {
      if (!mounted) return;
      setState(() {
        _live = HermesConfigDocument.validate(
          _controller.text,
          schema: _schema,
          knownRoots: _roots,
        );
      });
    });
    if (_blockers.isNotEmpty || _saveError != null || _status != null) {
      setState(() {
        _blockers = const [];
        _saveError = null;
        _status = null;
      });
    }
  }

  void _setDirty(bool dirty) {
    if (dirty == _dirty) return;
    setState(() => _dirty = dirty);
    widget.onDirtyChanged?.call(dirty);
  }

  /// Tab indents instead of moving focus.
  void _insertIndent() {
    final value = _controller.value;
    final selection = value.selection;
    if (!selection.isValid) return;
    const indent = '  ';
    _controller.value = TextEditingValue(
      text: value.text.replaceRange(selection.start, selection.end, indent),
      selection: TextSelection.collapsed(
        offset: selection.start + indent.length,
      ),
    );
  }

  /// Ctrl+Tab and Escape hand focus on, so the keyboard is never trapped in
  /// the editor.
  void _leaveEditor() {
    if (!_focus.nextFocus()) _focus.unfocus();
  }

  // -------------------------------------------------------------------------
  // Saving
  // -------------------------------------------------------------------------

  Future<void> _save() async {
    if (_busy || _load != _Load.ready) return;
    final client = ref.read(hermesAdminClientProvider);
    if (client == null) return;
    final scope = widget.scope;
    final text = _controller.text;
    _liveTimer?.cancel();

    // Refused here, before anything is read or written.
    final validation = HermesConfigDocument.validate(
      text,
      schema: _schema,
      knownRoots: _roots,
    );
    setState(() {
      _live = validation;
      _blockers = const [];
      _saveError = null;
      _status = null;
    });
    if (!validation.ok) return;

    setState(() {
      _busy = true;
      _working = true;
    });
    try {
      var fresh = await client.rawConfig(scope);
      while (true) {
        if (!mounted) return;
        final restored = HermesConfigDocument.restore(
          editedText: text,
          serverYaml: fresh.yaml,
        );
        if (!restored.ok) {
          setState(() => _blockers = restored.blockers);
          return;
        }
        final diff = HermesConfigDocument.diff(fresh.yaml, restored.text!);
        setState(() => _working = false);
        final decision = await _review(
          diff,
          validation.warnings.toList(growable: false),
          changedSinceLoad: fresh.yaml != _loadedRaw,
        );
        if (!mounted || decision == null) return;
        setState(() => _working = true);
        if (decision == _ReviewDecision.reload) {
          await _loadConfig();
          return;
        }
        // Right before writing, read again: if the file moved while the owner
        // was reviewing, they review the new difference first.
        final latest = await client.rawConfig(scope);
        if (latest.yaml != fresh.yaml) {
          fresh = latest;
          continue;
        }
        await _write(client, scope, fresh, restored.text!, diff);
        return;
      }
    } catch (error) {
      if (mounted) {
        setState(() => _saveError = _describe(error, "Couldn't save."));
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _working = false;
        });
      }
    }
  }

  Future<void> _write(
    HermesAdminClient client,
    String? scope,
    HermesAdminRawConfig fresh,
    String text,
    HermesConfigDiff diff,
  ) async {
    try {
      // The safety net first: no backup, no write.
      await ref.read(hermesConfigBackupStoreProvider).add(scope, fresh.yaml);
    } catch (_) {
      setState(
        () => _saveError = "Couldn't keep a backup, so nothing was saved.",
      );
      return;
    }
    await client.saveRawConfig(scope, text);
    final note = diff.needsRestart
        ? 'Saved. Restart needed for these changes to take effect.'
        : 'Saved. Applies to new chats.';
    // Show the file as the server wrote it.
    HermesAdminRawConfig written;
    try {
      written = await client.rawConfig(scope);
    } catch (_) {
      written = HermesAdminRawConfig(yaml: text, path: '');
    }
    if (!mounted) return;
    _showLoaded(written, status: note);
  }

  Future<_ReviewDecision?> _review(
    HermesConfigDiff diff,
    List<HermesConfigIssue> warnings, {
    required bool changedSinceLoad,
  }) => pushHermezSheetRoute<_ReviewDecision>(
    context,
    builder: (_) => _ReviewSheet(
      scopeLabel: _scopeLabel(),
      diff: diff,
      warnings: warnings,
      changedSinceLoad: changedSinceLoad,
    ),
  );

  String _scopeLabel() => widget.scope == null
      ? 'Server config'
      : 'Bot ${widget.botTitle ?? widget.scope}';

  // -------------------------------------------------------------------------
  // Reload, backups, leaving
  // -------------------------------------------------------------------------

  Future<void> _reload() async {
    if (_dirty &&
        !await _confirmDiscard(
          title: 'Discard your edits?',
          message: 'Reloading replaces the editor with the server’s version.',
          confirmLabel: 'Discard and reload',
        )) {
      return;
    }
    if (mounted) await _loadConfig();
  }

  Future<void> _openBackups() async {
    final backups = ref
        .read(hermesConfigBackupStoreProvider)
        .list(widget.scope);
    final chosen = await pushHermezSheetRoute<HermesConfigBackup>(
      context,
      builder: (_) =>
          _BackupsSheet(scopeLabel: _scopeLabel(), backups: backups),
    );
    if (chosen == null || !mounted) return;
    if (_dirty &&
        !await _confirmDiscard(
          title: 'Replace your edits?',
          message: 'The backup replaces what is in the editor.',
          confirmLabel: 'Replace',
        )) {
      return;
    }
    if (!mounted) return;
    // A restore is an ordinary edit: it goes through validation, the
    // secret check and the diff review like any other save.
    _controller.value = TextEditingValue(
      text: chosen.yaml,
      selection: const TextSelection.collapsed(offset: 0),
    );
    await _save();
  }

  Future<bool> _confirmDiscard({
    required String title,
    required String message,
    required String confirmLabel,
  }) async =>
      await pushHermezSheetRoute<bool>(
        context,
        heightFactor: 0.5,
        builder: (sheetContext) => HermezModalSheet(
          title: title,
          eyebrow: _scopeLabel(),
          body: Text(message),
          footer: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => Navigator.of(sheetContext).pop(false),
                child: const Text('Keep editing'),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: () => Navigator.of(sheetContext).pop(true),
                child: Text(confirmLabel),
              ),
            ],
          ),
        ),
      ) ??
      false;

  Future<void> _onPopBlocked() async {
    final leave = await _confirmDiscard(
      title: 'Leave without saving?',
      message: 'Your edits to the config have not been saved.',
      confirmLabel: 'Leave',
    );
    if (leave && mounted) Navigator.of(context).pop();
  }

  // -------------------------------------------------------------------------
  // Build
  // -------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    // A connection that arrives after the page opened.
    ref.listen(hermesAdminClientProvider, (previous, next) {
      if (next != null && _load == _Load.unavailable) unawaited(_loadConfig());
    });
    final theme = hermezVisualTheme(Theme.of(context));
    final palette = HermezChatPalette.forBrightness(theme.brightness);
    return Theme(
      data: theme,
      child: PopScope(
        canPop: !_dirty,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) unawaited(_onPopBlocked());
        },
        child: Material(
          type: MaterialType.transparency,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final body = Padding(
                padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _header(palette),
                    const SizedBox(height: 12),
                    Expanded(child: _content(palette)),
                  ],
                ),
              );
              return constraints.hasBoundedHeight
                  ? body
                  : SizedBox(height: 560, child: body);
            },
          ),
        ),
      ),
    );
  }

  Widget _header(HermezChatPalette palette) {
    final root = widget.scope == null;
    final canAct = _load == _Load.ready;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          runSpacing: 6,
          children: [
            Text(
              'Advanced config',
              style: HermezType.section(palette).copyWith(fontSize: 20),
            ),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                OutlinedButton.icon(
                  onPressed: canAct && !_busy ? _openBackups : null,
                  icon: const Icon(Icons.history_rounded, size: 18),
                  label: const Text('Backups'),
                ),
                OutlinedButton.icon(
                  onPressed: canAct && !_busy ? _reload : null,
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: const Text('Reload'),
                ),
                FilledButton.icon(
                  onPressed: canAct && _dirty && !_busy ? _save : null,
                  icon: _working
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save_outlined, size: 18),
                  label: const Text('Save'),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          root
              ? 'Editing the server’s root config. This does not change '
                    'existing bots.'
              : 'Editing ${widget.botTitle ?? widget.scope}’s config '
                    '(${widget.scope}). Changes apply to its new chats.',
          key: const ValueKey('advanced-config-scope'),
          style: HermezType.meta(palette),
        ),
        const SizedBox(height: 2),
        Text(
          'Secrets show as <secret:…> and are kept as they are unless you '
          'replace or delete them.',
          style: HermezType.meta(palette),
        ),
      ],
    );
  }

  Widget _content(HermezChatPalette palette) => switch (_load) {
    _Load.loading => Align(
      alignment: Alignment.topCenter,
      child: HermezSkeleton.lines(
        key: const ValueKey('advanced-config-loading'),
        count: 9,
      ),
    ),
    _Load.failed => _Notice(
      key: const ValueKey('advanced-config-error'),
      message: _loadError,
      action: OutlinedButton(
        onPressed: _loadConfig,
        child: const Text('Retry'),
      ),
    ),
    _Load.unavailable => const _Notice(
      key: ValueKey('advanced-config-unavailable'),
      message:
          'Advanced config isn’t available on this Hermes server, or this '
          'connection can’t reach it.',
    ),
    _Load.ready => _editor(palette),
  };

  Widget _editor(HermezChatPalette palette) {
    final mono = TextStyle(
      fontFamily: HermezDesktop.isActive
          ? 'Consolas'
          : AppTypography.monospaceFontFamily,
      fontFamilyFallback: const ['Cascadia Mono', 'Courier New', 'monospace'],
      fontSize: 13,
      height: 1.45,
      color: palette.ink,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: palette.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: palette.border),
            ),
            child: CallbackShortcuts(
              bindings: {
                const SingleActivator(LogicalKeyboardKey.tab): _insertIndent,
                const SingleActivator(LogicalKeyboardKey.tab, control: true):
                    _leaveEditor,
                const SingleActivator(LogicalKeyboardKey.escape): _leaveEditor,
              },
              child: Semantics(
                label: 'Config editor',
                child: TextField(
                  key: const ValueKey('advanced-config-editor'),
                  controller: _controller,
                  focusNode: _focus,
                  readOnly: _busy,
                  maxLines: null,
                  expands: true,
                  textAlignVertical: TextAlignVertical.top,
                  keyboardType: TextInputType.multiline,
                  autocorrect: false,
                  enableSuggestions: false,
                  smartDashesType: SmartDashesType.disabled,
                  smartQuotesType: SmartQuotesType.disabled,
                  style: mono,
                  cursorColor: palette.accent,
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    filled: false,
                    contentPadding: EdgeInsets.all(14),
                  ),
                ),
              ),
            ),
          ),
        ),
        ..._messages(palette),
      ],
    );
  }

  List<Widget> _messages(HermezChatPalette palette) {
    final status = Theme.of(context).extension<HermezStatusColors>();
    final danger = status?.danger ?? Theme.of(context).colorScheme.error;
    final warning = status?.warning ?? Colors.orange;
    final success = status?.success ?? Colors.green;
    final rows = <Widget>[
      for (final issue in _live.errors)
        _MessageRow(
          icon: Icons.error_outline_rounded,
          color: danger,
          text: _issueText(issue),
        ),
      for (final blocker in _blockers)
        _MessageRow(
          icon: Icons.key_off_outlined,
          color: danger,
          text:
              '${blocker.message}: ${blocker.key ?? 'a value'}'
              '${blocker.line == null ? '' : ' (line ${blocker.line})'}. '
              'A placeholder can only stay where it was.',
        ),
      if (_saveError != null)
        _MessageRow(
          icon: Icons.error_outline_rounded,
          color: danger,
          text: _saveError!,
        ),
      for (final issue in _live.warnings)
        _MessageRow(
          icon: Icons.warning_amber_rounded,
          color: warning,
          text: _issueText(issue),
        ),
      if (_commentsScrubbed > 0)
        _MessageRow(
          icon: Icons.visibility_off_outlined,
          color: warning,
          text:
              '$_commentsScrubbed comment(s) held a credential-like value. '
              'It is hidden as *** and stays hidden if you save.',
        ),
      if (_schema == null)
        _MessageRow(
          icon: Icons.info_outline_rounded,
          color: palette.muted,
          text:
              'This Hermes does not publish a config schema, so value types '
              'are not checked.',
        ),
      if (_status != null)
        _MessageRow(
          icon: Icons.check_circle_outline_rounded,
          color: success,
          text: _status!,
        ),
    ];
    if (rows.isEmpty) return const [];
    return [
      const SizedBox(height: 10),
      ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 150),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: rows,
          ),
        ),
      ),
    ];
  }

  static String _issueText(HermesConfigIssue issue) =>
      issue.line == null || issue.message.contains('line ')
      ? issue.message
      : '${issue.message} (line ${issue.line})';
}

// ---------------------------------------------------------------------------
// Messages
// ---------------------------------------------------------------------------

class _MessageRow extends StatelessWidget {
  const _MessageRow({
    required this.icon,
    required this.color,
    required this.text,
  });

  final IconData icon;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    final palette = HermezChatPalette.forBrightness(
      Theme.of(context).brightness,
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: HermezType.body(palette).copyWith(fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

/// A message in place of the editor, with an optional action.
class _Notice extends StatelessWidget {
  const _Notice({super.key, required this.message, this.action});

  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final palette = HermezChatPalette.forBrightness(
      Theme.of(context).brightness,
    );
    return Align(
      alignment: Alignment.topLeft,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: palette.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: palette.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message, style: HermezType.body(palette)),
            if (action != null) ...[const SizedBox(height: 12), action!],
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Save review
// ---------------------------------------------------------------------------

/// The diff the owner confirms before anything is written. A change under a
/// guard root (approvals, security, dashboard) is labelled and needs a second
/// confirmation. When the server's copy changed since the editor loaded, the
/// diff is against the latest version and the choices are Reload or
/// Overwrite.
class _ReviewSheet extends StatefulWidget {
  const _ReviewSheet({
    required this.scopeLabel,
    required this.diff,
    required this.warnings,
    required this.changedSinceLoad,
  });

  final String scopeLabel;
  final HermesConfigDiff diff;
  final List<HermesConfigIssue> warnings;
  final bool changedSinceLoad;

  @override
  State<_ReviewSheet> createState() => _ReviewSheetState();
}

class _ReviewSheetState extends State<_ReviewSheet> {
  bool _guardStep = false;

  bool get _guarded => widget.diff.guardRoots.isNotEmpty;

  void _write() {
    if (_guarded && !_guardStep) {
      setState(() => _guardStep = true);
      return;
    }
    Navigator.of(context).pop(_ReviewDecision.write);
  }

  @override
  Widget build(BuildContext context) {
    final palette = HermezChatPalette.forBrightness(
      Theme.of(context).brightness,
    );
    final status = Theme.of(context).extension<HermezStatusColors>();
    final warning = status?.warning ?? Colors.orange;
    final danger = status?.danger ?? Theme.of(context).colorScheme.error;
    final diff = widget.diff;
    final roots = (diff.guardRoots.toList()..sort()).join(', ');
    return HermezModalSheet(
      title: 'Review changes',
      eyebrow: widget.scopeLabel,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.changedSinceLoad)
            _Banner(
              key: const ValueKey('review-changed-banner'),
              color: warning,
              icon: Icons.sync_problem_rounded,
              text:
                  'This config changed on the server after you opened it. '
                  'The changes below are against the latest version. Reload '
                  'to discard your edits, or Overwrite to write yours.',
            ),
          if (_guarded)
            _Banner(
              key: const ValueKey('review-guard-banner'),
              color: danger,
              icon: Icons.shield_outlined,
              text:
                  'Guarded settings change: $roots. These control what the '
                  'bot may do without asking and who can reach it.',
              children: [
                for (final change in diff.guardChanges)
                  Text(
                    '${change.key}: ${change.from} → ${change.to}',
                    style: TextStyle(
                      fontFamily: AppTypography.monospaceFontFamily,
                      fontSize: 12,
                      color: palette.ink,
                    ),
                  ),
              ],
            ),
          for (final issue in widget.warnings)
            _Banner(
              color: warning,
              icon: Icons.warning_amber_rounded,
              text: issue.message,
            ),
          if (!diff.hasChanges)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text(
                'There are no differences from the server’s version.',
                style: HermezType.body(palette),
              ),
            )
          else ...[
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                '+${diff.added}  −${diff.removed} lines',
                style: HermezType.meta(palette),
              ),
            ),
            _DiffView(diff: diff),
            if (diff.needsRestart)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(
                  'These changes need a restart to take effect.',
                  style: HermezType.meta(palette),
                ),
              ),
          ],
        ],
      ),
      footer: _guardStep ? _guardFooter(danger) : _reviewFooter(),
    );
  }

  Widget _reviewFooter() {
    final canWrite = widget.diff.hasChanges;
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        if (widget.changedSinceLoad) ...[
          const SizedBox(width: 8),
          OutlinedButton(
            onPressed: () => Navigator.of(context).pop(_ReviewDecision.reload),
            child: const Text('Reload'),
          ),
        ],
        const SizedBox(width: 8),
        FilledButton(
          onPressed: canWrite ? _write : null,
          child: Text(widget.changedSinceLoad ? 'Overwrite' : 'Confirm'),
        ),
      ],
    );
  }

  Widget _guardFooter(Color danger) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(
        'Confirm again to change ${(widget.diff.guardRoots.toList()..sort()).join(', ')}.',
        key: const ValueKey('review-guard-confirm-text'),
        style: TextStyle(color: danger, fontWeight: FontWeight.w700),
      ),
      const SizedBox(height: 8),
      Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          TextButton(
            onPressed: () => setState(() => _guardStep = false),
            child: const Text('Back'),
          ),
          const SizedBox(width: 8),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: danger),
            onPressed: _write,
            child: const Text('Confirm guarded change'),
          ),
        ],
      ),
    ],
  );
}

class _Banner extends StatelessWidget {
  const _Banner({
    super.key,
    required this.color,
    required this.icon,
    required this.text,
    this.children = const [],
  });

  final Color color;
  final IconData icon;
  final String text;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final palette = HermezChatPalette.forBrightness(
      Theme.of(context).brightness,
    );
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.6)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  text,
                  style: HermezType.body(palette).copyWith(fontSize: 13),
                ),
                if (children.isNotEmpty) const SizedBox(height: 6),
                ...children,
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Diff view
// ---------------------------------------------------------------------------

/// Lines of unchanged text shown around each change.
const int _kDiffContext = 3;

/// A diff of masked text. One column on a phone; old beside new on a wide
/// desktop window.
class _DiffView extends StatelessWidget {
  const _DiffView({required this.diff});

  final HermesConfigDiff diff;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final sideBySide = HermezDesktop.isActive && constraints.maxWidth >= 720;
      final rows = _rows(diff.lines);
      return DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(
            color: HermezChatPalette.forBrightness(Theme.of(context).brightness)
                .border,
          ),
          borderRadius: BorderRadius.circular(10),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Column(
            key: ValueKey(
              sideBySide ? 'diff-side-by-side' : 'diff-single-column',
            ),
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final row in rows)
                if (row is int)
                  _Gap(count: row)
                else if (sideBySide)
                  _SideBySideRow(pair: row as _Pair)
                else
                  ..._unified(row as _Pair),
            ],
          ),
        ),
      );
    },
  );

  /// A single-column row for each side of a pair: removed lines, then added.
  static Iterable<Widget> _unified(_Pair pair) sync* {
    if (pair.left != null && pair.left!.kind != HermesDiffKind.same) {
      yield _DiffLine(line: pair.left!);
    }
    if (pair.right != null) yield _DiffLine(line: pair.right!);
  }

  /// Rows of the view: [_Pair]s, and an int for a stretch of unchanged lines
  /// that is left out.
  static List<Object> _rows(List<HermesDiffLine> lines) {
    final show = List<bool>.filled(lines.length, false);
    for (var i = 0; i < lines.length; i++) {
      if (lines[i].kind == HermesDiffKind.same) continue;
      final from = i - _kDiffContext < 0 ? 0 : i - _kDiffContext;
      final to = i + _kDiffContext >= lines.length
          ? lines.length - 1
          : i + _kDiffContext;
      for (var k = from; k <= to; k++) {
        show[k] = true;
      }
    }
    final rows = <Object>[];
    var i = 0;
    while (i < lines.length) {
      if (!show[i]) {
        var skipped = 0;
        while (i < lines.length && !show[i]) {
          skipped++;
          i++;
        }
        rows.add(skipped);
        continue;
      }
      if (lines[i].kind == HermesDiffKind.same) {
        rows.add(_Pair(lines[i], lines[i]));
        i++;
        continue;
      }
      // A run of changes: removed lines on the left, added on the right.
      final removed = <HermesDiffLine>[];
      final added = <HermesDiffLine>[];
      while (i < lines.length && lines[i].kind != HermesDiffKind.same) {
        (lines[i].kind == HermesDiffKind.removed ? removed : added).add(
          lines[i],
        );
        i++;
      }
      final count = removed.length > added.length
          ? removed.length
          : added.length;
      for (var k = 0; k < count; k++) {
        rows.add(
          _Pair(
            k < removed.length ? removed[k] : null,
            k < added.length ? added[k] : null,
          ),
        );
      }
    }
    return rows;
  }
}

/// The left (old) and right (new) line of one row.
class _Pair {
  const _Pair(this.left, this.right);

  final HermesDiffLine? left;
  final HermesDiffLine? right;
}

class _Gap extends StatelessWidget {
  const _Gap({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final palette = HermezChatPalette.forBrightness(
      Theme.of(context).brightness,
    );
    return Container(
      color: palette.canvas,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      child: Text(
        '⋯ $count unchanged line${count == 1 ? '' : 's'}',
        style: HermezType.meta(palette),
      ),
    );
  }
}

class _SideBySideRow extends StatelessWidget {
  const _SideBySideRow({required this.pair});

  final _Pair pair;

  @override
  Widget build(BuildContext context) => IntrinsicHeight(
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: pair.left == null
              ? const SizedBox.shrink()
              : _DiffLine(line: pair.left!),
        ),
        Expanded(
          child: pair.right == null
              ? const SizedBox.shrink()
              : _DiffLine(line: pair.right!),
        ),
      ],
    ),
  );
}

class _DiffLine extends StatelessWidget {
  const _DiffLine({required this.line});

  final HermesDiffLine line;

  @override
  Widget build(BuildContext context) {
    final palette = HermezChatPalette.forBrightness(
      Theme.of(context).brightness,
    );
    final status = Theme.of(context).extension<HermezStatusColors>();
    final added = line.kind == HermesDiffKind.added;
    final removed = line.kind == HermesDiffKind.removed;
    final tint = added
        ? (status?.success ?? Colors.green)
        : removed
        ? (status?.danger ?? Colors.red)
        : null;
    final number = added ? line.newNumber : line.oldNumber;
    return Container(
      color: tint?.withValues(alpha: 0.12),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 34,
            child: Text(
              number?.toString() ?? '',
              textAlign: TextAlign.right,
              style: HermezType.meta(palette),
            ),
          ),
          SizedBox(
            width: 18,
            child: Text(
              added
                  ? '+'
                  : removed
                  ? '−'
                  : '',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: tint ?? palette.muted,
                fontFamily: AppTypography.monospaceFontFamily,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          Expanded(
            child: Text(
              line.text,
              style: TextStyle(
                fontFamily: AppTypography.monospaceFontFamily,
                fontFamilyFallback: const ['Consolas', 'Courier New'],
                fontSize: 12.5,
                height: 1.4,
                color: palette.ink,
              ),
            ),
          ),
          if (line.guardRoot != null)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Text(
                'GUARD',
                key: const ValueKey('diff-guard-label'),
                style: HermezType.technical(status?.danger ?? Colors.red),
              ),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Backups
// ---------------------------------------------------------------------------

class _BackupsSheet extends StatelessWidget {
  const _BackupsSheet({required this.scopeLabel, required this.backups});

  final String scopeLabel;
  final List<HermesConfigBackup> backups;

  static String _when(DateTime time) {
    String two(int n) => n.toString().padLeft(2, '0');
    final t = time.toLocal();
    return '${t.year}-${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final palette = HermezChatPalette.forBrightness(
      Theme.of(context).brightness,
    );
    return HermezModalSheet(
      title: 'Backups',
      eyebrow: scopeLabel,
      body: backups.isEmpty
          ? Text(
              'No backups yet. One is kept each time you save.',
              style: HermezType.body(palette),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Text(
                    'Backups never hold secrets. Restoring one keeps the '
                    'server’s current secret wherever a placeholder is, and '
                    'goes through the same review as any save.',
                    style: HermezType.meta(palette),
                  ),
                ),
                for (final backup in backups)
                  Container(
                    key: ValueKey('backup-${backup.id}'),
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
                    decoration: BoxDecoration(
                      color: palette.surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: palette.border),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _when(backup.savedAt),
                                style: HermezType.body(palette),
                              ),
                              Text(
                                '${backup.yaml.split('\n').length} lines',
                                style: HermezType.meta(palette),
                              ),
                            ],
                          ),
                        ),
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(backup),
                          child: const Text('Restore'),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }
}
