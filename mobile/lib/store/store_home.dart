import 'dart:async';

import 'package:flutter/material.dart' hide Text;
import '../core/i18n.dart';

import '../core/api.dart';
import '../core/labels.dart';

/// شاشة صاحب المتجر: الطلبات الواردة، المنتجات، وفتح/إغلاق المتجر.
class StoreHome extends StatefulWidget {
  const StoreHome({super.key});

  @override
  State<StoreHome> createState() => _StoreHomeState();
}

class _StoreHomeState extends State<StoreHome> {
  List<Map<String, dynamic>> _stores = [];
  Map<String, dynamic>? _store;
  num _balance = 0;
  String? _error;
  bool _loading = true;
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    _loadStores();
  }

  Future<void> _loadStores() async {
    try {
      final uid = db.auth.currentUser!.id;
      final rows = await db.from('stores').select().eq('owner_id', uid).order('created_at');
      final list = [for (final r in rows) Map<String, dynamic>.of(r)];
      if (!mounted) return;
      setState(() {
        _stores = list;
        _store = list.isEmpty
            ? null
            : list.firstWhere((s) => s['id'] == _store?['id'], orElse: () => list.first);
        _loading = false;
        _error = null;
      });
      await _loadBalance();
    } catch (e) {
      if (mounted) setState(() {
        _error = friendlyError(e);
        _loading = false;
      });
    }
  }

  Future<void> _loadBalance() async {
    final s = _store;
    if (s == null) return;
    try {
      final b = await db.rpc('store_balance', params: {'sid': s['id']});
      if (mounted) setState(() => _balance = asNum(b));
    } catch (_) {}
  }

  Future<void> _toggleOpen(bool on) async {
    final s = _store!;
    try {
      await db.from('stores').update({'is_open': on}).eq('id', s['id']);
      setState(() => s['is_open'] = on);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    final s = _store;
    return Scaffold(
      appBar: AppBar(
        title: _stores.length > 1
            ? DropdownButton<String>(
                value: s!['id'] as String,
                underline: const SizedBox(),
                items: [for (final x in _stores) DropdownMenuItem(value: x['id'] as String, child: Text('${x['name']}'))],
                onChanged: (id) => setState(() {
                  _store = _stores.firstWhere((x) => x['id'] == id);
                  _loadBalance();
                }),
              )
            : Text(s == null ? 'متجري' : '${s['name']}'),
        actions: [
          const LangToggle(),
          IconButton(icon: const Icon(Icons.logout), tooltip: tr('خروج'), onPressed: () => db.auth.signOut()),
        ],
      ),
      body: s == null
          ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error ?? 'لا يوجد متجر مرتبط بحسابك. تواصل مع الإدارة.')))
          : Column(children: [
              SwitchListTile(
                title: Text(s['is_open'] == true ? 'المتجر مفتوح ويستقبل الطلبات' : 'المتجر مغلق'),
                subtitle: Text('مستحقاتك عند المنصة: ${dinar(_balance)}'),
                value: s['is_open'] == true,
                onChanged: _toggleOpen,
              ),
              const Divider(height: 1),
              Expanded(
                child: IndexedStack(index: _tab, children: [
                  _OrdersView(storeId: s['id'] as String, onChanged: _loadBalance),
                  _ProductsView(storeId: s['id'] as String),
                ]),
              ),
            ]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: [
          NavigationDestination(icon: Icon(Icons.receipt_long_outlined), selectedIcon: Icon(Icons.receipt_long), label: tr('الطلبات')),
          NavigationDestination(icon: Icon(Icons.inventory_2_outlined), selectedIcon: Icon(Icons.inventory_2), label: tr('المنتجات')),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- الطلبات

class _OrdersView extends StatefulWidget {
  final String storeId;
  final Future<void> Function() onChanged;
  const _OrdersView({super.key, required this.storeId, required this.onChanged});

  @override
  State<_OrdersView> createState() => _OrdersViewState();
}

class _OrdersViewState extends State<_OrdersView> {
  List<Map<String, dynamic>> _orders = [];
  Map<String, List<Map<String, dynamic>>> _items = {};
  bool _loaded = false;
  String? _error;
  Timer? _timer;
  int _lastNew = 0;

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(const Duration(seconds: 8), (_) => _load());
  }

  @override
  void didUpdateWidget(covariant _OrdersView old) {
    super.didUpdateWidget(old);
    if (old.storeId != widget.storeId) {
      _loaded = false;
      _load();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final rows = await db
          .from('orders')
          .select()
          .eq('store_id', widget.storeId)
          .inFilter('status', ['new', 'accepted', 'preparing', 'ready', 'picked_up', 'on_the_way', 'dispute'])
          .order('created_at', ascending: false);
      final orders = [for (final r in rows) Map<String, dynamic>.of(r)];
      final ids = [for (final o in orders) o['id']];
      final items = <String, List<Map<String, dynamic>>>{};
      if (ids.isNotEmpty) {
        final its = await db.from('order_items').select().inFilter('order_id', ids);
        for (final it in its) {
          items.putIfAbsent('${it['order_id']}', () => []).add(Map<String, dynamic>.of(it));
        }
      }
      if (!mounted) return;
      final newCount = orders.where((o) => o['status'] == 'new').length;
      if (_loaded && newCount > _lastNew) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('وصل طلب جديد!')));
      }
      setState(() {
        _orders = orders;
        _items = items;
        _lastNew = newCount;
        _loaded = true;
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    }
  }

  Future<void> _set(String id, String status) async {
    try {
      await db.rpc('store_set_status', params: {'p_order': id, 'p_status': status});
      await _load();
      await widget.onChanged();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return Center(child: _error != null ? Text(_error!) : const CircularProgressIndicator());
    if (_orders.isEmpty) return const Center(child: Text('لا طلبات حالياً'));
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: _orders.length,
        itemBuilder: (context, i) {
          final o = _orders[i];
          final status = '${o['status']}';
          final items = _items['${o['id']}'] ?? const [];
          Widget? action;
          if (status == 'new') {
            action = Row(children: [
              Expanded(child: FilledButton(onPressed: () => _set('${o['id']}', 'accepted'), child: const Text('قبول الطلب'))),
              const SizedBox(width: 8),
              OutlinedButton(onPressed: () => _set('${o['id']}', 'rejected'), child: const Text('رفض')),
            ]);
          } else if (status == 'accepted') {
            action = FilledButton(onPressed: () => _set('${o['id']}', 'preparing'), child: const Text('بدأت التحضير'));
          } else if (status == 'preparing') {
            action = FilledButton.icon(
              icon: const Icon(Icons.check_circle_outline),
              onPressed: () => _set('${o['id']}', 'ready'),
              label: const Text('الطلب جاهز، أرسل ليفرور'),
            );
          } else if (status == 'ready') {
            action = const Text('بانتظار أقرب ليفرور...', style: TextStyle(fontWeight: FontWeight.bold));
          }
          return Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(statusLabels[status] ?? status, style: const TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                for (final it in items) Text('${it['qty']} × ${it['name']}'),
                const SizedBox(height: 6),
                Text('ثمن المنتجات: ${dinar(asNum(o['items_total']))}'),
                if (action != null) ...[const SizedBox(height: 10), action],
              ]),
            ),
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------- المنتجات

class _ProductsView extends StatefulWidget {
  final String storeId;
  const _ProductsView({super.key, required this.storeId});

  @override
  State<_ProductsView> createState() => _ProductsViewState();
}

class _ProductsViewState extends State<_ProductsView> {
  late Future<List<Map<String, dynamic>>> _future = _load();

  @override
  void didUpdateWidget(covariant _ProductsView old) {
    super.didUpdateWidget(old);
    if (old.storeId != widget.storeId) _reload();
  }

  Future<List<Map<String, dynamic>>> _load() async {
    final rows = await db.from('products').select().eq('store_id', widget.storeId).order('name');
    return [for (final r in rows) Map<String, dynamic>.of(r)];
  }

  void _reload() => setState(() => _future = _load());

  Future<void> _edit([Map<String, dynamic>? p]) async {
    final name = TextEditingController(text: p == null ? '' : '${p['name']}');
    final price = TextEditingController(text: p == null ? '' : asNum(p['price']).toStringAsFixed(0));
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(p == null ? 'منتج جديد' : 'تعديل المنتج'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: name, decoration: InputDecoration(labelText: tr('اسم المنتج'))),
          const SizedBox(height: 12),
          TextField(
            controller: price,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(labelText: tr('السعر (دج)')),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('حفظ')),
        ],
      ),
    );
    if (ok != true) return;
    final n = name.text.trim();
    final pr = num.tryParse(price.text.trim());
    if (n.isEmpty || pr == null || pr < 0) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('أدخل اسماً وسعراً صحيحاً')));
      return;
    }
    try {
      if (p == null) {
        await db.from('products').insert({'store_id': widget.storeId, 'name': n, 'price': pr});
      } else {
        await db.from('products').update({'name': n, 'price': pr}).eq('id', p['id']);
      }
      _reload();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
    }
  }

  Future<void> _setAvailable(Map<String, dynamic> p, bool v) async {
    try {
      await db.from('products').update({'available': v}).eq('id', p['id']);
      _reload();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
    }
  }

  Future<void> _delete(Map<String, dynamic> p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('حذف "${p['name']}"؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('لا')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('حذف')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await db.from('products').delete().eq('id', p['id']);
      _reload();
    } catch (_) {
      // منتج مرتبط بطلبات سابقة: نخفيه بدل حذفه
      await _setAvailable(p, false);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('المنتج مرتبط بطلبات سابقة فتم إخفاؤه بدل حذفه')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(),
        icon: const Icon(Icons.add),
        label: const Text('منتج'),
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
          if (snap.hasError) return Center(child: Text(friendlyError(snap.error!)));
          final products = snap.data!;
          if (products.isEmpty) return const Center(child: Text('أضف أول منتج بالزر الأخضر'));
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 90),
            itemCount: products.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final p = products[i];
              final on = p['available'] == true;
              return ListTile(
                onTap: () => _edit(p),
                title: Text('${p['name']}', style: TextStyle(decoration: on ? null : TextDecoration.lineThrough)),
                subtitle: Text(dinar(asNum(p['price']))),
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  Switch(value: on, onChanged: (v) => _setAvailable(p, v)),
                  IconButton(icon: const Icon(Icons.delete_outline), onPressed: () => _delete(p)),
                ]),
              );
            },
          );
        },
      ),
    );
  }
}
