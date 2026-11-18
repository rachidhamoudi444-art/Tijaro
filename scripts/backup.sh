#!/usr/bin/env bash
# Full backup of the Tijaro project (run from any computer with git, pg_dump and curl).
# Usage:  DB_URL='postgresql://postgres:<DB_PASSWORD>@db.<PROJECT_REF>.supabase.co:5432/postgres' ./scripts/backup.sh
# DB_URL: Supabase dashboard -> Project Settings -> Database -> Connection string (URI). Never commit it.
set -euo pipefail
OUT="tijaro-backup-$(date +%Y%m%d-%H%M)"
mkdir -p "$OUT"
git bundle create "$OUT/tijaro-repo.bundle" --all          # complete git history
pg_dump "$DB_URL" --schema=public --no-owner --no-privileges -Fc -f "$OUT/public.dump"   # tables + data + functions
pg_dump "$DB_URL" --schema=auth --data-only --no-owner -Fc -f "$OUT/auth-users.dump"     # accounts (contains password hashes: keep private)
echo "Storage files (product-media bucket): download from Supabase dashboard -> Storage, or use the Supabase CLI."
echo "Backup written to $OUT  (store it offline, encrypted)."
