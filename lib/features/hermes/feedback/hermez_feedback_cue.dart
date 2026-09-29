import '../../../core/services/haptic_service.dart';

/// Semantic interface events. The UI names what happened; the sound, its
/// level, and the haptic are chosen here, in one place.
enum HermezFeedbackCue {
  controlSelect,

  objectOpen,
  objectClose,

  navLatchOpen,
  navLatchClose,

  sheetDetent,

  botWake,
  botEngage,

  runEngage,
  runComplete,
  runNeedsAttention,
  runFailed,

  approvalAccepted,
  approvalRejected,
}

/// How one cue sounds and feels.
class HermezFeedbackRecipe {
  const HermezFeedbackRecipe({
    this.sound,
    this.volume = 0,
    this.speed = 1,
    this.haptic,
  });

  /// Asset under `assets/sounds/hermez/`, or null for haptic only.
  final String? sound;

  /// Relative level; system media volume stays authoritative.
  final double volume;

  /// Playback speed; below 1 lowers the pitch (a closing latch).
  final double speed;

  final HapticType? haptic;
}

const String _dir = 'assets/sounds/hermez';

/// Starting levels from the sensory spec; device QA is authoritative.
const Map<HermezFeedbackCue, HermezFeedbackRecipe> hermezFeedbackRecipes = {
  HermezFeedbackCue.controlSelect: HermezFeedbackRecipe(
    sound: '$_dir/select_light.wav',
    volume: 0.20,
    haptic: HapticType.selection,
  ),
  HermezFeedbackCue.objectOpen: HermezFeedbackRecipe(
    sound: '$_dir/object_open.wav',
    volume: 0.28,
    haptic: HapticType.light,
  ),
  HermezFeedbackCue.objectClose: HermezFeedbackRecipe(
    sound: '$_dir/object_close.wav',
    volume: 0.26,
    haptic: HapticType.light,
  ),
  // Sound only: the side navigation settles without a haptic by design
  // (responsive_drawer_haptics_test pins that).
  HermezFeedbackCue.navLatchOpen: HermezFeedbackRecipe(
    sound: '$_dir/nav_latch.wav',
    volume: 0.28,
  ),
  HermezFeedbackCue.navLatchClose: HermezFeedbackRecipe(
    sound: '$_dir/nav_latch.wav',
    volume: 0.24,
    speed: 0.86,
  ),
  // Haptic only until device QA shows a sound helps.
  HermezFeedbackCue.sheetDetent: HermezFeedbackRecipe(
    haptic: HapticType.selection,
  ),
  HermezFeedbackCue.botWake: HermezFeedbackRecipe(
    sound: '$_dir/bot_wake.wav',
    volume: 0.30,
    haptic: HapticType.light,
  ),
  HermezFeedbackCue.botEngage: HermezFeedbackRecipe(
    sound: '$_dir/bot_engage.wav',
    volume: 0.30,
    haptic: HapticType.medium,
  ),
  HermezFeedbackCue.runEngage: HermezFeedbackRecipe(
    sound: '$_dir/run_engage.wav',
    volume: 0.30,
    haptic: HapticType.medium,
  ),
  HermezFeedbackCue.runNeedsAttention: HermezFeedbackRecipe(
    sound: '$_dir/attention.wav',
    volume: 0.35,
    haptic: HapticType.warning,
  ),
  HermezFeedbackCue.runComplete: HermezFeedbackRecipe(
    sound: '$_dir/success.wav',
    volume: 0.35,
    haptic: HapticType.success,
  ),
  HermezFeedbackCue.runFailed: HermezFeedbackRecipe(
    sound: '$_dir/failure.wav',
    volume: 0.32,
    haptic: HapticType.error,
  ),
  HermezFeedbackCue.approvalAccepted: HermezFeedbackRecipe(
    sound: '$_dir/approval_accept.wav',
    volume: 0.30,
    haptic: HapticType.success,
  ),
  HermezFeedbackCue.approvalRejected: HermezFeedbackRecipe(
    sound: '$_dir/approval_reject.wav',
    volume: 0.28,
    haptic: HapticType.medium,
  ),
};
