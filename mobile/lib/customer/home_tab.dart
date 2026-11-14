import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../core/api.dart';
import '../core/labels.dart';
import '../core/location.dart';
import 'store_card.dart';

/// الرئيسية: الشعار والمدينة، البحث، اللافتة، الفئات، متاجر قريبة، وبطاقة طلب ليفرور.
class HomeTab extends StatefulWidget {
  final void Function(String? groupKey, String query) onOpenStores;
  final VoidCallback onOpenCourier;
  final void Function(Map<String, dynamic> store) onOpenStore;

  const HomeTab({
    super.key,
    required this.onOpenStores,
    required this.onOpenCourier,
    required this.onOpenStore,
  });

  @override
  State<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<HomeTab> {
  final _search = TextEditingController();
  late Future<List<Map<String, dynamic>>> _nearby = _loadNearby();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<List<Map<String, dynamic>>> _loadNearby() async {
    final rows = await db
        .from('stores')
        .select('id,name,category,address,lat,lng,image_url')
        .eq('is_open', true);
    final stores = [for (final r in rows) Map<String, dynamic>.of(r)];
    final loc = await currentLocation();
    if (loc != null) {
      const dist = Distance();
      for (final s in stores) {
        s['_km'] = dist.as(
          LengthUnit.Kilometer,
          loc,
          LatLng(asNum(s['lat']).toDouble(), asNum(s['lng']).toDouble()),
        );
      }
      stores.sort((a, b) => (a['_km'] as num).compareTo(b['_km'] as num));
    }
    return stores.take(6).toList();
  }

  Future<void> _refresh() async {
    setState(() => _nearby = _loadNearby());
    await _nearby;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return SafeArea(
      child: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            // الشعار + المدينة
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(appName,
                    style: text.headlineMedium?.copyWith(color: scheme.primary, fontWeight: FontWeight.bold)),
                Row(children: [
                  Icon(Icons.location_on_outlined, color: scheme.primary, size: 20),
                  const SizedBox(width: 4),
                  Text(appCity),
                ]),
              ],
            ),
            const SizedBox(height: 16),
            // البحث
            TextField(
              controller: _search,
              textInputAction: TextInputAction.search,
              onSubmitted: (q) => widget.onOpenStores(null, q.trim()),
              decoration: InputDecoration(
                hintText: 'ابحث عن متجر أو منتج...',
                prefixIcon: const Icon(Icons.search),
                filled: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(20),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 16),
            // اللافتة
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: scheme.primary,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('كل التجارة في بلاصة وحدة',
                      style: text.titleLarge?.copyWith(color: scheme.onPrimary, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  Text('اكتشف محلات منطقتك واطلب بسهولة', style: text.bodyMedium?.copyWith(color: scheme.onPrimary)),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Text('تصفح حسب الفئة', style: text.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Row(
              children: [
                for (final g in categoryGroups)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Material(
                        color: scheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(16),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(16),
                          onTap: () => widget.onOpenStores(g.key, ''),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            child: Column(children: [
                              Icon(g.icon, color: scheme.primary),
                              const SizedBox(height: 6),
                              Text(g.label, style: text.bodySmall, textAlign: TextAlign.center),
                            ]),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            Text('متاجر قريبة منك', style: text.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            FutureBuilder<List<Map<String, dynamic>>>(
              future: _nearby,
              builder: (context, snap) {
                if (snap.connectionState != ConnectionState.done) {
                  return const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()));
                }
                if (snap.hasError) {
                  return Padding(padding: const EdgeInsets.all(12), child: Text(friendlyError(snap.error!)));
                }
                final stores = snap.data!;
                if (stores.isEmpty) {
                  return const Padding(padding: EdgeInsets.all(12), child: Text('لا توجد متاجر مفتوحة حالياً'));
                }
                return GridView.count(
                  crossAxisCount: 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 0.82,
                  children: [
                    for (final s in stores) StoreCard(store: s, onTap: () => widget.onOpenStore(s)),
                  ],
                );
              },
            ),
            const SizedBox(height: 20),
            // بطاقة طلب ليفرور
            Material(
              color: scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(20),
              child: InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: widget.onOpenCourier,
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Icon(Icons.delivery_dining, color: scheme.primary, size: 30),
                        const SizedBox(width: 10),
                        Text('تحتاج إلى ليفرور؟', style: text.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                      ]),
                      const SizedBox(height: 8),
                      Text('اطلب نقل غرض أو وثيقة من مكان إلى آخر.',
                          style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
                      const SizedBox(height: 12),
                      Text('اطلب ليفرور ←',
                          style: text.titleSmall?.copyWith(color: scheme.primary, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
