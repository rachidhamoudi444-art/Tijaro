import 'package:flutter/material.dart';

import '../core/labels.dart';

/// بطاقة متجر (صورة، اسم، فئة، ومسافة إن عُرفت) كما في التصميم.
class StoreCard extends StatelessWidget {
  final Map<String, dynamic> store;
  final VoidCallback onTap;
  const StoreCard({super.key, required this.store, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final km = store['_km'];
    final url = store['image_url'] as String?;

    Widget placeholder() => Container(
          color: scheme.surfaceContainerHighest,
          alignment: Alignment.center,
          child: Icon(Icons.storefront, size: 40, color: scheme.onSurfaceVariant),
        );

    return Card(
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AspectRatio(
                aspectRatio: 1.6,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: (url == null || url.isEmpty)
                      ? placeholder()
                      : Image.network(
                          url,
                          fit: BoxFit.cover,
                          width: double.infinity,
                          errorBuilder: (_, __, ___) => placeholder(),
                        ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '${store['name']}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              Text(
                groupLabelOf(store['category']),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
              if (km is num)
                Text(
                  '${km.toStringAsFixed(1)} كم',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.primary),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
