import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../widgets/hermez_bot_icons.dart';

/// Bot portraits cut from their white squares, so a figure stands in a
/// panel (or on its Pick field) instead of sitting on a white tile. A
/// portrait that already has transparency is used as it is.
///
/// The cut is made once per image file and cached beside it as
/// `cut_<file>.png`; assigning a new image makes a new cut.
abstract final class MangaCutouts {
  static final Map<String, Future<File?>> _pending = {};

  /// Files already resolved, so a figure built again (a page a swipe brings
  /// into view, a pose wrapping it) paints on its first frame instead of
  /// blinking empty while its future answers.
  static final Map<String, File?> _ready = {};

  static Future<File?> _once(String key, Future<File?> Function() load) =>
      _pending.putIfAbsent(key, () async {
        final file = await load();
        _ready[key] = file;
        return file;
      });

  /// The resolved file for [botName], when it is already known.
  static File? readyFor(String botName, {bool pick = false}) {
    final selector = pick ? HermezBotIcons.pickFor(botName) : null;
    if (selector != null) return selector;
    final source = HermezBotIcons.iconFor(botName);
    return source == null ? null : _ready[source.path];
  }

  /// The character selector's figure: the bot's own full-figure picture
  /// when it has one (already transparent, used as it is), else its cut-out.
  static Future<File?> forPick(String botName) {
    final pick = HermezBotIcons.pickFor(botName);
    if (pick == null) return forBot(botName);
    // One future per file: a new one on every rebuild restarts the
    // FutureBuilder each frame of a swipe.
    return _once('pick:${pick.path}', () async => pick);
  }

  /// The cut-out for [botName]'s assigned image, or null without one.
  static Future<File?> forBot(String botName) {
    final source = HermezBotIcons.iconFor(botName);
    if (source == null) return Future.value();
    return _once(source.path, () => _cut(source));
  }

  static Future<File?> _cut(File source) async {
    try {
      final name = source.uri.pathSegments.last.replaceAll('.', '_');
      final out = File('${source.parent.path}/cut_$name.png');
      if (await out.exists()) return out;
      final bytes = await source.readAsBytes();
      // Decoded no wider than 900 px: enough for a full-width Pick portrait
      // at 3x, without decoding a 1254 px original every time.
      final codec = await ui.instantiateImageCodec(bytes, targetWidth: 900);
      final frame = await codec.getNextFrame();
      final image = frame.image;
      final width = image.width, height = image.height;
      final raw = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      image.dispose();
      if (raw == null) return source;
      final rgba = raw.buffer.asUint8List();
      final cut = await Isolate.run(() => mangaCutRgba(rgba, width, height));
      if (cut == null) return source;
      final completer = Completer<ui.Image>();
      ui.decodeImageFromPixels(
        cut,
        width,
        height,
        ui.PixelFormat.rgba8888,
        completer.complete,
      );
      final cutImage = await completer.future;
      final png = await cutImage.toByteData(format: ui.ImageByteFormat.png);
      cutImage.dispose();
      if (png == null) return source;
      await out.writeAsBytes(png.buffer.asUint8List(), flush: true);
      return out;
    } catch (_) {
      // A portrait that cannot be cut shows as it is.
      return source;
    }
  }
}

/// Removes the near-white background connected to the image's edges.
/// Returns null when there is nothing to cut (the image is already
/// transparent at its corners). The mask is smoothed and eroded 2 px so no
/// pale fringe is left round the hair, then softened for antialiasing.
Uint8List? mangaCutRgba(Uint8List rgba, int w, int h) {
  int at(int x, int y) => (y * w + x) * 4;
  final corner = at(1, 1);
  if (rgba[corner + 3] < 200) return null;
  bool paper(int i) =>
      rgba[i + 3] > 200 &&
      rgba[i] >= 205 &&
      rgba[i + 1] >= 205 &&
      rgba[i + 2] >= 205;

  // Flood the paper from every edge pixel.
  final bg = Uint8List(w * h);
  final stack = <int>[];
  void seed(int x, int y) {
    final p = y * w + x;
    if (bg[p] == 0 && paper(p * 4)) {
      bg[p] = 1;
      stack.add(p);
    }
  }

  for (var x = 0; x < w; x++) {
    seed(x, 0);
    seed(x, h - 1);
  }
  for (var y = 0; y < h; y++) {
    seed(0, y);
    seed(w - 1, y);
  }
  while (stack.isNotEmpty) {
    final p = stack.removeLast();
    final x = p % w, y = p ~/ w;
    if (x > 0) seed(x - 1, y);
    if (x < w - 1) seed(x + 1, y);
    if (y > 0) seed(x, y - 1);
    if (y < h - 1) seed(x, y + 1);
  }

  // Figure mask (1 = keep), blurred and re-thresholded to smooth stair steps.
  var mask = Float32List(w * h);
  for (var p = 0; p < w * h; p++) {
    mask[p] = bg[p] == 1 ? 0 : 1;
  }
  mask = _box(_box(mask, w, h), w, h);
  final keep = Uint8List(w * h);
  for (var p = 0; p < w * h; p++) {
    keep[p] = mask[p] > .55 ? 1 : 0;
  }
  // Erode 2 px: drops the pale ring the flood leaves round the hair.
  final eroded = Uint8List(w * h);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      var all = 1;
      for (var dy = -2; dy <= 2 && all == 1; dy++) {
        final yy = y + dy;
        if (yy < 0 || yy >= h) continue;
        for (var dx = -2; dx <= 2; dx++) {
          final xx = x + dx;
          if (xx < 0 || xx >= w) continue;
          if (keep[yy * w + xx] == 0) {
            all = 0;
            break;
          }
        }
      }
      eroded[y * w + x] = all;
    }
  }
  var alpha = Float32List(w * h);
  for (var p = 0; p < w * h; p++) {
    alpha[p] = eroded[p].toDouble();
  }
  alpha = _box(alpha, w, h);
  final out = Uint8List.fromList(rgba);
  for (var p = 0; p < w * h; p++) {
    out[p * 4 + 3] = (out[p * 4 + 3] * alpha[p]).round().clamp(0, 255);
  }
  return out;
}

Float32List _box(Float32List src, int w, int h) {
  final out = Float32List(w * h);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      var sum = 0.0;
      var n = 0;
      for (var dy = -1; dy <= 1; dy++) {
        final yy = y + dy;
        if (yy < 0 || yy >= h) continue;
        for (var dx = -1; dx <= 1; dx++) {
          final xx = x + dx;
          if (xx < 0 || xx >= w) continue;
          sum += src[yy * w + xx];
          n++;
        }
      }
      out[y * w + x] = sum / n;
    }
  }
  return out;
}

/// A bot's figure, cut out, optionally with an ink outline that ties it to
/// the page's borders.
///
/// With an outline, the figure and its outline are baked once into a single
/// image at the size it is shown (see [_MangaOutlined]): on Android Flutter
/// renders with Impeller, which does not keep a repaint boundary as pixels,
/// so an outline drawn as eight filtered copies was redrawn on every frame
/// of a swipe. [decodeWidth] decodes a small portrait (a tile) at that width
/// instead of the file's full size.
class MangaPortrait extends StatelessWidget {
  const MangaPortrait({
    super.key,
    required this.botName,
    this.outline,
    this.outlineWidth = 1.5,
    this.alignment = Alignment.bottomCenter,
    this.fit = BoxFit.contain,
    this.pick = false,
    this.decodeWidth,
  });

  /// On the character selector: prefer the bot's full-figure picture.
  final bool pick;

  final String botName;
  final Color? outline;
  final double outlineWidth;
  final Alignment alignment;
  final BoxFit fit;

  /// Logical width to decode at; null decodes the file's full size.
  final double? decodeWidth;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
    // Reassigning a face redraws the figure.
    valueListenable: HermezBotIcons.assigned,
    builder: (context, _, _) => FutureBuilder<File?>(
      initialData: MangaCutouts.readyFor(botName, pick: pick),
      future: pick
          ? MangaCutouts.forPick(botName)
          : MangaCutouts.forBot(botName),
      builder: (context, snapshot) {
        final file = snapshot.data;
        if (file == null) return const SizedBox.shrink();
        final stroke = outline;
        if (stroke != null) {
          return _MangaOutlined(
            file: file,
            stroke: stroke,
            width: outlineWidth,
            alignment: alignment,
          );
        }
        final width = decodeWidth;
        final ImageProvider provider = width == null
            ? FileImage(file)
            : ResizeImage(
                FileImage(file),
                width: (width * MediaQuery.devicePixelRatioOf(context)).round(),
              );
        return RepaintBoundary(
          child: Image(
            image: provider,
            fit: fit,
            alignment: alignment,
            filterQuality: FilterQuality.medium,
            gaplessPlayback: true,
          ),
        );
      },
    ),
  );
}

/// The figure and its outline as one image, baked at the shown pixel size
/// and cached, so a frame draws a single texture.
class _MangaOutlined extends StatelessWidget {
  const _MangaOutlined({
    required this.file,
    required this.stroke,
    required this.width,
    required this.alignment,
  });

  final File file;
  final Color stroke;
  final double width;
  final Alignment alignment;

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    return LayoutBuilder(
      builder: (context, box) {
        if (!box.hasBoundedWidth || !box.hasBoundedHeight) {
          return const SizedBox.shrink();
        }
        final key = _BakeKey(
          file.path,
          stroke.toARGB32(),
          (width * dpr).round(),
          (box.maxWidth * dpr).round(),
          (box.maxHeight * dpr).round(),
        );
        return FutureBuilder<ui.Image?>(
          initialData: _MangaBakery.ready[key],
          future: _MangaBakery.bake(key),
          builder: (context, snapshot) {
            final image = snapshot.data;
            if (image == null) return const SizedBox.shrink();
            return RawImage(
              image: image,
              scale: dpr,
              fit: BoxFit.contain,
              alignment: alignment,
              filterQuality: FilterQuality.medium,
            );
          },
        );
      },
    );
  }
}

@immutable
class _BakeKey {
  const _BakeKey(this.path, this.colour, this.stroke, this.width, this.height);

  final String path;
  final int colour;
  final int stroke;
  final int width;
  final int height;

  @override
  bool operator ==(Object other) =>
      other is _BakeKey &&
      other.path == path &&
      other.colour == colour &&
      other.stroke == stroke &&
      other.width == width &&
      other.height == height;

  @override
  int get hashCode => Object.hash(path, colour, stroke, width, height);
}

/// Bakes outlined figures. A handful are kept (six bots, a few sizes); the
/// oldest goes when more arrive.
abstract final class _MangaBakery {
  static final Map<_BakeKey, Future<ui.Image?>> _pending = {};
  static final Map<_BakeKey, ui.Image?> ready = {};
  static const _keep = 12;

  static Future<ui.Image?> bake(_BakeKey key) =>
      _pending.putIfAbsent(key, () async {
        final image = await _render(key);
        ready[key] = image;
        while (_pending.length > _keep) {
          final oldest = _pending.keys.first;
          _pending.remove(oldest);
          ready.remove(oldest);
        }
        return image;
      });

  static Future<ui.Image?> _render(_BakeKey key) async {
    try {
      final bytes = await File(key.path).readAsBytes();
      // Decode straight to the shown size (fit inside the box, keeping the
      // aspect), leaving room for the outline.
      final probe = await ui.instantiateImageCodec(bytes);
      final first = (await probe.getNextFrame()).image;
      final iw = first.width, ih = first.height;
      first.dispose();
      final room = key.stroke * 2;
      final scale = math.min((key.width - room) / iw, (key.height - room) / ih);
      final w = math.max(1, (iw * scale).round());
      final h = math.max(1, (ih * scale).round());
      final codec = await ui.instantiateImageCodec(
        bytes,
        targetWidth: w,
        targetHeight: h,
      );
      final figure = (await codec.getNextFrame()).image;
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      final d = key.stroke.toDouble();
      final ink = Paint()
        ..colorFilter = ColorFilter.mode(Color(key.colour), BlendMode.srcIn);
      for (final o in [
        Offset(d, 0),
        Offset(-d, 0),
        Offset(0, d),
        Offset(0, -d),
        Offset(d * .7, d * .7),
        Offset(-d * .7, -d * .7),
        Offset(d * .7, -d * .7),
        Offset(-d * .7, d * .7),
      ]) {
        canvas.drawImage(figure, Offset(d, d) + o, ink);
      }
      canvas.drawImage(figure, Offset(d, d), Paint());
      final picture = recorder.endRecording();
      final baked = await picture.toImage(w + room, h + room);
      picture.dispose();
      figure.dispose();
      return baked;
    } catch (_) {
      return null;
    }
  }
}
