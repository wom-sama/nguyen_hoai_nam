// ImagePickerPlatform is the plugin's native testing boundary.
// ignore_for_file: depend_on_referenced_packages
import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';
import 'package:nguyen_hoai_nam/features/translation/translation_screen.dart';
import 'package:nguyen_hoai_nam/features/translation/translation_service.dart';
import 'package:nguyen_hoai_nam/ui/theme.dart';

class _Picker extends ImagePickerPlatform {
  _Picker(this.bytes);
  final Uint8List bytes;
  @override
  Future<XFile?> getImageFromSource({
    required ImageSource source,
    ImagePickerOptions options = const ImagePickerOptions(),
  }) async => XFile.fromData(bytes, mimeType: 'image/png');
}

/// Deliberate UI fixture; this does not claim native OCR recognition.
class _Translator extends TranslationService {
  ui.Image? receivedBitmap;
  final ready = Completer<void>();
  @override
  Future<OcrPage> recognizeBitmap(
    ui.Image bitmap, {
    required String sourceLanguage,
  }) async {
    receivedBitmap = bitmap;
    ready.complete();
    return OcrPage(
      text: 'Xin chào',
      regions: const [
        OcrRegion(text: 'Xin chào', bounds: Rect.fromLTWH(20, 20, 120, 40)),
      ],
    );
  }

  @override
  Future<String> translate(
    String text, {
    required String sourceLanguage,
    required String targetLanguage,
  }) async => 'Hello';
}

void main() {
  testWidgets(
    'selected photo displays the OCR bitmap with region translation as its main result',
    (tester) async {
      final bytes = await tester.runAsync(() async {
        final recorder = ui.PictureRecorder();
        Canvas(recorder).drawColor(Colors.white, BlendMode.src);
        final picture = recorder.endRecording();
        final image = await picture.toImage(200, 120);
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        image.dispose();
        picture.dispose();
        return data!.buffer.asUint8List();
      });
      final previous = ImagePickerPlatform.instance;
      ImagePickerPlatform.instance = _Picker(bytes!);
      addTearDown(() => ImagePickerPlatform.instance = previous);
      tester.view.physicalSize = const Size(600, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final translator = _Translator();
      await tester.pumpWidget(
        MaterialApp(
          theme: appTheme(),
          home: Scaffold(
            body: TranslationScreen(translationService: translator),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Chọn ảnh'));
      await tester.tap(find.text('Chọn ảnh'));
      // Codec callbacks return through the test binding's fake zone. Pump that
      // zone between short real waits rather than awaiting it from runAsync.
      for (
        var attempt = 0;
        attempt < 50 && !translator.ready.isCompleted;
        attempt++
      ) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump();
      }
      expect(
        translator.ready.isCompleted,
        isTrue,
        reason: 'The selected photo must reach OCR.',
      );
      await tester.pumpAndSettle();
      final preview = find.byKey(const ValueKey('photo-translation-preview'));
      final displayed = tester.widget<RawImage>(
        find.descendant(of: preview, matching: find.byType(RawImage)),
      );
      expect(displayed.image, same(translator.receivedBitmap));
      expect(find.byKey(const ValueKey('translated-region-0')), findsOneWidget);
      expect(find.text('Hello'), findsOneWidget);
      expect(find.text('Xem nội dung và thao tác'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
      await tester.ensureVisible(find.byTooltip('Đóng ảnh'));
      await tester.tap(find.byTooltip('Đóng ảnh'));
      await tester.pumpAndSettle();
      expect(preview, findsNothing);
      expect(translator.receivedBitmap!.debugDisposed, isTrue);
      expect(find.byType(TextField), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );
}
