/// Current-client guidance, sent only with a normal Conduit Hermes turn.
/// It is not evidence that any other client supports either renderer.
const hermesInlineUiInstructions = '''[Client capability: Conduit OpenUI v1]
This turn is in Hermez/Conduit with a bounded 73-component OpenUI v1 catalog: the 70 components shared with Hermes Desktop plus Image(alt, src?), ImageBlock(src, alt?) and ImageGallery([{src, alt, details}]) for pictures (https/http URLs, data:image URIs or MEDIA: paths declared in the same reply; see openui-desktop). Load openui-desktop for exact signatures and validation. Emit a closed openui fence with one inline root = Stack([...]) program when useful. Existing strict A2UI v0.9 remains supported: load a2ui-mobile. Separate openui and a2ui fences may coexist. Use ordinary prose for short answers. UI buttons return ordinary [A2UI_INTERACTION] requests in this same session/profile with context.renderer=openui and current form values; local controls do not send or change operational state. Drafts remain unsent. Buttons on an older reply are disabled once a newer turn exists, so put actions in the latest reply. This capability applies only to this turn, never WhatsApp/Teams/cron or a later unsupported client.''';

/// Earlier builds sent this text; server history still holds it, so keep
/// recognising it when presenting or retrying those rows.
const _legacyInstructions = '''[Client capability: Conduit OpenUI v1]
This turn is in Hermez/Conduit with the same bounded 70-component OpenUI v1 catalog as Hermes Desktop. Load openui-desktop for exact signatures and validation. Emit a closed openui fence with one inline root = Stack([...]) program when useful. Existing strict A2UI v0.9 remains supported: load a2ui-mobile. Separate openui and a2ui fences may coexist. Use ordinary prose for short answers. UI buttons return ordinary [A2UI_INTERACTION] requests in this same session/profile with context.renderer=openui and current form values; local controls do not send or change operational state. Drafts remain unsent. This capability applies only to this turn, never WhatsApp/Teams/cron or a later unsupported client.''';

/// Older JSON-RPC gateways have no client instructions parameter. Keep the
/// marker in this turn's model input. Server history retains the marker;
/// the local composed message remains the user's original text.
const _hermesInlineUiSuffix =
    '\n\n<hermez_client_capability>\n$hermesInlineUiInstructions\n</hermez_client_capability>';
const _legacyInlineUiSuffix =
    '\n\n<hermez_client_capability>\n$_legacyInstructions\n</hermez_client_capability>';

String hermesInlineUiTurnText(String text) {
  // Preserve the exact action envelope. Its renderer identifies this current
  // interaction; appending prose would make the JSON invalid for consumers.
  if (text.startsWith('[A2UI_INTERACTION]\n')) return text;
  // Slash commands are parsed by the gateway, not the model; the suffix would
  // become part of their arguments.
  if (text.startsWith('/')) return text;
  return text.endsWith(_hermesInlineUiSuffix) ||
          text.endsWith(_legacyInlineUiSuffix)
      ? text
      : '$text$_hermesInlineUiSuffix';
}

/// Hermes hands a finished background delegation back to the parent as a
/// user-role message. It is the server waking the model, not the owner, so
/// it is shown as a short notice instead of a sent bubble.
bool hermesIsDelegationResultNotice(String text) =>
    text.startsWith('[ASYNC DELEGATION ');

/// A turn Hermes admitted into the chat itself: a scheduled job's output, a
/// Kanban task's status wake, or an Umbrel incident hand-off. It starts the
/// turn but is not the owner speaking, so its text is not shown as a sent
/// bubble; the bot's reply (and any worker row on it) says what happened.
bool hermesIsAutomationTurn(String text) =>
    text.startsWith('[Cronjob "') ||
    text.startsWith('[kanban] Task t_') ||
    text.startsWith('[Umbrel incident ');

/// The summary Hermes leaves when it compacts a long chat. It is reference
/// for the model, stored as a user-role row; the chat shows it as a thin
/// "earlier messages summarized" line.
bool hermesIsCompactionHandoff(String text) =>
    text.startsWith('[CONTEXT COMPACTION');

/// Presentation only. Matching and server history keep the original wire text.
String hermesInlineUiVisibleText(String text) {
  for (final suffix in const [_hermesInlineUiSuffix, _legacyInlineUiSuffix]) {
    if (text.endsWith(suffix)) {
      return text.substring(0, text.length - suffix.length);
    }
  }
  return text;
}
