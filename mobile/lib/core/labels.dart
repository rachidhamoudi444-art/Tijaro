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
  final Color color; // لون النشاط يظهر في الفئات وبطاقات المتاجر
  const CategoryGroup(this.key, this.label, this.icon, this.categories, this.color);
}

const categoryGroups = [
  CategoryGroup('restaurant', 'مطاعم', Icons.restaurant, ['restaurant'], Color(0xFFF7931E)),
  CategoryGroup('grocery', 'مواد غذائية', Icons.shopping_basket_outlined, ['grocery'], Color(0xFF39B982)),
  CategoryGroup('vegetables', 'خضر وفواكه', Icons.eco_outlined, ['vegetables'], Color(0xFF43A047)),
  CategoryGroup('butcher', 'قصاب', Icons.set_meal_outlined, ['butcher'], Color(0xFFD64545)),
  CategoryGroup('women_clothing', 'ملابس نسائية', Icons.checkroom, ['women_clothing'], Color(0xFFE0509B)),
  CategoryGroup('men_clothing', 'ملابس رجالية', Icons.dry_cleaning_outlined, ['men_clothing'], Color(0xFF3B6FD4)),
  CategoryGroup('kids_clothing', 'ملابس أطفال', Icons.child_care, ['kids_clothing'], Color(0xFF8E6BDB)),
  CategoryGroup('kids_supplies', 'مستلزمات الأطفال', Icons.toys_outlined, ['kids_supplies'], Color(0xFFF2B705)),
  CategoryGroup('electronics', 'إلكترونيات', Icons.tv_outlined, ['electronics'], Color(0xFF3F51B5)),
  CategoryGroup('phones', 'هواتف وإكسسوارات', Icons.smartphone, ['phones'], Color(0xFF00A3B4)),
  CategoryGroup('cosmetics', 'كوسمتيك', Icons.face_retouching_natural, ['cosmetics'], Color(0xFFD6568F)),
  CategoryGroup('parapharmacy', 'شبه صيدلية', Icons.health_and_safety_outlined, ['parapharmacy'], Color(0xFF1FA39A)),
  CategoryGroup('bakery', 'مخبزة وحلويات', Icons.bakery_dining_outlined, ['bakery'], Color(0xFFC57A2E)),
  CategoryGroup('fish', 'أسماك', Icons.phishing_outlined, ['fish'], Color(0xFF1E9BD7)),
  CategoryGroup('stationery', 'مكتبة', Icons.menu_book_outlined, ['stationery'], Color(0xFF7E57C2)),
  CategoryGroup('hardware', 'خردوات', Icons.hardware_outlined, ['hardware'], Color(0xFF607D8B)),
  CategoryGroup('household', 'أدوات منزلية', Icons.chair_outlined, ['household'], Color(0xFFA1735C)),
  CategoryGroup('gifts', 'هدايا وزهور', Icons.card_giftcard, ['gifts'], Color(0xFFEC407A)),
  CategoryGroup('auto_parts', 'قطع غيار السيارات', Icons.directions_car_outlined, ['auto_parts'], Color(0xFF455A64)),
  CategoryGroup('pets', 'حيوانات أليفة', Icons.pets_outlined, ['pets'], Color(0xFF8D6E63)),
  CategoryGroup('other', 'أخرى', Icons.more_horiz, ['other'], Color(0xFF78909C)),
];

const categoryLabels = <String, String>{};

/// مجموعة التصنيف الذي ينتمي له المتجر.
CategoryGroup? groupOfCategory(dynamic category) {
  for (final g in categoryGroups) {
    if (g.categories.contains(category)) return g;
  }
  return null;
}

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
