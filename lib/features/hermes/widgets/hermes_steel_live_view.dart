import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/hermes_config.dart';
import '../providers/hermes_providers.dart';
import '../services/hermes_steel_viewer.dart';
import 'hermez_chat_palette.dart';

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
    return Scaffold(
      appBar: AppBar(title: const Text('Live browser')),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: sameRunningSession
                  ? HermesSteelLiveView(viewerUrl: viewerUrl)
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
