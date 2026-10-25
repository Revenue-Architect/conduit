import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../shared/theme/theme_extensions.dart';
import '../models/hermes_bot.dart';
import '../widgets/hermes_home_working.dart' show HermesWorkingAgent;
import '../widgets/hermez_bot_icons.dart';
import '../widgets/hermez_bot_video.dart';
import 'manga_portrait.dart';
import 'manga_theme.dart';
import 'manga_widgets.dart';

/// What Pick hands back: who, and the task to send them.
@immutable
class MangaPickResult {
  const MangaPickResult(this.bot, this.text);

  final HermesBot bot;
  final String text;
}

/// Pick opens out of the roster tile that was tapped: the tile's rectangle
/// grows into the screen as a circle of the bot's field colour, the content
/// settles in behind it, and closing folds it back faster than it opened.
class MangaPickRoute extends PageRoute<MangaPickResult> {
  MangaPickRoute({
    required this.bots,
    required this.initial,
    required this.origin,
    required this.working,
    this.speech = const {},
    this.instant = false,
  });

  /// What each bot last said, cleaned for its bubble (from Today).
  final Map<String, String?> speech;

  /// The app's landing: no reveal, Pick is simply the first screen.
  final bool instant;

  final List<HermesBot> bots;
  final int initial;

  /// The tile it grows from, in global coordinates; null grows from the
  /// bottom centre.
  final Rect? origin;
  final Map<String, HermesWorkingAgent> working;

  @override
  Color? get barrierColor => null;

  @override
  String? get barrierLabel => null;

  @override
  bool get opaque => false;

  @override
  bool get maintainState => true;

  @override
  Duration get transitionDuration => instant ? Duration.zero : MangaMotion.grow;

  @override
  Duration get reverseTransitionDuration => MangaMotion.shrink;

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) => MangaPickPage(
    bots: bots,
    initial: initial,
    working: working,
    speech: speech,
    entrance: animation,
  );

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (context.reduceMotion) {
      return FadeTransition(opacity: animation, child: child);
    }
    final size = MediaQuery.sizeOf(context);
    final from =
        origin ??
        Rect.fromCenter(
          center: Offset(size.width / 2, size.height - 60),
          width: 56,
          height: 56,
        );
    // Never from nothing: the reveal starts as big as the tile itself.
    final startRadius = from.shortestSide / 2;
    final centre = from.center;
    final endRadius = [
      Offset.zero,
      Offset(size.width, 0),
      Offset(0, size.height),
      Offset(size.width, size.height),
    ].map((corner) => (corner - centre).distance).reduce(math.max);
    return AnimatedBuilder(
      animation: animation,
      child: child,
      builder: (context, child) {
        final forward = animation.status != AnimationStatus.reverse;
        final t = (forward ? MangaMotion.drawer : MangaMotion.easeOut)
            .transform(animation.value);
        return ClipPath(
          clipper: _CircleReveal(
            centre,
            startRadius + (endRadius - startRadius) * t,
          ),
          child: child,
        );
      },
    );
  }
}

class _CircleReveal extends CustomClipper<Path> {
  _CircleReveal(this.centre, this.radius);

  final Offset centre;
  final double radius;

  @override
  Path getClip(Size size) =>
      Path()..addOval(Rect.fromCircle(center: centre, radius: radius));

  @override
  bool shouldReclip(_CircleReveal old) =>
      old.radius != radius || old.centre != centre;
}

/// Pick your fighter. The picked bot fills the screen in its own colour,
/// name huge, last words in a bubble; swipe for the next bot, and give the
/// task from the bottom.
class MangaPickPage extends StatefulWidget {
  const MangaPickPage({
    super.key,
    required this.bots,
    required this.initial,
    required this.working,
    required this.entrance,
    this.speech = const {},
  });

  final List<HermesBot> bots;
  final int initial;
  final Map<String, HermesWorkingAgent> working;
  final Map<String, String?> speech;
  final Animation<double> entrance;

  @override
  State<MangaPickPage> createState() => _MangaPickPageState();
}

class _MangaPickPageState extends State<MangaPickPage> {
  late final PageController _pages = PageController(
    initialPage: widget.initial.clamp(0, widget.bots.length - 1),
  );
  final _task = TextEditingController();
  late int _index = widget.initial.clamp(0, widget.bots.length - 1);

  @override
  void initState() {
    super.initState();
    _task.addListener(() => setState(() {}));
    widget.entrance.addStatusListener(_landed);
  }

  void _landed(AnimationStatus status) {
    // The name lands: one light tap, once.
    if (status == AnimationStatus.completed) HapticFeedback.lightImpact();
  }

  @override
  void dispose() {
    widget.entrance.removeStatusListener(_landed);
    _pages.dispose();
    _task.dispose();
    super.dispose();
  }

  HermesBot get _bot => widget.bots[_index];

  MangaField _field(int i) {
    final bot = widget.bots[i];
    return MangaField.forBot(bot.name, avatarColor: bot.avatarColor);
  }

  /// The field under the finger: two bots' colours mixed by how far the
  /// swipe has gone, so the colour follows the drag instead of snapping.
  MangaField _fieldAt(double page) {
    final a = page.floor().clamp(0, widget.bots.length - 1);
    final b = page.ceil().clamp(0, widget.bots.length - 1);
    final t = page - page.floor();
    final fa = _field(a), fb = _field(b);
    return MangaField(
      Color.lerp(fa.field, fb.field, t)!,
      Color.lerp(fa.deep, fb.deep, t)!,
      t < .5 ? fa.ink : fb.ink,
      Color.lerp(fa.paper, fb.paper, t)!,
    );
  }

  void _send() {
    final text = _task.text.trim();
    if (text.isEmpty) return;
    HapticFeedback.mediumImpact();
    Navigator.of(context).pop(MangaPickResult(_bot, text));
  }

  void _jump(int i) {
    if (i == _index) return;
    _pages.animateToPage(
      i,
      duration: const Duration(milliseconds: 300),
      curve: MangaMotion.easeInOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _pages,
      builder: (context, _) {
        final page = _pages.hasClients && _pages.position.haveDimensions
            ? (_pages.page ?? _index.toDouble())
            : _index.toDouble();
        final field = _fieldAt(page);
        return AnnotatedRegion<SystemUiOverlayStyle>(
          value: field.lightField
              ? SystemUiOverlayStyle.dark
              : SystemUiOverlayStyle.light,
          child: Scaffold(
            backgroundColor: field.field,
            resizeToAvoidBottomInset: true,
            body: Column(
              children: [
                Expanded(
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: CustomPaint(painter: _Slash(field.deep)),
                      ),
                      PageView.builder(
                        controller: _pages,
                        itemCount: widget.bots.length,
                        onPageChanged: (i) {
                          HapticFeedback.selectionClick();
                          setState(() => _index = i);
                        },
                        itemBuilder: (context, i) => _Fighter(
                          bot: widget.bots[i],
                          field: _field(i),
                          agent: widget.working[widget.bots[i].name],
                          entrance: widget.entrance,
                          words: widget.speech[widget.bots[i].name],
                          current: i == _index,
                        ),
                      ),
                      SafeArea(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(4, 4, 12, 0),
                          child: Row(
                            children: [
                              IconButton(
                                tooltip: 'Close',
                                onPressed: () => Navigator.of(context).pop(),
                                icon: Icon(
                                  Icons.close_rounded,
                                  color: field.ink,
                                ),
                              ),
                              const Spacer(),
                              _StatusPill(
                                field: field,
                                agent: widget.working[_bot.name],
                                bot: _bot,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                _Tray(
                  bots: widget.bots,
                  index: _index,
                  field: field,
                  working: widget.working.keys.toSet(),
                  controller: _task,
                  onTile: _jump,
                  onSend: _send,
                  hint: 'Give ${_bot.title} a task',
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// The diagonal slash across the field.
class _Slash extends CustomPainter {
  _Slash(this.colour);

  final Color colour;

  @override
  void paint(Canvas canvas, Size size) {
    final rise = math.tan(15 * math.pi / 180) * size.height;
    final x = size.width * .44;
    final w = size.width * .17;
    canvas.drawPath(
      Path()
        ..moveTo(x + rise, 0)
        ..lineTo(x + w + rise, 0)
        ..lineTo(x + w, size.height)
        ..lineTo(x, size.height)
        ..close(),
      Paint()..color = colour.withValues(alpha: .5),
    );
  }

  @override
  bool shouldRepaint(_Slash old) => old.colour != colour;
}

/// The bot's description without a leading "Name:" that repeats the title.
String? _role(HermesBot bot) {
  final text = bot.description?.trim();
  if (text == null || text.isEmpty) return null;
  final prefix = RegExp(
    '^${RegExp.escape(bot.title)}'
    r'\s*[:\-–]\s*',
    caseSensitive: false,
  );
  final role = text.replaceFirst(prefix, '');
  return role.isEmpty ? null : role[0].toUpperCase() + role.substring(1);
}

/// One fighter: name, role, last words, and the bot itself: its idle (or
/// working) clip in a square ink panel when it has one, else its cut-out
/// figure. With the keyboard up the stage is short, so the name keeps to
/// the left, the figure shrinks to the right and the role and bubble step
/// aside.
class _Fighter extends StatelessWidget {
  const _Fighter({
    required this.bot,
    required this.field,
    required this.agent,
    required this.entrance,
    required this.words,
    required this.current,
  });

  final HermesBot bot;
  final MangaField field;
  final HermesWorkingAgent? agent;
  final Animation<double> entrance;

  /// What the bot last said, cleaned for a bubble.
  final String? words;

  /// The fighter on screen: only it plays its clip.
  final bool current;

  @override
  Widget build(BuildContext context) {
    final reduce = context.reduceMotion;
    final stroke = field.lightField ? const Color(0xFF0E0E10) : field.tray;
    // The name and figure arrive after the colour: the reveal is the event,
    // the content settles in behind it, 12 px and a fade.
    final settle = CurvedAnimation(
      parent: entrance,
      curve: const Interval(.35, 1, curve: MangaMotion.easeOut),
      reverseCurve: const Interval(0, .4, curve: MangaMotion.easeOut),
    );
    Widget arrive(Widget child, {double dy = 12}) => reduce
        ? child
        : AnimatedBuilder(
            animation: settle,
            child: child,
            builder: (context, child) => Opacity(
              opacity: settle.value,
              child: Transform.translate(
                offset: Offset(0, dy * (1 - settle.value)),
                child: child,
              ),
            ),
          );
    final top = MediaQuery.paddingOf(context).top;
    final hasClip =
        HermezBotIcons.videoFor(bot.name, HermezBotClip.idle) != null ||
        HermezBotIcons.videoFor(bot.name, HermezBotClip.working) != null;
    final said = words;

    return LayoutBuilder(
      builder: (context, box) {
        // The keyboard takes the bottom half: a short stage.
        final compact = box.maxHeight < top + 420;
        final panelSide = compact
            ? math.max(
                80.0,
                math.min(box.maxWidth * .4, box.maxHeight - top - 70),
              )
            : math.min(box.maxWidth * .66, box.maxHeight * .5);
        final Widget figure = hasClip
            ? Transform.rotate(
                angle: -2 * math.pi / 180,
                child: Container(
                  width: panelSide,
                  height: panelSide,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(color: stroke, width: 3),
                  ),
                  child: current
                      ? HermezBotVideoMark(
                          botName: bot.name,
                          size: panelSide - 6,
                          working: agent != null,
                          square: true,
                          poster: _Still(bot: bot),
                        )
                      : _Still(bot: bot),
                ),
              )
            : MangaPortrait(
                botName: bot.name,
                outline: stroke,
                outlineWidth: 2,
              );
        return Stack(
          children: [
            if (agent != null)
              Positioned.fill(
                child: ShaderMask(
                  // Rays only on the figure's side: the name and role stay on
                  // a calm field.
                  shaderCallback: (rect) => const LinearGradient(
                    colors: [Colors.transparent, Colors.black],
                    stops: [.46, .6],
                  ).createShader(rect),
                  blendMode: BlendMode.dstIn,
                  child: const SpeedLines(
                    centre: Alignment(.4, .3),
                    ground: Colors.transparent,
                    tone: Color(0x1F0E0E10),
                    rays: 60,
                    clear: 0,
                  ),
                ),
              ),
            if (hasClip)
              AnimatedPositioned(
                duration: MangaMotion.enter,
                curve: MangaMotion.easeOut,
                right: compact ? 16 : 18,
                bottom: compact ? 12 : 28,
                width: panelSide,
                height: panelSide,
                child: arrive(figure, dy: 24),
              )
            else
              AnimatedPositioned(
                duration: MangaMotion.enter,
                curve: MangaMotion.easeOut,
                right: compact ? -box.maxWidth * .04 : -box.maxWidth * .15,
                bottom: -4,
                width: box.maxWidth * (compact ? .5 : .95),
                height: box.maxHeight * (compact ? .8 : .72),
                child: arrive(figure, dy: 24),
              ),
            Positioned(
              left: 18,
              top: top + 56,
              // Compact, the name keeps out of the figure's half.
              width: box.maxWidth * (compact ? .52 : 1) - 36,
              child: arrive(
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        bot.title.toUpperCase(),
                        maxLines: 1,
                        style: MangaType.fighter(field.ink),
                      ),
                    ),
                    AnimatedOpacity(
                      opacity: compact ? 0 : 1,
                      duration: MangaMotion.swap,
                      child: Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: SizedBox(
                          width: 170,
                          child: Text(
                            _role(bot) ?? '',
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: MangaType.line(field.ink),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (said != null && said.isNotEmpty && !compact)
              Positioned(
                left: 14,
                top: top + 214,
                width: math.min(206, box.maxWidth * .52),
                child: arrive(
                  MangaBubble(
                    fill: Colors.white,
                    stroke: stroke,
                    strokeWidth: 2.5,
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          agent != null
                              ? 'ON IT NOW'
                              : bot.lastActive == null
                              ? 'LAST SAID'
                              : 'LAST · ${mangaWhen(bot.lastActive!).toUpperCase()}',
                          style: MangaType.stamp(const Color(0xFF4A4A50)),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          said,
                          maxLines: 4,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: MangaType.line(const Color(0xFF0E0E10)),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// The bot's still (the clip's first frame), filling the panel.
class _Still extends StatelessWidget {
  const _Still({required this.bot});

  final HermesBot bot;

  @override
  Widget build(BuildContext context) {
    final file = HermezBotIcons.iconFor(bot.name);
    return file == null
        ? const SizedBox.expand()
        : Image.file(file, fit: BoxFit.cover, gaplessPlayback: true);
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({
    required this.field,
    required this.agent,
    required this.bot,
  });

  final MangaField field;
  final HermesWorkingAgent? agent;
  final HermesBot bot;

  @override
  Widget build(BuildContext context) {
    final last = bot.lastActive;
    final text = agent != null
        ? 'Working'
        : last == null
        ? 'Idle'
        : 'Idle · ${mangaLastSeen(mangaWhen(last))}';
    return AnimatedSwitcher(
      duration: MangaMotion.swap,
      switchInCurve: MangaMotion.easeOut,
      child: DecoratedBox(
        key: ValueKey(text),
        decoration: BoxDecoration(
          color: field.tray,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 9, 12, 9),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: field.paper,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Text(text, style: MangaType.label(field.paper)),
            ],
          ),
        ),
      ),
    );
  }
}

/// The dark tray: six tiles to jump between fighters, and the task box.
class _Tray extends StatelessWidget {
  const _Tray({
    required this.bots,
    required this.index,
    required this.field,
    required this.working,
    required this.controller,
    required this.onTile,
    required this.onSend,
    required this.hint,
  });

  final List<HermesBot> bots;
  final int index;
  final MangaField field;
  final Set<String> working;
  final TextEditingController controller;
  final ValueChanged<int> onTile;
  final VoidCallback onSend;
  final String hint;

  @override
  Widget build(BuildContext context) {
    final armed = controller.text.trim().isNotEmpty;
    final accent = MangaInk.light.accent;
    final bottom = math.max(MediaQuery.paddingOf(context).bottom, 12.0);
    return ColoredBox(
      color: field.tray,
      child: Padding(
        padding: EdgeInsets.fromLTRB(14, 12, 14, bottom + 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: 74,
              child: Row(
                children: [
                  for (var i = 0; i < bots.length && i < 6; i++) ...[
                    if (i > 0) const SizedBox(width: 6),
                    Expanded(
                      child: MangaPress(
                        semanticLabel: bots[i].title,
                        scale: .94,
                        onTap: () => onTile(i),
                        child: _Tile(
                          bot: bots[i],
                          selected: i == index,
                          field: field,
                          working: working.contains(bots[i].name),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 12),
            DecoratedBox(
              decoration: BoxDecoration(
                color: field.paper,
                borderRadius: BorderRadius.circular(28),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 5, 5, 5),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: controller,
                        minLines: 1,
                        maxLines: 4,
                        textCapitalization: TextCapitalization.sentences,
                        keyboardType: TextInputType.text,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => onSend(),
                        style: MangaType.body(const Color(0xFF0E0E10)),
                        cursorColor: const Color(0xFF0E0E10),
                        decoration: InputDecoration(
                          isCollapsed: true,
                          border: InputBorder.none,
                          hintText: hint,
                          hintStyle: MangaType.body(const Color(0xFF6B6670)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    MangaPress(
                      semanticLabel: 'Send',
                      onTap: armed ? onSend : null,
                      scale: .92,
                      child: AnimatedContainer(
                        duration: MangaMotion.swap,
                        curve: MangaMotion.easeOut,
                        width: 46,
                        height: 46,
                        decoration: BoxDecoration(
                          // Deep ink at rest, orange once there is a task.
                          color: armed ? accent : field.tray,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.arrow_forward_rounded,
                          color: armed ? const Color(0xFF0E0E10) : field.paper,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Swipe to switch',
              style: MangaType.label(field.paper.withValues(alpha: .7)),
            ),
          ],
        ),
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.bot,
    required this.selected,
    required this.field,
    required this.working,
  });

  final HermesBot bot;
  final bool selected;
  final MangaField field;
  final bool working;

  @override
  Widget build(BuildContext context) {
    final rest = Color.lerp(field.tray, Colors.white, .08)!;
    return AnimatedContainer(
      duration: MangaMotion.swap,
      curve: MangaMotion.easeOut,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: selected ? field.field : rest,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: selected ? field.paper : Colors.transparent,
          width: 2,
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            left: -6,
            right: -6,
            top: 6,
            bottom: selected ? 14 : -4,
            child: MangaPortrait(
              botName: bot.name,
              fit: BoxFit.cover,
              alignment: Alignment.topCenter,
            ),
          ),
          if (selected)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: ColoredBox(
                color: field.field,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      bot.title.toUpperCase(),
                      style: MangaType.fighter(field.ink)
                          .copyWith(fontSize: 11, letterSpacing: 0, height: 1),
                    ),
                  ),
                ),
              ),
            ),
          if (working)
            Positioned(
              right: 5,
              top: 5,
              child: Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(
                  color: MangaInk.light.accent,
                  shape: BoxShape.circle,
                  border: Border.all(color: rest, width: 2),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
