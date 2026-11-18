# Third-party components (license summary)

Direct dependencies from `mobile/pubspec.yaml`. Licenses below are from general knowledge of these
packages and MUST be re-verified with an automated scan (`flutter pub deps` + a license checker) before due diligence.

| Package | Typical license |
|---|---|
| Flutter SDK, intl, url_launcher, shared_preferences, image_picker, video_player | BSD-3-Clause |
| supabase_flutter, geolocator, latlong2 | MIT / Apache-2.0 / MIT |
| flutter_map | BSD-3-Clause |
| flutter_launcher_icons (dev only) | MIT |

Data and services:
- Map tiles: OpenStreetMap standard tile servers (data ODbL, attribution required; the public tile servers are not meant for heavy
  commercial traffic) with an Esri fallback. **Replace with a commercial tile provider before public launch.**
- Backend: Supabase (PostgreSQL, Auth, Storage). Build: GitHub Actions.
