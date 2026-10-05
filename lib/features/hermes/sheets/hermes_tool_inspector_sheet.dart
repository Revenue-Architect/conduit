import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../feedback/hermez_feedback.dart';
import '../motion/hermez_motion.dart';
import '../providers/hermes_providers.dart';
import '../services/hermes_activity_presenter.dart';
import '../services/hermes_desktop_api_service.dart';
import '../services/hermes_tool_inspector_service.dart';
import '../widgets/hermes_activity_view.dart';
import '../widgets/hermez_chat_palette.dart';
import '../widgets/hermez_live.dart';
import '../widgets/hermez_surfaces.dart';
import 'hermez_modal_sheet.dart';

/// One step up close: what Hermes asked the tool, what came back, how long
/// it took. Read from the stored transcript; nothing is re-run.
Future<void> showHermesToolInspector(
  BuildContext context, {
  required String sessionId,
  required HermesActivityRow row,
  HermezMorphOrigin? origin,
}) => pushHermezSheetRoute<void>(
  context,
  origin: origin,
  heightFactor: 0.88,
  builder: (_) => _HermesToolInspector(sessionId: sessionId, row: row),
);

class _HermesToolInspector extends ConsumerStatefulWidget {
  const _HermesToolInspector({required this.sessionId, required this.row});

  final String sessionId;
  final HermesActivityRow row;

  @override
  ConsumerState<_HermesToolInspector> createState() =>
      _HermesToolInspectorState();
}

class _HermesToolInspectorState extends ConsumerState<_HermesToolInspector> {
  late Future<List<Map<String, dynamic>>> _transcript;
  late int _index = widget.row.toolIds.length - 1;

  @override
  void initState() {
    super.initState();
    _transcript = _load();
  }

  Future<List<Map<String, dynamic>>> _load() async {
    final service = ref.read(hermesApiServiceProvider);
    if (service is! HermesDesktopApiService) return const [];
    final toolId = widget.row.toolIds.isEmpty
        ? null
        : widget.row.toolIds[_index];
    if (toolId != null) {
      try {
        return await service.toolCallMessages(widget.sessionId, toolId);
      } catch (_) {
        // Older gateways: fall back to the chat's own history.
      }
    }
    return service.getSessionMessages(widget.sessionId);
  }

  @override
  Widget build(BuildContext context) {
    final palette = HermezChatPalette.forBrightness(
      Theme.of(context).brightness,
    );
    final row = widget.row;
    final service = ref.watch(hermesApiServiceProvider);
    final secrets = service?.config.sensitiveValues ?? const <String>[];
    final status = switch (row.state) {
      HermesActivityRowState.running => 'RUNNING',
      HermesActivityRowState.failed => 'FAILED',
      HermesActivityRowState.waiting => 'WAITING',
      _ => 'DONE',
    };
    return HermezModalSheet(
      eyebrow: '$status · ${row.toolName ?? 'tool'}',
      title: row.verb,
      leading: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: row.state == HermesActivityRowState.failed
              ? palette.accent.withValues(alpha: 0.12)
              : palette.ink.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Center(
          child: row.state == HermesActivityRowState.running
              ? const HermezLiveDot(state: HermezLiveState.working)
              : Icon(hermesActivityIcon(row.family), color: palette.ink),
        ),
      ),
      subtitle: Wrap(
        spacing: 12,
        runSpacing: 4,
        children: [
          if (row.duration != null)
            _Fact(
              label: 'Took',
              value: HermesActivityPresenter.formatDuration(row.duration!),
            ),
          if (row.count > 1) _Fact(label: 'Runs', value: '${row.count}'),
          if (row.summary != null) _Fact(label: 'Hermes', value: row.summary!),
        ],
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _transcript,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 40),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            );
          }
          if (snapshot.hasError) {
            return _Note(
              text: 'Could not load this step from Hermes.',
              action: 'Retry',
              onAction: () => setState(() => _transcript = _load()),
            );
          }
          final toolId = row.toolIds.isEmpty ? null : row.toolIds[_index];
          final record = toolId == null
              ? null
              : findHermesToolCall(
                  snapshot.data ?? const [],
                  toolId,
                  sensitiveValues: secrets,
                );
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (row.toolIds.length > 1) ...[
                _RunSwitcher(
                  count: row.toolIds.length,
                  index: _index,
                  onSelect: (index) => setState(() {
                    _index = index;
                    _transcript = _load();
                  }),
                ),
                const SizedBox(height: 14),
              ],
              if (row.object != null) ...[
                _Section(
                  label: 'ACTION',
                  child: Text(row.object!, style: HermezType.body(palette)),
                ),
                const SizedBox(height: 16),
              ],
              if (record == null)
                _Note(
                  text: row.state == HermesActivityRowState.running
                      ? 'Still running. Its input and result show here once Hermes stores the step.'
                      : 'Hermes has not stored this step yet. It shows here when the turn is saved.',
                  action: 'Refresh',
                  onAction: () => setState(() => _transcript = _load()),
                )
              else ...[
                if (record.input != null)
                  _CodeSection(
                    label: 'INPUT',
                    text: record.input!,
                    truncated: record.inputTruncated,
                  ),
                if (record.input != null) const SizedBox(height: 16),
                if (record.result != null)
                  _CodeSection(
                    label: record.failed ? 'ERROR' : 'RESULT',
                    text: record.result!,
                    truncated: record.resultTruncated,
                    attention: record.failed,
                  )
                else
                  _Note(
                    text: 'No result yet. The step is still running.',
                    action: 'Refresh',
                    onAction: () => setState(() => _transcript = _load()),
                  ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final palette = HermezChatPalette.forBrightness(
      Theme.of(context).brightness,
    );
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(text: '$label ', style: HermezType.meta(palette)),
          TextSpan(
            text: value,
            style: HermezType.meta(palette).copyWith(
              color: palette.ink,
              fontWeight: FontWeight.w700,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

class _RunSwitcher extends StatelessWidget {
  const _RunSwitcher({
    required this.count,
    required this.index,
    required this.onSelect,
  });

  final int count;
  final int index;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final palette = HermezChatPalette.forBrightness(
      Theme.of(context).brightness,
    );
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (var i = 0; i < count; i++) ...[
            if (i > 0) const SizedBox(width: 6),
            HermezMotionSurface(
              weight: HermezMotionWeight.light,
              semanticLabel: 'Run ${i + 1} of $count',
              onTap: () => onSelect(i),
              child: AnimatedContainer(
                duration: HermezMotion.settleFor(HermezMotionWeight.light),
                curve: HermezMotion.curveLight,
                constraints: const BoxConstraints(minWidth: 44, minHeight: 36),
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: i == index ? palette.ink : palette.canvas,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: i == index ? palette.ink : palette.border,
                  ),
                ),
                child: Text(
                  '${i + 1}',
                  style: TextStyle(
                    color: i == index ? palette.surface : palette.ink,
                    fontWeight: FontWeight.w800,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.label, required this.child, this.trailing});
  final String label;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final palette = HermezChatPalette.forBrightness(
      Theme.of(context).brightness,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(label, style: HermezType.technical(palette.muted)),
            const Spacer(),
            ?trailing,
          ],
        ),
        const SizedBox(height: 8),
        child,
      ],
    );
  }
}

class _CodeSection extends StatefulWidget {
  const _CodeSection({
    required this.label,
    required this.text,
    required this.truncated,
    this.attention = false,
  });

  final String label;
  final String text;
  final bool truncated;
  final bool attention;

  @override
  State<_CodeSection> createState() => _CodeSectionState();
}

class _CodeSectionState extends State<_CodeSection> {
  static const _collapsed = 1600;
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final palette = HermezChatPalette.forBrightness(
      Theme.of(context).brightness,
    );
    final long = widget.text.length > _collapsed;
    final shown = !long || _expanded
        ? widget.text
        : '${widget.text.substring(0, _collapsed)}…';
    return _Section(
      label: widget.label,
      trailing: HermezMotionSurface(
        weight: HermezMotionWeight.light,
        semanticLabel: 'Copy ${widget.label.toLowerCase()}',
        onTap: () {
          Clipboard.setData(ClipboardData(text: widget.text));
          HermezFeedback.play(HermezFeedbackCue.controlSelect);
          ScaffoldMessenger.maybeOf(context)
              ?.showSnackBar(const SnackBar(content: Text('Copied')));
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.copy_rounded, size: 15, color: palette.muted),
              const SizedBox(width: 4),
              Text('Copy', style: HermezType.meta(palette)),
            ],
          ),
        ),
      ),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: palette.canvas,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: widget.attention
                ? palette.accent.withValues(alpha: 0.5)
                : palette.border.withValues(alpha: 0.7),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SelectableText(
              shown,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 12.5,
                height: 1.45,
                color: palette.ink,
              ),
            ),
            if (long || widget.truncated) ...[
              const SizedBox(height: 10),
              if (long)
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: TextButton(
                    onPressed: () => setState(() => _expanded = !_expanded),
                    child: Text(_expanded ? 'Show less' : 'Show all'),
                  ),
                ),
              if (widget.truncated && (!long || _expanded))
                Text(
                  'Shortened: Hermes keeps the full text in the transcript.',
                  style: HermezType.meta(palette),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note({required this.text, this.action, this.onAction});
  final String text;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final palette = HermezChatPalette.forBrightness(
      Theme.of(context).brightness,
    );
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: palette.canvas,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(text, style: HermezType.body(palette)),
          if (action != null && onAction != null)
            TextButton(onPressed: onAction, child: Text(action!)),
        ],
      ),
    );
  }
}
