import 'package:flutter/material.dart' hide Text;
import 'package:flutter/material.dart' as m show Text;
import 'package:video_player/video_player.dart';

import 'api.dart';
import 'i18n.dart';
import 'labels.dart';

/// صفحة المنتج: معرض صور وفيديو + السكريبت. تُستعمل عند الزبون (مع أزرار الكمية)
/// وعند التاجر كمعاينة (بدون كمية).
class ProductDetailScreen extends StatefulWidget {
  final String productId;
  final String name;
  final num price;
  final String? script;
  final int Function()? getQty;
  final void Function(int delta)? onChange;

  const ProductDetailScreen({
    super.key,
    required this.productId,
    required this.name,
    required this.price,
    this.script,
    this.getQty,
    this.onChange,
  });

  @override
  State<ProductDetailScreen> createState() => _ProductDetailScreenState();
}

class _ProductDetailScreenState extends State<ProductDetailScreen> {
  late final Future<List<Map<String, dynamic>>> _media = _load();
  int _page = 0;

  Future<List<Map<String, dynamic>>> _load() async {
    final rows = await db
        .from('product_media')
        .select('kind,url,sort')
        .eq('product_id', widget.productId)
        .order('sort')
        .order('created_at');
    // الصور أولاً ثم الفيديو
    final list = [for (final r in rows) Map<String, dynamic>.of(r)];
    list.sort((a, b) => (a['kind'] == 'video' ? 1 : 0).compareTo(b['kind'] == 'video' ? 1 : 0));
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final script = widget.script?.trim() ?? '';
    final qty = widget.getQty?.call() ?? 0;
    return Scaffold(
      appBar: AppBar(title: m.Text(widget.name)),
      body: ListView(
        children: [
          FutureBuilder<List<Map<String, dynamic>>>(
            future: _media,
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return const AspectRatio(aspectRatio: 1, child: Center(child: CircularProgressIndicator()));
              }
              final media = snap.data ?? const <Map<String, dynamic>>[];
              if (media.isEmpty) {
                return AspectRatio(
                  aspectRatio: 16 / 10,
                  child: Container(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                    child: Icon(Icons.image_outlined, size: 48, color: Theme.of(context).colorScheme.outline),
                  ),
                );
              }
              return Column(children: [
                AspectRatio(
                  aspectRatio: 1,
                  child: PageView.builder(
                    itemCount: media.length,
                    onPageChanged: (i) => setState(() => _page = i),
                    itemBuilder: (_, i) {
                      final it = media[i];
                      final url = it['url'] as String;
                      return it['kind'] == 'video'
                          ? NetworkVideo(url: url)
                          : Image.network(url, fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => const Center(child: Icon(Icons.broken_image_outlined)));
                    },
                  ),
                ),
                if (media.length > 1)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      for (var i = 0; i < media.length; i++)
                        Container(
                          width: 8,
                          height: 8,
                          margin: const EdgeInsets.symmetric(horizontal: 3),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: i == _page ? Theme.of(context).colorScheme.primary : Colors.grey.shade300,
                          ),
                        ),
                    ]),
                  ),
              ]);
            },
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              m.Text(widget.name, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 4),
              m.Text(dinar(widget.price),
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Theme.of(context).colorScheme.primary)),
              if (script.isNotEmpty) ...[
                const SizedBox(height: 16),
                m.Text(script, style: Theme.of(context).textTheme.bodyLarge),
              ],
            ]),
          ),
        ],
      ),
      bottomNavigationBar: widget.onChange == null
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(children: [
                  if (qty > 0) ...[
                    IconButton(
                        icon: const Icon(Icons.remove_circle_outline),
                        onPressed: () => setState(() => widget.onChange!(-1))),
                    m.Text('$qty', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  ],
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () => setState(() => widget.onChange!(1)),
                      icon: const Icon(Icons.add_shopping_cart),
                      label: Text(qty > 0 ? 'زيادة الكمية' : 'أضف إلى السلة'),
                    ),
                  ),
                ]),
              ),
            ),
    );
  }
}

/// مشغّل فيديو بسيط من رابط: ضغطة للتشغيل/الإيقاف وشريط تقدّم.
class NetworkVideo extends StatefulWidget {
  final String url;
  const NetworkVideo({super.key, required this.url});

  @override
  State<NetworkVideo> createState() => _NetworkVideoState();
}

class _NetworkVideoState extends State<NetworkVideo> {
  late final VideoPlayerController _c = VideoPlayerController.networkUrl(Uri.parse(widget.url));
  bool _ready = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _c.initialize().then((_) {
      if (mounted) setState(() => _ready = true);
    }).catchError((_) {
      if (mounted) setState(() => _failed = true);
    });
    _c.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) return const Center(child: Icon(Icons.videocam_off_outlined, size: 40));
    if (!_ready) return const Center(child: CircularProgressIndicator());
    return GestureDetector(
      onTap: () => _c.value.isPlaying ? _c.pause() : _c.play(),
      child: Container(
        color: Colors.black,
        child: Stack(alignment: Alignment.center, children: [
          Center(child: AspectRatio(aspectRatio: _c.value.aspectRatio, child: VideoPlayer(_c))),
          if (!_c.value.isPlaying)
            const Icon(Icons.play_circle_fill, size: 64, color: Colors.white70),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: VideoProgressIndicator(_c, allowScrubbing: true),
          ),
        ]),
      ),
    );
  }
}
