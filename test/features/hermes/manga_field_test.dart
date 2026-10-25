import 'package:conduit/features/hermes/manga/manga_theme.dart';
import 'package:conduit/features/hermes/widgets/hermez_bot_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(() => HermezBotIcons.colors.value = {});

  test('a colour chosen for a bot replaces its own selector field', () {
    expect(MangaField.forBot('chief').field, const Color(0xFFE8702A));

    HermezBotIcons.colors.value = {'default': const Color(0xFF5B2FA6)};
    final chief = MangaField.forBot('chief');
    expect(chief.field, const Color(0xFF5B2FA6));
    // White reads better than black on violet.
    expect(chief.ink, const Color(0xFFFFFFFF));

    // Black reads better on a light colour.
    expect(
      MangaField.fromColor(const Color(0xFFE8B526)).ink,
      const Color(0xFF0E0E10),
    );
  });
}
