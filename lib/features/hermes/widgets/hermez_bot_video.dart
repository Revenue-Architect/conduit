import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../../shared/theme/theme_extensions.dart';
import 'hermez_bot_icons.dart';

/// A bot's face as a short looping clip: its idle video, or its working video
/// while [working] (the idle one when it has none). Silent, mixed with other
/// audio so it never interrupts voice, and paused in the background, off
/// screen and under reduced motion. [poster] (the bot's image) shows until a
/// clip is ready and whenever none can play.
class HermezBotVideoMark extends StatefulWidget {
  const HermezBotVideoMark({
    super.key,
    required this.botName,
    required this.size,
    required this.working,
    required this.poster,
  });

  final String botName;
  final double size;
  final bool working;
  final Widget poster;

  @override
  State<HermezBotVideoMark> createState() => _HermezBotVideoMarkState();
}

class _HermezBotVideoMarkState extends State<HermezBotVideoMark>
    with WidgetsBindingObserver {
  final Map<HermezBotClip, _Clip> _clips = {};
  bool _foreground = true;
  bool _visible = true;
  bool _reduceMotion = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    HermezBotIcons.videos.addListener(_syncFiles);
    _syncFiles();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _visible = TickerMode.valuesOf(context).enabled;
    _reduceMotion = context.reduceMotion;
    _apply();
  }

  @override
  void didUpdateWidget(HermezBotVideoMark oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.botName != widget.botName) _syncFiles();
    if (oldWidget.working != widget.working) _apply();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _apply();
  }

  /// Opens a controller per assigned clip, replacing one whose file changed.
  void _syncFiles() {
    for (final clip in HermezBotClip.values) {
      final file = HermezBotIcons.videoFor(widget.botName, clip);
      final current = _clips[clip];
      if (current?.file.path == file?.path) continue;
      current?.controller.dispose();
      _clips.remove(clip);
      if (file != null) _open(clip, file);
    }
    if (mounted) setState(() {});
  }

  void _open(HermezBotClip clip, File file) {
    final controller = VideoPlayerController.file(
      file,
      videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
    );
    final entry = _Clip(file, controller);
    _clips[clip] = entry;
    controller
        .initialize()
        .then((_) async {
          // A clip replaced or a mark gone while it loaded is not shown.
          if (!mounted || !identical(_clips[clip], entry)) return;
          await controller.setLooping(true);
          await controller.setVolume(0);
          if (!mounted || !identical(_clips[clip], entry)) return;
          setState(() => entry.ready = true);
          _apply();
        })
        .catchError((Object _) {
          // A missing or unreadable file leaves the poster in place.
          if (mounted && identical(_clips[clip], entry)) {
            setState(() => entry.failed = true);
          }
        });
  }

  /// The clip on screen: working while the bot works and has one, else idle.
  _Clip? get _wanted {
    bool usable(_Clip? c) => c != null && c.ready && !c.failed;
    final working = _clips[HermezBotClip.working];
    final idle = _clips[HermezBotClip.idle];
    if (widget.working && usable(working)) return working;
    if (usable(idle)) return idle;
    return usable(working) ? working : null;
  }

  void _apply() {
    final wanted = _wanted;
    final play = _foreground && _visible && !_reduceMotion;
    for (final clip in _clips.values) {
      if (!clip.ready || clip.failed) continue;
      if (identical(clip, wanted) && play) {
        if (!clip.controller.value.isPlaying) clip.controller.play();
      } else if (clip.controller.value.isPlaying) {
        clip.controller.pause();
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    HermezBotIcons.videos.removeListener(_syncFiles);
    for (final clip in _clips.values) {
      clip.controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final wanted = _wanted;
    final size = wanted?.controller.value.size;
    return SizedBox.square(
      dimension: widget.size,
      child: Stack(
        fit: StackFit.expand,
        children: [
          widget.poster,
          if (wanted != null && size != null && !size.isEmpty)
            IgnorePointer(
              child: ClipOval(
                // The same crop for every clip: centred, filling the circle.
                child: FittedBox(
                  fit: BoxFit.cover,
                  clipBehavior: Clip.hardEdge,
                  child: SizedBox(
                    width: size.width,
                    height: size.height,
                    child: VideoPlayer(wanted.controller),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

final class _Clip {
  _Clip(this.file, this.controller);

  final File file;
  final VideoPlayerController controller;
  bool ready = false;
  bool failed = false;
}
