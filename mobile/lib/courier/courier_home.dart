import 'dart:async';

import 'dart:async';

import 'package:flutter/material.dart' hide Text;
import 'package:url_launcher/url_launcher.dart';
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
                  for (final o in _mine) _MyOrderCard(order: o, onStatus: _setStatus, onDeliver: _deliver, onChanged: _refresh),
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

class _MyOrderCard extends StatefulWidget {
  final Map<String, dynamic> order;
  final Future<void> Function(String id, String status) onStatus;
  final Future<void> Function(Map<String, dynamic> order) onDeliver;
  final Future<void> Function({bool silent}) onChanged;

  const _MyOrderCard({
    required this.order,
    required this.onStatus,
    required this.onDeliver,
    required this.onChanged,
  });

  @override
  State<_MyOrderCard> createState() => _MyOrderCardState();
}

class _MyOrderCardState extends State<_MyOrderCard> {
  Map<String, dynamic>? _contact; // هاتف الزبون/المتجر + عدد الاتصالات + وقت الوصول
  int _needCalls = 3;
  int _waitMinutes = 10;
  Timer? _tick;
  bool _busy = false;

  Map<String, dynamic> get order => widget.order;
  String get status => order['status'] as String;
  String get id => order['id'] as String;

  @override
  void initState() {
    super.initState();
    _load();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && status == 'on_the_way') setState(() {});
    });
  }

  @override
  void didUpdateWidget(covariant _MyOrderCard old) {
    super.didUpdateWidget(old);
    if (old.order['status'] != order['status']) _load();
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final rows = await db.rpc('courier_order_contact', params: {'p_order': id});
      final st = await db
          .from('app_settings')
          .select()
          .inFilter('key', ['required_call_attempts', 'wait_minutes_at_address']);
      if (!mounted) return;
      setState(() {
        _contact = (rows as List).isEmpty ? null : Map<String, dynamic>.of(rows.first);
        for (final r in st) {
          if (r['key'] == 'required_call_attempts') _needCalls = asNum(r['value']).toInt();
          if (r['key'] == 'wait_minutes_at_address') _waitMinutes = asNum(r['value']).toInt();
        }
      });
    } catch (_) {}
  }

  void _msg(String m) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  Future<void> _run(Future<void> Function() job) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await job();
    } catch (e) {
      _msg(friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _dial(String? phone) async {
    if (phone == null || phone.isEmpty) return;
    await launchUrl(Uri(scheme: 'tel', path: phone));
  }

  /// يسجّل محاولة الاتصال (مع موقعك) ثم يفتح الهاتف.
  Future<void> _callCustomer() => _run(() async {
        final loc = await currentLocation();
        if (loc == null) {
          _msg('تعذّر تحديد موقعك. فعّل GPS وامنح الإذن.');
          return;
        }
        await db.rpc('courier_log_call', params: {'p_order': id, 'p_lat': loc.latitude, 'p_lng': loc.longitude});
        await _load();
        await _dial('${_contact?['customer_phone'] ?? ''}');
      });

  Future<void> _arrived() => _run(() async {
        final loc = await currentLocation();
        if (loc == null) {
          _msg('تعذّر تحديد موقعك. فعّل GPS وامنح الإذن.');
          return;
        }
        await db.rpc('courier_arrived', params: {'p_order': id, 'p_lat': loc.latitude, 'p_lng': loc.longitude});
        await _load();
        _msg('تم تسجيل وصولك. ابدأ الانتظار.');
      });

  Duration? _waitLeft() {
    final a = DateTime.tryParse('${_contact?['arrived_at']}')?.toLocal();
    if (a == null) return null;
    final left = a.add(Duration(minutes: _waitMinutes)).difference(DateTime.now());
    return left.isNegative ? Duration.zero : left;
  }

  int get _calls => (_contact?['calls'] as num?)?.toInt() ?? 0;

  Future<bool> _confirm(String title, String body) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('رجوع')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('تأكيد')),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _notDelivered() async {
    final left = _waitLeft();
    final met = _calls >= _needCalls && left != null && left == Duration.zero;
    final ok = await _confirm(
      'تبليغ: لم يُسلَّم',
      met
          ? 'الشروط مكتملة (اتصالات ووصول وانتظار). سيُسجَّل الخطأ على الزبون وتُعوَّض.'
          : 'الشروط غير مكتملة (المطلوب $_needCalls اتصالات، ووصول، وانتظار $_waitMinutes دقائق). سيُحال الطلب إلى الإدارة للبتّ فيه.',
    );
    if (!ok) return;
    await _run(() async {
      final r = await db.rpc('courier_report_not_delivered', params: {'p_order': id});
      _msg(r == 'customer_fault' ? 'سُجّل الخطأ على الزبون وتم تعويضك.' : 'أُحيل الطلب إلى الإدارة.');
      await widget.onChanged(silent: true);
    });
  }

  Future<void> _storeFault() async {
    final ok = await _confirm('المتجر لم يجهّز الطلب', 'سيُحال الطلب إلى الإدارة للبتّ فيه. هل تريد المتابعة؟');
    if (!ok) return;
    await _run(() async {
      await db.rpc('courier_report_store_fault', params: {'p_order': id});
      _msg('أُحيل الطلب إلى الإدارة.');
      await widget.onChanged(silent: true);
    });
  }

  /// وجهة الملاحة: المتجر قبل الاستلام، والزبون بعده.
  (double, double)? _navTarget() {
    final after = status == 'picked_up' || status == 'on_the_way';
    final lat = after ? order['dropoff_lat'] : order['pickup_lat'];
    final lng = after ? order['dropoff_lng'] : order['pickup_lng'];
    if (lat is num && lng is num) return (lat.toDouble(), lng.toDouble());
    return null;
  }

  String _mmss(Duration d) =>
      '${d.inMinutes.toString().padLeft(2, '0')}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    Widget? action;
    if (status == 'ready') {
      action = FilledButton(onPressed: () => widget.onStatus(id, 'picked_up'), child: const Text('استلمت الطلب'));
    } else if (status == 'picked_up') {
      action = FilledButton(onPressed: () => widget.onStatus(id, 'on_the_way'), child: const Text('انطلقت للزبون'));
    } else if (status == 'on_the_way') {
      action = FilledButton(onPressed: () => widget.onDeliver(order), child: const Text('سلّمت الطلب'));
    } else {
      action = const Text('بانتظار جاهزية المتجر');
    }
    final afterPickup = status == 'picked_up' || status == 'on_the_way';
    final left = _waitLeft();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${_typeLabel(order['type'])} • ${_statusLabels[status] ?? status}',
              style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          if (_contact?['store_name'] != null) Text('المتجر: ${_contact!['store_name']}'),
          if (afterPickup && _contact?['customer_name'] != null) Text('الزبون: ${_contact!['customer_name']}'),
          Text('العنوان: ${order['dropoff_address']}'),
          Text('المطلوب من الزبون: ${(asNum(order['items_total']) + asNum(order['delivery_fee']) + asNum(order['service_fee'])).toStringAsFixed(0)} دج'),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
            action,
            if (_navTarget() != null)
              OutlinedButton.icon(
                icon: const Icon(Icons.navigation_outlined),
                label: Text(afterPickup ? 'الملاحة إلى الزبون' : 'الملاحة إلى المتجر'),
                onPressed: () {
                  final t = _navTarget()!;
                  openInGoogleMaps(t.$1, t.$2);
                },
              ),
            if (!afterPickup && '${_contact?['store_phone'] ?? ''}'.isNotEmpty)
              OutlinedButton.icon(
                icon: const Icon(Icons.phone_outlined),
                label: const Text('اتصال بالمتجر'),
                onPressed: () => _dial('${_contact!['store_phone']}'),
              ),
          ]),
          if (status == 'ready') ...[
            const SizedBox(height: 6),
            TextButton(onPressed: _busy ? null : _storeFault, child: const Text('المتجر لم يجهّز الطلب')),
          ],
          if (afterPickup) ...[
            const Divider(height: 22),
            Text('إن لم يرد الزبون', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 6),
            Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
              FilledButton.tonalIcon(
                icon: const Icon(Icons.call),
                label: Text('اتصال بالزبون ($_calls/$_needCalls)'),
                onPressed: _busy ? null : _callCustomer,
              ),
              if (status == 'on_the_way')
                FilledButton.tonalIcon(
                  icon: const Icon(Icons.pin_drop_outlined),
                  label: Text(left == null ? 'وصلت إلى العنوان' : 'وصلت ✓'),
                  onPressed: (_busy || left != null) ? null : _arrived,
                ),
            ]),
            if (left != null && left > Duration.zero)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text('وقت الانتظار المتبقي: ${_mmss(left)}', style: const TextStyle(fontWeight: FontWeight.bold)),
              ),
            const SizedBox(height: 6),
            TextButton(
              onPressed: (_busy || status != 'on_the_way') ? null : _notDelivered,
              child: const Text('لم يُسلَّم (الزبون لا يرد)'),
            ),
          ],
        ]),
      ),
    );
  }
}
