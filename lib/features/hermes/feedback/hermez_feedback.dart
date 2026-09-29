import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_soloud/flutter_soloud.dart';

import '../../../core/persistence/preferences_store.dart';
import '../../../core/services/haptic_service.dart';
import '../../chat/services/tts_manager.dart';
import 'hermez_feedback_cue.dart';

export 'hermez_feedback_cue.dart';

/// Plays short sounds. The seam lets tests stand in for the audio engine.
abstract class HermezSoundBackend {
  /// Starts the engine and preloads [assets]. May throw.
  Future<void> start(Iterable<String> assets);

  /// Plays a preloaded asset. May throw.
  void play(String asset, {required double volume, required double speed});
}

/// [HermezSoundBackend] on flutter_soloud, tuned for short interface cues.
class SoLoudSoundBackend implements HermezSoundBackend {
  final Map<String, AudioSource> _sources = {};

  @override
  Future<void> start(Iterable<String> assets) async {
    final soloud = SoLoud.instance;
    if (!soloud.isInitialized) {
      await soloud.init(sampleRate: 48000, channels: Channels.mono);
    }
    for (final asset in assets.toSet()) {
      _sources[asset] = await soloud.loadAsset(asset);
    }
  }

  @override
  void play(String asset, {required double volume, required double speed}) {
    final source = _sources[asset];
    if (source == null) return;
    final soloud = SoLoud.instance;
    final handle = soloud.play(source, volume: volume);
    if (speed != 1) soloud.setRelativePlaySpeed(handle, speed);
  }
}

/// Hermez sensory feedback: a presentation-only observer.
///
/// [trigger] never throws, never blocks, and returns nothing a caller could
/// wait on, so no backend action can depend on it. Sound is dropped when it
/// is switched off, the app is in the background, voice or speech playback
/// is active, or the engine failed to start; the haptic still plays.
class HermezFeedback with WidgetsBindingObserver {
  HermezFeedback._({
    HermezSoundBackend? backend,
    Future<void> Function(HapticType type)? haptic,
  }) : _backend = backend ?? SoLoudSoundBackend(),
       _haptic = haptic ?? ConduitHaptics.trigger;

  /// The app-wide instance.
  static HermezFeedback instance = HermezFeedback._();

  /// Replaces [instance] for tests.
  @visibleForTesting
  static HermezFeedback forTesting({
    required HermezSoundBackend backend,
    Future<void> Function(HapticType type)? haptic,
  }) => HermezFeedback._(backend: backend, haptic: haptic);

  /// Plays [cue] on the app-wide instance. Fire and forget.
  static void play(HermezFeedbackCue cue) => instance.trigger(cue);

  static const String soundsPreferenceKey = 'hermez_interface_sounds';

  final HermezSoundBackend _backend;
  final Future<void> Function(HapticType type) _haptic;

  /// "Interface sounds" (on by default). Local only; never synced.
  late final ValueNotifier<bool> soundsEnabled = ValueNotifier<bool>(
    PreferencesStore.getBool(soundsPreferenceKey) ?? true,
  );

  final List<bool Function()> _suppressors = [];
  _EngineState _engine = _EngineState.idle;
  bool _foreground = true;
  bool _observing = false;

  @visibleForTesting
  bool get soundReady => _engine == _EngineState.ready;

  /// Persists the "Interface sounds" choice. Touches nothing in Hermes.
  Future<void> setSoundsEnabled(bool enabled) async {
    soundsEnabled.value = enabled;
    try {
      await PreferencesStore.put(soundsPreferenceKey, enabled);
    } catch (error) {
      debugPrint('HermezFeedback: could not save sound setting: $error');
    }
  }

  /// Registers a condition under which sound is suppressed (voice mode,
  /// speech playback). Returns a callback that removes it.
  VoidCallback addSoundSuppressor(bool Function() suppressed) {
    _suppressors.add(suppressed);
    return () => _suppressors.remove(suppressed);
  }

  /// Starts the engine in the background after the first frame. Safe to
  /// call repeatedly; failure only disables sound for this process.
  void warmUp() {
    if (!_observing) {
      _observing = true;
      WidgetsBinding.instance.addObserver(this);
      // Clicks would intrude on assistant speech.
      addSoundSuppressor(() => TtsManager.instance.isPlaying);
    }
    if (_engine != _EngineState.idle) return;
    _engine = _EngineState.starting;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_start());
    });
  }

  Future<void> _start() async {
    try {
      await _backend.start(
        hermezFeedbackRecipes.values.map((r) => r.sound).whereType<String>(),
      );
      _engine = _EngineState.ready;
    } catch (error) {
      _engine = _EngineState.failed;
      debugPrint('HermezFeedback: interface audio unavailable: $error');
    }
  }

  @visibleForTesting
  Future<void> startForTesting() => _start();

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
  }

  @visibleForTesting
  set foregroundForTesting(bool value) => _foreground = value;

  bool get _soundAllowed {
    if (_engine != _EngineState.ready) return false;
    if (!_foreground || !soundsEnabled.value) return false;
    for (final suppressed in _suppressors) {
      try {
        if (suppressed()) return false;
      } catch (_) {
        return false;
      }
    }
    return true;
  }

  /// Plays [cue]. Never throws; never waits.
  void trigger(HermezFeedbackCue cue) {
    final recipe = hermezFeedbackRecipes[cue];
    if (recipe == null) return;
    final haptic = recipe.haptic;
    if (haptic != null) {
      try {
        unawaited(_haptic(haptic).catchError((Object _) {}));
      } catch (_) {}
    }
    final sound = recipe.sound;
    if (sound == null || !_soundAllowed) return;
    try {
      _backend.play(sound, volume: recipe.volume, speed: recipe.speed);
    } catch (error) {
      _engine = _EngineState.failed;
      debugPrint('HermezFeedback: interface audio disabled: $error');
    }
  }
}

enum _EngineState { idle, starting, ready, failed }
