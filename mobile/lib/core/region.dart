import 'package:flutter/material.dart' hide Text;
import 'package:flutter/material.dart' as m show Text;

import 'api.dart';
import 'i18n.dart';

/// البلدية التي اختارها الزبون (null = لم يختر بعد).
final ValueNotifier<Map<String, dynamic>?> myCommune = ValueNotifier(null);

String regionName(Map<String, dynamic> r) =>
    ((appLang.value == 'fr' ? r['name_fr'] : r['name_ar']) ?? '') as String;

Future<void> loadMyCommune() async {
  final p = await db.from('profiles').select('commune_id').eq('id', db.auth.currentUser!.id).single();
  final id = p['commune_id'];
  if (id == null) {
    myCommune.value = null;
    return;
  }
  final c = await db.from('communes').select('id,name_ar,name_fr,wilaya_id').eq('id', id).single();
  myCommune.value = Map<String, dynamic>.of(c);
}

/// اختيار الولاية ثم البلدية. المفتوحة فقط قابلة للاختيار، والباقي يظهر "قريباً".
class RegionPickerScreen extends StatefulWidget {
  final bool mandatory;
  const RegionPickerScreen({super.key, this.mandatory = false});

  @override
  State<RegionPickerScreen> createState() => _RegionPickerScreenState();
}

class _RegionPickerScreenState extends State<RegionPickerScreen> {
  late Future<void> _load = _fetch();
  List<Map<String, dynamic>> _wilayas = [];
  List<Map<String, dynamic>> _communes = [];
  Map<String, dynamic>? _wilaya;
  bool _saving = false;

  Future<void> _fetch() async {
    final w = await db.from('wilayas').select('id,name_ar,name_fr').order('id');
    final c = await db.from('communes').select('id,wilaya_id,name_ar,name_fr,is_active').order('id');
    _wilayas = [for (final r in w) Map<String, dynamic>.of(r)];
    _communes = [for (final r in c) Map<String, dynamic>.of(r)];
  }

  bool _wilayaOpen(int id) => _communes.any((c) => c['wilaya_id'] == id && c['is_active'] == true);

  Future<void> _choose(Map<String, dynamic> c) async {
    setState(() => _saving = true);
    try {
      await db.rpc('set_my_commune', params: {'p_commune': c['id']});
      await loadMyCommune();
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final inWilaya = _wilaya != null;
    return PopScope(
      canPop: !widget.mandatory && !inWilaya,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && inWilaya) setState(() => _wilaya = null);
      },
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: !widget.mandatory || inWilaya,
          leading: inWilaya ? BackButton(onPressed: () => setState(() => _wilaya = null)) : null,
          title: Text(inWilaya ? 'اختر بلديتك' : 'اختر ولايتك'),
        ),
        body: FutureBuilder<void>(
          future: _load,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snap.hasError) {
              return Center(child: Padding(padding: const EdgeInsets.all(16), child: Text(friendlyError(snap.error!))));
            }
            final scheme = Theme.of(context).colorScheme;
            final items = inWilaya
                ? _communes.where((c) => c['wilaya_id'] == _wilaya!['id']).toList()
                : _wilayas;
            return Stack(children: [
              ListView.separated(
                padding: const EdgeInsets.only(bottom: 24),
                itemCount: items.length + 1,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, i) {
                  if (i == items.length) {
                    return const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text('سنفتح مدناً جديدة قريباً'),
                    );
                  }
                  final r = items[i];
                  final open = inWilaya ? r['is_active'] == true : _wilayaOpen(r['id'] as int);
                  return ListTile(
                    enabled: open,
                    leading: Icon(inWilaya ? Icons.location_city : Icons.map_outlined,
                        color: open ? scheme.primary : Colors.grey),
                    title: m.Text(regionName(r)),
                    trailing: open
                        ? Icon(inWilaya ? Icons.check_circle_outline : Icons.chevron_left)
                        : const Text('قريباً'),
                    onTap: !open || _saving
                        ? null
                        : () => inWilaya ? _choose(r) : setState(() => _wilaya = r),
                  );
                },
              ),
              if (_saving) const Center(child: CircularProgressIndicator()),
            ]);
          },
        ),
      ),
    );
  }
}
