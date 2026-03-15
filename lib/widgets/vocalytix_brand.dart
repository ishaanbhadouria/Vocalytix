import 'package:flutter/material.dart';

class VocalytixBrandButton extends StatelessWidget {
  const VocalytixBrandButton({
    super.key,
    this.onTap,
    this.compact = false,
  });

  final VoidCallback? onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final brand = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        VocalytixLogoMark(size: compact ? 34 : 42),
        SizedBox(width: compact ? 8 : 10),
        Text(
          "Vocalytix",
          style: TextStyle(
            color: const Color(0xFFE9EEFF),
            fontSize: compact ? 19 : 24,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.9,
          ),
        ),
      ],
    );

    if (onTap == null) return brand;

    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        child: brand,
      ),
    );
  }
}

class VocalytixLogoMark extends StatelessWidget {
  const VocalytixLogoMark({
    super.key,
    this.size = 42,
  });

  final double size;

  @override
  Widget build(BuildContext context) {
    final radius = size * 0.28;

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(radius),
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFFFF4154), Color(0xFFFFA63D)],
                ),
              ),
            ),
          ),
          Positioned(
            left: 0,
            bottom: -size * 0.14,
            child: ClipPath(
              clipper: _SpeechTailClipper(),
              child: Container(
                width: size * 0.42,
                height: size * 0.36,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF1B2A6B), Color(0xFF1D56A5)],
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            right: -size * 0.02,
            bottom: -size * 0.02,
            child: ClipPath(
              clipper: _BottomRibbonClipper(),
              child: Container(
                width: size * 0.9,
                height: size * 0.52,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF48B9F2), Color(0xFF2B62B0)],
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            left: size * 0.10,
            right: size * 0.18,
            top: size * 0.14,
            bottom: size * 0.16,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                _bar(size * 0.12),
                SizedBox(width: size * 0.04),
                _bar(size * 0.26),
                SizedBox(width: size * 0.04),
                _bar(size * 0.40),
                SizedBox(width: size * 0.04),
                _bar(size * 0.56),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _bar(double height) {
    return Align(
      alignment: Alignment.bottomCenter,
      child: Container(
        width: size * 0.10,
        height: height,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(size * 0.04),
        ),
      ),
    );
  }
}

class _SpeechTailClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    return Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(0, size.height)
      ..close();
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}

class _BottomRibbonClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    return Path()
      ..moveTo(0, size.height * 0.28)
      ..quadraticBezierTo(
        size.width * 0.45,
        -size.height * 0.04,
        size.width,
        0,
      )
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}
