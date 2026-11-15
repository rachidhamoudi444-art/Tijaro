import 'package:flutter/material.dart' hide Text;

/// اسم التطبيق (مؤقت حسب التصور المعروض، يُغيَّر من هنا فقط).
const appName = 'Tijaro';
const appCity = 'تيبازة';

/// كل تصنيف متجر: (المفتاح، الاسم، الأيقونة). المفتاح يطابق قيد الجدول stores.category.
class CategoryGroup {
  final String key;
  final String label;
  final IconData icon;
  final List<String> categories;
  const CategoryGroup(this.key, this.label, this.icon, this.categories);
}

const categoryGroups = [
  CategoryGroup('restaurant', 'مطاعم', Icons.restaurant, ['restaurant']),
  CategoryGroup('grocery', 'مواد غذائية', Icons.shopping_basket_outlined, ['grocery']),
  CategoryGroup('vegetables', 'خضر وفواكه', Icons.eco_outlined, ['vegetables']),
  CategoryGroup('butcher', 'قصاب', Icons.set_meal_outlined, ['butcher']),
  CategoryGroup('women_clothing', 'ملابس نسائية', Icons.checkroom, ['women_clothing']),
  CategoryGroup('men_clothing', 'ملابس رجالية', Icons.dry_cleaning_outlined, ['men_clothing']),
  CategoryGroup('kids_clothing', 'ملابس أطفال', Icons.child_care, ['kids_clothing']),
  CategoryGroup('kids_supplies', 'مستلزمات الأطفال', Icons.toys_outlined, ['kids_supplies']),
  CategoryGroup('electronics', 'إلكترونيات', Icons.tv_outlined, ['electronics']),
  CategoryGroup('phones', 'هواتف وإكسسوارات', Icons.smartphone, ['phones']),
  CategoryGroup('cosmetics', 'كوسمتيك', Icons.face_retouching_natural, ['cosmetics']),
  CategoryGroup('parapharmacy', 'شبه صيدلية', Icons.health_and_safety_outlined, ['parapharmacy']),
  CategoryGroup('bakery', 'مخبزة وحلويات', Icons.bakery_dining_outlined, ['bakery']),
  CategoryGroup('fish', 'أسماك', Icons.phishing_outlined, ['fish']),
  CategoryGroup('stationery', 'مكتبة', Icons.menu_book_outlined, ['stationery']),
  CategoryGroup('hardware', 'خردوات', Icons.hardware_outlined, ['hardware']),
  CategoryGroup('household', 'أدوات منزلية', Icons.chair_outlined, ['household']),
  CategoryGroup('gifts', 'هدايا وزهور', Icons.card_giftcard, ['gifts']),
  CategoryGroup('auto_parts', 'قطع غيار السيارات', Icons.directions_car_outlined, ['auto_parts']),
  CategoryGroup('pets', 'حيوانات أليفة', Icons.pets_outlined, ['pets']),
  CategoryGroup('other', 'أخرى', Icons.more_horiz, ['other']),
];

const categoryLabels = <String, String>{};

CategoryGroup? groupByKey(String? key) {
  for (final g in categoryGroups) {
    if (g.key == key) return g;
  }
  return null;
}

/// اسم الفئة التي يظهر بها المتجر على بطاقته.
String groupLabelOf(dynamic category) {
  for (final g in categoryGroups) {
    if (g.categories.contains(category)) return g.label;
  }
  return '';
}

const statusLabels = {
  'new': 'بانتظار قبول المتجر',
  'accepted': 'تم قبول الطلب',
  'preparing': 'قيد التحضير',
  'ready': 'جاهز، بانتظار الليفرور',
  'picked_up': 'الليفرور استلم الطلب',
  'on_the_way': 'في الطريق إليك',
  'delivered': 'تم التسليم',
  'not_delivered': 'لم يُسلَّم',
  'dispute': 'قيد المراجعة',
  'rejected': 'رفضه المتجر',
  'cancelled': 'ملغى',
};

String orderTypeLabel(dynamic t, [dynamic freeKind]) {
  switch (t) {
    case 'store':
      return 'طلب من متجر';
    case 'p2p':
      return 'نقل من نقطة إلى نقطة';
    case 'free':
      return freeKind == 'purchase' ? 'شراء وتوصيل' : 'طلب حر';
    default:
      return '$t';
  }
}

String dinar(num v) => '${v.toStringAsFixed(0)} دج';
