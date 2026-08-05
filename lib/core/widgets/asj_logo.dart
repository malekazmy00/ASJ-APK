import 'package:flutter/material.dart';

/// إعادة رسم اللوجو الأصلي بنفس الإحداثيات المستخدمة في نسخة Streamlit
/// (views/base.py -> render_header):
///
///   <svg viewBox="0 0 100 100">
///     <path d="M 20 75 A 40 40 0 1 1 80 75" stroke="#0A2540" stroke-width="10"/>
///     <path d="M 5 55 L 30 55 L 40 25 L 60 85 L 70 55 L 95 55"
///           stroke="#00D2FF" stroke-width="6"/>
///   </svg>
///
/// أول مسار: قوس طبي (زي سماعة الطبيب) بالكحلي الغامق.
/// تاني مسار: خط نبض (Heartbeat) بالسماوي، يمر فوق القوس.
/// نفس نظام الإحداثيات (0-100) هنا، ويتم تحجيمه تلقائياً حسب [size].
class AsjLogoPainter extends CustomPainter {
  const AsjLogoPainter();

  static const Color archColor = Color(0xFF0A2540);
  static const Color pulseColor = Color(0xFF00D2FF);

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / 100;

    final archPaint = Paint()
      ..color = archColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 10 * scale
      ..strokeCap = StrokeCap.round;

    final archPath = Path()
      ..moveTo(20 * scale, 75 * scale)
      ..arcToPoint(
        Offset(80 * scale, 75 * scale),
        radius: Radius.circular(40 * scale),
        largeArc: true,
        clockwise: true,
      );
    canvas.drawPath(archPath, archPaint);

    final pulsePaint = Paint()
      ..color = pulseColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6 * scale
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final pulsePath = Path()
      ..moveTo(5 * scale, 55 * scale)
      ..lineTo(30 * scale, 55 * scale)
      ..lineTo(40 * scale, 25 * scale)
      ..lineTo(60 * scale, 85 * scale)
      ..lineTo(70 * scale, 55 * scale)
      ..lineTo(95 * scale, 55 * scale);
    canvas.drawPath(pulsePath, pulsePaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// اختصار جاهز للاستخدام: `AsjLogo(size: 90)`
class AsjLogo extends StatelessWidget {
  const AsjLogo({super.key, this.size = 70});

  final double size;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(size, size),
      painter: const AsjLogoPainter(),
    );
  }
}
