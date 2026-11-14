import 'package:supabase_flutter/supabase_flutter.dart';

SupabaseClient get db => Supabase.instance.client;

/// نحوّل رقم الهاتف إلى إيميل داخلي، فيسجّل المستخدم برقمه وكلمة مرور فقط (بلا SMS).
String phoneToEmail(String phone) {
  final digits = phone.replaceAll(RegExp(r'[^0-9]'), '');
  return '$digits@phone.local';
}

/// يحوّل أخطاء الخادم إلى رسالة مفهومة للمستخدم.
String friendlyError(Object e) {
  if (e is PostgrestException) return e.message;
  if (e is AuthException) {
    if (e.message.toLowerCase().contains('invalid login')) {
      return 'رقم الهاتف أو كلمة المرور غير صحيحة';
    }
    return e.message;
  }
  return 'حدث خطأ: $e';
}

num asNum(dynamic v) => v is num ? v : num.tryParse('$v') ?? 0;
