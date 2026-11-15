/// أرقام الهاتف الجزائرية: موبيليس (06) أو أوريدو (05) أو جازي (07) فقط.

/// يوحّد الصيغة إلى 10 أرقام تبدأ بصفر (يقبل +213 و 00213 و 9 أرقام بلا صفر).
String normalizePhone(String raw) {
  var d = raw.replaceAll(RegExp(r'[^0-9]'), '');
  if (d.startsWith('00213')) d = '0${d.substring(5)}';
  if (d.startsWith('213') && d.length == 12) d = '0${d.substring(3)}';
  if (d.length == 9 && RegExp(r'^[567]').hasMatch(d)) d = '0$d';
  return d;
}

final _mobile = RegExp(r'^0[567][0-9]{8}$');

bool isValidMobile(String normalized) => _mobile.hasMatch(normalized);

String? operatorOf(String normalized) {
  if (!isValidMobile(normalized)) return null;
  switch (normalized[1]) {
    case '5':
      return 'أوريدو';
    case '6':
      return 'موبيليس';
    case '7':
      return 'جازي';
  }
  return null;
}
