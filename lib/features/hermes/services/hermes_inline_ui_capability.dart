/// Current-client guidance, sent only with a normal Conduit Hermes turn.
/// It is not evidence that any other client supports either renderer.
const hermesInlineUiInstructions = '''[Client capability: Conduit OpenUI v1]
This turn is in Hermez/Conduit with the same bounded 70-component OpenUI v1 catalog as Hermes Desktop. Load openui-desktop for exact signatures and validation. Emit a closed openui fence with one inline root = Stack([...]) program when useful. Existing strict A2UI v0.9 remains supported: load a2ui-mobile. Separate openui and a2ui fences may coexist. Use ordinary prose for short answers. UI buttons return ordinary [A2UI_INTERACTION] requests in this same session/profile with context.renderer=openui and current form values; local controls do not send or change operational state. Drafts remain unsent. This capability applies only to this turn, never WhatsApp/Teams/cron or a later unsupported client.''';

/// Older JSON-RPC gateways have no client instructions parameter. Keep the
/// marker in this turn's model input. Server history retains the marker;
/// the local composed message remains the user's original text.
const _hermesInlineUiSuffix =
    '\n\n<hermez_client_capability>\n$hermesInlineUiInstructions\n</hermez_client_capability>';

String hermesInlineUiTurnText(String text) {
  // Preserve the exact action envelope. Its renderer identifies this current
  // interaction; appending prose would make the JSON invalid for consumers.
  if (text.startsWith('[A2UI_INTERACTION]\n')) return text;
  return text.endsWith(_hermesInlineUiSuffix)
      ? text
      : '$text$_hermesInlineUiSuffix';
}

/// Presentation only. Matching and server history keep the original wire text.
String hermesInlineUiVisibleText(String text) =>
    text.endsWith(_hermesInlineUiSuffix)
    ? text.substring(0, text.length - _hermesInlineUiSuffix.length)
    : text;
