import 'dart:io';

import 'package:conduit/core/persistence/preferences_store.dart';
import 'package:conduit/core/services/haptic_service.dart';
import 'package:conduit/features/hermes/feedback/hermez_feedback.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Backend implements HermezSoundBackend {
  _Backend({this.failStart = false, this.failPlay = false});

  final bool failStart;
  final bool failPlay;
  final List<String> played = [];

  @override
  Future<void> start(Iterable<String> assets) async {
    if (failStart) throw StateError('no audio device');
  }

  @override
  void play(String asset, {required double volume, required double speed}) {
    if (failPlay) throw StateError('engine crashed');
    played.add(asset);
  }
}

void main() {
  late List<HapticType> haptics;

  Future<(HermezFeedback, _Backend)> make({
    bool failStart = false,
    bool failPlay = false,
  }) async {
    final backend = _Backend(failStart: failStart, failPlay: failPlay);
    final feedback = HermezFeedback.forTesting(
      backend: backend,
      haptic: (type) async => haptics.add(type),
    );
    await feedback.startForTesting();
    return (feedback, backend);
  }

  setUp(() async {
    haptics = [];
    SharedPreferences.setMockInitialValues({});
    PreferencesStore.debugReset();
    PreferencesStore.debugOverride(await SharedPreferences.getInstance());
  });

  test('a cue plays its sound and its haptic', () async {
    final (feedback, backend) = await make();
    feedback.trigger(HermezFeedbackCue.objectOpen);
    expect(backend.played, ['assets/sounds/hermez/object_open.wav']);
    expect(haptics, [HapticType.light]);
  });

  test(
    'an engine that fails to start leaves haptics and never throws',
    () async {
      final (feedback, backend) = await make(failStart: true);
      expect(feedback.soundReady, isFalse);
      expect(
        () => feedback.trigger(HermezFeedbackCue.runComplete),
        returnsNormally,
      );
      expect(backend.played, isEmpty);
      expect(haptics, [HapticType.success]);
    },
  );

  test('an engine that throws while playing is switched off quietly', () async {
    final (feedback, _) = await make(failPlay: true);
    expect(
      () => feedback.trigger(HermezFeedbackCue.runFailed),
      returnsNormally,
    );
    expect(feedback.soundReady, isFalse);
    expect(
      () => feedback.trigger(HermezFeedbackCue.runFailed),
      returnsNormally,
    );
    expect(haptics, [HapticType.error, HapticType.error]);
  });

  test('a throwing haptic never escapes', () async {
    final backend = _Backend();
    final feedback = HermezFeedback.forTesting(
      backend: backend,
      haptic: (type) => throw StateError('no vibrator'),
    );
    await feedback.startForTesting();
    expect(
      () => feedback.trigger(HermezFeedbackCue.controlSelect),
      returnsNormally,
    );
    expect(backend.played, hasLength(1));
  });

  test('sound is dropped when off, backgrounded, or suppressed', () async {
    final (feedback, backend) = await make();

    await feedback.setSoundsEnabled(false);
    feedback.trigger(HermezFeedbackCue.controlSelect);
    expect(backend.played, isEmpty);
    expect(PreferencesStore.getBool(HermezFeedback.soundsPreferenceKey), false);
    await feedback.setSoundsEnabled(true);

    feedback.foregroundForTesting = false;
    feedback.trigger(HermezFeedbackCue.controlSelect);
    expect(backend.played, isEmpty);
    feedback.foregroundForTesting = true;

    var voiceActive = true;
    final remove = feedback.addSoundSuppressor(() => voiceActive);
    feedback.trigger(HermezFeedbackCue.controlSelect);
    expect(backend.played, isEmpty);
    voiceActive = false;
    feedback.trigger(HermezFeedbackCue.controlSelect);
    expect(backend.played, hasLength(1));
    remove();

    // Haptics were never suppressed.
    expect(haptics, everyElement(HapticType.selection));
    expect(haptics, hasLength(4));
  });

  test('sheet detent is haptic only', () async {
    final (feedback, backend) = await make();
    feedback.trigger(HermezFeedbackCue.sheetDetent);
    expect(backend.played, isEmpty);
    expect(haptics, [HapticType.selection]);
  });

  test('every cue sound is bundled', () {
    final sounds = hermezFeedbackRecipes.values
        .map((recipe) => recipe.sound)
        .whereType<String>()
        .toSet();
    for (final sound in sounds) {
      expect(File(sound).existsSync(), isTrue, reason: sound);
    }
  });
}
