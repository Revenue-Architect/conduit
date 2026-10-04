import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/navigation_service.dart';
import '../../hermes/sheets/hermez_modal_sheet.dart';
import '../../hermes/widgets/hermez_chat_palette.dart';
import '../../hermes/widgets/hermez_surfaces.dart';
import '../models/spaces_models.dart';
import '../providers/spaces_providers.dart';
import '../services/hermes_spaces_client.dart';

/// A title suggested from a reply: its first heading, else its first line.
String suggestPageTitle(String markdown) {
  final lines = markdown
      .split('\n')
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty && !line.startsWith('```'));
  String? first;
  for (final line in lines) {
    final heading = RegExp(r'^#{1,6}\s+(.+)$').firstMatch(line);
    if (heading != null) return _clip(_plain(heading.group(1)!));
    first ??= line;
  }
  final plain = _plain(first ?? '');
  return plain.isEmpty ? 'Saved reply' : _clip(plain);
}

String _plain(String text) => text
    .replaceAll(RegExp(r'[*_`~>#\[\]]'), '')
    .replaceAll(RegExp(r'\(https?://[^)]*\)'), '')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

String _clip(String text) {
  const max = 72;
  if (text.length <= max) return text;
  final cut = text.substring(0, max);
  final space = cut.lastIndexOf(' ');
  return '${(space > 40 ? cut.substring(0, space) : cut).trimRight()}…';
}

/// "Save as Page": pick a Space and a title for an assistant reply. The reply
/// Markdown becomes the Page body; the conversation is recorded as its source.
Future<void> showSaveAsPageSheet(
  BuildContext context,
  WidgetRef ref, {
  required String markdown,
  String? sourceSessionId,
}) async {
  final client = ref.read(hermesSpacesClientProvider);
  if (client == null) return;
  final messenger = ScaffoldMessenger.maybeOf(context);
  final saved = await pushHermezSheetRoute<(HermesPage, HermesSpace)>(
    context,
    heightFactor: 0.62,
    builder: (sheetContext) => _SaveAsPageSheet(
      client: client,
      markdown: markdown.length > SpacesLimits.pageContent
          ? markdown.substring(0, SpacesLimits.pageContent)
          : markdown,
      sourceSessionId: sourceSessionId,
    ),
  );
  if (saved == null) return;
  final (page, space) = saved;
  ref.invalidate(spacesListProvider);
  messenger
    ?..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text('Saved to ${space.name}'),
        action: SnackBarAction(
          label: 'Open Page',
          onPressed: () => NavigationService.router.pushNamed(
            RouteNames.spacePage,
            pathParameters: {'spaceId': space.id, 'pageId': page.id},
          ),
        ),
      ),
    );
}

class _SaveAsPageSheet extends StatefulWidget {
  const _SaveAsPageSheet({
    required this.client,
    required this.markdown,
    this.sourceSessionId,
  });

  final HermesSpacesClient client;
  final String markdown;
  final String? sourceSessionId;

  @override
  State<_SaveAsPageSheet> createState() => _SaveAsPageSheetState();
}

class _SaveAsPageSheetState extends State<_SaveAsPageSheet> {
  late final TextEditingController _title = TextEditingController(
    text: suggestPageTitle(widget.markdown),
  );
  late final Future<List<HermesSpace>> _spaces = widget.client.spaces();
  String? _spaceId;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  Future<void> _save(List<HermesSpace> spaces) async {
    final spaceId = _spaceId ?? (spaces.isEmpty ? null : spaces.first.id);
    final title = _title.text.trim();
    if (spaceId == null || title.isEmpty) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final page = await widget.client.createPage(
        spaceId,
        title: title,
        content: widget.markdown,
        sourceSessionId: widget.sourceSessionId,
      );
      final space = spaces.firstWhere((space) => space.id == spaceId);
      if (mounted) Navigator.pop(context, (page, space));
    } on SpacesApiException catch (error) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = error.message;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = HermezChatPalette.forBrightness(
      Theme.of(context).brightness,
    );
    return FutureBuilder<List<HermesSpace>>(
      future: _spaces,
      builder: (context, snapshot) {
        final spaces = snapshot.data ?? const <HermesSpace>[];
        final selected = _spaceId ?? (spaces.isEmpty ? null : spaces.first.id);
        return HermezModalSheet(
          eyebrow: 'Save as Page',
          title: 'Keep this reply',
          body: ListView(
            padding: const EdgeInsets.fromLTRB(22, 4, 22, 16),
            children: [
              Text('SPACE', style: HermezType.technical(palette.muted)),
              const SizedBox(height: 6),
              if (snapshot.hasError)
                Text('Could not load Spaces.', style: HermezType.meta(palette))
              else if (!snapshot.hasData)
                const LinearProgressIndicator()
              else if (spaces.isEmpty)
                Text(
                  'Create a Space first, from Spaces in the side menu.',
                  style: HermezType.meta(palette),
                )
              else
                DropdownButtonFormField<String>(
                  initialValue: selected,
                  isExpanded: true,
                  items: [
                    for (final space in spaces)
                      DropdownMenuItem(
                        value: space.id,
                        child: Text(space.name),
                      ),
                  ],
                  onChanged: _saving
                      ? null
                      : (value) => setState(() => _spaceId = value),
                ),
              const SizedBox(height: 18),
              Text('TITLE', style: HermezType.technical(palette.muted)),
              const SizedBox(height: 6),
              TextField(
                controller: _title,
                enabled: !_saving,
                maxLength: SpacesLimits.pageTitle,
                textCapitalization: TextCapitalization.sentences,
                onChanged: (_) => setState(() {}),
              ),
              if (_error != null)
                Text(_error!, style: TextStyle(color: palette.accent)),
            ],
          ),
          footer: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: _saving ? null : () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed:
                    _saving || spaces.isEmpty || _title.text.trim().isEmpty
                    ? null
                    : () => _save(spaces),
                child: Text(_saving ? 'Saving…' : 'Save'),
              ),
            ],
          ),
        );
      },
    );
  }
}
