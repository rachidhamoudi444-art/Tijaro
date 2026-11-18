# Ownership evidence file (technical facts only)

This file lists verifiable technical facts. It is NOT a legal opinion. Have a lawyer review it.

## Assets and who controls them
| Asset | Fact | How to verify |
|---|---|---|
| Source repository | GitHub `rachidhamoudi444-art/tijaro`, created 2026-11-14, owner = the founder's personal GitHub account | GitHub -> repository -> Settings |
| Database / backend | Supabase project `tijaro` (ref `gsoiylzuntqlcshlfnqu`, region eu-west-3, created 2026-11-14) | Supabase dashboard -> Organization -> Members (confirm you are *Owner*) |
| Brand / logo | Name "Tijaro / تيجارو", logo and Tipaza cover photo supplied by the founder | Keep the original files |
| Android signing key | Private keystore generated 2026-11-18, held by the founder (GitHub secret + offline copy) | `keytool -list -v -keystore <file>` |
| Domain, Play Store account, Apple account, company registration | **None exist yet** | to be created |

## Development history (git)
All commits are authored by the AI coding assistant "Claude" working at the founder's direction in the founder's account
(co-author lines are in each commit). This should be disclosed to investors; do not rewrite history to hide it.

| Date | Commit | Summary |
|---|---|---|
| 2026-11-14 | 5f26757 | Initial commit: Tijaro v0.2 (Supabase schema, tests, Flutter customer + courier apps, CI) |
| 2026-11-14 | c50b629 | CI: disable Android lint on release build (lint tool crash) |
| 2026-11-14 | 54be8f3 | CI: publish APK as a GitHub release asset |
| 2026-11-15 | 67d2cd8 | Add public Supabase config (publishable key only) |
| 2026-11-15 | ea127bf | White theme, 21 store categories, Algerian-mobile phone validation, maps fix + Google Maps |
| 2026-11-15 | 3b53550 | Apply theme/categories/phone validation code and fixed signing key |
| 2026-11-15 | ae9a8aa | Maps: OpenStreetMap primary, Esri fallback (CARTO needs API key) |
| 2026-11-15 | f574d12 | Store owner screen, nearest-courier dispatch on ready, courier live location |
| 2026-11-15 | d2b5cea | Arabic/French language switch, brand logo and app icon, Tipaza banner |
| 2026-11-15 | 29851af | Fix const context for translated hint text |
| 2026-11-15 | 8b975db | Real logo and Tipaza cover, header logo, category colors |
| 2026-11-16 | f95e03f | Three apps from one codebase: customer, driver, business (APP_MODE) + CI matrix |
| 2026-11-16 | bb8df5a | Courier: call attempts, arrived, wait timer, not-delivered, store-fault; contact RPC |
| 2026-11-16 | fdf8f5e | Wilayas/communes: 7 wilayas, 220 communes, gated by admin; customer picks wilaya then comm |
| 2026-11-18 | e2fd427 | Product photos/videos/script (merchant upload + customer detail page); fix app icons (rena |

## Recommended steps to strengthen ownership (to confirm with a lawyer)
1. Complete the legal owner name in `LICENSE`; create a company or auto-entrepreneur registration and assign the IP to it in writing.
2. Check how copyright in AI-assisted code is treated in Algerian law; consider registering the software with ONDA and the
   brand "Tijaro" with INAPI (verify current procedures).
3. Keep the repository private; keep all admin accounts (GitHub, Supabase, Google, domain) on accounts you personally own with 2-factor authentication.
4. Keep an offline encrypted backup (see `scripts/backup.sh`) and the private keystore.
5. Contractors/developers must sign an IP-assignment agreement before getting repository access.
