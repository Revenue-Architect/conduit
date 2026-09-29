import 'package:flutter/material.dart';

import '../../../shared/widgets/conduit_dialog_route.dart';

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
