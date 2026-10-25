import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/persistence/preferences_store.dart';

const _classicKey = 'conduit_classic_layout';
const _lastBotKey = 'conduit_manga_last_bot';

/// "Classic layout" in Appearance: the list screens from before the manga
/// page. Off by default; one switch goes back.
final mangaClassicLayoutProvider = NotifierProvider<MangaClassicLayout, bool>(
  MangaClassicLayout.new,
);

class MangaClassicLayout extends Notifier<bool> {
  @override
  bool build() => PreferencesStore.get<bool>(_classicKey) ?? false;

  Future<void> set(bool value) async {
    state = value;
    await PreferencesStore.put(_classicKey, value);
  }
}

/// The bot the task box on Today sends to: the last one picked.
final mangaLastBotProvider = NotifierProvider<MangaLastBot, String?>(
  MangaLastBot.new,
);

class MangaLastBot extends Notifier<String?> {
  @override
  String? build() => PreferencesStore.get<String>(_lastBotKey);

  Future<void> set(String name) async {
    if (state == name) return;
    state = name;
    await PreferencesStore.put(_lastBotKey, name);
  }
}

/// Whether the manga layout is on, for widgets below a page that already
/// watches [mangaClassicLayoutProvider] (so they rebuild with it).
/// Outside a ProviderScope (a widget pumped alone) it is the classic look.
bool mangaLayoutOf(BuildContext context) {
  try {
    return !ProviderScope.containerOf(
      context,
      listen: false,
    ).read(mangaClassicLayoutProvider);
  } on StateError {
    return false;
  }
}
