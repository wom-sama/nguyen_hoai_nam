import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:nguyen_hoai_nam/features/translation/translation_overlay.dart';
import 'package:nguyen_hoai_nam/features/translation/translation_service.dart';

void main() {
  test('contain projection preserves scale and includes letterbox offsets', () {
    final projection = ImageProjection.contain(
      imageSize: const Size(640, 480),
      viewportSize: const Size(320, 320),
    );
    expect(projection.imageRect, const Rect.fromLTWH(0, 40, 320, 240));
    expect(
      projection.project(const Rect.fromLTWH(64, 48, 128, 96)),
      const Rect.fromLTWH(32, 64, 64, 48),
    );
  });

  test('upright dimensions swap once for 90 and 270 degree ML Kit input', () {
    for (final rotation in InputImageRotation.values) {
      final expected =
          rotation == InputImageRotation.rotation90deg ||
              rotation == InputImageRotation.rotation270deg
          ? const Size(480, 640)
          : const Size(640, 480);
      expect(uprightImageSize(const Size(640, 480), rotation), expected);
    }
  });

  test('front preview mirrors bounds inside the image, not its letterbox', () {
    final projection = ImageProjection.contain(
      imageSize: const Size(640, 480),
      viewportSize: const Size(500, 240),
      mirror: true,
    );
    expect(projection.imageRect, const Rect.fromLTWH(90, 0, 320, 240));
    expect(
      projection.project(const Rect.fromLTWH(64, 48, 128, 96)),
      const Rect.fromLTWH(314, 24, 64, 48),
    );
  });

  testWidgets('labels stay in their image region and expose unabridged text', (
    tester,
  ) async {
    final region = TranslatedOcrRegion(
      originalText: 'Safety notice',
      translatedText: List.filled(35, 'Thông báo an toàn').join(' '),
      bounds: const Rect.fromLTWH(20, 20, 150, 60),
    );
    TranslatedOcrRegion? tapped;
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 300,
              height: 300,
              child: TranslationOverlayViewport(
                imageSize: const Size(300, 200),
                regions: [region],
                image: const ColoredBox(color: Colors.black),
                onRegionTap: (value) => tapped = value,
              ),
            ),
          ),
        ),
      ),
    );
    final label = find.byKey(const ValueKey('translated-region-0'));
    expect(tester.getSize(label), const Size(150, 60));
    expect(
      find.bySemanticsLabel(RegExp(RegExp.escape(region.translatedText))),
      findsOneWidget,
    );
    await tester.tap(label);
    expect(tapped, same(region));
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });

  testWidgets('small edge text has a readable label clamped inside the image', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 300,
              height: 300,
              child: TranslationOverlayViewport(
                imageSize: const Size(300, 200),
                image: const ColoredBox(color: Colors.black),
                regions: const [
                  TranslatedOcrRegion(
                    originalText: 'Exit',
                    translatedText: 'Lối ra',
                    bounds: Rect.fromLTWH(290, 195, 10, 5),
                  ),
                ],
                onRegionTap: (_) {},
              ),
            ),
          ),
        ),
      ),
    );
    final label = tester.getRect(
      find.byKey(const ValueKey('translated-region-0')),
    );
    final viewport = tester.getRect(find.byType(TranslationOverlayViewport));
    expect(label.width, 72);
    expect(label.height, 28);
    expect(label.right, viewport.right);
    expect(label.bottom, viewport.top + 250);
    expect(tester.takeException(), isNull);
  });

  testWidgets('large system text keeps at least one readable label line', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: Scaffold(
            body: Center(
              child: SizedBox(
                width: 300,
                height: 300,
                child: TranslationOverlayViewport(
                  imageSize: const Size(300, 200),
                  image: const ColoredBox(color: Colors.black),
                  regions: const [
                    TranslatedOcrRegion(
                      originalText: 'Exit',
                      translatedText: 'Lối ra',
                      bounds: Rect.fromLTWH(20, 20, 50, 10),
                    ),
                  ],
                  onRegionTap: (_) {},
                ),
              ),
            ),
          ),
        ),
      ),
    );
    expect(
      tester.getSize(find.byKey(const ValueKey('translated-region-0'))).height,
      greaterThanOrEqualTo(12 * 2 * 1.2 + 8),
    );
    expect(tester.takeException(), isNull);
  });
}
