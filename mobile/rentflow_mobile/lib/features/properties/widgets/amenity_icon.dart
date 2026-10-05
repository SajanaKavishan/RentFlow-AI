import 'package:flutter/material.dart';

// Keep these names and 24px outline paths aligned with the web amenity catalog
// and src/shared/ui/Icons.jsx. Painting the same vectors avoids font differences.
String amenityIconName(String name, {String? canonicalKey}) {
  const icons = {
    'wifi': 'wifi',
    'parking': 'car',
    'air-conditioning': 'wind',
    'washer-dryer': 'washer',
    'gym': 'dumbbell',
    'swimming-pool': 'waves',
    'balcony': 'balcony',
    'elevator': 'elevator',
    'furnished': 'sofa',
    'garden': 'leaf',
    'security': 'shield',
    'rooftop': 'rooftop',
  };
  final canonical = icons[canonicalKey];
  if (canonical != null) return canonical;
  final normalized = name.toLowerCase().replaceAll(RegExp('[^a-z0-9]'), '');
  const aliases = {
    'wifi': 'wifi',
    'wirelessinternet': 'wifi',
    'internet': 'wifi',
    'parking': 'car',
    'carparking': 'car',
    'airconditioning': 'wind',
    'aircon': 'wind',
    'ac': 'wind',
    'washerdryer': 'washer',
    'washeranddryer': 'washer',
    'laundry': 'washer',
    'gym': 'dumbbell',
    'swimmingpool': 'waves',
    'pool': 'waves',
    'balcony': 'balcony',
    'elevator': 'elevator',
    'lift': 'elevator',
    'furnished': 'sofa',
    'fullyfurnished': 'sofa',
    'garden': 'leaf',
    'security': 'shield',
    'rooftop': 'rooftop',
  };
  return aliases[normalized] ?? 'amenity';
}

class AmenityIcon extends StatelessWidget {
  const AmenityIcon({
    super.key,
    required this.name,
    this.canonicalKey,
    this.size = 19,
    this.color,
  });

  final String name;
  final String? canonicalKey;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: SizedBox.square(
      dimension: size,
      child: CustomPaint(
        painter: _AmenityPainter(
          amenityIconName(name, canonicalKey: canonicalKey),
          color ?? IconTheme.of(context).color ?? Colors.black,
        ),
      ),
    ),
  );
}

class _AmenityPainter extends CustomPainter {
  const _AmenityPainter(this.icon, this.color);
  final String icon;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 24, size.height / 24);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.7
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    for (final path in _paths(icon)) {
      canvas.drawPath(path, paint);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_AmenityPainter oldDelegate) =>
      icon != oldDelegate.icon || color != oldDelegate.color;
}

Path _rect(double x, double y, double width, double height, double radius) =>
    Path()..addRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(x, y, width, height),
        Radius.circular(radius),
      ),
    );

List<Path> _paths(String icon) => switch (icon) {
  'wifi' => [
    Path()
      ..moveTo(5, 12.5)
      ..arcToPoint(const Offset(19, 12.5), radius: const Radius.circular(10))
      ..moveTo(8, 16)
      ..arcToPoint(const Offset(16, 16), radius: const Radius.circular(6)),
    Path()
      ..moveTo(12, 20)
      ..lineTo(12.01, 20),
  ],
  'car' => [
    Path()
      ..moveTo(5, 11)
      ..lineTo(7, 6)
      ..lineTo(17, 6)
      ..lineTo(19, 11),
    _rect(3, 10, 18, 8, 2),
    Path()
      ..moveTo(6, 18)
      ..lineTo(6, 20)
      ..moveTo(18, 18)
      ..lineTo(18, 20)
      ..moveTo(7, 14)
      ..lineTo(7.01, 14)
      ..moveTo(17, 14)
      ..lineTo(17.01, 14),
  ],
  'wind' => [
    Path()
      ..moveTo(4, 8)
      ..lineTo(14, 8)
      ..arcToPoint(
        const Offset(12, 6),
        radius: const Radius.circular(2),
        largeArc: true,
        clockwise: false,
      )
      ..moveTo(4, 12)
      ..lineTo(19, 12)
      ..arcToPoint(
        const Offset(17, 14),
        radius: const Radius.circular(2),
        largeArc: true,
      )
      ..moveTo(4, 16)
      ..lineTo(11, 16),
  ],
  'washer' => [
    _rect(5, 3, 14, 18, 2),
    Path()..addOval(Rect.fromCircle(center: const Offset(12, 13), radius: 4)),
    Path()
      ..moveTo(8, 6)
      ..lineTo(8.01, 6)
      ..moveTo(11, 6)
      ..lineTo(15, 6),
  ],
  'dumbbell' => [
    Path()
      ..moveTo(6, 8)
      ..lineTo(6, 16)
      ..moveTo(18, 8)
      ..lineTo(18, 16)
      ..moveTo(3, 10)
      ..lineTo(3, 14)
      ..moveTo(21, 10)
      ..lineTo(21, 14)
      ..moveTo(6, 12)
      ..lineTo(18, 12),
  ],
  'waves' => [
    for (final y in [7.0, 13.0, 19.0])
      Path()
        ..moveTo(3, y)
        ..cubicTo(5, y, 5, y + 2, 7, y + 2)
        ..cubicTo(9, y + 2, 9, y, 11, y)
        ..cubicTo(13, y, 13, y + 2, 15, y + 2)
        ..cubicTo(17, y + 2, 17, y, 19, y)
        ..cubicTo(21, y, 21, y + 2, 23, y + 2),
  ],
  'balcony' => [
    Path()
      ..moveTo(7, 12)
      ..lineTo(7, 3)
      ..lineTo(17, 3)
      ..lineTo(17, 12)
      ..moveTo(12, 3)
      ..lineTo(12, 12)
      ..moveTo(3, 12)
      ..lineTo(21, 12)
      ..moveTo(4, 12)
      ..lineTo(4, 21)
      ..moveTo(8, 12)
      ..lineTo(8, 21)
      ..moveTo(12, 12)
      ..lineTo(12, 21)
      ..moveTo(16, 12)
      ..lineTo(16, 21)
      ..moveTo(20, 12)
      ..lineTo(20, 21)
      ..moveTo(3, 21)
      ..lineTo(21, 21),
  ],
  'elevator' => [
    _rect(5, 3, 14, 18, 1),
    Path()
      ..moveTo(12, 7)
      ..lineTo(12, 17)
      ..moveTo(9, 10)
      ..lineTo(12, 7)
      ..lineTo(15, 10)
      ..moveTo(15, 14)
      ..lineTo(12, 17)
      ..lineTo(9, 14),
  ],
  'sofa' => [
    Path()
      ..moveTo(5, 12)
      ..lineTo(5, 8)
      ..arcToPoint(const Offset(8, 5), radius: const Radius.circular(3))
      ..lineTo(16, 5)
      ..arcToPoint(const Offset(19, 8), radius: const Radius.circular(3))
      ..lineTo(19, 12),
    Path()
      ..moveTo(4, 11)
      ..arcToPoint(
        const Offset(2, 13),
        radius: const Radius.circular(2),
        clockwise: false,
      )
      ..lineTo(2, 18)
      ..lineTo(22, 18)
      ..lineTo(22, 13)
      ..arcToPoint(
        const Offset(20, 11),
        radius: const Radius.circular(2),
        clockwise: false,
      )
      ..moveTo(5, 18)
      ..lineTo(5, 20)
      ..moveTo(19, 18)
      ..lineTo(19, 20),
  ],
  'leaf' => [
    Path()
      ..moveTo(20, 4)
      ..cubicTo(10, 4, 5, 9, 5, 15)
      ..cubicTo(5, 18, 7, 20, 10, 20)
      ..cubicTo(16, 20, 20, 14, 20, 4)
      ..close(),
    Path()
      ..moveTo(4, 21)
      ..cubicTo(7, 15, 11, 12, 16, 9),
  ],
  'shield' => [
    Path()
      ..moveTo(12, 3)
      ..lineTo(5, 6)
      ..lineTo(5, 11)
      ..cubicTo(5, 15.6, 7.8, 19, 12, 21)
      ..cubicTo(16.2, 19, 19, 15.6, 19, 11)
      ..lineTo(19, 6)
      ..close(),
    Path()
      ..moveTo(9, 12)
      ..lineTo(11, 14)
      ..lineTo(15, 10),
  ],
  'rooftop' => [
    Path()
      ..moveTo(3, 11)
      ..lineTo(12, 4)
      ..lineTo(21, 11)
      ..moveTo(6, 10)
      ..lineTo(6, 20)
      ..lineTo(18, 20)
      ..lineTo(18, 10),
    Path()
      ..moveTo(12, 11)
      ..lineTo(12.7, 13.1)
      ..lineTo(15, 13.2)
      ..lineTo(13.2, 14.6)
      ..lineTo(13.8, 16.8)
      ..lineTo(12, 15.5)
      ..lineTo(10.2, 16.8)
      ..lineTo(10.8, 14.6)
      ..lineTo(9, 13.2)
      ..lineTo(11.3, 13.1)
      ..close(),
  ],
  _ => [
    _rect(4, 4, 6, 6, 1),
    _rect(14, 4, 6, 6, 1),
    _rect(4, 14, 6, 6, 1),
    _rect(14, 14, 6, 6, 1),
  ],
};
