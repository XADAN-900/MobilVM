import 'package:flutter/material.dart';

/// Strata logosu: 16 / 32 / 64-bit'i temsil eden üç katman (Android ikonuyla aynı çizim).
class StrataLogo extends StatelessWidget {
  const StrataLogo({super.key, this.size = 40});
  final double size;

  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: Size.square(size), painter: const _LogoPainter());
}

class _LogoPainter extends CustomPainter {
  const _LogoPainter();

  static Path _poly(List<double> p) {
    final path = Path()..moveTo(p[0], p[1]);
    for (var i = 2; i < p.length; i += 2) {
      path.lineTo(p[i], p[i + 1]);
    }
    return path..close();
  }

  @override
  void paint(Canvas canvas, Size size) {
    // Orijinal tasarım 108'lik ızgarada x,y: 30..78 aralığında
    canvas.save();
    canvas.scale(size.width / 52);
    canvas.translate(-28, -28);
    void layer(List<double> pts, Color a, Color b, double y1, double y2) {
      final paint = Paint()
        ..shader = LinearGradient(colors: [a, b]).createShader(Rect.fromPoints(Offset(30, y1), Offset(78, y2)))
        ..isAntiAlias = true;
      canvas.drawPath(_poly(pts), paint);
    }

    layer([30, 59, 54, 71, 78, 59, 78, 66, 54, 78, 30, 66], const Color(0xFF67E8F9), const Color(0xFF0891B2), 59, 78);
    layer([30, 47, 54, 59, 78, 47, 78, 54, 54, 66, 30, 54], const Color(0xFFA5B4FC), const Color(0xFF4F46E5), 47, 66);
    layer([54, 30, 78, 42, 54, 54, 30, 42], const Color(0xFFDDD6FE), const Color(0xFF7C3AED), 30, 54);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Logo + "Strata" yazısı.
class StrataWordmark extends StatelessWidget {
  const StrataWordmark({super.key, this.size = 28});
  final double size;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        StrataLogo(size: size * 1.25),
        SizedBox(width: size * 0.4),
        ShaderMask(
          shaderCallback: (r) => const LinearGradient(
            colors: [Color(0xFFDDD6FE), Color(0xFFA5B4FC), Color(0xFF67E8F9)],
          ).createShader(r),
          child: Text(
            'Strata',
            style: TextStyle(
              fontSize: size,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
              color: Colors.white,
            ),
          ),
        ),
        SizedBox(width: size * 0.25),
        Container(
          padding: EdgeInsets.symmetric(horizontal: size * 0.22, vertical: size * 0.05),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(size * 0.2),
            border: Border.all(color: const Color(0xFF7C5CFF).withOpacity(0.6)),
          ),
          child: Text(
            'VM',
            style: TextStyle(
              fontSize: size * 0.42,
              fontWeight: FontWeight.w700,
              color: const Color(0xFFA5B4FC),
              letterSpacing: 1,
            ),
          ),
        ),
      ],
    );
  }
}
