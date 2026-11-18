# Handover guide for a developer

## Accounts you need access to
GitHub repo `rachidhamoudi444-art/tijaro` | Supabase project `gsoiylzuntqlcshlfnqu` (Owner/Admin) | (later) Google Play, Firebase, SMS provider, domain.

## Secrets (never in git)
| Secret | Where it lives | Purpose |
|---|---|---|
| `TIJARO_KEYSTORE_B64` | GitHub -> Settings -> Secrets and variables -> Actions | Android signing key (base64 of the keystore) |
| Supabase `service_role` key + DB password | Supabase dashboard -> Project Settings (API / Database) | server/admin use only |
| Publishable key + URL | `mobile/env.json` (public by design) | app -> Supabase |

## Build locally
```
cd mobile && flutter create . --org dz.tipaza.delivery --project-name delivery_app --platforms=android
flutter pub get
flutter run --dart-define=APP_MODE=customer --dart-define-from-file=env.json     # or driver / business
```
(then re-apply the manifest permissions INTERNET, ACCESS_FINE_LOCATION, ACCESS_COARSE_LOCATION as in CI)

## Recreate the backend in a new Supabase project
1. New project; Auth -> Providers: Email ON, *Confirm email* OFF, Phone OFF.
2. SQL editor: run `supabase/schema.sql`, then `supabase/storage.sql`, then (optional) `supabase/seed.sql`.
3. Put the new URL + publishable key in `mobile/env.json`; rebuild.
4. Restore data from a backup made with `scripts/backup.sh` if needed.

## Tests
`tests/01_flow_and_security.sql` against Postgres (see the `db-tests` job in CI). All 15 groups must pass.

## Known gaps / roadmap
See `docs/ARCHITECTURE.md` (Not built yet) and `docs/SECURITY.md` (Open items).
