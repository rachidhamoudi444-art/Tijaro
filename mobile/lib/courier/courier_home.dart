import 'dart:async';

import 'package:flutter/material.dart' hide Text;
import '../core/i18n.dart';

import '../core/api.dart';
import '../core/location.dart';

/// الشاشة الرئيسية للليفرور: الحالة، المحفظة، الطلبات المفتوحة، وطلباتي الجارية.
class CourierHome extends StatefulWidget {
  const CourierHome({super.key});

  @override
  State<CourierHome> createState() => _CourierHomeState();
}

class _CourierHomeState extends State<CourierHome> {
  bool _available = false;
  num _balance = 0;
  num _cashOpen = 0;
  List<Map<String, dynamic>> _open = [];
  List<Map<String, dynamic>> _mine = [];
  bool _loading = true;
  Timer? _timer;

  String get _uid => db.auth.currentUser!.id;

  @override
  void initState() {
    super.initState();
    _refresh();
    // تحديث دوري بسيط كل 10 ثوانٍ (يُستبدل لاحقاً بالتحديث اللحظي Realtime)
    _timer = Timer.periodic(const Duration(seconds: 10), (_) => _refresh(silent: true));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _refresh({bool silent = false}) async {
    try {
      final me = await db.from('couriers').select('available').eq('id', _uid).single();
      // موقعي الحالي يُرسل دورياً ليصل الطلب لأقرب ليفرور
      if (me['available'] == true) {
        final loc = await currentLocation();
        if (loc != null) {
          await db.rpc('courier_set_available', params: {'p_on': true, 'p_lat': loc.latitude, 'p_lng': loc.longitude});
        }
      }
      final bal = await db.rpc('courier_balance', params: {'cid': _uid});
      final cash = await db.rpc('courier_cash_open', params: {'cid': _uid});
      final mine = await db
          .from('orders')
          .select()
          .eq('courier_id', _uid)
          .inFilter('status', ['accepted', 'preparing', 'ready', 'picked_up', 'on_the_way'])
          .order('created_at');
      final open = _available || me['available'] == true
          ? await db.rpc('open_orders_for_courier')
          : <dynamic>[];
      if (!mounted) return;
      setState(() {
        _available = me['available'] == true;
        _balance = asNum(bal);
        _cashOpen = asNum(cash);
        _mine = List<Map<String, dynamic>>.from(mine);
        _open = List<Map<String, dynamic>>.from(open as List);
        _loading = false;
      });
    } catch (e) {
      if (!silent) _toast(friendlyError(e));
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _setAvailable(bool on) async {
    try {
      final loc = on ? await currentLocation() : null;
      await db.rpc('courier_set_available', params: {
        'p_on': on,
        'p_lat': loc?.latitude,
        'p_lng': loc?.longitude,
      });
      await _refresh();
    } catch (e) {
      _toast(friendlyError(e));
    }
  }

  Future<void> _accept(String orderId) async {
    try {
      await db.rpc('courier_accept', params: {'p_order': orderId});
      _toast('تم قبول الطلب');
      await _refresh();
    } catch (e) {
      _toast(friendlyError(e));
      await _refresh(silent: true);
    }
  }

  Future<void> _setStatus(String orderId, String status) async {
    try {
      await db.rpc('courier_set_status', params: {'p_order': orderId, 'p_status': status});
      await _refresh();
    } catch (e) {
      _toast(friendlyError(e));
    }
  }

  Future<void> _deliver(Map<String, dynamic> order) async {
    final isPurchase = order['type'] == 'free' && order['free_kind'] == 'purchase';
    final expected = asNum(order['items_total']) + asNum(order['delivery_fee']) + asNum(order['service_fee']);
    final cashCtl = TextEditingController(text: isPurchase ? '' : expected.toStringAsFixed(0));
    final itemsCtl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تأكيد التسليم'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          if (isPurchase)
            TextField(
              controller: itemsCtl,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(labelText: tr('ثمن المشتريات حسب الفاتورة (دج)')),
              onChanged: (v) {
                final items = num.tryParse(v) ?? 0;
                cashCtl.text = (items + asNum(order['delivery_fee']) + asNum(order['service_fee'])).toStringAsFixed(0);
              },
            ),
          TextField(
            controller: cashCtl,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(labelText: tr('المبلغ المحصَّل من الزبون (دج)')),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('تم التسليم')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await db.rpc('courier_deliver', params: {
        'p_order': order['id'],
        'p_cash': num.tryParse(cashCtl.text) ?? 0,
        if (isPurchase) 'p_items_override': num.tryParse(itemsCtl.text) ?? 0,
      });
      _toast('تم التسليم وتسجيل العمولة');
      await _refresh();
    } catch (e) {
      _toast(friendlyError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('الليفرور'),
        actions: [
          const LangToggle(),
          IconButton(
            tooltip: tr('خروج'),
            icon: const Icon(Icons.logout),
            onPressed: () => db.auth.signOut(),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _refresh,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(children: [
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(_available ? 'متاح لاستقبال الطلبات' : 'غير متاح'),
                          value: _available,
                          onChanged: _setAvailable,
                        ),
                        const Divider(),
                        _kv('رصيد المحفظة', '${_balance.toStringAsFixed(0)} دج'),
                        _kv('نقد بيدك (للتسليم للمكتب)', '${_cashOpen.toStringAsFixed(0)} دج'),
                      ]),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text('طلباتي الجارية', style: Theme.of(context).textTheme.titleMedium),
                  if (_mine.isEmpty) const Padding(padding: EdgeInsets.all(12), child: Text('لا طلبات جارية')),
                  for (final o in _mine) _MyOrderCard(order: o, onStatus: _setStatus, onDeliver: _deliver),
                  const SizedBox(height: 16),
                  Text('طلبات متاحة', style: Theme.of(context).textTheme.titleMedium),
                  if (!_available)
                    const Padding(padding: EdgeInsets.all(12), child: Text('فعّل "متاح" لترى الطلبات'))
                  else if (_open.isEmpty)
                    const Padding(padding: EdgeInsets.all(12), child: Text('لا طلبات حالياً')),
                  for (final o in _open)
                    Card(
                      child: ListTile(
                        title: Text('${_typeLabel(o['type'])} • توصيل ${asNum(o['delivery_fee']).toStringAsFixed(0)} دج'),
                        subtitle: Text(o['distance_to_pickup_km'] == null
                            ? 'المسافة غير معروفة'
                            : 'يبعد ${o['distance_to_pickup_km']} كم عن نقطة الاستلام'),
                        trailing: FilledButton(
                          onPressed: () => _accept(o['order_id'] as String),
                          child: const Text('قبول'),
                        ),
                      ),
                    ),
                ],
              ),
            ),
    );
  }

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(k), Text(v, style: const TextStyle(fontWeight: FontWeight.bold))]),
      );
}

String _typeLabel(dynamic t) => switch (t) {
      'store' => 'طلب متجر',
      'p2p' => 'نقطة لنقطة',
      'free' => 'طلب حر',
      _ => '$t',
    };

const _statusLabels = {
  'accepted': 'المتجر قبل الطلب',
  'preparing': 'قيد التحضير',
  'ready': 'جاهز للاستلام',
  'picked_up': 'تم الاستلام',
  'on_the_way': 'في الطريق للزبون',
};

class _MyOrderCard extends StatelessWidget {
  final Map<String, dynamic> order;
  final Future<void> Function(String id, String status) onStatus;
  final Future<void> Function(Map<String, dynamic> order) onDeliver;

  const _MyOrderCard({required this.order, required this.onStatus, required this.onDeliver});

  /// وجهة الملاحة: المتجر قبل الاستلام، والزبون بعده.
  (double, double)? _navTarget() {
    final after = order['status'] == 'picked_up' || order['status'] == 'on_the_way';
    final lat = after ? order['dropoff_lat'] : order['pickup_lat'];
    final lng = after ? order['dropoff_lng'] : order['pickup_lng'];
    if (lat is num && lng is num) return (lat.toDouble(), lng.toDouble());
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final status = order['status'] as String;
    final id = order['id'] as String;
    Widget? action;
    if (status == 'ready') {
      action = FilledButton(onPressed: () => onStatus(id, 'picked_up'), child: const Text('استلمت الطلب'));
    } else if (status == 'picked_up') {
      action = FilledButton(onPressed: () => onStatus(id, 'on_the_way'), child: const Text('انطلقت للزبون'));
    } else if (status == 'on_the_way') {
      action = FilledButton(onPressed: () => onDeliver(order), child: const Text('سلّمت الطلب'));
    } else {
      action = const Text('بانتظار جاهزية المتجر');
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${_typeLabel(order['type'])} • ${_statusLabels[status] ?? status}',
              style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text('العنوان: ${order['dropoff_address']}'),
          Text('المطلوب من الزبون: ${(asNum(order['items_total']) + asNum(order['delivery_fee']) + asNum(order['service_fee'])).toStringAsFixed(0)} دج'),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
            action,
            if (_navTarget() != null)
              OutlinedButton.icon(
                icon: const Icon(Icons.navigation_outlined),
                label: Text(status == 'on_the_way' || status == 'picked_up' ? 'الملاحة إلى الزبون' : 'الملاحة إلى المتجر'),
                onPressed: () {
                  final t = _navTarget()!;
                  openInGoogleMaps(t.$1, t.$2);
                },
              ),
          ]),
        ]),
      ),
    );
  }
}
