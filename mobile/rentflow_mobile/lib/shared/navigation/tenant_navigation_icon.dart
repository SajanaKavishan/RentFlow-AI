import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'role_navigation.dart';

/// Compact line icons for the Tenant bar; labels belong to NavigationDestination.
class TenantNavigationIcon extends StatelessWidget {
  const TenantNavigationIcon({
    super.key,
    required this.destination,
    this.selected = false,
  });

  final RoleDestinationId destination;
  final bool selected;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: SizedBox.square(
      dimension: 22,
      child: CustomPaint(painter: _TenantIconPainter(destination, selected)),
    ),
  );
}

class _TenantIconPainter extends CustomPainter {
  const _TenantIconPainter(this.destination, this.selected);

  final RoleDestinationId destination;
  final bool selected;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 24, size.height / 24);
    final paint = Paint()
      ..color = selected ? AppPalette.darkOlive : const Color(0xFF8A9DBB)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.65
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    switch (destination) {
      case RoleDestinationId.home:
        final path = Path()
          ..moveTo(4.5, 10)
          ..lineTo(12, 3.8)
          ..lineTo(19.5, 10)
          ..lineTo(19.5, 19.3)
          ..quadraticBezierTo(19.5, 20.5, 18.3, 20.5)
          ..lineTo(5.7, 20.5)
          ..quadraticBezierTo(4.5, 20.5, 4.5, 19.3)
          ..close();
        if (selected) paint.style = PaintingStyle.fill;
        canvas.drawPath(path, paint);
      case RoleDestinationId.properties:
        canvas.drawCircle(const Offset(10.5, 10.5), 6.5, paint);
        canvas.drawLine(
          const Offset(15.2, 15.2),
          const Offset(20.5, 20.5),
          paint,
        );
      case RoleDestinationId.applications:
        canvas.drawPath(
          Path()
            ..moveTo(13.5, 3)
            ..lineTo(6.5, 3)
            ..quadraticBezierTo(5, 3, 5, 4.5)
            ..lineTo(5, 19.5)
            ..quadraticBezierTo(5, 21, 6.5, 21)
            ..lineTo(17.5, 21)
            ..quadraticBezierTo(19, 21, 19, 19.5)
            ..lineTo(19, 8.5)
            ..close()
            ..moveTo(13.5, 3)
            ..lineTo(13.5, 8.5)
            ..lineTo(19, 8.5)
            ..moveTo(8.5, 9)
            ..lineTo(10, 9)
            ..moveTo(8.5, 12.5)
            ..lineTo(15.5, 12.5)
            ..moveTo(8.5, 16)
            ..lineTo(15.5, 16),
          paint,
        );
      case RoleDestinationId.maintenance:
        canvas.drawPath(
          Path()
            ..moveTo(14.3, 3.2)
            ..cubicTo(10.8, 2.5, 8.2, 5.8, 9.3, 9.3)
            ..lineTo(3.5, 15.1)
            ..cubicTo(1.4, 17.3, 4.7, 20.6, 6.9, 18.5)
            ..lineTo(12.7, 12.7)
            ..cubicTo(16.2, 13.8, 19.5, 11.2, 18.8, 7.7)
            ..lineTo(15.5, 10)
            ..lineTo(12.5, 7)
            ..close(),
          paint,
        );
      case RoleDestinationId.profile:
        canvas.drawCircle(const Offset(12, 7), 3.2, paint);
        canvas.drawPath(
          Path()
            ..moveTo(5, 20)
            ..lineTo(5, 18)
            ..cubicTo(5, 12, 19, 12, 19, 18)
            ..lineTo(19, 20),
          paint,
        );
      default:
        break;
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _TenantIconPainter oldDelegate) =>
      oldDelegate.destination != destination ||
      oldDelegate.selected != selected;
}
