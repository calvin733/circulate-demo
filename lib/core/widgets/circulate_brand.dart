import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

const circulateName = 'Circulate';
const circulateTagline = 'Good things deserve another chapter.';

class CirculateMark extends StatelessWidget {
  const CirculateMark({super.key, this.size = 32, this.color});
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: CustomPaint(
      size: Size.square(size),
      painter: _CirculateMarkPainter(
        color ?? Theme.of(context).colorScheme.primary,
      ),
    ),
  );
}

class CirculateWordmark extends StatelessWidget {
  const CirculateWordmark({super.key, this.size = 25});
  final double size;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      CirculateMark(size: size + 4),
      const SizedBox(width: AppTokens.sm),
      Flexible(
        child: Text(
          circulateName,
          style: Theme.of(context).textTheme.headlineMedium
              ?.copyWith(fontSize: size, letterSpacing: -.65),
        ),
      ),
    ],
  );
}

class _CirculateMarkPainter extends CustomPainter {
  const _CirculateMarkPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 48, size.height / 48);
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final mark = Path()
      ..moveTo(7, 27)
      ..cubicTo(6, 16, 14, 8, 24, 8)
      ..cubicTo(30, 8, 35, 11, 38, 16)
      ..lineTo(30, 16)
      ..moveTo(41, 21)
      ..cubicTo(42, 32, 34, 40, 24, 40)
      ..cubicTo(18, 40, 13, 37, 10, 32)
      ..lineTo(18, 32);
    canvas.drawPath(mark, stroke);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_CirculateMarkPainter oldDelegate) =>
      color != oldDelegate.color;
}
