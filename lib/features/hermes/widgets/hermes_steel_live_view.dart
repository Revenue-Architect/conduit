import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/hermes_config.dart';
import '../providers/hermes_providers.dart';
import '../services/hermes_steel_viewer.dart';
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
  });
  final String viewerUrl;
  final String sessionId;
  @override
  State<HermesRunBrowserSection> createState() =>
      _HermesRunBrowserSectionState();
}

class _HermesRunBrowserSectionState extends State<HermesRunBrowserSection> {
  bool _open = false;
  final _aperture = GlobalKey();
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Wrap(
        spacing: 8,
        children: [
          OutlinedButton.icon(
            onPressed: () => setState(() => _open = !_open),
            icon: const Icon(Icons.visibility_outlined),
            label: Text(_open ? 'Close browser' : 'Watch browser'),
          ),
          if (_open)
            TextButton.icon(
              icon: const Icon(Icons.open_in_full),
              label: const Text('Expand'),
              onPressed: () => Navigator.of(context).push(
                HermezRoute<void>(
                  motion: HermezRouteMotion.expand,
                  reducedMotion: context.reduceMotion,
                  origin: _aperture.currentContext == null
                      ? null
                      : HermezMorphOrigin.of(
                          _aperture.currentContext!,
                          radius: 16,
                        ),
                  builder: (_) => HermesSteelFullScreenPage(
                    viewerUrl: widget.viewerUrl,
                    sessionId: widget.sessionId,
                  ),
                ),
              ),
            ),
        ],
      ),
      if (_open) ...[
        SizedBox(
          key: _aperture,
          height: 260,
          child: _AfterArrival(
            placeholder: const _BrowserAperture(),
            child: HermesSteelLiveView(viewerUrl: widget.viewerUrl),
          ),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: Text('Watch only · Hermes controls this browser.'),
        ),
      ],
    ],
  );
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
  String? _error;
  int _generation = 0;

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
    final uri = steelViewerUri(widget.viewerUrl, interactive: false);
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
                      onLoadStop: (_, _) {
                        if (mounted) setState(() => _loading = false);
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
  });

  final String viewerUrl;
  final String sessionId;

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
        title: const Text('Live browser'),
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
                        child: HermesSteelLiveView(viewerUrl: viewerUrl),
                      ),
                    )
                  : const Center(child: Text('This run is no longer active.')),
            ),
            const Padding(
              padding: EdgeInsets.all(12),
              child: Text('Watch only · Hermes still controls this browser.'),
            ),
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
