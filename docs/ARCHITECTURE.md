# Architecture

```
Flutter app (one codebase, 3 builds: APP_MODE=customer|driver|business)  --HTTPS-->  Supabase
   customer: dz.tipaza.delivery.delivery_app   driver: dz.tipaza.driver   business: dz.tipaza.business
Supabase = PostgreSQL 17 + Auth (phone+password via synthetic email <digits>@phone.local) + Storage (product-media)
CI = GitHub Actions: db-tests (postgres:16) -> build-apk x3 -> publish release "latest"
```

## Repository layout
- `mobile/lib/` Flutter source: `core/` (i18n ar/fr, theme, API, location, region picker, product detail), `customer/`, `store/`, `courier/`.
- `mobile/` has no `android/` folder: CI generates it with `flutter create` and patches the manifest/gradle (see `.github/workflows/ci.yml`).
- `supabase/schema.sql` full database (tables, RLS, functions); `storage.sql` bucket + policies; `seed.sql` demo data.
- `tests/` SQL test suite (15 groups) that runs against a local Postgres in CI.

## Core business rules (implemented in the database)
- COD only. Courier prepaid wallet (min 1000 DA), 10% commission on delivery fee, cash handover to the office.
- Delivery fee from store-to-customer distance (tiers in `pricing_tiers`). Orders go to the nearest eligible couriers first, then to all.
- Fault handling: 3 logged call attempts + arrival + wait before a customer fault; customer banned after 2 faults; compensation 50% (weekly cap).
- Cities: 7 wilayas / 220 communes preloaded; only communes with `is_active = true` are usable (admin toggles via RPC).

## Not built yet
Admin dashboard (web), push notifications, SMS OTP / password recovery, in-app calls, courier wallet UI, live tracking,
e-payment, iOS build, realtime (apps poll every 8-10 s).
