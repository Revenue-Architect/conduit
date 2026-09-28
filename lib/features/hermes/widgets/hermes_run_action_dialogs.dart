import 'package:flutter/material.dart';

import '../../../shared/widgets/conduit_dialog_route.dart';

Future<String?> promptHermesSteer(BuildContext context) async {
  var draft = '';
  return showConduitDialog<String>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Steer this run'),
      content: TextFormField(
        onChanged: (value) => draft = value,
        autofocus: true,
        maxLines: 3,
        decoration: const InputDecoration(
          hintText: 'What should Hermes change?',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext, draft.trim()),
          child: const Text('Send'),
        ),
      ],
    ),
  );
}

Future<bool> confirmHermesStop(BuildContext context) async =>
    await showConduitDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Stop this run?'),
        content: const Text('Hermes will interrupt the active turn.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Stop'),
          ),
        ],
      ),
    ) ??
    false;
