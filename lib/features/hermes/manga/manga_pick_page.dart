import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/theme/theme_extensions.dart';
import '../models/hermes_bot.dart';
import '../widgets/hermes_home_working.dart'
    show HermesWorkingAgent, watchHermesWorkingAgents;
import '../widgets/hermes_tab_dock.dart' show hermesDockClearance;
import 'manga_pick_launch.dart' show mangaLastWordsProvider;
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
    this.instant = false,
  });

  /// The app's landing: no reveal, Pick is simply the first screen.
  final bool instant;

  final List<HermesBot> bots;
  final int initial;

  /// The tile it grows from, in global coordinates; null grows from the
  /// bottom centre.
  final Rect? origin;

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
  ) => MangaPickPage(bots: bots, initial: initial, entrance: animation);

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
class MangaPickPage extends ConsumerStatefulWidget {
  const MangaPickPage({
    super.key,
    required this.bots,
    required this.initial,
    required this.entrance,
    this.onSend,
  });

  final List<HermesBot> bots;
  final int initial;
  final Animation<double> entrance;

  /// Set when Pick is the Chats tab rather than a route: the task goes here
  /// (the field clears), there is no close button, and the tray sits above
  /// the floating tab dock.
  final void Function(HermesBot bot, String text)? onSend;

  bool get embedded => onSend != null;

  @override
  ConsumerState<MangaPickPage> createState() => _MangaPickPageState();
}

class _MangaPickPageState extends ConsumerState<MangaPickPage>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final PageController _pages = PageController(
    initialPage: widget.initial.clamp(0, widget.bots.length - 1),
  );
  final _task = TextEditingController();
  final _focus = FocusNode();
  late int _index = widget.initial.clamp(0, widget.bots.length - 1);

  /// The typing pose: 0 at rest, 1 while the task box has the keyboard.
  /// One short transform-only move, so the stage never re-lays out.
  late final AnimationController _typing = AnimationController(
    vsync: this,
    duration: MangaMotion.enter,
    reverseDuration: MangaMotion.exit,
  );

  /// The keyboard's full height, learned the first time it opens (until
  /// then a typical phone's), so the pose knows how much stage is left.
  static double _keyboard = 0;
  bool _keyboardUp = false;

  @override
  void initState() {
    super.initState();
    _task.addListener(() => setState(() {}));
    widget.entrance.addStatusListener(_landed);
    WidgetsBinding.instance.addObserver(this);
    _focus.addListener(() {
      if (context.reduceMotion) {
        _typing.value = _focus.hasFocus ? 1 : 0;
      } else if (_focus.hasFocus) {
        _typing.animateTo(1, curve: MangaMotion.easeOut);
      } else {
        _typing.animateBack(0, curve: MangaMotion.easeOut);
      }
    });
  }

  @override
  void didChangeMetrics() {
    final view = View.of(context);
    final inset = view.viewInsets.bottom / view.devicePixelRatio;
    if (inset > _keyboard) _keyboard = inset;
    // Back or the keyboard's own hide button closes it without taking the
    // focus away: leave the typing pose with it.
    if (_keyboardUp && inset == 0 && _focus.hasFocus) _focus.unfocus();
    _keyboardUp = inset > 0;
  }

  void _landed(AnimationStatus status) {
    // The name lands: one light tap, once.
    if (status == AnimationStatus.completed) HapticFeedback.lightImpact();
  }

  @override
  void dispose() {
    widget.entrance.removeStatusListener(_landed);
    WidgetsBinding.instance.removeObserver(this);
    _typing.dispose();
    _focus.dispose();
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
    final onSend = widget.onSend;
    if (onSend != null) {
      _task.clear();
      FocusScope.of(context).unfocus();
      onSend(_bot, text);
      return;
    }
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
    final working = {
      for (final agent in watchHermesWorkingAgents(ref)) agent.profile: agent,
    };
    // Watched here, in build: the pager builds its pages later.
    final words = {
      for (final bot in widget.bots)
        bot.name: ref.watch(mangaLastWordsProvider(bot.name)).value,
    };
    // Built once per state change, not once per frame: the swipe only moves
    // the pages, so they ride along as the builder's child.
    final pager = RepaintBoundary(
      child: PageView.builder(
        controller: _pages,
        itemCount: widget.bots.length,
        onPageChanged: (i) {
          HapticFeedback.selectionClick();
          setState(() => _index = i);
        },
        itemBuilder: (context, i) => _Fighter(
          bot: widget.bots[i],
          field: _field(i),
          agent: working[widget.bots[i].name],
          entrance: widget.entrance,
          words: words[widget.bots[i].name],
          typing: _typing,
          // The stage the keyboard and tray leave visible: the full stage,
          // plus the room under the tray, less the keyboard.
          keyboard: _keyboard > 0
              ? _keyboard
              : MediaQuery.sizeOf(context).height * .45,
          rest: widget.embedded
              ? hermesDockClearance(context)
              : math.max(MediaQuery.paddingOf(context).bottom, 12),
        ),
      ),
    );
    return AnimatedBuilder(
      animation: _pages,
      child: pager,
      builder: (context, pager) {
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
            // The keyboard does not resize the page: relaying out the stage
            // every frame of the keyboard's slide is what stuttered. The
            // tray alone rides the keyboard (see _KeyboardLift).
            resizeToAvoidBottomInset: false,
            body: Column(
              children: [
                Expanded(
                  child: GestureDetector(
                    // A tap on the stage puts the keyboard away.
                    behavior: HitTestBehavior.translucent,
                    onTap: () => FocusScope.of(context).unfocus(),
                    child: RepaintBoundary(
                      child: Stack(
                        children: [
                          Positioned.fill(
                            child: CustomPaint(painter: _Slash(field.deep)),
                          ),
                          ?pager,
                          SafeArea(
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(4, 4, 12, 0),
                              child: Row(
                                children: [
                                  if (!widget.embedded)
                                    IconButton(
                                      tooltip: 'Close',
                                      onPressed: () =>
                                          Navigator.of(context).pop(),
                                      icon: Icon(
                                        Icons.close_rounded,
                                        color: field.ink,
                                      ),
                                    )
                                  else
                                    const SizedBox(height: 48),
                                  const Spacer(),
                                  _StatusPill(
                                    field: field,
                                    agent: working[_bot.name],
                                    bot: _bot,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                _KeyboardLift(
                  // As a tab the floating dock sits under the tray.
                  rest: widget.embedded
                      ? hermesDockClearance(context)
                      : math.max(MediaQuery.paddingOf(context).bottom, 12),
                  child: _Tray(
                    bots: widget.bots,
                    index: _index,
                    field: field,
                    working: working.keys.toSet(),
                    controller: _task,
                    focus: _focus,
                    onTile: _jump,
                    onSend: _send,
                    hint: 'Give ${_bot.title} a task',
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Slides the tray up with the keyboard, frame for frame, without relaying
/// out anything: a translation on top of a fixed layout. Only this widget
/// listens to the keyboard's height, so nothing else rebuilds while it
/// moves. [rest] is the room kept under the tray when the keyboard is down
/// (the tab dock, or the gesture bar); the lift starts once the keyboard
/// rises past it, so there is no jump.
class _KeyboardLift extends StatelessWidget {
  const _KeyboardLift({required this.rest, required this.child});

  final double rest;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    final lift = math.max(0.0, keyboard - rest);
    return Padding(
      padding: EdgeInsets.only(bottom: rest),
      child: Transform.translate(offset: Offset(0, -lift), child: child),
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

/// One fighter: name, role, last words, and the bot's cut-out figure. The
/// layout never changes with the keyboard: the tray slides over the stage,
/// and a typing pose moves the name, figure and bubble into the stage that
/// stays visible, with transforms only.
class _Fighter extends StatelessWidget {
  const _Fighter({
    required this.bot,
    required this.field,
    required this.agent,
    required this.entrance,
    required this.words,
    required this.typing,
    required this.keyboard,
    required this.rest,
  });

  final HermesBot bot;
  final MangaField field;
  final HermesWorkingAgent? agent;
  final Animation<double> entrance;

  /// What the bot last said, cleaned for a bubble.
  final String? words;

  /// The typing pose (0 rest, 1 keyboard up), and what it needs to fit the
  /// stage the keyboard leaves: the keyboard's height and the room kept
  /// under the tray at rest.
  final Animation<double> typing;
  final double keyboard;
  final double rest;

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
    final said = words;

    return LayoutBuilder(
      builder: (context, box) {
        final Widget figure = MangaPortrait(
          botName: bot.name,
          pick: true,
          outline: stroke,
          outlineWidth: 2,
        );
        // Where things go while typing. The visible stage is the stage plus
        // the room under the tray, less the keyboard. The name shrinks into
        // the top left, the figure into the right half below the pill, the
        // bubble into the left column under the name.
        final w = box.maxWidth, h = box.maxHeight;
        final visible = math.max(160.0, h + rest - keyboard);
        const nameScale = .6;
        final figureTop = top + 56.0;
        final figureRestTop = h - 4 - h * .72;
        final figureScale = ((visible - figureTop - 6) / (h * .72)).clamp(
          .25,
          1.0,
        );
        final figureDx = w * .78 - w * .675;
        final bubbleTop = top + 56 + 72 * nameScale + 14;
        final bubbleScale = .8;
        Widget pose(
          Widget child, {
          required Alignment origin,
          double dx = 0,
          double dy = 0,
          double scale = 1,
          double fade = 1,
        }) => AnimatedBuilder(
          animation: typing,
          child: child,
          builder: (context, child) {
            final t = typing.value;
            if (t == 0) return child!;
            final k = 1 + (scale - 1) * t;
            return Opacity(
              opacity: 1 - (1 - fade) * t,
              child: Transform(
                alignment: origin,
                transform: Matrix4.translationValues(dx * t, dy * t, 0)
                  ..scaleByDouble(k, k, 1, 1),
                child: child,
              ),
            );
          },
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
            Positioned(
              right: -box.maxWidth * .15,
              bottom: -4,
              width: box.maxWidth * .95,
              height: box.maxHeight * .72,
              child: pose(
                arrive(figure, dy: 24),
                origin: Alignment.topCenter,
                dx: figureDx,
                dy: figureTop - figureRestTop,
                scale: figureScale,
              ),
            ),
            Positioned(
              left: 18,
              top: top + 56,
              width: box.maxWidth - 36,
              child: arrive(
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    pose(
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          bot.title.toUpperCase(),
                          maxLines: 1,
                          style: MangaType.fighter(field.ink),
                        ),
                      ),
                      origin: Alignment.topLeft,
                      scale: nameScale,
                    ),
                    pose(
                      origin: Alignment.topLeft,
                      fade: 0,
                      Padding(
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
            if (said != null && said.isNotEmpty)
              Positioned(
                left: 14,
                top: top + 214,
                width: math.min(240, box.maxWidth * .6),
                child: pose(
                  origin: Alignment.topLeft,
                  dy: bubbleTop - (top + 214),
                  scale: bubbleScale,
                  arrive(
                    MangaBubble(
                      fill: Colors.white,
                      stroke: stroke,
                      strokeWidth: 2.5,
                      // An oval's text box is narrower than the oval: about
                      // 70% of its width, so the margins are generous.
                      padding: const EdgeInsets.fromLTRB(34, 20, 34, 24),
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
              ),
          ],
        );
      },
    );
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
    required this.focus,
    required this.onTile,
    required this.onSend,
    required this.hint,
  });

  final List<HermesBot> bots;
  final int index;
  final MangaField field;
  final Set<String> working;
  final TextEditingController controller;
  final FocusNode focus;
  final ValueChanged<int> onTile;
  final VoidCallback onSend;
  final String hint;

  @override
  Widget build(BuildContext context) {
    final armed = controller.text.trim().isNotEmpty;
    final accent = MangaInk.light.accent;
    const bottom = 6.0;
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
                        focusNode: focus,
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
              pick: true,
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
