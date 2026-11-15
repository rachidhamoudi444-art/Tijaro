import 'package:flutter/material.dart' hide Text;
import 'i18n.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import 'location.dart';

/// شاشة اختيار موقع على الخريطة: يحرّك المستخدم الخريطة والدبوس ثابت في الوسط.
class LocationPickerScreen extends StatefulWidget {
  final LatLng? initial;
  final String title;
  const LocationPickerScreen({super.key, this.initial, this.title = 'حدّد الموقع'});

  @override
  State<LocationPickerScreen> createState() => _LocationPickerScreenState();
}

class _LocationPickerScreenState extends State<LocationPickerScreen> {
  final MapController _controller = MapController();
  late LatLng _center = widget.initial ?? tipazaCenter;

  Future<void> _goToMe() async {
    final loc = await currentLocation();
    if (!mounted) return;
    if (loc == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذّر تحديد موقعك. فعّل GPS وامنح الإذن.')),
      );
      return;
    }
    _controller.move(loc, 16);
    _center = loc;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _controller,
            options: MapOptions(
              initialCenter: _center,
              initialZoom: 15,
              onPositionChanged: (camera, hasGesture) {
                _center = camera.center;
              },
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                fallbackUrl: 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Street_Map/MapServer/tile/{z}/{y}/{x}',
                userAgentPackageName: 'dz.tipaza.delivery.delivery_app',
                maxZoom: 19,
              ),
              const RichAttributionWidget(
                alignment: AttributionAlignment.bottomLeft,
                attributions: [
                  TextSourceAttribution('© OpenStreetMap contributors'),
                ],
              ),
            ],
          ),
          // طرف الدبوس يقع على مركز الخريطة تماماً
          const Center(
            child: Padding(
              padding: EdgeInsets.only(bottom: 40),
              child: Icon(Icons.location_pin, size: 48, color: Colors.red),
            ),
          ),
          Positioned(
            right: 16,
            top: 16,
            child: FloatingActionButton.small(
              heroTag: 'my_location',
              onPressed: _goToMe,
              child: const Icon(Icons.my_location),
            ),
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 24,
            child: FilledButton(
              onPressed: () => Navigator.pop(context, _center),
              child: const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text('تأكيد هذا الموقع'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// سطر يعرض الموقع المختار وزر فتح الخريطة.
class LocationRow extends StatelessWidget {
  final String label;
  final LatLng? value;
  final LatLng? mapStart;
  final ValueChanged<LatLng> onChanged;

  const LocationRow({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.mapStart,
  });

  @override
  Widget build(BuildContext context) {
    final v = value;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(Icons.place, color: v == null ? Colors.grey : Colors.green),
      title: Text(label),
      subtitle: Text(v == null ? 'لم يُحدَّد بعد' : 'تم تحديد الموقع على الخريطة'),
      trailing: TextButton(
        child: const Text('الخريطة'),
        onPressed: () async {
          final picked = await Navigator.push<LatLng>(
            context,
            MaterialPageRoute(
              builder: (_) => LocationPickerScreen(initial: v ?? mapStart, title: label),
            ),
          );
          if (picked != null) onChanged(picked);
        },
      ),
    );
  }
}
