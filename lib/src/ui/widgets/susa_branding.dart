import 'package:flutter/material.dart';

class SusaGeoBranding extends StatelessWidget {
  final double monogramSize;
  final double titleSize;
  final double subtitleSize;
  final bool light;

  const SusaGeoBranding({
    super.key,
    this.monogramSize = 110,
    this.titleSize = 40,
    this.subtitleSize = 14,
    this.light = false,
  });

  @override
  Widget build(BuildContext context) {
    final titleColor = light ? Colors.white : const Color(0xFF203C7A);
    final subtitleColor =
        light ? Colors.white70 : Colors.black.withValues(alpha: 0.6);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: monogramSize,
          height: monogramSize,
          child: Stack(
            children: [
              _cornerBorder(Alignment.topLeft, const Color(0xFFEE7C43)),
              _cornerBorder(Alignment.topRight, const Color(0xFF8BC34A)),
              _cornerBorder(Alignment.bottomLeft, const Color(0xFF4DB6AC)),
              _cornerBorder(Alignment.bottomRight, const Color(0xFF4FC3F7)),
              Center(
                child: RichText(
                  text: TextSpan(
                    children: [
                      TextSpan(
                        text: 'S',
                        style: TextStyle(
                          fontSize: monogramSize * 0.34,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF4155B3),
                        ),
                      ),
                      TextSpan(
                        text: 'G',
                        style: TextStyle(
                          fontSize: monogramSize * 0.34,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFFEE7C43),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            "SusaGeo",
            maxLines: 1,
            softWrap: false,
            style: TextStyle(
              fontSize: titleSize,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.8,
              color: titleColor,
            ),
          ),
        ),
        Text(
          "by Susalabs",
          style: TextStyle(
            fontSize: subtitleSize,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.4,
            color: subtitleColor,
          ),
        ),
      ],
    );
  }

  Widget _cornerBorder(Alignment alignment, Color color) {
    return Align(
      alignment: alignment,
      child: Container(
        width: monogramSize * 0.34,
        height: monogramSize * 0.34,
        decoration: BoxDecoration(
          border: Border(
            top: alignment.y < 0 ? BorderSide(color: color, width: 4) : BorderSide.none,
            bottom:
                alignment.y > 0 ? BorderSide(color: color, width: 4) : BorderSide.none,
            left:
                alignment.x < 0 ? BorderSide(color: color, width: 4) : BorderSide.none,
            right:
                alignment.x > 0 ? BorderSide(color: color, width: 4) : BorderSide.none,
          ),
        ),
      ),
    );
  }
}
