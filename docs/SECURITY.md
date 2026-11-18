# Security model (what is enforced, and where)

- All 17 `public` tables have Row Level Security enabled. Clients may only read what policies allow; every
  money/state change goes through `SECURITY DEFINER` functions (RPC) that check the caller's role (`supabase/schema.sql`).
- Ledgers (`wallet_ledger`, `store_ledger`) are append-only (trigger `forbid_change`).
- The `anon` role has no access to application tables or functions.
- The 30 `SECURITY DEFINER` functions reported by the Supabase linter are intentional: they are the app's API and
  each one validates `auth.uid()` and the role inside.
- Storage bucket `product-media` is public-read; writes are limited to the owner of the store whose id is the first
  folder of the object path (`supabase/storage.sql`).
- The client only contains the Supabase URL and the *publishable* key (`mobile/env.json`). The `service_role` key
  and the database password are NOT in the repository and must never be.
- The Android signing key is a private keystore stored as GitHub secret `TIJARO_KEYSTORE_B64`.
- Tests: `tests/01_flow_and_security.sql` (15 groups) run in CI on every push.

Open items: enable leaked-password protection (Supabase Auth, Pro plan), SMS verification of phone numbers,
password recovery, independent security review, separate staging project.
