import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import '../../ui/components.dart';
import '../../ui/theme.dart';
import 'translation_service.dart';

/// ML Kit already rotates recognition coordinates upright. Only the dimensions
/// swap here; rotating its returned bounds a second time would misplace labels.
Size uprightImageSize(Size rawSize, InputImageRotation rotation) =>
    rotation == InputImageRotation.rotation90deg ||
        rotation == InputImageRotation.rotation270deg
    ? Size(rawSize.height, rawSize.width)
    : rawSize;

class ImageProjection {
  ImageProjection.contain({
    required this.imageSize,
    required Size viewportSize,
    this.mirror = false,
  }) : imageRect = Alignment.center.inscribe(
         applyBoxFit(BoxFit.contain, imageSize, viewportSize).destination,
         Offset.zero & viewportSize,
       );

  final Size imageSize;
  final Rect imageRect;
  final bool mirror;

  Rect project(Rect bounds) {
    final scale = imageRect.width / imageSize.width;
    final left = mirror ? imageSize.width - bounds.right : bounds.left;
    return Rect.fromLTWH(
      imageRect.left + left * scale,
      imageRect.top + bounds.top * scale,
      bounds.width * scale,
      bounds.height * scale,
    );
  }
}

/// Image and labels share one explicit contain transform, including letterboxes.
/// The supplied image must already be upright; [mirror] mirrors label geometry
/// for a front camera preview that the camera plugin itself mirrors.
class TranslationOverlayViewport extends StatelessWidget {
  const TranslationOverlayViewport({
    super.key,
    required this.imageSize,
    required this.image,
    required this.regions,
    required this.onRegionTap,
    this.mirror = false,
  });

  final Size imageSize;
  final Widget image;
  final List<TranslatedOcrRegion> regions;
  final ValueChanged<TranslatedOcrRegion> onRegionTap;
  final bool mirror;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final projection = ImageProjection.contain(
        imageSize: imageSize,
        viewportSize: constraints.biggest,
        mirror: mirror,
      );
      return ClipRect(
        child: Stack(
          fit: StackFit.expand,
          children: [
            Positioned.fromRect(rect: projection.imageRect, child: image),
            for (var index = 0; index < regions.length; index++)
              if (!projection
                  .project(regions[index].bounds)
                  .intersect(projection.imageRect)
                  .isEmpty)
                _label(context, projection, regions[index], index),
          ],
        ),
      );
    },
  );

  Widget _label(
    BuildContext context,
    ImageProjection projection,
    TranslatedOcrRegion region,
    int index,
  ) {
    final anchor = projection
        .project(region.bounds)
        .intersect(projection.imageRect);
    // Very small source lettering must not reduce the translated label below a
    // readable line. Keep its anchor and clamp the expanded label to the image.
    final fontSize = (anchor.height / 2.8).clamp(12.0, 18.0).toDouble();
    final scaledFontSize = MediaQuery.textScalerOf(context).scale(fontSize);
    final width = math.min(
      projection.imageRect.width,
      math.max(anchor.width, 72.0),
    );
    final height = math.min(
      projection.imageRect.height,
      math.max(anchor.height, math.max(28.0, scaledFontSize * 1.2 + 8)),
    );
    final rect = Rect.fromLTWH(
      anchor.left
          .clamp(projection.imageRect.left, projection.imageRect.right - width)
          .toDouble(),
      anchor.top
          .clamp(projection.imageRect.top, projection.imageRect.bottom - height)
          .toDouble(),
      width,
      height,
    );
    final lines = math.max(
      1,
      ((rect.height - 8) / (scaledFontSize * 1.2)).floor(),
    );
    return Positioned.fromRect(
      rect: rect,
      child: Semantics(
        button: true,
        label:
            'Bản dịch: ${region.translatedText}. Bản gốc: ${region.originalText}',
        hint: 'Mở toàn bộ nội dung',
        excludeSemantics: true,
        onTap: () => onRegionTap(region),
        child: GestureDetector(
          onTap: () => onRegionTap(region),
          behavior: HitTestBehavior.opaque,
          child: ClipRect(
            key: ValueKey('translated-region-$index'),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: const Color(0xFFFDF7EE).withValues(alpha: .96),
                border: Border.all(color: AppColors.pink.withValues(alpha: .7)),
                borderRadius: BorderRadius.circular(3),
              ),
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Text(
                  region.translatedText,
                  maxLines: lines,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: const Color(0xFF30242B),
                    fontSize: fontSize,
                    fontWeight: FontWeight.w600,
                    height: 1.2,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

Future<void> showOcrRegionDetails(
  BuildContext context,
  TranslatedOcrRegion region,
) => showModalBottomSheet<void>(
  context: context,
  showDragHandle: true,
  isScrollControlled: true,
  sheetAnimationStyle: MediaQuery.disableAnimationsOf(context)
      ? AnimationStyle.noAnimation
      : null,
  builder: (context) => SafeArea(
    child: ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * .75,
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Bản dịch', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            SelectableText(
              region.translatedText,
              style: const TextStyle(fontSize: 20, height: 1.5),
            ),
            const GoogleTranslationAttribution(),
            const Divider(height: 28),
            Text('Bản gốc', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 8),
            SelectableText(region.originalText),
          ],
        ),
      ),
    ),
  ),
);
