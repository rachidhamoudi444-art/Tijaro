import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/labels.dart';
import 'checkout_screen.dart';

/// صفحة متجر واحد: المنتجات والسلة (متجر واحد في كل طلب).
class StoreScreen extends StatefulWidget {
  final Map<String, dynamic> store;
  const StoreScreen({super.key, required this.store});

  @override
  State<StoreScreen> createState() => _StoreScreenState();
}

class _StoreScreenState extends State<StoreScreen> {
  late final Future<List<Map<String, dynamic>>> _products = _load();
  final Map<String, int> _cart = {};
  List<Map<String, dynamic>> _loaded = [];

  Future<List<Map<String, dynamic>>> _load() async {
    final rows = await db
        .from('products')
        .select('id,name,price,image_url')
        .eq('store_id', widget.store['id'])
        .eq('available', true)
        .order('name');
    _loaded = List<Map<String, dynamic>>.from(rows);
    return _loaded;
  }

  num get _total {
    num t = 0;
    for (final p in _loaded) {
      t += asNum(p['price']) * (_cart[p['id']] ?? 0);
    }
    return t;
  }

  int get _count => _cart.values.fold(0, (a, b) => a + b);

  void _change(String id, int delta) {
    setState(() {
      final next = (_cart[id] ?? 0) + delta;
      if (next <= 0) {
        _cart.remove(id);
      } else {
        _cart[id] = next;
      }
    });
  }

  Future<void> _checkout() async {
    final created = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => CheckoutScreen(store: widget.store, products: _loaded, cart: Map.of(_cart)),
      ),
    );
    if (created == true && mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('${widget.store['name']}')),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _products,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) return Center(child: Text(friendlyError(snap.error!)));
          final products = snap.data!;
          if (products.isEmpty) return const Center(child: Text('لا توجد منتجات متوفرة'));
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 100),
            itemCount: products.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final p = products[i];
              final id = p['id'] as String;
              final qty = _cart[id] ?? 0;
              return ListTile(
                title: Text('${p['name']}'),
                subtitle: Text(dinar(asNum(p['price']))),
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  if (qty > 0) ...[
                    IconButton(icon: const Icon(Icons.remove_circle_outline), onPressed: () => _change(id, -1)),
                    Text('$qty', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  ],
                  IconButton(icon: const Icon(Icons.add_circle), onPressed: () => _change(id, 1)),
                ]),
              );
            },
          );
        },
      ),
      bottomNavigationBar: _count == 0
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: FilledButton(
                  onPressed: _checkout,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text('متابعة الطلب ($_count) • ${dinar(_total)}'),
                  ),
                ),
              ),
            ),
    );
  }
}
