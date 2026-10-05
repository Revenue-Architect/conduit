import 'package:conduit/core/models/chat_message.dart';
import 'package:conduit/features/chat/providers/chat_providers.dart';
import 'package:flutter_test/flutter_test.dart';

ChatMessage _assistant(
  String id,
  String content, {
  String? session = 'stored-1',
  bool streaming = false,
}) => ChatMessage(
  id: id,
  role: 'assistant',
  content: content,
  timestamp: DateTime.utc(2026, 10, 5),
  isStreaming: streaming,
  metadata: session == null ? null : {'hermesSessionId': session},
);

void main() {
  test('a finished run the native transcript ends with is the same reply', () {
    // The run's copy keeps its reasoning block; the transcript row does not.
    final run = _assistant(
      'local-1',
      '<details type="reasoning" done="true">\n<summary>Thought</summary>\n'
          'checking\n</details>\nQA passed:  date ran.\n',
    );
    final tail = _assistant('server-9', 'QA passed: date ran.');
    expect(
      hermesNativeTranscriptEndsWithReply(transcriptTail: tail, reply: run),
      isTrue,
    );
  });

  test('a different reply, session or a live run is never matched', () {
    final tail = _assistant('server-9', 'OK');
    expect(
      hermesNativeTranscriptEndsWithReply(
        transcriptTail: tail,
        reply: _assistant('local-1', 'Done.'),
      ),
      isFalse,
    );
    expect(
      hermesNativeTranscriptEndsWithReply(
        transcriptTail: tail,
        reply: _assistant('local-1', 'OK', session: 'stored-2'),
      ),
      isFalse,
    );
    expect(
      hermesNativeTranscriptEndsWithReply(
        transcriptTail: tail,
        reply: _assistant('local-1', 'OK', streaming: true),
      ),
      isFalse,
    );
    // The transcript ends with the user's turn: the reply is not in it yet.
    expect(
      hermesNativeTranscriptEndsWithReply(
        transcriptTail: ChatMessage(
          id: 'server-8',
          role: 'user',
          content: 'OK',
          timestamp: DateTime.utc(2026, 10, 5),
        ),
        reply: _assistant('local-1', 'OK'),
      ),
      isFalse,
    );
    // An empty reply says nothing about which turn it was.
    expect(
      hermesNativeTranscriptEndsWithReply(
        transcriptTail: _assistant('server-9', ''),
        reply: _assistant('local-1', ''),
      ),
      isFalse,
    );
  });
}
