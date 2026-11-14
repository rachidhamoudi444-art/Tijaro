import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

/// وسط مدينة تيبازة (نقطة بداية الخريطة).
const tipazaCenter = LatLng(36.5897, 2.4475);

/// الموقع الحالي، أو null إذا رُفض الإذن أو كان GPS مغلقاً.
Future<LatLng?> currentLocation() async {
  try {
    if (!await Geolocator.isLocationServiceEnabled()) return null;
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
      return null;
    }
    final p = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        timeLimit: Duration(seconds: 10),
      ),
    );
    return LatLng(p.latitude, p.longitude);
  } catch (_) {
    return null;
  }
}
