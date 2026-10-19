import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../hermes/providers/hermes_providers.dart';
import '../../hermes/views/hermes_page_chrome.dart';
import '../../hermes/widgets/hermez_chat_palette.dart';
import '../providers/push_providers.dart';
import '../services/push_gateway_client.dart';

/// The default gateway address: the Hermes host this app already uses, on the
/// phone gateway's port. Falls back to the tailnet name from the design.
String defaultGatewayOrigin(String hermesBaseUrl) {
  final uri = Uri.tryParse(hermesBaseUrl.trim());
  if (uri != null && uri.host.isNotEmpty && uri.scheme == 'https') {
    return 'https://${uri.host}:8450';
  }
  return 'https://umbrel.tail4c9e01.ts.net:8450';
}

/// Pairs this phone with the notification gateway: the gateway address, the
/// one-time code from the Umbrel, and a name for this phone.
class PushPairingPage extends ConsumerStatefulWidget {
  const PushPairingPage({super.key});

  @override
  ConsumerState<PushPairingPage> createState() => _PushPairingPageState();
}

class _PushPairingPageState extends ConsumerState<PushPairingPage> {
  late final TextEditingController _gateway = TextEditingController(
    text: defaultGatewayOrigin(ref.read(hermesConfigProvider).baseUrl),
  );
  final TextEditingController _code = TextEditingController();
  final TextEditingController _name = TextEditingController(
    text: 'Android phone',
  );
  bool _busy = false;
  String? _message;
  bool _done = false;

  @override
  void dispose() {
    _gateway.dispose();
    _code.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _pair() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    final message = await ref
        .read(pushPairingControllerProvider)
        .pair(origin: _gateway.text, code: _code.text, deviceName: _name.text);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _message = message;
      _done = message == null;
    });
    if (_done && mounted) {
      _code.clear();
      if (context.canPop()) context.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = HermezChatPalette.forBrightness(Theme.of(context).brightness);
    final paired = ref.watch(pushPairingProvider).asData?.value;
    return HermesPageChrome(
      title: 'Pair this phone',
      subtitle: 'One code, valid for five minutes.',
      child: ListView(
        padding: const EdgeInsets.fromLTRB(18, 0, 18, 32),
        children: [
          HermesPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'On the Umbrel, run',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 6),
                SelectableText(
                  'docker exec hermes-notify notifyctl pair',
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 13,
                    color: palette.accent,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'It prints a one-time code. Enter it below. The code works '
                  'once.',
                  style: TextStyle(color: palette.muted, height: 1.35),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          if (paired != null)
            HermesPanel(
              child: Text(
                'This phone is already paired (device ${paired.deviceId}). '
                'Pairing again replaces it.',
                style: TextStyle(color: palette.muted),
              ),
            ),
          if (paired != null) const SizedBox(height: 16),
          TextField(
            controller: _gateway,
            enabled: !_busy,
            keyboardType: TextInputType.url,
            autocorrect: false,
            enableSuggestions: false,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              labelText: 'Gateway address',
              helperText: 'https only on the tailnet; http for local testing',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _code,
            enabled: !_busy,
            autocorrect: false,
            enableSuggestions: false,
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(
              labelText: 'Pairing code',
              helperText: 'Letters and numbers; spaces and dashes are ignored',
              border: OutlineInputBorder(),
            ),
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 20,
              letterSpacing: 2,
            ),
            onSubmitted: (_) => unawaited(_pair()),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _name,
            enabled: !_busy,
            decoration: const InputDecoration(
              labelText: 'Name for this phone',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 18),
          FilledButton(
            onPressed: _busy ? null : () => unawaited(_pair()),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: _busy
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2.4),
                    )
                  : const Text('Pair'),
            ),
          ),
          if (_message != null) ...[
            const SizedBox(height: 14),
            Semantics(
              liveRegion: true,
              child: Text(
                _message!,
                style: TextStyle(
                  color: _done ? palette.muted : const Color(0xFFD64545),
                  height: 1.35,
                ),
              ),
            ),
          ],
          const SizedBox(height: 10),
          Text(
            'Scanning a QR code is not available in this build; type the code.',
            style: TextStyle(fontSize: 12, color: palette.muted),
          ),
          if (normalizeGatewayOrigin(_gateway.text)?.startsWith('http://') ??
              false)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'This address is not encrypted. Use it only on your home '
                'network for testing.',
                style: TextStyle(fontSize: 12, color: palette.muted),
              ),
            ),
        ],
      ),
    );
  }
}
