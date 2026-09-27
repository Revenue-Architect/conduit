import 'dart:async';

import 'package:flutter/material.dart';
import 'package:genui/genui.dart';

import '../services/hermes_a2ui_layout_normalizer.dart';
import 'hermes_visual_catalog.dart';
import 'hermez_visual_theme.dart';

/// Renders the completed body of one Hermes `a2ui` fence as native widgets.
/// Each response owns its own controller and surface lifecycle.
class HermesA2uiSurface extends StatefulWidget {
  const HermesA2uiSurface({
    super.key,
    required this.payload,
    this.onInteraction,
    this.isBusy = false,
  });

  final String payload;
  final FutureOr<void> Function(String interactionPrompt)? onInteraction;
  final bool isBusy;

  @override
  State<HermesA2uiSurface> createState() => _HermesA2uiSurfaceState();
}

class _HermesA2uiSurfaceState extends State<HermesA2uiSurface> {
  late SurfaceController _controller;
  late A2uiTransportAdapter _transport;
  StreamSubscription<SurfaceUpdate>? _surfaceUpdates;
  StreamSubscription<dynamic>? _messages;
  StreamSubscription<ChatMessage>? _submissions;
  final List<String> _surfaceIds = <String>[];
  bool _pipelineInitialized = false;
  bool _isComplete = false;
  bool _hasError = false;
  bool _interactionInFlight = false;
  int _renderGeneration = 0;

  @override
  void initState() {
    super.initState();
    _initialize(widget.payload);
  }

  @override
  void didUpdateWidget(covariant HermesA2uiSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.payload != widget.payload) {
      _disposePipeline();
      _surfaceIds.clear();
      _isComplete = false;
      _hasError = false;
      _interactionInFlight = false;
      _initialize(widget.payload);
    }
  }

  void _initialize(String payload) {
    final generation = ++_renderGeneration;
    // Keep the built-in asset widgets unavailable: they can fetch arbitrary
    // agent-supplied URLs. Hermes MEDIA uses Conduit's authenticated client.
    // The added visual items render bounded data only and do no I/O.
    final catalog = createHermesVisualCatalog();
    final normalized = normalizeHermesA2uiPayload(payload, catalog: catalog);
    if (!normalized.isReady) {
      _hasError = true;
      _isComplete = true;
      return;
    }

    _controller = SurfaceController(catalogs: [catalog]);
    _transport = A2uiTransportAdapter();
    _pipelineInitialized = true;
    _surfaceUpdates = _controller.surfaceUpdates.listen(_handleSurfaceUpdate);
    _messages = _transport.incomingMessages.listen(_controller.handleMessage);
    _submissions = _controller.onSubmit.listen((message) {
      unawaited(_forwardInteractions(message));
    });

    // GenUI consumes complete A2UI JSON messages here. Rendering starts only
    // after the Hermes assistant turn has completed; no partial JSON is fed.
    runZonedGuarded<void>(() {
      _transport.addChunk(normalized.payload);
      // addChunk feeds an asynchronous stream. A next-event-turn callback
      // lets its complete JSON messages reach SurfaceController first, while
      // also allowing malformed/text-only payloads to leave the loading state.
      Timer.run(() => _markComplete(generation));
    }, (_, _) => _markError(generation));
  }

  void _handleSurfaceUpdate(SurfaceUpdate update) {
    var changed = false;
    if (update is SurfaceAdded) {
      if (!_surfaceIds.contains(update.surfaceId)) {
        _surfaceIds.add(update.surfaceId);
        changed = true;
      }
    } else if (update is SurfaceRemoved) {
      changed = _surfaceIds.remove(update.surfaceId);
    }
    if (changed && mounted) setState(() {});
  }

  void _markComplete(int generation) {
    if (!mounted || generation != _renderGeneration) return;
    setState(() => _isComplete = true);
  }

  void _markError(int generation) {
    if (!mounted || generation != _renderGeneration) return;
    setState(() {
      _hasError = true;
      _isComplete = true;
    });
  }

  Future<void> _forwardInteractions(ChatMessage message) async {
    final onInteraction = widget.onInteraction;
    final interactions = message.parts.uiInteractionParts;
    if (onInteraction == null ||
        widget.isBusy ||
        _interactionInFlight ||
        interactions.isEmpty) {
      return;
    }

    setState(() => _interactionInFlight = true);
    try {
      // A single tap is one Hermes turn. Never fan one submission out into
      // multiple turns, even if a malformed payload creates extra parts.
      await onInteraction(
        '[A2UI_INTERACTION]\n${interactions.first.interaction}',
      );
    } catch (_) {
      // The chat send path owns its normal user-visible error handling. Keep
      // a failing callback from becoming an unhandled stream error here.
    } finally {
      if (mounted) setState(() => _interactionInFlight = false);
    }
  }

  void _disposePipeline() {
    if (!_pipelineInitialized) return;
    unawaited(_surfaceUpdates?.cancel());
    unawaited(_messages?.cancel());
    unawaited(_submissions?.cancel());
    _transport.dispose();
    _controller.dispose();
    _pipelineInitialized = false;
  }

  @override
  void dispose() {
    _disposePipeline();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_surfaceIds.isEmpty) {
      if (!_isComplete) {
        return const Padding(
          padding: EdgeInsets.only(top: 12),
          child: SizedBox(
            height: 72,
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          ),
        );
      }
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text(
          _hasError
              ? 'This A2UI card could not be displayed safely. Ask Hermes to regenerate it.'
              : 'This A2UI response did not contain a renderable surface.',
          style: Theme.of(context).textTheme.bodySmall
              ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
      );
    }

    final surface = Padding(
      padding: const EdgeInsets.only(top: 12),
      child: IgnorePointer(
        ignoring:
            _interactionInFlight ||
            widget.isBusy ||
            widget.onInteraction == null,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final surfaceId in _surfaceIds)
              Surface(
                key: ValueKey<String>('hermes-a2ui-surface:$surfaceId'),
                surfaceContext: _controller.contextFor(surfaceId),
              ),
          ],
        ),
      ),
    );
    return Theme(data: hermezVisualTheme(Theme.of(context)), child: surface);
  }
}
