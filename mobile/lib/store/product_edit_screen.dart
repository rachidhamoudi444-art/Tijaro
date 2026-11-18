import 'package:flutter/material.dart' hide Text;
import 'package:flutter/material.dart' as m show Text;
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/api.dart';
import '../core/i18n.dart';
import '../core/product_detail.dart';

/// إضافة/تعديل منتج: الاسم، السعر، صور (حتى 6)، فيديو (واحد)، وسكريبت يرافقها.
class ProductEditScreen extends StatefulWidget {
  final String storeId;
  final Map<String, dynamic>? product;
  const ProductEditScreen({super.key, required this.storeId, this.product});

  @override
  State<ProductEditScreen> createState() => _ProductEditScreenState();
}

class _ProductEditScreenState extends State<ProductEditScreen> {
  static const _bucket = 'product-media';
  static const _maxVideoBytes = 45 * 1024 * 1024;

  late String? _id = widget.product?['id'] as String?;
  late final _name = TextEditingController(text: '${widget.product?['name'] ?? ''}');
  late final _price = TextEditingController(
      text: widget.product == null ? '' : asNum(widget.product!['price']).toStringAsFixed(0));
  late final _script = TextEditingController(text: '${widget.product?['script'] ?? ''}');
  List<Map<String, dynamic>> _media = [];
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    if (_id != null) _loadMedia();
  }

  @override
  void dispose() {
    _name.dispose();
    _price.dispose();
    _script.dispose();
    super.dispose();
  }

  void _snack(String msg) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _loadMedia() async {
    final rows = await db.from('product_media').select().eq('product_id', _id!).order('sort').order('created_at');
    if (mounted) setState(() => _media = [for (final r in rows) Map<String, dynamic>.of(r)]);
  }

  /// يحفظ بيانات المنتج (وينشئه إن كان جديداً). يرجع false إن كانت البيانات ناقصة.
  Future<bool> _ensureSaved() async {
    final n = _name.text.trim();
    final pr = num.tryParse(_price.text.trim());
    if (n.isEmpty || pr == null || pr < 0) {
      _snack('أدخل اسماً وسعراً صحيحاً');
      return false;
    }
    final script = _script.text.trim();
    final data = {'name': n, 'price': pr, 'script': script.isEmpty ? null : script};
    if (_id == null) {
      final row = await db.from('products').insert({'store_id': widget.storeId, ...data}).select('id').single();
      _id = row['id'] as String;
    } else {
      await db.from('products').update(data).eq('id', _id!);
    }
    return true;
  }

  /// الغلاف = أول صورة، ويُخزَّن في products.image_url لتظهر في القوائم.
  Future<void> _syncCover() async {
    final firstImage = _media.where((x) => x['kind'] == 'image').toList();
    await db.from('products').update({'image_url': firstImage.isEmpty ? null : firstImage.first['url']}).eq('id', _id!);
  }

  Future<void> _addImage(ImageSource src) async {
    if (_media.where((x) => x['kind'] == 'image').length >= 6) {
      _snack('الحد الأقصى 6 صور لكل منتج');
      return;
    }
    final x = await ImagePicker().pickImage(source: src, maxWidth: 1600, imageQuality: 80);
    if (x != null) await _upload(x, 'image');
  }

  Future<void> _addVideo() async {
    if (_media.any((x) => x['kind'] == 'video')) {
      _snack('فيديو واحد لكل منتج');
      return;
    }
    final x = await ImagePicker().pickVideo(source: ImageSource.gallery, maxDuration: const Duration(seconds: 60));
    if (x == null) return;
    if (await x.length() > _maxVideoBytes) {
      _snack('الفيديو كبير (الحد 45 ميغا). اختر فيديو أقصر.');
      return;
    }
    await _upload(x, 'video');
  }

  Future<void> _upload(XFile x, String kind) async {
    setState(() => _busy = true);
    try {
      if (!await _ensureSaved()) return;
      final bytes = await x.readAsBytes();
      final isPng = x.path.toLowerCase().endsWith('.png');
      final ext = kind == 'video' ? 'mp4' : (isPng ? 'png' : 'jpg');
      final ct = kind == 'video' ? 'video/mp4' : (isPng ? 'image/png' : 'image/jpeg');
      final path = '${widget.storeId}/$_id/${DateTime.now().millisecondsSinceEpoch}.$ext';
      await db.storage.from(_bucket).uploadBinary(path, bytes, fileOptions: FileOptions(contentType: ct));
      final url = db.storage.from(_bucket).getPublicUrl(path);
      await db.from('product_media').insert({
        'product_id': _id,
        'store_id': widget.storeId,
        'kind': kind,
        'url': url,
        'path': path,
        'sort': _media.length,
      });
      await _loadMedia();
      await _syncCover();
    } catch (e) {
      _snack(friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _remove(Map<String, dynamic> it) async {
    setState(() => _busy = true);
    try {
      await db.storage.from(_bucket).remove([it['path'] as String]);
      await db.from('product_media').delete().eq('id', it['id']);
      await _loadMedia();
      await _syncCover();
    } catch (e) {
      _snack(friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _makeCover(Map<String, dynamic> it) async {
    setState(() => _busy = true);
    try {
      final minSort = _media.map((x) => (x['sort'] as num).toInt()).fold<int>(0, (a, b) => a < b ? a : b);
      await db.from('product_media').update({'sort': minSort - 1}).eq('id', it['id']);
      await _loadMedia();
      await _syncCover();
    } catch (e) {
      _snack(friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    try {
      if (await _ensureSaved() && mounted) Navigator.pop(context, true);
    } catch (e) {
      _snack(friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _preview() async {
    setState(() => _busy = true);
    try {
      if (!await _ensureSaved() || !mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ProductDetailScreen(
            productId: _id!,
            name: _name.text.trim(),
            price: num.parse(_price.text.trim()),
            script: _script.text,
          ),
        ),
      );
    } catch (e) {
      _snack(friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _addMenu() {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Wrap(children: [
          ListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: const Text('صورة من المعرض'),
            onTap: () {
              Navigator.pop(ctx);
              _addImage(ImageSource.gallery);
            },
          ),
          ListTile(
            leading: const Icon(Icons.photo_camera_outlined),
            title: const Text('التقاط صورة'),
            onTap: () {
              Navigator.pop(ctx);
              _addImage(ImageSource.camera);
            },
          ),
          ListTile(
            leading: const Icon(Icons.videocam_outlined),
            title: const Text('فيديو من المعرض (حتى دقيقة)'),
            onTap: () {
              Navigator.pop(ctx);
              _addVideo();
            },
          ),
        ]),
      ),
    );
  }

  Widget _tile(Map<String, dynamic> it, int index) {
    final isVideo = it['kind'] == 'video';
    final isCover = !isVideo && _media.where((x) => x['kind'] == 'image').first['id'] == it['id'];
    return PopupMenuButton<String>(
      onSelected: (v) => v == 'del' ? _remove(it) : _makeCover(it),
      itemBuilder: (_) => [
        if (!isVideo && !isCover) PopupMenuItem(value: 'cover', child: Text('جعلها الغلاف')),
        PopupMenuItem(value: 'del', child: Text('حذف')),
      ],
      child: Stack(children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: SizedBox(
            width: 96,
            height: 96,
            child: isVideo
                ? Container(
                    color: Colors.black87,
                    child: const Center(child: Icon(Icons.play_circle_fill, color: Colors.white, size: 36)),
                  )
                : Image.network(it['url'] as String, fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const Icon(Icons.broken_image_outlined)),
          ),
        ),
        if (isCover)
          Positioned(
            left: 4,
            top: 4,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary, borderRadius: BorderRadius.circular(8)),
              child: const Text('الغلاف', style: TextStyle(color: Colors.white, fontSize: 11)),
            ),
          ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final images = _media.where((x) => x['kind'] == 'image').length;
    final hasVideo = _media.any((x) => x['kind'] == 'video');
    return Scaffold(
        appBar: AppBar(
          title: Text(widget.product == null ? 'منتج جديد' : 'تعديل المنتج'),
          actions: [
            TextButton(onPressed: _busy ? null : _save, child: const Text('حفظ')),
          ],
        ),
        body: Stack(children: [
          ListView(
            padding: const EdgeInsets.all(16),
            children: [
              TextField(controller: _name, decoration: InputDecoration(labelText: tr('اسم المنتج'))),
              const SizedBox(height: 12),
              TextField(
                controller: _price,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(labelText: tr('السعر (دج)')),
              ),
              const SizedBox(height: 20),
              Row(children: [
                Expanded(
                  child: Text('الصور والفيديو', style: Theme.of(context).textTheme.titleMedium),
                ),
                m.Text('$images/6 • ${hasVideo ? 1 : 0}/1', style: Theme.of(context).textTheme.bodySmall),
              ]),
              const SizedBox(height: 10),
              Wrap(spacing: 10, runSpacing: 10, children: [
                for (var i = 0; i < _media.length; i++) _tile(_media[i], i),
                InkWell(
                  onTap: _busy ? null : _addMenu,
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    width: 96,
                    height: 96,
                    decoration: BoxDecoration(
                      border: Border.all(color: Theme.of(context).colorScheme.primary, width: 1.5),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(Icons.add_a_photo_outlined, color: Theme.of(context).colorScheme.primary),
                  ),
                ),
              ]),
              const SizedBox(height: 6),
              Text('اضغط على أي صورة للحذف أو جعلها الغلاف. الصورة الأولى هي التي تظهر في القوائم.',
                  style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 20),
              Text('السكريبت (نص يرافق الصور والفيديو)', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              TextField(
                controller: _script,
                minLines: 5,
                maxLines: 12,
                maxLength: 2000,
                decoration: InputDecoration(
                  hintText: tr('اكتب وصف المنتج ومميزاته وطريقة استعماله... يظهر للزبون تحت الصور والفيديو.'),
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _busy ? null : _preview,
                icon: const Icon(Icons.visibility_outlined),
                label: const Text('معاينة كما يراها الزبون'),
              ),
              const SizedBox(height: 40),
            ],
          ),
          if (_busy)
            Positioned.fill(
              child: Container(
                color: Colors.black26,
                child: const Center(child: CircularProgressIndicator()),
              ),
            ),
        ]),
    );
  }
}
