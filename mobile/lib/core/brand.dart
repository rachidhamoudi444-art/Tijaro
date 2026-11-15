import 'package:flutter/material.dart' hide Text;

import 'i18n.dart';
import 'theme.dart';

/// شعار Tijaro: الأيقونة + الاسم بالحرفين.
class TijaroLogo extends StatelessWidget {
  final double size;
  const TijaroLogo({super.key, this.size = 84});

  @override
  Widget build(BuildContext context) {
    return Column(mainAxisSize: MainAxisSize.min, children: [
      ClipRRect(
        borderRadius: BorderRadius.circular(size * 0.22),
        child: Image.asset('assets/icon_full.png', width: size, height: size),
      ),
      const SizedBox(height: 10),
      const Text('Tijaro',
          style: TextStyle(fontSize: 34, fontWeight: FontWeight.w800, color: Brand.green, height: 1.1)),
      const Text('تيجارو', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Brand.fresh)),
    ]);
  }
}
