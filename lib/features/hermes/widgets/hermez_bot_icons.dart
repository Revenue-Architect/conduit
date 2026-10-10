import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

/// Custom bot icons kept on the device: image files in one folder plus
/// `bot_icons.json` mapping a bot's profile name to a file name. The folder
/// is the app's external files dir on Android, so a pack can also be copied
/// in over adb. Nothing is uploaded or bundled.
class HermezBotIcons {
  HermezBotIcons._();

  static final ValueNotifier<Map<String, File>> assigned = ValueNotifier({});
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

  static String _key(String name) => name.trim().toLowerCase();

  /// Loads the assignments; call once at startup.
  static Future<void> load() async {
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
              const SizedBox(height: 8),
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
