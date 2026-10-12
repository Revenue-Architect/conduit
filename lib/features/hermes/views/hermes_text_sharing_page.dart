import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:permission_handler/permission_handler.dart';

/// Sharing is opt-in. Permission and pairing actions are always initiated here.
class HermesTextSharingPage extends StatefulWidget {
  const HermesTextSharingPage({super.key});

  @override
  State<HermesTextSharingPage> createState() => _HermesTextSharingPageState();
}

class _HermesTextSharingPageState extends State<HermesTextSharingPage> {
  static const _channel = MethodChannel('app.cogwheel.conduit/text-sharing');
  final _code = TextEditingController();
  Map<String, dynamic> _status = {};
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _action('status');
  }

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _action(String action, [Map<String, Object?>? args]) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final value = await _channel.invokeMapMethod<String, dynamic>(
        action,
        args,
      );
      if (mounted) setState(() => _status = value ?? {});
      if (action == 'enroll') _code.clear();
    } on PlatformException catch (error) {
      if (mounted) {
        setState(
          () => _error =
              error.message ?? 'Could not finish. Try again when connected.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _enable(bool enabled) async {
    if (enabled) {
      // Android presents these permission prompts to the phone owner.
      final result = await [Permission.sms, Permission.contacts].request();
      if (!mounted) return;
      if (result.values.any((status) => !status.isGranted)) {
        setState(
          () => _error = 'Message and contact access are needed to share texts. You can allow them in App info.',
        );
        return;
      }
    }
    await _action('setEnabled', {'enabled': enabled});
  }

  Future<void> _forget() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Forget this device?'),
        content: const Text(
          'Sharing stops and this phone’s pairing is revoked. Your messages and chats stay on the phone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Forget device'),
          ),
        ],
      ),
    );
    if (confirmed == true) await _action('forget');
  }

  @override
  Widget build(BuildContext context) {
    final paired = _status['paired'] == true;
    final paused =
        (_status['pausedUntil'] as num? ?? 0) >
        DateTime.now().millisecondsSinceEpoch;
    return Scaffold(
      appBar: AppBar(title: const Text('Share texts with Hermes')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            'Let Hermes notice useful loose ends in your texts.',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 12),
          const Text(
            'Shares SMS and supported RCS text in both directions over your private connection. One-time codes are filtered. Google Messages stays your messaging app.',
          ),
          const SizedBox(height: 24),
          if (!paired) ...[
            const Text(
              'Pair this phone',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            const Text(
              'Enter the one-time pairing code shown on your Umbrel host. Pairing does not turn sharing on.',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _code,
              enabled: !_busy,
              autocorrect: false,
              enableSuggestions: false,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(labelText: 'Pairing code'),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _busy
                  ? null
                  : () => _action('enroll', {
                      'code': _code.text.trim().toUpperCase(),
                    }),
              child: const Text('Pair phone'),
            ),
          ] else ...[
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Share texts with Hermes'),
              subtitle: Text(
                paused
                    ? 'Paused for 24 hours'
                    : 'Read-only sharing. You control when it runs.',
              ),
              value: _status['enabled'] == true,
              onChanged: _busy ? null : _enable,
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Last sync'),
              subtitle: Text(
                (_status['lastSync'] as String?)?.isNotEmpty == true
                    ? _status['lastSync'] as String
                    : 'Not synced yet',
              ),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Messages shared today'),
              subtitle: Text('${_status['sentToday'] ?? 0}'),
            ),
            if (_status['enabled'] == true) ...[
              OutlinedButton(
                onPressed: _busy ? null : () => _action('sync'),
                child: const Text('Sync now'),
              ),
              TextButton(
                onPressed: _busy ? null : () => _action('pause'),
                child: const Text('Pause 24 h'),
              ),
            ],
            TextButton(
              onPressed: _busy ? null : _forget,
              child: const Text('Forget device'),
            ),
          ],
          if (_busy)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            ),
          if (_error != null ||
              (_status['error'] as String?)?.isNotEmpty == true)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Text(
                _error ?? _status['error'] as String,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
        ],
      ),
    );
  }
}
