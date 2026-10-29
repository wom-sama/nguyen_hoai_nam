import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'theme.dart';

/// A separate paint layer: no layout, pointer handling or content rebuilds.
class PaperBackdrop extends StatefulWidget {
  const PaperBackdrop({super.key});
  @override
  State<PaperBackdrop> createState() => _PaperBackdropState();
}

class _PaperBackdropState extends State<PaperBackdrop>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final _motion = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 36),
  );
  bool _foreground = true;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  void _sync() {
    final enabled =
        _foreground &&
        TickerMode.valuesOf(context).enabled &&
        !MediaQuery.disableAnimationsOf(context);
    if (enabled && !_motion.isAnimating) {
      _motion.repeat();
    } else if (!enabled) {
      _motion.stop();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (mounted) _sync();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: ExcludeSemantics(
      child: RepaintBoundary(
        child: CustomPaint(
          painter: _PaperPainter(_motion),
          size: Size.infinite,
        ),
      ),
    ),
  );
}

class _PaperPainter extends CustomPainter {
  _PaperPainter(this.motion) : super(repaint: motion);
  final Animation<double> motion;
  @override
  void paint(Canvas canvas, Size size) {
    final phase = motion.value * math.pi * 2;
    final paint = Paint()
      ..color = AppColors.pink.withValues(alpha: .065)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.3;
    canvas.save();
    canvas.translate(size.width - 13 + math.sin(phase) * 7, size.height * .23);
    canvas.rotate(-.15 + math.sin(phase) * .025);
    canvas.drawCircle(Offset.zero, 77, paint);
    canvas.drawCircle(Offset.zero, 68, paint);
    for (int tick = 0; tick < 12; tick++) {
      final a = tick * math.pi / 6;
      canvas.drawLine(
        Offset(math.cos(a) * 59, math.sin(a) * 59),
        Offset(math.cos(a) * 64, math.sin(a) * 64),
        paint,
      );
    }
    canvas.drawPath(
      Path()
        ..moveTo(-19, -29)
        ..lineTo(0, 0)
        ..lineTo(29, -11),
      paint..strokeWidth = 2,
    );
    canvas.restore();
    canvas.save();
    canvas.translate(
      -22 + math.cos(phase) * 6,
      size.height * .76 + math.sin(phase) * 9,
    );
    canvas.rotate(.12 + math.cos(phase) * .025);
    final sheet = RRect.fromRectAndRadius(
      const Rect.fromLTWH(0, 0, 142, 163),
      const Radius.circular(6),
    );
    paint.strokeWidth = 1.3;
    canvas.drawRRect(sheet, paint);
    canvas.drawLine(const Offset(0, 31), const Offset(142, 31), paint);
    for (int row = 0; row < 4; row++) {
      final y = 55.0 + row * 25;
      canvas.drawPath(
        Path()
          ..moveTo(21, y)
          ..lineTo(26, y + 5)
          ..lineTo(35, y - 5),
        paint,
      );
      canvas.drawLine(Offset(47, y), Offset(row == 3 ? 96 : 120, y), paint);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_PaperPainter oldDelegate) => oldDelegate.motion != motion;
}
