# تشغيل المنصة (النسخة 0.2: تطبيق الليفرور + تطبيق الزبون)

## 1) إنشاء مشروع Supabase (مجاني)
1. ادخل إلى supabase.com وأنشئ حساباً ثم **New project** (اختر أقرب منطقة: Frankfurt أو Paris).
2. **مهم:** من `Authentication → Providers → Email` أوقف **Confirm email**، لأن التطبيق يسجّل بالهاتف وكلمة مرور عبر إيميل داخلي.
3. من `SQL Editor` الصق محتوى `supabase/schema.sql` كاملاً ثم اضغط Run.
4. من `Project Settings → API` انسخ **Project URL** و **anon public key** (لا تستعمل أبداً service_role داخل التطبيق).

## 2) تثبيت Flutter على حاسوبك
- تثبيت Flutter من docs.flutter.dev/get-started/install ثم تشغيل `flutter doctor` حتى تصير كل العلامات خضراء (Android Studio مطلوب للأندرويد).
- ضع المجلد `mobile/` في مكان على جهازك، ثم داخله شغّل **مرة واحدة فقط**:
  ```
  flutter create . --org dz.tipaza.delivery --project-name delivery_app
  flutter pub get
  ```
  (لا يمسح ملفات `lib/` ولا `pubspec.yaml` الموجودة.)

## 3) أذونات أندرويد (الموقع والإنترنت) - مرة واحدة
افتح الملف `android/app/src/main/AndroidManifest.xml` (يُنشأ بعد `flutter create`) وضع هذه الأسطر داخل وسم `<manifest>` وقبل وسم `<application>`:
```xml
<uses-permission android:name="android.permission.INTERNET"/>
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION"/>
<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION"/>
```

## 4) تشغيل التطبيق على هاتفك
وصّل هاتف أندرويد (تفعيل USB debugging) ثم:
```
flutter run --dart-define=SUPABASE_URL=https://xxxx.supabase.co --dart-define=SUPABASE_ANON_KEY=eyJ...
```

## 5) إنشاء الحسابات الأولى
1. من التطبيق: **حساب جديد (زبون)** وسجّل ثلاثة حسابات (أدمن، ليفرور، صاحب متجر) بأرقام هواتف مختلفة.
2. من `SQL Editor` في Supabase شغّل ملف `supabase/seed.sql` بعد تعديل الأرقام في أعلاه، فيحوّل الحسابات إلى أدوار ويضيف متجراً ومنتجات تجريبية ويشحن محفظة الليفرور.
3. افتح التطبيق بحساب الليفرور: فعّل "متاح" وسترى الطلبات التي ينشئها الزبون.

## ما يعمل في هذه النسخة وما لا يعمل
| يعمل (حسب كتابتي، لم يُجرَّب على هاتف بعد) | لم يُبنَ بعد |
| --- | --- |
| دخول وتسجيل بالهاتف وكلمة مرور | لوحة المتجر والأدمن (ويب) |
| **تطبيق الزبون** بتصميم Tijaro: الرئيسية، البحث، الفئات، متاجر قريبة، صفحة المتجر والسلة، تأكيد الطلب مع الخريطة وسعر التوصيل، طلباتي وتتبعها وإلغاؤها، الطلب الحر (نقل / شراء وتوصيل) | الإشعارات (FCM) |
| **تطبيق الليفرور:** متاح، المحفظة، النقد المفتوح، قبول الطلبات، تغيير الحالات، التسليم | GPS الليفرور وخريطته |
| كل المنطق المالي والصلاحيات في قاعدة البيانات (مُختبَر) | زر الاتصال وتسجيل المحاولات وإبلاغ "لم يُسلَّم" في واجهة الليفرور |
| | صور المتاجر (حقل `image_url` جاهز في القاعدة) |

## إذا ظهر خطأ
انسخ الخطأ كاملاً من الطرفية (Terminal) وأرسله لي كما هو، مع نتيجة `flutter --version`.
