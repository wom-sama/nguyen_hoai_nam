import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'theme.dart';

/// Original H/N strokes share the spine of a small time ledger.
class HnMark extends StatelessWidget {
  const HnMark({super.key, this.size = 48, this.inverse = false});
  final double size;
  final bool inverse;

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Dấu HN, Nguyễn Hoài Nam',
    image: true,
    child: CustomPaint(size: Size.square(size), painter: _HnPainter(inverse)),
  );
}

class _HnPainter extends CustomPainter {
  const _HnPainter(this.inverse);
  final bool inverse;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 48, size.height / 48);
    final background = Paint()
      ..color = inverse ? AppColors.cream : AppColors.pink;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(0, 0, 48, 48),
        const Radius.circular(5),
      ),
      background,
    );
    final stroke = Paint()
      ..color = inverse ? AppColors.pink : AppColors.cream
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.square
      ..strokeJoin = StrokeJoin.miter;
    canvas.drawPath(
      Path()
        ..moveTo(11, 14)
        ..lineTo(11, 34)
        ..moveTo(11, 24)
        ..lineTo(23, 24)
        ..moveTo(23, 34)
        ..lineTo(23, 14)
        ..lineTo(36, 34)
        ..lineTo(36, 14),
      stroke,
    );
    canvas.drawLine(
      const Offset(10, 39),
      const Offset(37, 39),
      stroke..strokeWidth = 1,
    );
    canvas.drawLine(const Offset(31, 9), const Offset(37, 9), stroke);
    canvas.drawLine(const Offset(37, 9), const Offset(37, 12), stroke);
  }

  @override
  bool shouldRepaint(_HnPainter oldDelegate) => oldDelegate.inverse != inverse;
}

class LedgerHeading extends StatelessWidget {
  const LedgerHeading({
    super.key,
    required this.title,
    required this.kicker,
    this.subtitle,
  });
  final String title, kicker;
  final String? subtitle;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 20),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    kicker,
                    style: TextStyle(
                      fontSize: 10,
                      letterSpacing: 1.3,
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                  const SizedBox(height: 7),
                  Text(title, style: Theme.of(context).textTheme.headlineLarge),
                ],
              ),
            ),
            const SizedBox(width: 14),
            const HnMark(size: 32),
          ],
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 10),
          Text(
            subtitle!,
            style: const TextStyle(color: AppColors.muted, height: 1.65),
          ),
        ],
      ],
    ),
  );
}

class LedgerSection extends StatelessWidget {
  const LedgerSection({
    super.key,
    required this.number,
    required this.title,
    this.action,
  });
  final String number, title;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 26, bottom: 14),
    child: Row(
      children: [
        Text(
          number,
          style: TextStyle(
            fontSize: 11,
            color: Theme.of(context).colorScheme.primary,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(title, style: Theme.of(context).textTheme.titleMedium),
        ),
        ?action,
      ],
    ),
  );
}

/// Flat paper, a ruled heading and a perforated footer belong to the shift receipt.
class LedgerSheet extends StatelessWidget {
  const LedgerSheet({
    super.key,
    required this.label,
    required this.reference,
    required this.child,
    this.footer,
  });
  final String label, reference;
  final Widget child;
  final Widget? footer;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        side: const BorderSide(color: AppColors.line),
        borderRadius: BorderRadius.circular(4),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primaryContainer,
              border: const Border(bottom: BorderSide(color: AppColors.line)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.3,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ),
                if (reference.isNotEmpty)
                  Text(
                    reference,
                    style: const TextStyle(
                      fontSize: 10,
                      color: AppColors.muted,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
              ],
            ),
          ),
          Padding(padding: const EdgeInsets.all(16), child: child),
          if (footer != null) ...[
            const SizedBox(
              height: 1,
              child: CustomPaint(painter: _PerforationPainter()),
            ),
            Padding(padding: const EdgeInsets.all(18), child: footer!),
          ],
        ],
      ),
    ),
  );
}

class _PerforationPainter extends CustomPainter {
  const _PerforationPainter();
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.line
      ..strokeWidth = 1;
    for (double x = 0; x < size.width; x += 9) {
      canvas.drawLine(
        Offset(x, 0),
        Offset(math.min(x + 4, size.width), 0),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_PerforationPainter oldDelegate) => false;
}

class ConfirmationStamp extends StatelessWidget {
  const ConfirmationStamp({super.key, required this.label});
  final String label;
  @override
  Widget build(BuildContext context) => Transform.rotate(
    angle: -.045,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.green, width: 1.5),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.verified_outlined, size: 16, color: AppColors.green),
          const SizedBox(width: 7),
          Flexible(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 10,
                color: AppColors.green,
                fontWeight: FontWeight.w700,
                letterSpacing: .8,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

/// Only the selected tab animates; its subtree and scroll state remain mounted.
class TabEntrance extends StatefulWidget {
  const TabEntrance({super.key, required this.active, required this.child});
  final bool active;
  final Widget child;
  @override
  State<TabEntrance> createState() => _TabEntranceState();
}

class _TabEntranceState extends State<TabEntrance>
    with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 240),
    value: 1,
  );
  late final _curve = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeOutCubic,
  );
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.value = 1;
    }
  }

  @override
  void didUpdateWidget(TabEntrance oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active &&
        !oldWidget.active &&
        !MediaQuery.disableAnimationsOf(context)) {
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _curve.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TickerMode(
    enabled: widget.active,
    child: FadeTransition(
      opacity: _curve,
      child: SlideTransition(
        position: Tween(
          begin: const Offset(0, .018),
          end: Offset.zero,
        ).animate(_curve),
        child: widget.child,
      ),
    ),
  );
}
