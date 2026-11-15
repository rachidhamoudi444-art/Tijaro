import 'package:flutter/material.dart' hide Text;
import 'core/i18n.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'auth_gate.dart';
import 'core/theme.dart';

// تُمرَّر عند التشغيل: --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...
const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (supabaseUrl.isEmpty || supabaseAnonKey.isEmpty) {
    runApp(const _MissingConfig());
    return;
  }
  await loadLang();
  await Supabase.initialize(url: supabaseUrl, anonKey: supabaseAnonKey);
  runApp(const DeliveryApp());
}

class DeliveryApp extends StatelessWidget {
  const DeliveryApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: appLang,
      builder: (context, lang, _) => MaterialApp(
        title: 'Tijaro',
        debugShowCheckedModeBanner: false,
        locale: Locale(lang),
        supportedLocales: const [Locale('ar'), Locale('fr')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        // واجهة بيضاء نظيفة، والأخضر للعناصر المهمة
        theme: buildTheme(),
        themeMode: ThemeMode.light,
        // المفتاح يعيد بناء كل الشاشات عند تبديل اللغة
        home: KeyedSubtree(key: ValueKey(lang), child: const AuthGate()),
      ),
    );
  }
}

class _MissingConfig extends StatelessWidget {
  const _MissingConfig();

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'إعدادات Supabase ناقصة.\nشغّل التطبيق مع:\n--dart-define=SUPABASE_URL=...\n--dart-define=SUPABASE_ANON_KEY=...',
              textAlign: TextAlign.center,
              textDirection: TextDirection.ltr,
            ),
          ),
        ),
      ),
    );
  }
}
