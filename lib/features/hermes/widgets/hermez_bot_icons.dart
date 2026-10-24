import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

/// Which of a bot's two looping clips plays: calm, or while it works.
enum HermezBotClip { idle, working }

/// Custom bot icons kept on the device: image files in one folder plus
/// `bot_icons.json` mapping a bot's profile name to a file name. The folder
/// is the app's external files dir on Android, so a pack can also be copied
/// in over adb. Nothing is uploaded or bundled.
///
/// A bot can also have an idle and a working video (`bot_videos.json`), copied
/// into the same app-owned folder so clearing the gallery never breaks them.
/// Its image stays its poster and fallback.
class HermezBotIcons {
  HermezBotIcons._();

  static final ValueNotifier<Map<String, File>> assigned = ValueNotifier({});
  static final ValueNotifier<Map<String, Map<HermezBotClip, File>>> videos =
      ValueNotifier({});
  static Directory? _dir;

  static Future<Directory> _folder() async {
    if (_dir != null) return _dir!;
    final base = Platform.isAndroid
        ? (await getExternalStorageDirectory() ??
              await getApplicationSupportDirectory())
        : await getApplicationSupportDirectory();
    _dir = Directory('${base.path}/bot_icons');
    await _dir!.create(recursive: true);
    return _dir!;
  }

  static File _mapFile(Directory dir) => File('${dir.path}/bot_icons.json');

  static File _videoMapFile(Directory dir) =>
      File('${dir.path}/bot_videos.json');

  /// One key per bot, whichever of its names a surface shows: the default
  /// profile reads as "Chief", so both find the icon the owner chose for it.
  static String _key(String name) {
    final key = name.trim().toLowerCase();
    return key == 'chief' ? 'default' : key;
  }

  /// Loads the assignments; call once at startup.
  static Future<void> load() async {
    await _loadVideos();
    try {
      final dir = await _folder();
      final mapFile = _mapFile(dir);
      if (!await mapFile.exists()) return;
      final raw = jsonDecode(await mapFile.readAsString()) as Map;
      final next = <String, File>{};
      raw.forEach((name, file) {
        final f = File('${dir.path}/$file');
        if (f.existsSync()) next[_key('$name')] = f;
      });
      assigned.value = next;
    } catch (_) {}
  }

  static File? iconFor(String? botName) =>
      botName == null ? null : assigned.value[_key(botName)];

  static Future<void> _loadVideos() async {
    try {
      final dir = await _folder();
      final mapFile = _videoMapFile(dir);
      if (!await mapFile.exists()) return;
      final raw = jsonDecode(await mapFile.readAsString()) as Map;
      final next = <String, Map<HermezBotClip, File>>{};
      raw.forEach((name, clips) {
        if (clips is! Map) return;
        final files = <HermezBotClip, File>{};
        for (final clip in HermezBotClip.values) {
          final file = clips[clip.name];
          if (file is! String) continue;
          final f = File('${dir.path}/$file');
          if (f.existsSync()) files[clip] = f;
        }
        if (files.isNotEmpty) next[_key('$name')] = files;
      });
      videos.value = next;
    } catch (_) {}
  }

  /// The bot's clip for [clip], when one is set and still on the device.
  static File? videoFor(String? botName, HermezBotClip clip) =>
      botName == null ? null : videos.value[_key(botName)]?[clip];

  static bool hasVideo(String? botName) =>
      botName != null && (videos.value[_key(botName)]?.isNotEmpty ?? false);

  static Future<void> assignVideo(
    String botName,
    HermezBotClip clip,
    File? file,
  ) async {
    final dir = await _folder();
    final next = {
      for (final e in videos.value.entries)
        e.key: Map<HermezBotClip, File>.of(e.value),
    };
    final clips = next.putIfAbsent(_key(botName), () => {});
    if (file == null) {
      clips.remove(clip);
    } else {
      clips[clip] = file;
    }
    if (clips.isEmpty) next.remove(_key(botName));
    videos.value = next;
    await _videoMapFile(dir).writeAsString(
      jsonEncode({
        for (final e in next.entries)
          e.key: {
            for (final c in e.value.entries)
              c.key.name: c.value.uri.pathSegments.last,
          },
      }),
    );
  }

  /// Copies one gallery video into the app's folder, under a fresh name so
  /// a later import never overwrites a clip in use.
  static Future<File?> importVideo() async {
    final picked = await ImagePicker().pickVideo(source: ImageSource.gallery);
    if (picked == null) return null;
    final dir = await _folder();
    final ext =
        RegExp(r'\.[A-Za-z0-9]+$').firstMatch(picked.name)?[0] ?? '.mp4';
    final name = 'clip_${DateTime.now().millisecondsSinceEpoch}$ext';
    return File(picked.path).copy('${dir.path}/$name');
  }

  static Future<List<File>> library() async {
    final dir = await _folder();
    return dir
        .listSync()
        .whereType<File>()
        .where(
          (f) => RegExp(
            r'\.(png|jpe?g|webp)$',
            caseSensitive: false,
          ).hasMatch(f.path),
        )
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));
  }

  static Future<void> assign(String botName, File? file) async {
    final dir = await _folder();
    final next = Map<String, File>.of(assigned.value);
    if (file == null) {
      next.remove(_key(botName));
    } else {
      next[_key(botName)] = file;
    }
    assigned.value = next;
    await _mapFile(dir).writeAsString(
      jsonEncode({
        for (final e in next.entries) e.key: e.value.uri.pathSegments.last,
      }),
    );
  }

  /// Copies picked gallery images into the icon folder.
  static Future<void> importFromGallery() async {
    final picked = await ImagePicker().pickMultiImage();
    final dir = await _folder();
    for (final x in picked) {
      await File(x.path).copy('${dir.path}/${x.name}');
    }
  }

  /// Bottom sheet: pick a library icon, import more, or reset.
  static Future<void> showPicker(BuildContext context, String botName) async {
    final files = await library();
    if (!context.mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Icon for $botName',
                style: Theme.of(sheetContext).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 320),
                child: GridView.count(
                  shrinkWrap: true,
                  crossAxisCount: 4,
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                  children: [
                    for (final f in files)
                      InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () async {
                          await assign(botName, f);
                          if (sheetContext.mounted) {
                            Navigator.pop(sheetContext);
                          }
                        },
                        child: Image.file(f, cacheWidth: 160),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 4),
              // A looping clip per state; the chosen image stays the poster.
              for (final clip in HermezBotClip.values)
                _VideoRow(botName: botName, clip: clip),
              const SizedBox(height: 4),
              Row(
                children: [
                  TextButton.icon(
                    icon: const Icon(Icons.add_photo_alternate_outlined),
                    label: const Text('Import images'),
                    onPressed: () async {
                      Navigator.pop(sheetContext);
                      await importFromGallery();
                      if (context.mounted) await showPicker(context, botName);
                    },
                  ),
                  const Spacer(),
                  TextButton(
                    child: const Text('Default'),
                    onPressed: () async {
                      await assign(botName, null);
                      if (sheetContext.mounted) Navigator.pop(sheetContext);
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _VideoRow extends StatelessWidget {
  const _VideoRow({required this.botName, required this.clip});

  final String botName;
  final HermezBotClip clip;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
    valueListenable: HermezBotIcons.videos,
    builder: (context, _, _) {
      final file = HermezBotIcons.videoFor(botName, clip);
      final name = clip == HermezBotClip.idle ? 'Idle video' : 'Working video';
      return ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.movie_outlined),
        title: Text(name),
        subtitle: Text(
          file == null
              ? clip == HermezBotClip.idle
                    ? 'None: the image shows'
                    : 'None: the idle video plays'
              : 'Set',
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (file != null)
              TextButton(
                onPressed: () =>
                    HermezBotIcons.assignVideo(botName, clip, null),
                child: const Text('Clear'),
              ),
            TextButton(
              onPressed: () async {
                final picked = await HermezBotIcons.importVideo();
                if (picked != null) {
                  await HermezBotIcons.assignVideo(botName, clip, picked);
                }
              },
              child: Text(file == null ? 'Choose' : 'Replace'),
            ),
          ],
        ),
      );
    },
  );
}
