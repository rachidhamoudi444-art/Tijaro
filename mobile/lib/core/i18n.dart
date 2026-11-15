import 'package:flutter/material.dart' as m;
import 'package:shared_preferences/shared_preferences.dart';

import 'fr.dart';

/// اللغة الحالية: 'ar' أو 'fr'. تُحفظ على الجهاز.
final m.ValueNotifier<String> appLang = m.ValueNotifier<String>('ar');


Future<void> loadLang() async {
  try {
    final p = await SharedPreferences.getInstance();
    final l = p.getString('lang');
    if (l == 'ar' || l == 'fr') appLang.value = l!;
  } catch (_) {}
}

Future<void> setLang(String l) async {
  appLang.value = l;
  try {
    final p = await SharedPreferences.getInstance();
    await p.setString('lang', l);
  } catch (_) {}
}

final _arabic = RegExp(r'[؀-ۿ]');
final List<MapEntry<RegExp, String>> _fragRules = () {
  final keys = frFrag.keys.toList()..sort((a, b) => b.length.compareTo(a.length));
  return [
    for (final k in keys)
      MapEntry(
        // لا نستبدل داخل كلمة أطول (حتى لا نُفسد أسماء المنتجات والمتاجر)
        RegExp('(?<![\\u0600-\\u06FF])${RegExp.escape(k)}(?![\\u0600-\\u06FF])'),
        frFrag[k]!,
      ),
  ];
}();

/// يترجم نصاً عربياً إلى الفرنسية عند اختيار الفرنسية. النص غير العربي يبقى كما هو.
String tr(String s) {
  if (appLang.value != 'fr' || !_arabic.hasMatch(s)) return s;
  final exact = frFull[s];
  if (exact != null) return exact;
  var out = s;
  for (final r in _fragRules) {
    out = out.replaceAll(r.key, r.value);
  }
  return out;
}

/// بديل لـ Text يترجم تلقائياً. (يُستورد مع إخفاء Text الأصلي)
class Text extends m.StatelessWidget {
  final String data;
  final m.TextStyle? style;
  final m.TextAlign? textAlign;
  final int? maxLines;
  final m.TextOverflow? overflow;
  final m.TextDirection? textDirection;
  final bool? softWrap;

  const Text(
    this.data, {
    super.key,
    this.style,
    this.textAlign,
    this.maxLines,
    this.overflow,
    this.textDirection,
    this.softWrap,
  });

  @override
  m.Widget build(m.BuildContext context) => m.Text(
        tr(data),
        style: style,
        textAlign: textAlign,
        maxLines: maxLines,
        overflow: overflow,
        textDirection: textDirection,
        softWrap: softWrap,
      );
}

/// زر تبديل اللغة (يعرض اسم اللغة الأخرى).
class LangToggle extends m.StatelessWidget {
  const LangToggle({super.key});

  @override
  m.Widget build(m.BuildContext context) {
    final isAr = appLang.value == 'ar';
    return m.TextButton.icon(
      onPressed: () => setLang(isAr ? 'fr' : 'ar'),
      icon: const m.Icon(m.Icons.language, size: 18),
      label: m.Text(isAr ? 'Français' : 'العربية'),
    );
  }
}
