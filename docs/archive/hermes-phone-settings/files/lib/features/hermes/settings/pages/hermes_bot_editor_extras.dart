import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/utils/debug_logger.dart';
import '../../admin/hermes_admin_models.dart';
import '../../admin/hermes_admin_providers.dart';

/// The shapes and colours Hermes' own apps draw a bot with.
const hermesBotShapes = [
  'squircle',
  'circle',
  'pill',
  'triangle',
  'hexagon',
  'cloud',
  'drop',
];
const hermesBotColors = [
  '#8b5cf6',
  '#3b82f6',
  '#06b6d4',
  '#10b981',
  '#f59e0b',
  '#ef4444',
  '#ec4899',
  '#64748b',
];

/// Largest avatar image Hermes accepts (`profiles.set_asset`).
const kHermesAvatarMaxBytes = 2 * 1024 * 1024;

/// The MIME type for an avatar file name, or null when Hermes won't take it.
String? hermesAvatarMime(String fileName) =>
    switch (fileName.split('.').last.toLowerCase()) {
      'png' => 'image/png',
      'jpg' || 'jpeg' => 'image/jpeg',
      'webp' => 'image/webp',
      _ => null,
    };

Color _hex(String value) =>
    Color(int.parse(value.substring(1), radix: 16) | 0xFF000000);

/// How a bot looks in Hermes' other apps: shape, colour and an optional
/// image. Hermez draws its own mark, so this is said plainly.
class HermesBotLookEditor extends StatelessWidget {
  const HermesBotLookEditor({
    super.key,
    required this.shape,
    required this.color,
    required this.imageBytes,
    required this.hasImage,
    required this.onShape,
    required this.onColor,
    required this.onImage,
    required this.onClearImage,
  });

  final String shape;
  final String color;
  final Uint8List? imageBytes;
  final bool hasImage;
  final ValueChanged<String> onShape;
  final ValueChanged<String> onColor;
  final void Function(String dataUrl, Uint8List bytes) onImage;
  final VoidCallback onClearImage;

  Future<void> _pick(BuildContext context) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: const ['png', 'jpg', 'jpeg', 'webp'],
    );
    if (file == null) return;
    final mime = hermesAvatarMime(file.name);
    Uint8List? bytes;
    try {
      bytes = await file.readAsBytes();
    } catch (_) {
      bytes = null;
    }
    if (mime == null || bytes == null) {
      messenger?.showSnackBar(
        const SnackBar(content: Text('Use a PNG, JPEG or WebP image.')),
      );
      return;
    }
    if (bytes.length > kHermesAvatarMaxBytes) {
      messenger?.showSnackBar(
        const SnackBar(content: Text('That image is over 2 MB.')),
      );
      return;
    }
    onImage('data:$mime;base64,${base64Encode(bytes)}', bytes);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final image = imageBytes;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Look', style: theme.textTheme.titleSmall),
        const SizedBox(height: 4),
        Text(
          'How the bot appears in Hermes\' other apps. Hermez draws its own '
          'mark from the name.',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Container(
              width: 56,
              height: 56,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: _hex(color),
                borderRadius: BorderRadius.circular(
                  shape == 'circle' || shape == 'pill' ? 28 : 16,
                ),
              ),
              child: image != null
                  ? Image.memory(image, fit: BoxFit.cover)
                  : hasImage
                  ? const Icon(Icons.image_outlined, color: Colors.white)
                  : null,
            ),
            const SizedBox(width: 12),
            OutlinedButton.icon(
              key: const ValueKey('bot-look-upload'),
              onPressed: () => _pick(context),
              icon: const Icon(Icons.upload_rounded, size: 18),
              label: const Text('Upload image'),
            ),
            if (hasImage || image != null) ...[
              const SizedBox(width: 8),
              TextButton(
                onPressed: onClearImage,
                child: const Text('Remove image'),
              ),
            ],
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final s in hermesBotShapes)
              ChoiceChip(
                label: Text(s),
                selected: s == shape,
                onSelected: (_) => onShape(s),
              ),
          ],
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          children: [
            for (final c in hermesBotColors)
              Semantics(
                button: true,
                selected: c == color,
                label: 'Colour $c',
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: () => onColor(c),
                  child: Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: _hex(c),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: c == color
                            ? theme.colorScheme.onSurface
                            : Colors.transparent,
                        width: 2,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

/// A bot's memories (R26): read, edit and delete what Hermes remembers.
/// Hermes has no route to add one, so Add says why instead (KTD17).
class HermesBotMemorySection extends ConsumerStatefulWidget {
  const HermesBotMemorySection({super.key, required this.profile});

  final String profile;

  @override
  ConsumerState<HermesBotMemorySection> createState() =>
      _HermesBotMemorySectionState();
}

class _HermesBotMemorySectionState
    extends ConsumerState<HermesBotMemorySection> {
  List<HermesAdminLearningNode>? _memories;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final client = ref.read(hermesAdminClientProvider);
    if (client == null) return;
    try {
      final graph = await client.learningGraph(widget.profile);
      if (!mounted) return;
      setState(() {
        _memories = graph.nodes.where((n) => n.kind == 'memory').toList();
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = 'Couldn\'t load memories.');
      DebugLogger.warning(
        'bot-memory-load-failed',
        scope: 'hermes/bots',
        data: {'errorType': error.runtimeType.toString()},
      );
    }
  }

  Future<void> _edit(HermesAdminLearningNode node) async {
    final client = ref.read(hermesAdminClientProvider);
    if (client == null) return;
    setState(() => _busy = true);
    String text;
    try {
      text = (await client.learningNode(widget.profile, node.id)).content;
    } catch (_) {
      text = node.preview ?? '';
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (!mounted) return;
    final controller = TextEditingController(text: text);
    final saved = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit memory'),
        content: SizedBox(
          width: 520,
          child: TextField(
            controller: controller,
            autofocus: true,
            minLines: 4,
            maxLines: 12,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (saved == null || saved.trim() == text.trim()) return;
    await _run(
      () => client.updateLearningNode(widget.profile, node.id, saved.trim()),
    );
  }

  Future<void> _delete(HermesAdminLearningNode node) async {
    final client = ref.read(hermesAdminClientProvider);
    if (client == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Forget this memory?'),
        content: Text(node.preview ?? node.label, maxLines: 6),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Forget'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _run(() => client.deleteLearningNode(widget.profile, node.id));
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
      await _load();
    } catch (error) {
      if (mounted) setState(() => _error = 'That didn\'t save. Try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final memories = _memories;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text('Memory', style: theme.textTheme.titleSmall),
            ),
            if (_busy)
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            Tooltip(
              message: 'Hermes only adds memories during a chat. Ask the bot '
                  'to remember something.',
              child: const TextButton(onPressed: null, child: Text('Add')),
            ),
          ],
        ),
        if (_error != null)
          Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
        if (memories == null && _error == null)
          const Padding(
            padding: EdgeInsets.all(12),
            child: LinearProgressIndicator(),
          )
        else if (memories != null && memories.isEmpty)
          Text('No memories yet.', style: theme.textTheme.bodySmall)
        else if (memories != null)
          for (final node in memories)
            ListTile(
              key: ValueKey('bot-memory-${node.id}'),
              contentPadding: EdgeInsets.zero,
              title: Text(
                node.preview ?? node.label,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                node.memorySource == 'profile' ? 'About you' : 'Notes',
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: 'Edit memory',
                    onPressed: _busy ? null : () => _edit(node),
                    icon: const Icon(Icons.edit_outlined),
                  ),
                  IconButton(
                    tooltip: 'Forget memory',
                    onPressed: _busy ? null : () => _delete(node),
                    icon: const Icon(Icons.delete_outline_rounded),
                  ),
                ],
              ),
            ),
      ],
    );
  }
}
