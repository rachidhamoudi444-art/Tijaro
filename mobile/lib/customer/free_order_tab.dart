import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../core/api.dart';
import '../core/labels.dart';
import '../core/location.dart';
import '../core/location_picker.dart';

/// الطلب الحر: نقل غرض/وثيقة من نقطة إلى نقطة، أو شراء من أي محل وتوصيله.
class FreeOrderTab extends StatefulWidget {
  final VoidCallback onCreated;
  const FreeOrderTab({super.key, required this.onCreated});

  @override
  State<FreeOrderTab> createState() => _FreeOrderTabState();
}

class _FreeOrderTabState extends State<FreeOrderTab> {
  int _mode = 0; // 0 = نقل، 1 = شراء وتوصيل
  final _desc = TextEditingController();
  final _budget = TextEditingController();
  final _fromAddr = TextEditingController();
  final _toAddr = TextEditingController();
  LatLng? _from;
  LatLng? _to;
  num? _fee;
  num _serviceFee = 0;
  num _maxPurchase = 2000;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _useCurrentLocationAsDropoff();
  }

  @override
  void dispose() {
    _desc.dispose();
    _budget.dispose();
    _fromAddr.dispose();
    _toAddr.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    try {
      final rows = await db
          .from('app_settings')
          .select('key,value')
          .inFilter('key', ['free_order_service_fee', 'free_order_max_purchase']);
      for (final r in rows) {
        if (r['key'] == 'free_order_service_fee') _serviceFee = asNum(r['value']);
        if (r['key'] == 'free_order_max_purchase') _maxPurchase = asNum(r['value']);
      }
      if (mounted) setState(() {});
    } catch (_) {
      // القيم الافتراضية كافية للعرض، والخادم هو الذي يفرض الحدود فعلاً
    }
  }

  Future<void> _useCurrentLocationAsDropoff() async {
    final loc = await currentLocation();
    if (loc != null && mounted && _to == null) {
      _to = loc;
      await _requote();
    }
  }

  Future<void> _requote() async {
    if (_from == null || _to == null) {
      if (mounted) setState(() => _fee = null);
      return;
    }
    try {
      final fee = await db.rpc('quote_delivery_fee', params: {
        'p_from_lat': _from!.latitude,
        'p_from_lng': _from!.longitude,
        'p_to_lat': _to!.latitude,
        'p_to_lng': _to!.longitude,
      });
      if (mounted) setState(() => _fee = asNum(fee));
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    }
  }

  Future<void> _submit() async {
    final purchase = _mode == 1;
    final budget = num.tryParse(_budget.text.trim());
    if (_desc.text.trim().isEmpty) {
      setState(() => _error = 'اكتب وصف ما تريده');
      return;
    }
    if (purchase && (budget == null || budget <= 0)) {
      setState(() => _error = 'أدخل الميزانية التقديرية للشراء');
      return;
    }
    if (purchase && budget! > _maxPurchase) {
      setState(() => _error = 'الميزانية تتجاوز سقف الشراء (${dinar(_maxPurchase)})');
      return;
    }
    if (_from == null || _to == null || _toAddr.text.trim().isEmpty) {
      setState(() => _error = 'حدّد موقع الاستلام وموقع التسليم واكتب عنوان التسليم');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await db.rpc('create_free_order', params: {
        'p_type': purchase ? 'free' : 'p2p',
        'p_kind': purchase ? 'purchase' : null,
        'p_desc': _desc.text.trim(),
        'p_budget': purchase ? budget : null,
        'p_from_addr': _fromAddr.text.trim(),
        'p_from_lat': _from!.latitude,
        'p_from_lng': _from!.longitude,
        'p_addr': _toAddr.text.trim(),
        'p_lat': _to!.latitude,
        'p_lng': _to!.longitude,
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم إرسال طلبك، سيصلك ليفرور قريباً')));
      widget.onCreated();
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final purchase = _mode == 1;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        SegmentedButton<int>(
          segments: const [
            ButtonSegment(value: 0, label: Text('نقل وثيقة/غرض'), icon: Icon(Icons.local_post_office_outlined)),
            ButtonSegment(value: 1, label: Text('شراء وتوصيل'), icon: Icon(Icons.shopping_bag_outlined)),
          ],
          selected: {_mode},
          onSelectionChanged: (s) => setState(() => _mode = s.first),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _desc,
          maxLines: 3,
          decoration: InputDecoration(
            labelText: purchase ? 'ماذا تريد أن يشتري لك الليفرور؟' : 'ما الذي يجب نقله؟',
            border: const OutlineInputBorder(),
          ),
        ),
        if (purchase) ...[
          const SizedBox(height: 12),
          TextField(
            controller: _budget,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: 'الميزانية التقديرية (دج)',
              helperText: 'الحد الأقصى ${dinar(_maxPurchase)}. تدفع ثمن الفاتورة الفعلي كاش للليفرور.',
              border: const OutlineInputBorder(),
            ),
          ),
        ],
        const SizedBox(height: 12),
        TextField(
          controller: _fromAddr,
          decoration: InputDecoration(
            labelText: purchase ? 'اسم المحل أو مكان الشراء (اختياري)' : 'عنوان الاستلام',
            border: const OutlineInputBorder(),
          ),
        ),
        LocationRow(
          label: purchase ? 'موقع المحل' : 'موقع الاستلام',
          value: _from,
          mapStart: _to,
          onChanged: (v) {
            _from = v;
            _requote();
          },
        ),
        const Divider(),
        TextField(
          controller: _toAddr,
          maxLines: 2,
          decoration: const InputDecoration(labelText: 'عنوان التسليم', border: OutlineInputBorder()),
        ),
        LocationRow(
          label: 'موقع التسليم',
          value: _to,
          mapStart: _from,
          onChanged: (v) {
            _to = v;
            _requote();
          },
        ),
        const Divider(height: 24),
        _row('التوصيل', _fee == null ? '—' : dinar(_fee!)),
        if (purchase) _row('رسوم الخدمة', dinar(_serviceFee)),
        _row(
          purchase ? 'تدفع كاش: ثمن الفاتورة + التوصيل + الخدمة' : 'تدفع كاش للتوصيل',
          _fee == null ? '—' : dinar(_fee! + (purchase ? _serviceFee : 0)) + (purchase ? ' + الفاتورة' : ''),
          bold: true,
        ),
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
                : const Text('اطلب ليفرور'),
          ),
        ),
      ],
    );
  }

  Widget _row(String k, String v, {bool bold = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Flexible(child: Text(k, style: TextStyle(fontWeight: bold ? FontWeight.bold : null))),
          const SizedBox(width: 8),
          Text(v, style: TextStyle(fontWeight: bold ? FontWeight.bold : null)),
        ]),
      );
}
