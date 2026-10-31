import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/hermes_providers.dart' show hermesApiServiceProvider;

import '../services/hermes_desktop_api_service.dart';
import 'hermez_chat_palette.dart';
import '../motion/hermez_card_stack.dart';

/// Hermes' Bot Desktop through its own noVNC stream (`/api/display/ws`).
/// Watching is the default; "Take over" holds Hermes' control lease, which is
/// what lets keyboard and mouse through, and leaving hands it back.
class HermesBotScreenView extends StatefulWidget {
  const HermesBotScreenView({super.key, required this.service});

  final HermesDesktopApiService service;

  @override
  State<HermesBotScreenView> createState() => _HermesBotScreenViewState();
}

class _HermesBotScreenViewState extends State<HermesBotScreenView> {
  ({Uri socket, String viewerId})? _screen;
  InAppWebViewController? _web;
  String? _error;
  bool _control = false;
  bool _busy = false;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _open();
  }

  @override
  void dispose() {
    final screen = _screen;
    if (_control && screen != null) {
      widget.service.handBackBotScreen(screen.viewerId).ignore();
    }
    super.dispose();
  }

  // Each ticket is single-use, so every (re)connect asks for a new one.
  Future<void> _open() async {
    setState(() {
      _error = null;
      _screen = null;
      _control = false;
    });
    try {
      final screen = await widget.service.observeBotScreen();
      if (mounted) {
        setState(() {
          _screen = screen;
          _generation++;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'The Bot Screen isn’t running right now.');
      }
    }
  }

  Future<void> _toggleControl(BuildContext chipContext) async {
    final screen = _screen;
    if (screen == null || _busy) return;
    final take = !_control;
    // Taking over asks first (docs/app-design-2026-10-30, m06): the chip
    // becomes the confirm card. Handing back needs no question.
    if (take && !await _confirmTakeOver(chipContext)) return;
    if (!mounted) return;
    setState(() => _busy = true);
    try {
      take
          ? await widget.service.takeBotScreen(screen.viewerId)
          : await widget.service.handBackBotScreen(screen.viewerId);
      await _web?.evaluateJavascript(source: 'window.setControl($take)');
      if (mounted) setState(() => _control = take);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(
            content: Text(
              take
                  ? 'Hermes didn’t hand over control.'
                  : 'Couldn’t hand control back.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = HermezChatPalette.forBrightness(
      Theme.of(context).brightness,
    );
    final screen = _screen;
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: ColoredBox(
        color: Colors.black,
        child: Stack(
          children: [
            if (screen != null)
              Positioned.fill(
                child: RepaintBoundary(
                  child: InAppWebView(
                    key: ValueKey('bot-screen-$_generation'),
                    // Served as the Hermes origin, so the socket passes
                    // Hermes' Host/Origin check like its own dashboard.
                    initialData: InAppWebViewInitialData(
                      data: _page(screen.socket),
                      baseUrl: WebUri(
                        screen.socket
                            .replace(
                              scheme: screen.socket.scheme == 'wss'
                                  ? 'https'
                                  : 'http',
                              path: '/',
                              query: '',
                            )
                            .toString(),
                      ),
                    ),
                    initialSettings: InAppWebViewSettings(
                      javaScriptEnabled: true,
                      transparentBackground: true,
                    ),
                    onWebViewCreated: (controller) {
                      _web = controller;
                      controller.addJavaScriptHandler(
                        handlerName: 'screen',
                        callback: (args) {
                          // Hermes closes a viewer whose control another
                          // person took; it reconnects watching.
                          if (mounted && '${args.firstOrNull}' == 'closed') {
                            setState(() {
                              _control = false;
                              _error = 'The Bot Screen disconnected.';
                            });
                          }
                        },
                      );
                    },
                  ),
                ),
              )
            else if (_error == null)
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
                          onPressed: _open,
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            if (screen != null && _error == null)
              Positioned(
                right: 8,
                bottom: 8,
                child: Builder(
                  builder: (chipContext) => HermesTakeOverChip(
                    control: _control,
                    busy: _busy,
                    onPressed: () => _toggleControl(chipContext),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// The Bot Screen on its own page, opened from Work at any time.
class HermesBotScreenPage extends ConsumerWidget {
  const HermesBotScreenPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final service = ref.watch(hermesApiServiceProvider);
    final palette = HermezChatPalette.forBrightness(
      Theme.of(context).brightness,
    );
    return Scaffold(
      backgroundColor: palette.canvas,
      appBar: AppBar(
        title: const Text('Bot Screen'),
        backgroundColor: palette.canvas,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          child: service is HermesDesktopApiService
              ? HermesBotScreenView(service: service)
              : const Center(
                  child: Text('Connect to Hermes to see its screen.'),
                ),
        ),
      ),
    );
  }
}

/// The Take over chip turned into its confirm card. The lease only fences
/// the bot's screen and browser (Hermes' display lease), so the card says
/// that commands it already started keep running.
Future<bool> _confirmTakeOver(BuildContext chipContext) => confirmHermezCard(
  chipContext,
  title: 'Take over the screen?',
  body:
      'While you have control, the bot can’t use its screen or browser. '
      'Commands it already started keep running. Leaving hands it back.',
  confirmLabel: 'Take over',
  cancelLabel: 'Keep watching',
);

/// "Take over" while watching, "Hand back" while in control.
class HermesTakeOverChip extends StatelessWidget {
  const HermesTakeOverChip({
    super.key,
    required this.control,
    required this.onPressed,
    this.busy = false,
  });

  final bool control;
  final bool busy;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final palette = HermezChatPalette.forBrightness(
      Theme.of(context).brightness,
    );
    return FilledButton.icon(
      key: const ValueKey('hermes-take-over'),
      style: FilledButton.styleFrom(
        backgroundColor: control ? palette.ink : palette.accent,
        foregroundColor: palette.canvas,
        visualDensity: VisualDensity.compact,
      ),
      onPressed: busy ? null : onPressed,
      icon: Icon(
        control ? Icons.smart_toy_outlined : Icons.pan_tool_alt_outlined,
        size: 16,
      ),
      label: Text(control ? 'Hand back' : 'Take over'),
    );
  }
}

String _page(Uri socket) =>
    '''
<!doctype html><html><head>
<meta name="viewport" content="width=device-width,initial-scale=1">
<style>html,body,#s{margin:0;height:100%;background:#000;overflow:hidden}</style>
</head><body><div id="s"></div><script type="module">
import * as m from 'https://cdn.jsdelivr.net/npm/@novnc/novnc@1.5.0/lib/rfb.js/+esm';
const RFB = m.default && m.default.default ? m.default.default : m.default;
const rfb = new RFB(document.getElementById('s'), ${jsonEncode(socket.toString())});
rfb.viewOnly = true;
rfb.scaleViewport = true;
window.setControl = (on) => { rfb.viewOnly = !on; if (on) rfb.focus(); };
rfb.addEventListener('disconnect', () =>
  window.flutter_inappwebview.callHandler('screen', 'closed'));
</script></body></html>''';
