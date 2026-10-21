import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android builds retain the native push receiver and startup bridge', () {
    final manifest = File('android/app/src/main/AndroidManifest.xml')
        .readAsStringSync();
    expect(manifest, contains('android:name=".push.PushReceiver"'));
    expect(manifest, contains('org.unifiedpush.android.connector.MESSAGE'));
    expect(
      File('android/app/build.gradle.kts').readAsStringSync(),
      contains('org.unifiedpush.android:connector:'),
    );
    expect(File('lib/main.dart').readAsStringSync(), contains('pushRuntimeProvider'));
    expect(
      File('android/app/src/main/kotlin/app/cogwheel/conduit/MainActivity.kt')
          .readAsStringSync(),
      contains('PushBridge.attach'),
    );
  });
}
