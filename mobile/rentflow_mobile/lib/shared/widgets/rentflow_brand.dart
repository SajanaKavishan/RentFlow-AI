import 'package:flutter/material.dart';

class RentFlowBrand extends StatelessWidget {
  const RentFlowBrand({
    super.key,
    this.markSize = 44,
    this.textSize = 18,
    this.textColor = Colors.white,
  });

  final double markSize;
  final double textSize;
  final Color textColor;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      ClipRRect(
        borderRadius: BorderRadius.circular(markSize * .29),
        child: Image.asset(
          'assets/brand/auth-mark.png',
          width: markSize,
          height: markSize,
          fit: BoxFit.cover,
          excludeFromSemantics: true,
        ),
      ),
      SizedBox(width: markSize * .18),
      Flexible(
        child: Text.rich(
          TextSpan(
            children: [
              const TextSpan(text: 'RentFlow '),
              TextSpan(
                text: 'AI',
                style: const TextStyle(color: Color(0xFFD8B65F)),
              ),
            ],
          ),
          style: TextStyle(
            color: textColor,
            fontSize: textSize,
            fontWeight: FontWeight.w800,
            letterSpacing: -.7,
          ),
        ),
      ),
    ],
  );
}
