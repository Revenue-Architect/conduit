import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// The pointer lock over an A2UI surface while it cannot send a turn (the
/// message is read-only, Hermes is busy, or a tap is already in flight).
///
/// Like an [IgnorePointer], except that a [HermesA2uiLocalControl] still takes
/// input: opening a compartment is local presentation, reveals content that is
/// already in the response, and sends nothing. Anything the local control
/// holds that could submit re-locks itself through [lockedOf].
class HermesA2uiInteractionLock extends StatelessWidget {
  const HermesA2uiInteractionLock({
    super.key,
    required this.locked,
    required this.child,
  });

  final bool locked;
  final Widget child;

  /// Whether the nearest surface is locked. Registers a dependency, so a
  /// local control rebuilds when the lock changes.
  static bool lockedOf(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<_HermesA2uiLockScope>()
          ?.locked ??
      false;

  @override
  Widget build(BuildContext context) => _HermesA2uiLockScope(
    locked: locked,
    child: _LocalControlGate(locked: locked, child: child),
  );
}

/// Marks a subtree whose input is local only and stays usable while the
/// surface is locked.
class HermesA2uiLocalControl extends StatelessWidget {
  const HermesA2uiLocalControl({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) =>
      MetaData(metaData: _localControlTag, child: child);
}

const Object _localControlTag = #hermesA2uiLocalControl;

class _HermesA2uiLockScope extends InheritedWidget {
  const _HermesA2uiLockScope({required this.locked, required super.child});

  final bool locked;

  @override
  bool updateShouldNotify(_HermesA2uiLockScope oldWidget) =>
      locked != oldWidget.locked;
}

class _LocalControlGate extends SingleChildRenderObjectWidget {
  const _LocalControlGate({required this.locked, super.child});

  final bool locked;

  @override
  _RenderLocalControlGate createRenderObject(BuildContext context) =>
      _RenderLocalControlGate(locked);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderLocalControlGate renderObject,
  ) => renderObject.locked = locked;
}

class _RenderLocalControlGate extends RenderProxyBox {
  _RenderLocalControlGate(this.locked);

  bool locked;

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    if (!locked) return super.hitTest(result, position: position);
    final target = child;
    if (target == null || !size.contains(position)) return false;
    // Probe first; only a hit that lands inside a local control is let
    // through, and only then is it recorded in the real result.
    final probe = BoxHitTestResult();
    if (!target.hitTest(probe, position: position)) return false;
    final local = probe.path.any(
      (entry) =>
          entry.target is RenderMetaData &&
          (entry.target as RenderMetaData).metaData == _localControlTag,
    );
    if (!local) return false;
    return super.hitTest(result, position: position);
  }
}
