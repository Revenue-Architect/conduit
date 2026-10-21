import 'dart:io';

import 'package:pigeon/pigeon.dart';

/// Pigeon inputs and the Kotlin file each one writes. The push bridge lives in
/// its own file so the large platform APIs file is never edited for it.
const _targets = <({String input, String kotlinOutput})>[
  (
    input: 'pigeons/conduit_platform_apis.dart',
    kotlinOutput:
        'android/app/src/main/kotlin/app/cogwheel/conduit/'
        'ConduitPlatformApis.g.kt',
  ),
  (
    input: 'pigeons/conduit_push_api.dart',
    kotlinOutput:
        'android/app/src/main/kotlin/app/cogwheel/conduit/push/'
        'ConduitPushApi.g.kt',
  ),
];

Future<void> main() async {
  for (final target in _targets) {
    final input = File(target.input).absolute.uri
        .normalizePath()
        .toFilePath();
    final result = await Pigeon.run(['--input', input]);
    if (result != 0) {
      exit(result);
    }

    // Pigeon 27.3 emits spaces after some Kotlin closing braces. Normalize only
    // trailing whitespace so generation stays reproducible and `git diff --check`
    // remains a useful gate.
    final kotlinOutput = File(target.kotlinOutput);
    final generated = await kotlinOutput.readAsString();
    final normalized = generated
        .replaceAll(RegExp(r'[ \t]+$', multiLine: true), '')
        // Pigeon 27.3 narrows nullable messages and structured details in Kotlin
        // FlutterApi error replies even though FlutterError accepts both.
        .replaceAll(
          'FlutterError(it[0] as String, it[1] as String, it[2] as String?)',
          'FlutterError(it[0] as String, it[1] as? String, it[2])',
        );
    if (generated != normalized) {
      await kotlinOutput.writeAsString(normalized);
    }
  }
}
