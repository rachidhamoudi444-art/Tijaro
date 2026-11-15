import 'package:flutter/material.dart' hide Text;

import 'i18n.dart';

/// شعار الترويسة: أيقونة الحقيبة مع T + الاسم بالحرفين (Tijaro / تيجارو).
class TijaroHeaderLogo extends StatelessWidget {
  final double height;
  const TijaroHeaderLogo({super.key, this.height = 46});

  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Image.asset('assets/icon_full.png', height: height, width: height),
      const SizedBox(width: 8),
      Image.asset('assets/wordmark.png', height: height * 0.9),
    ]);
  }
}

/// شعار كبير لشاشة الدخول.
class TijaroLogo extends StatelessWidget {
  final double size;
  const TijaroLogo({super.key, this.size = 96});

  @override
  Widget build(BuildContext context) {
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Image.asset('assets/icon_full.png', width: size, height: size),
      const SizedBox(height: 6),
      Image.asset('assets/wordmark.png', height: size * 0.85),
    ]);
  }
}
