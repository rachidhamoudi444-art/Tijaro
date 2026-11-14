import 'package:flutter/material.dart';

/// اسم التطبيق (مؤقت حسب التصور المعروض، يُغيَّر من هنا فقط).
const appName = 'Tijaro';
const appCity = 'تيبازة';

const categoryLabels = {
  'restaurant': 'مطاعم',
  'vegetables': 'خضر وفواكه',
  'butcher': 'قصابات',
  'grocery': 'بقالة',
  'clothing': 'ملابس',
  'electronics': 'إلكترونيات',
  'other': 'أخرى',
};

/// فئات الواجهة (كما في التصميم): كل فئة تجمع تصنيفات المتاجر.
class CategoryGroup {
  final String key;
  final String label;
  final IconData icon;
  final List<String> categories;
  const CategoryGroup(this.key, this.label, this.icon, this.categories);
}

const categoryGroups = [
  CategoryGroup('restaurants', 'مطاعم', Icons.restaurant, ['restaurant']),
  CategoryGroup('food', 'مواد غذائية', Icons.shopping_basket_outlined, ['vegetables', 'butcher', 'grocery']),
  CategoryGroup('clothing', 'ملابس', Icons.checkroom, ['clothing']),
  CategoryGroup('electronics', 'إلكترونيات', Icons.smartphone, ['electronics']),
];

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
  return categoryLabels[category] ?? '';
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
