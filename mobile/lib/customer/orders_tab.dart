import 'dart:async';

import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/labels.dart';

/// شاشة طلباتي (تُفتح من حسابي أو بعد إنشاء طلب).
class OrdersScreen extends StatelessWidget {
  const OrdersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('طلباتي')),
      body: const OrdersTab(),
    );
  }
}

class OrdersTab extends StatefulWidget {
  const OrdersTab({super.key});

  @override
  State<OrdersTab> createState() => _OrdersTabState();
}

class _OrdersTabState extends State<OrdersTab> {
  List<Map<String, dynamic>>? _orders;
  String? _error;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _load();
    // تحديث دوري كل 10 ثوانٍ (يُستبدل لاحقاً بالتحديث اللحظي Realtime)
    _timer = Timer.periodic(const Duration(seconds: 10), (_) => _load());
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
          .eq('customer_id', db.auth.currentUser!.id)
          .order('created_at', ascending: false)
          .limit(50);
      if (mounted) {
        setState(() {
          _orders = List<Map<String, dynamic>>.from(rows);
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    }
  }

  num _total(Map<String, dynamic> o) =>
      asNum(o['items_total']) + asNum(o['delivery_fee']) + asNum(o['service_fee']);

  @override
  Widget build(BuildContext context) {
    if (_error != null && _orders == null) return Center(child: Text(_error!));
    if (_orders == null) return const Center(child: CircularProgressIndicator());
    if (_orders!.isEmpty) return const Center(child: Text('لا طلبات بعد'));
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: _orders!.length,
        itemBuilder: (context, i) {
          final o = _orders![i];
          final status = '${o['status']}';
          return Card(
            child: ListTile(
              title: Text(orderTypeLabel(o['type'], o['free_kind'])),
              subtitle: Text('${statusLabels[status] ?? status}\n${dinar(_total(o))}'),
              isThreeLine: true,
              trailing: const Icon(Icons.chevron_left),
              onTap: () => showModalBottomSheet<void>(
                context: context,
                isScrollControlled: true,
                builder: (_) => _OrderSheet(order: o, onChanged: _load),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _OrderSheet extends StatefulWidget {
  final Map<String, dynamic> order;
  final Future<void> Function() onChanged;
  const _OrderSheet({required this.order, required this.onChanged});

  @override
  State<_OrderSheet> createState() => _OrderSheetState();
}

class _OrderSheetState extends State<_OrderSheet> {
  late final Future<List<List<Map<String, dynamic>>>> _detail = _load();
  bool _busy = false;

  Future<List<List<Map<String, dynamic>>>> _load() async {
    final id = widget.order['id'];
    final items = await db.from('order_items').select().eq('order_id', id);
    final events = await db.from('order_events').select().eq('order_id', id).order('at');
    return [List<Map<String, dynamic>>.from(items), List<Map<String, dynamic>>.from(events)];
  }

  Future<void> _cancel() async {
    setState(() => _busy = true);
    try {
      await db.rpc('customer_cancel', params: {'p_order': widget.order['id']});
      await widget.onChanged();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final o = widget.order;
    final canCancel = o['status'] == 'new' || o['status'] == 'accepted';
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: FutureBuilder<List<List<Map<String, dynamic>>>>(
          future: _detail,
          builder: (context, snap) {
            final items = snap.data?[0] ?? const <Map<String, dynamic>>[];
            final events = snap.data?[1] ?? const <Map<String, dynamic>>[];
            return SingleChildScrollView(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text(orderTypeLabel(o['type'], o['free_kind']), style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 4),
                Text('الحالة: ${statusLabels[o['status']] ?? o['status']}'),
                if (o['description'] != null) Text('الوصف: ${o['description']}'),
                Text('العنوان: ${o['dropoff_address']}'),
                const Divider(height: 24),
                for (final it in items) Text('${it['qty']} × ${it['name']} — ${dinar(asNum(it['unit_price']) * asNum(it['qty']))}'),
                if (items.isNotEmpty) const SizedBox(height: 8),
                Text('التوصيل: ${dinar(asNum(o['delivery_fee']))}'),
                if (asNum(o['service_fee']) > 0) Text('رسوم الخدمة: ${dinar(asNum(o['service_fee']))}'),
                const Divider(height: 24),
                Text('سير الطلب', style: Theme.of(context).textTheme.titleSmall),
                if (snap.connectionState != ConnectionState.done) const LinearProgressIndicator(),
                for (final e in events)
                  Text('• ${statusLabels[e['status']] ?? e['status']}  (${_time(e['at'])})'),
                if (canCancel) ...[
                  const SizedBox(height: 16),
                  OutlinedButton(
                    onPressed: _busy ? null : _cancel,
                    child: const Text('إلغاء الطلب'),
                  ),
                ],
              ]),
            );
          },
        ),
      ),
    );
  }

  String _time(dynamic iso) {
    final d = DateTime.tryParse('$iso')?.toLocal();
    if (d == null) return '';
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.hour)}:${two(d.minute)}';
  }
}
