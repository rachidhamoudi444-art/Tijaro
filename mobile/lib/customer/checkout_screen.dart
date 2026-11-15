import 'package:flutter/material.dart' hide Text;
import '../core/i18n.dart';
import 'package:latlong2/latlong.dart';

import '../core/api.dart';
import '../core/labels.dart';
import '../core/location.dart';
import '../core/location_picker.dart';

/// تأكيد الطلب: العنوان، الموقع، سعر التوصيل، والدفع كاش عند الاستلام.
class CheckoutScreen extends StatefulWidget {
  final Map<String, dynamic> store;
  final List<Map<String, dynamic>> products;
  final Map<String, int> cart;

  const CheckoutScreen({super.key, required this.store, required this.products, required this.cart});

  @override
  State<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends State<CheckoutScreen> {
  final _address = TextEditingController();
  LatLng? _loc;
  num? _fee;
  bool _busy = false;
  String? _error;

  LatLng get _storeLoc => LatLng(asNum(widget.store['lat']).toDouble(), asNum(widget.store['lng']).toDouble());

  num get _itemsTotal {
    num t = 0;
    for (final p in widget.products) {
      t += asNum(p['price']) * (widget.cart[p['id']] ?? 0);
    }
    return t;
  }

  @override
  void initState() {
    super.initState();
    _useCurrentLocation();
  }

  @override
  void dispose() {
    _address.dispose();
    super.dispose();
  }

  Future<void> _useCurrentLocation() async {
    final loc = await currentLocation();
    if (loc != null && mounted && _loc == null) _setLocation(loc);
  }

  Future<void> _setLocation(LatLng loc) async {
    setState(() {
      _loc = loc;
      _fee = null;
    });
    try {
      final fee = await db.rpc('quote_delivery_fee', params: {
        'p_from_lat': _storeLoc.latitude,
        'p_from_lng': _storeLoc.longitude,
        'p_to_lat': loc.latitude,
        'p_to_lng': loc.longitude,
      });
      if (mounted) setState(() => _fee = asNum(fee));
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    }
  }

  Future<void> _submit() async {
    if (_loc == null) {
      setState(() => _error = 'حدّد موقع التسليم على الخريطة');
      return;
    }
    if (_address.text.trim().isEmpty) {
      setState(() => _error = 'اكتب عنوانك (الحي، الشارع، علامة مميزة)');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await db.rpc('create_store_order', params: {
        'p_store': widget.store['id'],
        'p_items': [
          for (final e in widget.cart.entries) {'product_id': e.key, 'qty': e.value},
        ],
        'p_addr': _address.text.trim(),
        'p_lat': _loc!.latitude,
        'p_lng': _loc!.longitude,
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم إرسال طلبك للمتجر')));
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final lines = [
      for (final p in widget.products)
        if ((widget.cart[p['id']] ?? 0) > 0) p,
    ];
    final total = _fee == null ? null : _itemsTotal + _fee!;
    return Scaffold(
      appBar: AppBar(title: const Text('تأكيد الطلب')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('${widget.store['name']}', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          for (final p in lines)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Text('${widget.cart[p['id']]} × ${p['name']}'),
                Text(dinar(asNum(p['price']) * widget.cart[p['id']]!)),
              ]),
            ),
          const Divider(height: 24),
          TextField(
            controller: _address,
            maxLines: 2,
            decoration: InputDecoration(labelText: tr('عنوان التسليم'), border: OutlineInputBorder()),
          ),
          const SizedBox(height: 8),
          LocationRow(label: 'موقع التسليم', value: _loc, mapStart: _storeLoc, onChanged: _setLocation),
          const Divider(height: 24),
          _row('ثمن المنتجات', dinar(_itemsTotal)),
          _row('التوصيل', _fee == null ? (_loc == null ? '—' : '...') : dinar(_fee!)),
          _row('المجموع (كاش عند الاستلام)', total == null ? '—' : dinar(total), bold: true),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _busy ? null : _submit,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: _busy
                  ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('تأكيد الطلب'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _row(String k, String v, {bool bold = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(k, style: TextStyle(fontWeight: bold ? FontWeight.bold : null)),
          Text(v, style: TextStyle(fontWeight: bold ? FontWeight.bold : null)),
        ]),
      );
}
