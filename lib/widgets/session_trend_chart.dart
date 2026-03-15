import 'package:flutter/material.dart';

class SessionTrendChart extends StatelessWidget {
  const SessionTrendChart({
    super.key,
    required this.scores,
    required this.accentColor,
    required this.label,
  });

  final List<double> scores;
  final Color accentColor;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF0E172F),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accentColor.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: accentColor,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 86,
            child: CustomPaint(
              painter: _TrendChartPainter(
                scores: scores,
                accentColor: accentColor,
              ),
              child: const SizedBox.expand(),
            ),
          ),
        ],
      ),
    );
  }
}

class _TrendChartPainter extends CustomPainter {
  _TrendChartPainter({
    required this.scores,
    required this.accentColor,
  });

  final List<double> scores;
  final Color accentColor;

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.08)
      ..strokeWidth = 1;

    for (var i = 1; i <= 3; i++) {
      final y = size.height * (i / 4);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    if (scores.length < 2) return;

    final points = <Offset>[];
    for (var i = 0; i < scores.length; i++) {
      final x = (i / (scores.length - 1)) * size.width;
      final normalized = (scores[i].clamp(0, 100)) / 100;
      final y = size.height - (normalized * (size.height - 8)) - 4;
      points.add(Offset(x, y));
    }

    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (var i = 1; i < points.length; i++) {
      final prev = points[i - 1];
      final next = points[i];
      final control1 = Offset((prev.dx + next.dx) / 2, prev.dy);
      final control2 = Offset((prev.dx + next.dx) / 2, next.dy);
      path.cubicTo(
          control1.dx, control1.dy, control2.dx, control2.dy, next.dx, next.dy);
    }

    final fillPath = Path.from(path)
      ..lineTo(points.last.dx, size.height)
      ..lineTo(points.first.dx, size.height)
      ..close();

    canvas.drawPath(
      fillPath,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            accentColor.withValues(alpha: 0.28),
            accentColor.withValues(alpha: 0.02),
          ],
        ).createShader(Offset.zero & size),
    );

    canvas.drawPath(
      path,
      Paint()
        ..color = accentColor
        ..strokeWidth = 3
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round,
    );

    for (final point in points) {
      canvas.drawCircle(point, 4.5, Paint()..color = const Color(0xFF0B1020));
      canvas.drawCircle(point, 3, Paint()..color = accentColor);
    }
  }

  @override
  bool shouldRepaint(covariant _TrendChartPainter oldDelegate) {
    return oldDelegate.scores != scores ||
        oldDelegate.accentColor != accentColor;
  }
}
