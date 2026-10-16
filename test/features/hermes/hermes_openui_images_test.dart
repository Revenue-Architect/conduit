import 'dart:ui' as ui;

import 'package:conduit/features/hermes/services/hermes_inline_ui_capability.dart';
import 'package:conduit/features/hermes/services/hermes_openui_image_source.dart';
import 'package:conduit/features/hermes/services/hermes_openui_parser.dart';
import 'package:conduit/features/hermes/widgets/hermes_openui_surface.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _png =
    'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAMAAAAB4CAMAAACTmw0tAAAAYFBMVEXMMCfPOS7SQzXVTT3YV0TcYUzfa1PidVrlfmLoiGnsknHvnHjypn/1sIf4uo78xJb8xJbzuI7qrYfhooDYl3jQjHHHgGq+dWK1alusX1SkVEybSEWSPT6JMjaAJy94HCgULny6AAACFUlEQVR42u3W23aCMBCF4Vhb7agXVpGDFfv+b1kOAgOZKjYmsNea/QT/dxEYY8QtpL2JW0p7l/YhbiVtLe1Tmmv/0rF/5dhP6P2E3k/o/TQuf+H4fP3109z610/2E3o/ofcTej9h/n67fkLvJ/R+Qu8n9H6CPB9sAG4/ofcTej+h9xPc+TwOMO/zh29jwPtFAFK/BIDqtwEI5wPrtwBo/UMAXP8AgNffBwD29wAw5wPr5wDIfgbA7O8AoP0tALW/AWCdDzYAt78GAPdXAOT+EgDdvzGI58NjAE7/1oD3iwCkfgkA1W8DEM4H1m8B0PqHALj+AQCvvw8A7O8BYM4H1s8BkP0MgNnfAUD7WwBqfwPAOh9sAG5/DQDurwDI/SUAun9rEM+HxwCc/p0B7xcBSP0SYLr+6Mg2rt8GTHA+RO044Hi47W6/BQjbfyoWRQ8A1b7+6B8CwvWfmo0ElBP6B4BA/Se+JwBcsZMAQfrjOHYC1IadBPB/PsT1XAH7YgLAd3/c7hWAxmDC9Ccx34sAFcIE6E+K+QLszc/Vb39SzyegnKfzIWnnGyAZHPvThC8AYGhw6k+LTQC45nnu3p/eNhEgrxH/7U+7TQgo9/znJ8uyNJ0PIM8vl8vY/uy22QHq3es/nzO2mQLKffOd+RSgAAUoQAEKUIACFKAABShAAQpQgAIUoAAFKEABClCAAhSgAAUEBfwC+qtD1Ge8LdIAAAAASUVORK5CYII=';

/// A decoded one-frame image, so no codec or network is involved.
class _FakeImage extends ImageProvider<_FakeImage> {
  _FakeImage(this.image, this.url, {this.fail = false});
  final ui.Image image;
  final String url;
  final bool fail;

  @override
  Future<_FakeImage> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture<_FakeImage>(this);

  @override
  ImageStreamCompleter loadImage(_FakeImage key, ImageDecoderCallback decode) =>
      OneFrameImageStreamCompleter(
        fail
            ? Future<ImageInfo>.error(StateError('offline'))
            : SynchronousFuture<ImageInfo>(ImageInfo(image: image.clone())),
      );

  @override
  bool operator ==(Object other) => other is _FakeImage && other.url == url;

  @override
  int get hashCode => url.hashCode;
}

void main() {
  late ui.Image image;
  final requested = <String>[];

  setUp(requested.clear);

  Future<void> pumpProgram(
    WidgetTester tester,
    String code, {
    bool fail = false,
    List<String>? sent,
    Widget? Function(String path)? mediaPreview,
    Brightness brightness = Brightness.light,
  }) async {
    image = (await tester.runAsync(() => createTestImage(width: 40, height: 25)))!;
    await tester.binding.setSurfaceSize(const Size(360, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(brightness: brightness),
        // No Scaffold, as in the real chat.
        home: SingleChildScrollView(
          child: HermesOpenuiSurface(
            payload: code,
            surfaceId: 'images',
            onInteraction: sent?.add,
            mediaPreview: mediaPreview,
            remoteImageProvider: (url) {
              requested.add(url);
              return _FakeImage(image, url, fail: fail);
            },
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  bool placeholderFor(String alt) =>
      find.text('Image unavailable').evaluate().isNotEmpty &&
      find.text(alt).evaluate().isNotEmpty;

  test('the capability note advertises the image components; the earlier note stays hidden', () {
    expect(hermesInlineUiInstructions, contains('ImageGallery'));
    const legacy = '''[Client capability: Conduit OpenUI v1]
This turn is in Hermez/Conduit with the same bounded 70-component OpenUI v1 catalog as Hermes Desktop. Load openui-desktop for exact signatures and validation. Emit a closed openui fence with one inline root = Stack([...]) program when useful. Existing strict A2UI v0.9 remains supported: load a2ui-mobile. Separate openui and a2ui fences may coexist. Use ordinary prose for short answers. UI buttons return ordinary [A2UI_INTERACTION] requests in this same session/profile with context.renderer=openui and current form values; local controls do not send or change operational state. Drafts remain unsent. This capability applies only to this turn, never WhatsApp/Teams/cron or a later unsupported client.''';
    const legacyWire =
        'Hello\n\n<hermez_client_capability>\n$legacy\n</hermez_client_capability>';
    expect(hermesInlineUiVisibleText(legacyWire), 'Hello');
    expect(hermesInlineUiTurnText(legacyWire), legacyWire);
    final current = hermesInlineUiTurnText('Hello');
    expect(current, isNot(legacyWire));
    expect(hermesInlineUiVisibleText(current), 'Hello');
  });

  group('source rules', () {
    test('http, https, LAN hosts, raster data URIs and bare paths are usable', () {
      for (final url in [
        'https://images.example/photo.jpg',
        'http://100.88.112.22:8080/a.png',
        'http://umbrel.local/a.png',
        'http://localhost:3000/a.png',
      ]) {
        expect(
          classifyHermesOpenuiImageSource(url).kind,
          HermesOpenuiImageKind.remote,
          reason: url,
        );
      }
      expect(
        classifyHermesOpenuiImageSource(_png).kind,
        HermesOpenuiImageKind.data,
      );
      for (final path in ['/tmp/chart.png', r'C:\Users\k\chart.png', 'chart.png']) {
        expect(
          classifyHermesOpenuiImageSource(path).kind,
          HermesOpenuiImageKind.declared,
          reason: path,
        );
      }
    });

    test('other schemes, credentials, odd data and oversize sources are rejected', () {
      for (final src in [
        'javascript:alert(1)',
        'file:///etc/passwd',
        'content://media/external/1',
        'intent://x#Intent;end',
        'ftp://host/a.png',
        'data:text/html;base64,PHA+',
        'data:image/svg+xml;base64,PHN2Zz4=',
        'https://user:pw@images.example/a.png',
        '//images.example/a.png',
        'https://images.example/${'a' * 2050}',
        'data:image/png;base64,${'A' * 49200}',
        'https://x.example/a\nb',
        '',
      ]) {
        expect(
          classifyHermesOpenuiImageSource(src).kind,
          HermesOpenuiImageKind.rejected,
          reason: src.length > 40 ? src.substring(0, 40) : src,
        );
      }
    });
  });

  group('schema', () {
    test('accepts the new components and rejects bad arguments', () {
      final tree = parseHermesOpenui(
        'root = Stack([Image("Alt","https://x.example/a.png"),Image("No source"),'
        'ImageBlock("https://x.example/a.png","Block"),'
        'ImageGallery([{src: "https://x.example/a.png", alt: "One", details: "d"},'
        '{"src": "https://x.example/b.png"}])])',
      );
      expect(tree.children, hasLength(4));
      expect(tree.children.last.props['images'], [
        {'src': 'https://x.example/a.png', 'alt': 'One', 'details': 'd'},
        {'src': 'https://x.example/b.png'},
      ]);
      final many = List.filled(13, '{src: "https://x.example/a.png"}');
      for (final code in [
        'root = Stack([Image()])',
        'root = Stack([Image("")])',
        'root = Stack([Image(42)])',
        'root = Stack([Image("a","data:image/png;base64,${'A' * 49200}")])',
        'root = Stack([ImageBlock("https://x.example/a.png","${'c' * 161}")])',
        'root = Stack([ImageBlock()])',
        'root = Stack([ImageCard("https://x.example/a.png","T")])',
        'root = Stack([ImageGallery([])])',
        'root = Stack([ImageGallery([Image("not an object")])])',
        'root = Stack([ImageGallery([{alt: "no src"}])])',
        'root = Stack([ImageGallery([{src: "https://x.example/a.png", extra: "x"}])])',
        'root = Stack([ImageGallery([{src: "a", src: "b"}])])',
        'root = Stack([ImageGallery([{src: 42}])])',
        'root = Stack([ImageGallery([{src: "https://x.example/a.png", details: "${'d' * 501}"}])])',
        'root = Stack([ImageGallery([${many.join(',')}])])',
        'root = Stack([ImageGallery([{src: "a"]])])',
        'root = Stack([Text({src: "a"})])',
        'root = Stack([ImageGallery([{__proto__: "a", src: "b"}])])',
      ]) {
        expect(
          () => parseHermesOpenui(code),
          throwsFormatException,
          reason: code.length > 80 ? code.substring(0, 80) : code,
        );
      }
    });
  });

  for (final brightness in Brightness.values) {
    testWidgets('a valid https image renders without a Scaffold $brightness', (
      tester,
    ) async {
      await pumpProgram(
        tester,
        'root = Stack([ImageBlock("https://images.example/photo.jpg","Harbour"),Image("Thumb","https://images.example/thumb.jpg")])',
        brightness: brightness,
      );
      expect(requested, [
        'https://images.example/photo.jpg',
        'https://images.example/thumb.jpg',
      ]);
      expect(find.byType(Image), findsNWidgets(2));
      expect(find.text('Image unavailable'), findsNothing);
      expect(find.byType(Scaffold), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('private LAN http and data image sources render', (tester) async {
    await pumpProgram(
      tester,
      'root = Stack([ImageBlock("http://100.88.112.22:8080/a.png","LAN"),Image("Embedded","$_png")])',
    );
    expect(requested, ['http://100.88.112.22:8080/a.png']);
    expect(find.byType(Image), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });

  for (final src in [
    'javascript:alert(1)',
    'file:///etc/passwd',
    'content://media/external/1',
    'intent://x#Intent;end',
    'ftp://host/a.png',
    'data:text/html;base64,PHA+',
    'https://user:pw@images.example/a.png',
    '/tmp/not-declared.png',
  ]) {
    testWidgets('rejected or undeclared source shows a placeholder: $src', (
      tester,
    ) async {
      await pumpProgram(tester, 'root = Stack([ImageBlock("$src","Safe alt")])');
      expect(requested, isEmpty);
      expect(find.byType(Image), findsNothing);
      expect(find.text('Safe alt'), findsOneWidget);
      expect(find.text('This OpenUI could not be displayed. Ask Hermes to regenerate it.'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('a load failure becomes the placeholder, not an error tile', (
    tester,
  ) async {
    await pumpProgram(
      tester,
      'root = Stack([Image("Gone photo","https://images.example/gone.png")])',
      fail: true,
    );
    await tester.pump();
    expect(placeholderFor('Gone photo'), isTrue);
    expect(find.textContaining('could not be displayed'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a Hermes-declared path previews only when the host declared it', (
    tester,
  ) async {
    await pumpProgram(
      tester,
      'root = Stack([ImageBlock("/tmp/declared.png","Declared"),ImageBlock("/tmp/other.png","Other")])',
      mediaPreview: (path) =>
          path == '/tmp/declared.png' ? const Text('host preview') : null,
    );
    expect(find.text('host preview'), findsOneWidget);
    expect(find.text('Other'), findsOneWidget);
    expect(find.text('Image unavailable'), findsNothing);
    expect(find.textContaining('MEDIA'), findsOneWidget);
  });

  testWidgets('tapping an image opens a local zoom viewer that sends nothing', (
    tester,
  ) async {
    final sent = <String>[];
    await pumpProgram(
      tester,
      'root = Stack([ImageBlock("https://images.example/photo.jpg","Harbour")])',
      sent: sent,
    );
    await tester.tap(find.byType(Image));
    await tester.pumpAndSettle();
    expect(find.byType(InteractiveViewer), findsOneWidget);
    expect(find.byTooltip('Close image'), findsOneWidget);
    await tester.tap(find.byTooltip('Close image'));
    await tester.pumpAndSettle();
    expect(find.byType(InteractiveViewer), findsNothing);
    expect(sent, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the gallery swipes between images and dots follow', (
    tester,
  ) async {
    await pumpProgram(
      tester,
      'root = Stack([ImageGallery(['
      '{src: "https://images.example/1.jpg", alt: "First", details: "one"},'
      '{src: "https://images.example/2.jpg", alt: "Second", details: "two"},'
      '{src: "https://images.example/3.jpg", alt: "Third", details: "three"}])])',
    );
    expect(find.text('1 / 3'), findsOneWidget);
    expect(find.text('First · one'), findsOneWidget);
    await tester.fling(find.byType(PageView), const Offset(-300, 0), 1200);
    await tester.pumpAndSettle();
    expect(find.text('2 / 3'), findsOneWidget);
    expect(find.text('Second · two'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('openui-gallery-dot-2')));
    await tester.pumpAndSettle();
    expect(find.text('3 / 3'), findsOneWidget);
    expect(find.text('Third · three'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an Image without a source shows its alt text as a placeholder', (
    tester,
  ) async {
    await pumpProgram(tester, 'root = Stack([Image("Plan sketch")])');
    expect(requested, isEmpty);
    expect(find.byType(Image), findsNothing);
    expect(find.text('Plan sketch'), findsOneWidget);
    expect(find.text('Image unavailable'), findsOneWidget);
  });

  testWidgets('gallery images open the viewer with their details', (
    tester,
  ) async {
    await pumpProgram(
      tester,
      'root = Stack([ImageGallery([{src: "https://images.example/1.jpg", alt: "First", details: "Long description"}])])',
    );
    await tester.tap(find.byType(Image));
    await tester.pumpAndSettle();
    expect(find.text('First\nLong description'), findsOneWidget);
  });
}
