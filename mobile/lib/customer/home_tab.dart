import 'package:flutter/material.dart' hide Text;
import '../core/i18n.dart';
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
                Row(children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.asset('assets/icon_full.png', width: 34, height: 34),
                  ),
                  const SizedBox(width: 8),
                  Text(appName,
                      style: text.headlineSmall?.copyWith(color: scheme.primary, fontWeight: FontWeight.w800)),
                ]),
                Row(children: [
                  const LangToggle(),
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
                hintText: tr('ابحث عن متجر أو منتج...'),
                prefixIcon: Icon(Icons.search),
              ),
            ),
            const SizedBox(height: 16),
            // اللافتة: الشعار تحته صورة تيبازة
            ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: Stack(
                children: [
                  Image.asset('assets/tipaza.jpg', height: 190, width: double.infinity, fit: BoxFit.cover),
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            scheme.primary.withOpacity(0.92),
                            scheme.primary.withOpacity(0.55),
                            Colors.transparent,
                          ],
                          stops: const [0, 0.5, 1],
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('كل التجارة في بلاصة وحدة',
                            style: text.titleLarge?.copyWith(color: Colors.white, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 4),
                        Text('اكتشف محلات منطقتك واطلب بسهولة',
                            style: text.bodyMedium?.copyWith(color: Colors.white)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Text('تصفح حسب الفئة', style: text.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            GridView.count(
              crossAxisCount: 4,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              childAspectRatio: 0.85,
              children: [
                for (final g in categoryGroups.take(11))
                  _CategoryTile(
                    icon: g.icon,
                    label: g.label,
                    onTap: () => widget.onOpenStores(g.key, ''),
                  ),
                _CategoryTile(
                  icon: Icons.apps,
                  label: 'كل الفئات',
                  onTap: () => widget.onOpenStores(null, ''),
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

class _CategoryTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _CategoryTile({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: scheme.primaryContainer,
                child: Icon(icon, color: scheme.primary, size: 22),
              ),
              const SizedBox(height: 6),
              Text(label,
                  maxLines: 2,
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall),
            ],
          ),
        ),
      ),
    );
  }
}
