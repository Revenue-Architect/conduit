import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show MethodChannel;
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
///
/// And a background colour for the character selector (`bot_colors.json`),
/// so a new picture can get a field that matches it.
class HermezBotIcons {
  HermezBotIcons._();

  static final ValueNotifier<Map<String, File>> assigned = ValueNotifier({});
  static final ValueNotifier<Map<String, Map<HermezBotClip, File>>> videos =
      ValueNotifier({});
  static final ValueNotifier<Map<String, Color>> colors = ValueNotifier({});
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

  static File _colorMapFile(Directory dir) =>
      File('${dir.path}/bot_colors.json');

  /// One key per bot, whichever of its names a surface shows: the default
  /// profile reads as "Chief", so both find the icon the owner chose for it.
  static String _key(String name) {
    final key = name.trim().toLowerCase();
    return key == 'chief' ? 'default' : key;
  }

  /// Loads the assignments; call once at startup.
  static Future<void> load() async {
    await _loadVideos();
    await _loadColors();
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

  /// A full-figure picture for the character selector, placed beside the
  /// icons as `pick_<bot>.png` (Chief is `pick_default.png`). The selector
  /// falls back to [iconFor] without one; nothing else uses it.
  static File? pickFor(String? botName) {
    final dir = _dir;
    if (dir == null || botName == null) return null;
    final file = File('${dir.path}/pick_${_key(botName)}.png');
    return file.existsSync() ? file : null;
  }

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

  static Future<void> _loadColors() async {
    try {
      final file = _colorMapFile(await _folder());
      if (!await file.exists()) return;
      final raw = jsonDecode(await file.readAsString()) as Map;
      colors.value = {
        for (final e in raw.entries)
          if (e.value is int) _key('${e.key}'): Color(e.value as int),
      };
    } catch (_) {}
  }

  /// The selector background the owner chose for [botName], if any.
  static Color? colorFor(String botName) => colors.value[_key(botName)];

  /// Sets the selector background for [botName]; null goes back to its own.
  static Future<void> assignColor(String botName, Color? color) async {
    final next = Map<String, Color>.of(colors.value);
    if (color == null) {
      next.remove(_key(botName));
    } else {
      next[_key(botName)] = color;
    }
    colors.value = next;
    await _colorMapFile(await _folder()).writeAsString(
      jsonEncode({for (final e in next.entries) e.key: e.value.toARGB32()}),
    );
  }

  /// The strongest colour in the bot's picture (its selector figure, else its
  /// icon): the most common saturated hue, averaged. Null when there is no
  /// picture or nothing in it is saturated.
  static Future<Color?> pictureColor(String botName) async {
    final file = pickFor(botName) ?? iconFor(botName);
    if (file == null) return null;
    try {
      final codec = await ui.instantiateImageCodec(
        await file.readAsBytes(),
        targetWidth: 96,
      );
      final image = (await codec.getNextFrame()).image;
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      image.dispose();
      if (data == null) return null;
      final buckets = <int, List<int>>{};
      for (var i = 0; i + 3 < data.lengthInBytes; i += 4) {
        if (data.getUint8(i + 3) < 200) continue;
        final c = Color.fromARGB(
          255,
          data.getUint8(i),
          data.getUint8(i + 1),
          data.getUint8(i + 2),
        );
        final hsl = HSLColor.fromColor(c);
        if (hsl.saturation < .5 || hsl.lightness < .25 || hsl.lightness > .8) {
          continue;
        }
        final sum = buckets.putIfAbsent(hsl.hue ~/ 10, () => [0, 0, 0, 0]);
        sum[0] += data.getUint8(i);
        sum[1] += data.getUint8(i + 1);
        sum[2] += data.getUint8(i + 2);
        sum[3]++;
      }
      if (buckets.isEmpty) return null;
      final top = buckets.values.reduce((a, b) => a[3] >= b[3] ? a : b);
      return Color.fromARGB(
        255,
        top[0] ~/ top[3],
        top[1] ~/ top[3],
        top[2] ~/ top[3],
      );
    } catch (_) {
      return null;
    }
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

  static const _frames = MethodChannel('com.conduit.app/video_frame');

  /// Saves [video]'s first frame as the bot's still image, so its poster,
  /// lists and Home all match the clip. Android only; false when it failed.
  static Future<bool> useFirstFrame(String botName, File video) async {
    if (!Platform.isAndroid) return false;
    try {
      final dir = await _folder();
      final out = File(
        '${dir.path}/still_${_key(botName)}_'
        '${DateTime.now().millisecondsSinceEpoch}.png',
      );
      final saved = await _frames.invokeMethod<bool>('firstFrame', {
        'path': video.path,
        'out': out.path,
      });
      if (saved != true || !await out.exists()) return false;
      await assign(botName, out);
      return true;
    } catch (_) {
      return false;
    }
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
      // Tall enough for the icons and both video rows; scrolls when not.
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: SingleChildScrollView(
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
                constraints: const BoxConstraints(maxHeight: 240),
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
              _ColorRow(botName: botName),
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

/// The bot's background on the character selector: a swatch, the colour of
/// its picture, or its own default.
class _ColorRow extends StatelessWidget {
  const _ColorRow({required this.botName});

  final String botName;

  static const _swatches = [
    Color(0xFFE8702A), // flame
    Color(0xFFC21E33), // crimson
    Color(0xFFF2A3B6), // pink
    Color(0xFF5B2FA6), // violet
    Color(0xFF2F6FE4), // cobalt
    Color(0xFF1F9E94), // teal
    Color(0xFF2E9D5B), // emerald
    Color(0xFFE8B526), // gold
    Color(0xFFE9E7E2), // bone
    Color(0xFFFFFFFF), // white
    Color(0xFF2A2A2E), // charcoal
  ];

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
    valueListenable: HermezBotIcons.colors,
    builder: (context, _, _) {
      final chosen = HermezBotIcons.colorFor(botName);
      final outline = Theme.of(context).colorScheme.outline;
      final onSurface = Theme.of(context).colorScheme.onSurface;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.palette_outlined),
            title: const Text('Selector background'),
            subtitle: Text(chosen == null ? 'Its own colour' : 'Set'),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextButton(
                  onPressed: () async {
                    final color = await HermezBotIcons.pictureColor(botName);
                    if (color != null) {
                      await HermezBotIcons.assignColor(botName, color);
                    } else if (context.mounted) {
                      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                        const SnackBar(
                          content: Text('No strong colour in the picture'),
                        ),
                      );
                    }
                  },
                  child: const Text('From picture'),
                ),
                if (chosen != null)
                  TextButton(
                    onPressed: () => HermezBotIcons.assignColor(botName, null),
                    child: const Text('Default'),
                  ),
              ],
            ),
          ),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final color in [
                if (chosen != null && !_swatches.contains(chosen)) chosen,
                ..._swatches,
              ])
                Semantics(
                  button: true,
                  selected: color == chosen,
                  label: 'Background colour',
                  child: GestureDetector(
                    onTap: () => HermezBotIcons.assignColor(botName, color),
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: color == chosen ? onSurface : outline,
                          width: color == chosen ? 3 : 1,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
        ],
      );
    },
  );
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
                if (picked == null) return;
                await HermezBotIcons.assignVideo(botName, clip, picked);
                // The idle clip's first frame becomes the still image; a
                // working clip gives it only while there is no idle one.
                if (clip == HermezBotClip.idle ||
                    HermezBotIcons.videoFor(botName, HermezBotClip.idle) ==
                        null) {
                  await HermezBotIcons.useFirstFrame(botName, picked);
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
