import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/hermes_config.dart';
import '../providers/hermes_providers.dart';
import '../services/hermes_steel_viewer.dart';
import 'hermes_bot_screen_view.dart' show HermesTakeOverChip;
import 'hermez_chat_palette.dart';
import '../motion/hermez_motion.dart';
import '../../../shared/theme/theme_extensions.dart';

/// Shared lazy watch aperture. Platform views mount only after their enclosing
/// morph has settled, and are removed again before it contracts.
class HermesRunBrowserSection extends StatefulWidget {
  const HermesRunBrowserSection({
    super.key,
    required this.viewerUrl,
    required this.sessionId,
    this.initiallyOpen = false,
    this.refreshToken = 0,
    this.label = 'Watch the browser',
    this.icon = Icons.language_rounded,
    this.title = 'Live browser',
    this.viewBuilder,
  });
  final String viewerUrl;
  final String label;
  final IconData icon;

  /// The full-screen page's title.
  final String title;

  /// Another live view in place of Steel's player (the Bot Screen).
  final WidgetBuilder? viewBuilder;
  final String sessionId;

  /// A change reloads the player. Steel's player connects once, when it
  /// loads; opened before Hermes has its browser session, it would wait on
  /// "connecting" for the whole run.
  final int refreshToken;

  /// Opens on its own: a browsing run is shown as it happens.
  final bool initiallyOpen;
  @override
  State<HermesRunBrowserSection> createState() =>
      _HermesRunBrowserSectionState();
}

class _HermesRunBrowserSectionState extends State<HermesRunBrowserSection> {
  late bool _open = widget.initiallyOpen;
  var _reloads = 0;
  final _aperture = GlobalKey();
  void _expand() => Navigator.of(context).push(
    HermezRoute<void>(
      motion: HermezRouteMotion.expand,
      reducedMotion: context.reduceMotion,
      origin: _aperture.currentContext == null
          ? null
          : HermezMorphOrigin.of(_aperture.currentContext!, radius: 16),
      builder: (_) => HermesSteelFullScreenPage(
        viewerUrl: widget.viewerUrl,
        sessionId: widget.sessionId,
        title: widget.title,
        viewBuilder: widget.viewBuilder,
      ),
    ),
  );

  // One quiet line, like the run's other steps; the player unfolds under it.
  @override
  Widget build(BuildContext context) {
    final palette = HermezChatPalette.forBrightness(
      Theme.of(context).brightness,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: HermezMotionSurface(
                key: const ValueKey('hermes-watch-browser'),
                semanticLabel: _open ? 'Close: ${widget.label}' : widget.label,
                semanticsExpanded: _open,
                weight: HermezMotionWeight.light,
                originRadius: 12,
                onTap: () => setState(() => _open = !_open),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 40),
                  child: Row(
                    children: [
                      Icon(widget.icon, size: 15, color: palette.accent),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          widget.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: palette.ink,
                          ),
                        ),
                      ),
                      AnimatedRotation(
                        turns: _open ? 0.25 : 0,
                        duration: const Duration(milliseconds: 220),
                        curve: Curves.easeOutCubic,
                        child: Icon(
                          Icons.chevron_right_rounded,
                          size: 16,
                          color: palette.muted,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (_open)
              IconButton(
                key: const ValueKey('hermes-browser-reload'),
                tooltip: 'Reload the browser view',
                visualDensity: VisualDensity.compact,
                icon: Icon(
                  Icons.refresh_rounded,
                  size: 17,
                  color: palette.muted,
                ),
                onPressed: () => setState(() => _reloads++),
              ),
            if (_open)
              IconButton(
                key: const ValueKey('hermes-browser-expand'),
                tooltip: 'Full screen',
                visualDensity: VisualDensity.compact,
                icon: Icon(
                  Icons.open_in_full_rounded,
                  size: 17,
                  color: palette.muted,
                ),
                onPressed: _expand,
              ),
          ],
        ),
        HermezReveal(
          visible: _open,
          revealKey: ValueKey('steel-${widget.sessionId}'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                key: _aperture,
                height: 220,
                child: _AfterArrival(
                  placeholder: const _BrowserAperture(),
                  child: KeyedSubtree(
                    key: ValueKey(
                      'steel-view-${widget.refreshToken}-$_reloads',
                    ),
                    child:
                        widget.viewBuilder?.call(context) ??
                        HermesSteelLiveView(viewerUrl: widget.viewerUrl),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Embeds Steel's own debug player. It creates no Hermes/Steel session and
/// opens no separate casting transport. Rebuilding after collapse reconnects.
class HermesSteelLiveView extends StatefulWidget {
  const HermesSteelLiveView({
    super.key,
    required this.viewerUrl,
    this.viewerBuilder,
  });

  final String viewerUrl;
  final Widget Function(Uri uri)? viewerBuilder;

  @override
  State<HermesSteelLiveView> createState() => _HermesSteelLiveViewState();
}

class _HermesSteelLiveViewState extends State<HermesSteelLiveView> {
  bool _loading = true;

  // Steel's player takes input only when loaded interactive, so taking over
  // or handing back reloads it in the other mode.
  bool _control = false;
  String? _error;
  int _generation = 0;

  // Steel's player joins the browser session once, when it loads. Opened before
  // Hermes' session is up, it waits on "Session connecting…" for the whole
  // run, while a later reopen joins at once. So while it still says so, it is
  // reloaded every few seconds, as a person reopening it would, up to a cap.
  static const _connectCheck = Duration(seconds: 4);
  static const _maxConnectReloads = 15;
  int _connectReloads = 0;
  Timer? _connectTimer;

  @override
  void dispose() {
    _connectTimer?.cancel();
    super.dispose();
  }

  void _checkConnected(InAppWebViewController controller) {
    _connectTimer?.cancel();
    if (_connectReloads >= _maxConnectReloads) return;
    _connectTimer = Timer(_connectCheck, () async {
      if (!mounted) return;
      Object? text;
      try {
        text = await controller.evaluateJavascript(
          source:
              "(document.body ? document.body.innerText : '') + ' ' + "
              "Array.from(document.querySelectorAll('input'))"
              ".map(function (i) { return i.value + ' ' + i.placeholder; })"
              ".join(' ')",
        );
      } catch (_) {
        return;
      }
      if (!mounted || '$text'.toLowerCase().contains('connecting') == false) {
        return;
      }
      _connectReloads++;
      setState(() => _generation++);
    });
  }

  @override
  void didUpdateWidget(covariant HermesSteelLiveView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.viewerUrl != widget.viewerUrl) {
      _generation++;
      _loading = true;
      _error = null;
    }
  }

  void _retry() => setState(() {
    _generation++;
    _loading = true;
    _error = null;
  });

  @override
  Widget build(BuildContext context) {
    final uri = steelViewerUri(widget.viewerUrl, interactive: _control);
    final palette = HermezChatPalette.forBrightness(
      Theme.of(context).brightness,
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: ColoredBox(
        color: palette.canvas,
        child: Stack(
          children: [
            Positioned.fill(
              child: RepaintBoundary(
                child:
                    widget.viewerBuilder?.call(uri) ??
                    InAppWebView(
                      key: ValueKey('${uri.toString()}-$_generation'),
                      initialUrlRequest: URLRequest(
                        url: WebUri(uri.toString()),
                      ),
                      initialSettings: InAppWebViewSettings(
                        javaScriptEnabled: true,
                        mediaPlaybackRequiresUserGesture: false,
                      ),
                      onLoadStop: (controller, _) {
                        if (mounted) setState(() => _loading = false);
                        _checkConnected(controller);
                      },
                      onReceivedError: (_, request, error) {
                        if (request.isForMainFrame == true && mounted) {
                          setState(() {
                            _loading = false;
                            _error = 'Can’t reach Steel. Check your connection and retry.';
                          });
                        }
                      },
                    ),
              ),
            ),
            if (_loading && widget.viewerBuilder == null)
              const Center(child: CircularProgressIndicator.adaptive()),
            if (_error == null)
              Positioned(
                right: 8,
                bottom: 8,
                child: HermesTakeOverChip(
                  control: _control,
                  onPressed: () => setState(() {
                    _control = !_control;
                    _loading = true;
                  }),
                ),
              ),
            if (_error != null)
              Positioned.fill(
                child: ColoredBox(
                  color: palette.canvas,
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_error!, textAlign: TextAlign.center),
                        TextButton(
                          onPressed: _retry,
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class HermesSteelFullScreenPage extends ConsumerWidget {
  const HermesSteelFullScreenPage({
    super.key,
    required this.viewerUrl,
    required this.sessionId,
    this.title = 'Live browser',
    this.viewBuilder,
  });

  final String viewerUrl;
  final String sessionId;
  final String title;
  final WidgetBuilder? viewBuilder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeSession = ref.watch(hermesActiveSessionProvider);
    final turn = ref.watch(hermesDesktopTurnStateProvider).asData?.value;
    final sameRunningSession =
        activeSession == sessionId && turn == HermesDesktopTurnState.running;
    final palette = HermezChatPalette.forBrightness(
      Theme.of(context).brightness,
    );
    return Scaffold(
      backgroundColor: palette.canvas,
      appBar: AppBar(
        title: Text(title),
        backgroundColor: palette.canvas,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: sameRunningSession
                  ? Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: _AfterArrival(
                        placeholder: const _BrowserAperture(),
                        child:
                            viewBuilder?.call(context) ??
                            HermesSteelLiveView(viewerUrl: viewerUrl),
                      ),
                    )
                  : const Center(child: Text('This run is no longer active.')),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}

/// Holds a platform view back while its route is still moving. A WebView
/// under a changing clip or transform can tear; the aperture travels as a
/// placeholder and the real browser appears once the route has settled.
class _AfterArrival extends StatefulWidget {
  const _AfterArrival({required this.placeholder, required this.child});

  final Widget placeholder;
  final Widget child;

  @override
  State<_AfterArrival> createState() => _AfterArrivalState();
}

class _AfterArrivalState extends State<_AfterArrival> {
  Animation<double>? _animation;
  bool _arrived = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final animation = ModalRoute.of(context)?.animation;
    if (identical(animation, _animation)) return;
    _animation?.removeStatusListener(_onStatus);
    _animation = animation;
    animation?.addStatusListener(_onStatus);
    _arrived = animation == null || animation.isCompleted;
  }

  void _onStatus(AnimationStatus status) {
    final arrived = status == AnimationStatus.completed;
    if (arrived != _arrived && mounted) setState(() => _arrived = arrived);
  }

  @override
  void dispose() {
    _animation?.removeStatusListener(_onStatus);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      _arrived ? widget.child : widget.placeholder;
}

class _BrowserAperture extends StatelessWidget {
  const _BrowserAperture();

  @override
  Widget build(BuildContext context) {
    final palette = HermezChatPalette.forBrightness(
      Theme.of(context).brightness,
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: palette.border),
      ),
      child: Center(
        child: Icon(Icons.language_rounded, color: palette.muted, size: 32),
      ),
    );
  }
}
