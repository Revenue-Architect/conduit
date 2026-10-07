import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/services/navigation_service.dart';
import '../../../../core/utils/debug_logger.dart';
import '../../admin/hermes_admin_client.dart';
import '../../admin/hermes_admin_models.dart';
import '../../admin/hermes_admin_providers.dart';
import '../../providers/hermes_providers.dart';
import '../../widgets/hermez_chat_palette.dart';
import '../hermes_settings_categories.dart';
import 'hermes_bot_editor_extras.dart';

/// What a bot's name becomes as a Hermes profile id: lowercase letters,
/// digits, `-` and `_`, starting with a letter or digit, at most 64.
String hermesBotIdFor(String name) {
  final lowered = name.trim().toLowerCase().replaceAll(RegExp(r'\s+'), '-');
  final cleaned = lowered
      .replaceAll(RegExp(r'[^a-z0-9_-]'), '')
      .replaceAll(RegExp(r'^[-_]+'), '');
  return cleaned.length > 64 ? cleaned.substring(0, 64) : cleaned;
}

const _reservedBotIds = {'default', 'all', 'root', 'new'};

/// Why [id] can't be a new bot's id, or null when it can.
String? hermesBotIdProblem(String id, Iterable<String> existing) {
  if (id.isEmpty) return 'Give the bot a name';
  if (_reservedBotIds.contains(id)) return '"$id" is reserved';
  if (existing.contains(id)) return 'A bot called "$id" already exists';
  return null;
}

/// Create or edit a bot: name, title, description and SOUL, with links to
/// its model and tools settings. [name] null means New Bot (R18, R24).
class HermesBotEditorPage extends ConsumerStatefulWidget {
  const HermesBotEditorPage({super.key, this.name});

  final String? name;

  @override
  ConsumerState<HermesBotEditorPage> createState() =>
      _HermesBotEditorPageState();
}

class _HermesBotEditorPageState extends ConsumerState<HermesBotEditorPage> {
  final _name = TextEditingController();
  final _title = TextEditingController();
  final _description = TextEditingController();
  final _soul = TextEditingController();
  bool _loading = false;
  String _shape = 'squircle';
  String _color = '#8b5cf6';
  String? _chat;
  bool _hadImage = false;
  String? _newImage;
  Uint8List? _newImageBytes;
  bool _clearImage = false;
  bool _saving = false;
  String? _error;
  String? _step;

  bool get _creating => widget.name == null;

  @override
  void initState() {
    super.initState();
    _name.addListener(() => setState(() {}));
    if (!_creating) _load();
  }

  @override
  void dispose() {
    _name.dispose();
    _title.dispose();
    _description.dispose();
    _soul.dispose();
    super.dispose();
  }

  HermesAdminClient? get _client => ref.read(hermesAdminClientProvider);

  Future<void> _load() async {
    final client = _client;
    final name = widget.name;
    if (client == null || name == null) return;
    setState(() => _loading = true);
    try {
      final bots = await ref.read(hermesBotsProvider.future);
      final bot = bots.where((b) => b.name == name).firstOrNull;
      _title.text = bot?.title == name ? '' : (bot?.title ?? '');
      _description.text = bot?.description ?? '';
      if (bot != null) {
        _shape = hermesBotShapes.contains(bot.avatarShape)
            ? bot.avatarShape
            : 'squircle';
        _color = bot.avatarColor;
        _chat = bot.chatSessionId;
        _hadImage = bot.hasAvatar;
      }
      final soul = await client.profileSoul(name);
      _soul.text = soul.content;
    } catch (error) {
      _error = 'Couldn\'t load this bot. Try again.';
      DebugLogger.warning(
        'bot-editor-load-failed',
        scope: 'hermes/bots',
        data: {'errorType': error.runtimeType.toString()},
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    final client = _client;
    if (client == null || _saving) return;
    final existing = (ref.read(hermesBotsProvider).value ?? const []).map(
      (b) => b.name,
    );
    final id = _creating ? hermesBotIdFor(_name.text) : widget.name!;
    if (_creating) {
      final problem = hermesBotIdProblem(id, existing);
      if (problem != null) {
        setState(() => _error = problem);
        return;
      }
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      if (_creating) {
        _step = 'Creating the bot';
        await client.createProfile(
          HermesAdminProfileDraft(
            name: id,
            description: _description.text,
            soul: _soul.text,
          ),
        );
      }
      _step = 'Saving its details';
      final title = _title.text.trim();
      await client.configureProfile(
        id,
        description: _creating ? null : _description.text.trim(),
        uiMeta: {
          'hermes-bots': {
            'title': title.isEmpty ? id : title,
            'shape': _shape,
            'color': _color,
            'imageKind': _newImage != null || (_hadImage && !_clearImage)
                ? 'photo'
                : 'shape',
            'chat': ?_chat,
          },
        },
      );
      if (_newImage != null) {
        _step = 'Saving its image';
        await client.setProfileAvatar(id, _newImage!);
      } else if (_clearImage && _hadImage) {
        _step = 'Removing its image';
        await client.clearProfileAvatar(id);
      }
      if (!_creating) {
        _step = 'Saving its SOUL';
        await client.setProfileSoul(id, _soul.text);
      }
      ref.invalidate(hermesBotsProvider);
      ref.invalidate(hermesAdminProfilesProvider);
      ref.invalidate(hermesBotAvatarProvider(id));
      if (mounted) Navigator.of(context).maybePop(id);
    } catch (error) {
      final step = _step;
      setState(() {
        _error = _creating && step != 'Creating the bot'
            ? 'The bot was created, but "$step" failed. Open it and try again.'
            : '$step failed. Try again.';
      });
      DebugLogger.warning(
        'bot-editor-save-failed',
        scope: 'hermes/bots',
        data: {'errorType': error.runtimeType.toString(), 'step': step},
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final client = _client;
    final name = widget.name;
    if (client == null || name == null) return;
    final typed = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: Text('Delete $name?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'This deletes the bot with its chats, memory, keys and '
                'scheduled jobs. It can\'t be undone.',
              ),
              const SizedBox(height: 12),
              TextField(
                controller: typed,
                autofocus: true,
                decoration: InputDecoration(labelText: 'Type "$name"'),
                onChanged: (_) => setLocal(() {}),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: typed.text.trim() == name
                  ? () => Navigator.of(context).pop(true)
                  : null,
              child: const Text('Delete'),
            ),
          ],
        ),
      ),
    );
    typed.dispose();
    if (confirmed != true) return;
    setState(() => _saving = true);
    try {
      await client.deleteProfile(name);
      if (ref.read(hermesSettingsScopeProvider) == name) {
        ref.read(hermesSettingsScopeProvider.notifier).reset();
      }
      ref.invalidate(hermesBotsProvider);
      ref.invalidate(hermesAdminProfilesProvider);
      if (mounted) Navigator.of(context).maybePop();
    } catch (error) {
      setState(() => _error = 'Delete failed. Try again.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _openSettings(HermesSettingsCategory category) {
    final name = widget.name;
    if (name == null) return;
    ref.read(hermesSettingsScopeProvider.notifier).select(name);
    NavigationService.router.pushNamed(
      RouteNames.hermesSettingsCategory,
      pathParameters: {'category': category.slug},
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = HermezChatPalette.forBrightness(
      Theme.of(context).brightness,
    );
    final noClient = ref.watch(hermesAdminClientProvider) == null;
    final idPreview = hermesBotIdFor(_name.text);
    return Scaffold(
      backgroundColor: palette.canvas,
      appBar: AppBar(
        backgroundColor: palette.canvas,
        title: Text(_creating ? 'New bot' : 'Edit ${widget.name}'),
        actions: [
          if (!_creating && widget.name != 'default')
            IconButton(
              key: const ValueKey('bot-editor-delete'),
              tooltip: 'Delete bot',
              onPressed: _saving ? null : _delete,
              icon: const Icon(Icons.delete_outline_rounded),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    if (noClient)
                      const _Note(
                        'Bot management needs a Desktop Gateway connection.',
                      ),
                    if (_creating) ...[
                      TextField(
                        key: const ValueKey('bot-editor-name'),
                        controller: _name,
                        decoration: InputDecoration(
                          labelText: 'Name',
                          helperText: idPreview.isEmpty
                              ? null
                              : 'Its id will be "$idPreview"',
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    TextField(
                      controller: _title,
                      decoration: const InputDecoration(
                        labelText: 'Title (how it shows in the app)',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _description,
                      decoration: const InputDecoration(
                        labelText: 'Description',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _soul,
                      minLines: 6,
                      maxLines: 16,
                      decoration: const InputDecoration(
                        labelText: 'SOUL (who the bot is and how it works)',
                        alignLabelWithHint: true,
                      ),
                    ),
                    const SizedBox(height: 20),
                    HermesBotLookEditor(
                      shape: _shape,
                      color: _color,
                      imageBytes: _newImageBytes,
                      hasImage: _hadImage && !_clearImage,
                      onShape: (v) => setState(() => _shape = v),
                      onColor: (v) => setState(() => _color = v),
                      onImage: (url, bytes) => setState(() {
                        _newImage = url;
                        _newImageBytes = bytes;
                        _clearImage = false;
                      }),
                      onClearImage: () => setState(() {
                        _newImage = null;
                        _newImageBytes = null;
                        _clearImage = true;
                      }),
                    ),
                    if (!_creating && !noClient) ...[
                      const SizedBox(height: 20),
                      HermesBotMemorySection(profile: widget.name!),
                    ],
                    if (!_creating) ...[
                      const SizedBox(height: 20),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final category in [
                            HermesSettingsCategory.models,
                            HermesSettingsCategory.tools,
                            HermesSettingsCategory.advanced,
                          ])
                            OutlinedButton.icon(
                              onPressed: () => _openSettings(category),
                              icon: Icon(category.icon, size: 18),
                              label: Text(category.label),
                            ),
                        ],
                      ),
                    ],
                    if (_error != null) ...[
                      const SizedBox(height: 16),
                      _Note(_error!, error: true),
                    ],
                    const SizedBox(height: 20),
                    Align(
                      alignment: AlignmentDirectional.centerEnd,
                      child: FilledButton(
                        key: const ValueKey('bot-editor-save'),
                        onPressed: _saving || noClient ? null : _save,
                        child: Text(
                          _saving
                              ? (_step ?? 'Saving')
                              : (_creating ? 'Create bot' : 'Save'),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note(this.text, {this.error = false});

  final String text;
  final bool error;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: error ? scheme.error : scheme.outline),
      ),
      child: Text(text, style: TextStyle(color: error ? scheme.error : null)),
    );
  }
}
