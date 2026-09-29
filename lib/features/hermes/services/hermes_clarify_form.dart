/// Hermes clarify requests come in two shapes:
///
/// - single: `{question, choices, multi_select}`, answered with one `answer`;
/// - batch: `{questions: [{qid, question, choices, multi_select}]}`. Current
///   Hermes sends even a single question this way. Each question is answered
///   by its `qid` (`clarify.respond` with `question_id`, or `{answers}` for a
///   server request). A respond without a `question_id` is a cancel-all, which
///   the tool reads as an empty answer.
library;

final class HermesClarifyQuestion {
  const HermesClarifyQuestion({
    required this.qid,
    required this.question,
    this.choices = const [],
  });

  final String qid;
  final String question;
  final List<String> choices;
}

/// The batch questions in [payload], or null for a single-question request.
List<HermesClarifyQuestion>? hermesClarifyBatch(Map<String, dynamic> payload) {
  final raw = payload['questions'];
  if (raw is! List || raw.isEmpty) return null;
  final questions = <HermesClarifyQuestion>[];
  for (final entry in raw.take(20)) {
    if (entry is! Map) continue;
    final qid = entry['qid']?.toString() ?? '';
    if (qid.isEmpty || qid.length > 64) continue;
    final choices = entry['choices'];
    questions.add(
      HermesClarifyQuestion(
        qid: qid,
        question: entry['question']?.toString() ?? '',
        choices: choices is List
            ? [for (final c in choices.take(12)) ?c?.toString()]
            : const [],
      ),
    );
  }
  return questions.isEmpty ? null : questions;
}

/// The text to show: the single question, the batch's only question, or the
/// batch numbered one per line.
String hermesClarifyPrompt(Map<String, dynamic> payload) {
  final batch = hermesClarifyBatch(payload);
  if (batch == null) return payload['question']?.toString() ?? '';
  if (batch.length == 1) return batch.single.question;
  return [
    for (var i = 0; i < batch.length; i++) '${i + 1}. ${batch[i].question}',
    'Answer each on its own line.',
  ].join('\n');
}

/// Choices to offer: the single request's, or a one-question batch's.
List<Object?> hermesClarifyChoices(Map<String, dynamic> payload) {
  final batch = hermesClarifyBatch(payload);
  if (batch == null) {
    final choices = payload['choices'];
    return choices is List ? choices : const [];
  }
  return batch.length == 1 ? batch.single.choices : const [];
}

/// One answer per question id. With several questions, one line of [value]
/// per question when the line count matches; otherwise the whole answer goes
/// to the first question and the rest are skipped.
Map<String, String> hermesClarifyBatchAnswers(List<String> qids, String value) {
  if (qids.length == 1) return {qids.single: value};
  final lines = value
      .split('\n')
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .toList();
  if (lines.length == qids.length) {
    return {for (var i = 0; i < qids.length; i++) qids[i]: lines[i]};
  }
  return {for (var i = 0; i < qids.length; i++) qids[i]: i == 0 ? value : ''};
}
