import 'package:flutter/material.dart' hide Text;
import '../core/i18n.dart';

import '../core/api.dart';
import '../core/labels.dart';
import 'store_card.dart';

/// كل المتاجر المفتوحة مع بحث وتصفية حسب الفئة. يُعاد بناؤها (بمفتاح) عند الفتح من الرئيسية.
class StoresTab extends StatefulWidget {
  final String? initialGroup;
  final String initialQuery;
  final void Function(Map<String, dynamic> store) onOpenStore;

  const StoresTab({
    super.key,
    this.initialGroup,
    this.initialQuery = '',
    required this.onOpenStore,
  });

  @override
  State<StoresTab> createState() => _StoresTabState();
}

class _StoresTabState extends State<StoresTab> {
  late String? _group = widget.initialGroup;
  late final TextEditingController _search = TextEditingController(text: widget.initialQuery);
  late Future<List<Map<String, dynamic>>> _future = _load();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<List<Map<String, dynamic>>> _load() async {
    var q = db.from('stores').select('id,name,category,address,lat,lng,image_url').eq('is_open', true);
    final g = groupByKey(_group);
    if (g != null) q = q.inFilter('category', g.categories);
    final text = _search.text.trim();
    if (text.isNotEmpty) q = q.ilike('name', '%$text%');
    final rows = await q.order('name');
    return [for (final r in rows) Map<String, dynamic>.of(r)];
  }

  void _reload() => setState(() => _future = _load());

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: TextField(
            controller: _search,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _reload(),
            decoration: InputDecoration(
              hintText: tr('ابحث عن متجر...'),
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _search.text.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () {
                        _search.clear();
                        _reload();
                      },
                    ),
              filled: true,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
            ),
          ),
        ),
        SizedBox(
          height: 56,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            children: [
              Padding(
                padding: const EdgeInsetsDirectional.only(end: 8),
                child: ChoiceChip(
                  label: const Text('الكل'),
                  selected: _group == null,
                  onSelected: (_) {
                    _group = null;
                    _reload();
                  },
                ),
              ),
              for (final g in categoryGroups)
                Padding(
                  padding: const EdgeInsetsDirectional.only(end: 8),
                  child: ChoiceChip(
                    avatar: Icon(g.icon, size: 18, color: _group == g.key ? Colors.white : g.color),
                    label: Text(g.label),
                    selectedColor: g.color,
                    labelStyle: TextStyle(color: _group == g.key ? Colors.white : null),
                    selected: _group == g.key,
                    onSelected: (_) {
                      _group = g.key;
                      _reload();
                    },
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: FutureBuilder<List<Map<String, dynamic>>>(
            future: _future,
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snap.hasError) return Center(child: Text(friendlyError(snap.error!)));
              final stores = snap.data!;
              if (stores.isEmpty) {
                return const Center(child: Text('لا توجد متاجر مفتوحة مطابقة حالياً'));
              }
              return RefreshIndicator(
                onRefresh: () async => _reload(),
                child: GridView.builder(
                  padding: const EdgeInsets.all(16),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: 0.82,
                  ),
                  itemCount: stores.length,
                  itemBuilder: (context, i) => StoreCard(
                    store: stores[i],
                    onTap: () => widget.onOpenStore(stores[i]),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
