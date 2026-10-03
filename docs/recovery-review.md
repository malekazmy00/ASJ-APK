# Supabase recovery review — 3 October 2026

The recovery project is `qdbisozoknncbqtgsmpc` in the free ASJ Recovery organization. Its database was restored from the 29 September backup, including 958 inventory items, 25,440 knowledge records, five application users, storage bucket metadata, and application migration history. GitHub integration points to `malekazmy00/ASJ-APK`; automatic production deployment and preview branches are disabled during recovery.

## Changes prepared

- Validate every signed session against the current account status and role. Deleted, suspended, demoted, or password-revoked accounts cannot keep their previous authorization. Database verification errors fail closed.
- Reject missing or short signing secrets and restrict token verification to HS256.
- Protect Gemini diagnostics with an administrator session, bound upstream requests to ten seconds, and avoid returning raw upstream errors.
- Fetch only safe user fields in Flutter; restrict anonymous database reads to those columns, excluding password hashes.
- Revoke sensitive RPC execution from `PUBLIC` as well as `anon` and `authenticated`. PostgreSQL's default `PUBLIC` grant otherwise defeats a direct-role revoke.
- Make the grouped inventory view use its caller's permissions.
- Recover the four production migrations missing from this repository, preserving their real recorded versions. Preserve explicit timestamps in the deployed Edge Function behavior.

The database permission migration has been applied to the recovery project. Application and Edge Function changes must still be deployed.

## Required before building a release APK

1. Resolve database authorization: the original app intentionally uses custom JWTs and direct anonymous PostgREST calls. The new database has RLS enabled on every application table, with no policies, so those direct calls currently cannot access its rows. Merely switching URL/key or adding policies that allow everyone would not provide account authorization. Adapt authenticated data access before declaring the app operational.
2. Deploy all 15 Edge Functions and configure a strong `APP_JWT_SECRET`. Old secret values are not in database backups. Gemini keys must be supplied separately if AI features are needed.
3. Set Codemagic's `SUPABASE_URL` and `SUPABASE_ANON_KEY` to the new project. The existing APK keeps the URL embedded when it was built and needs replacement.
4. Confirm Android signing continuity with the existing APK. This repository generates Android files with `flutter create`; it does not configure a persistent release keystore. A build with a different certificate cannot update an already installed APK.
5. Reconcile the legacy manually applied migrations before enabling automated database deployment; historical database versions do not cover every `000`–`017` source file.

## Validation

- All 15 Edge Function entrypoints pass `deno check`.
- Four session identity tests pass, including demotion, suspension/deletion, password revocation, and malformed account data.
- Database checks confirm sensitive RPCs are unavailable to `anon` and remain callable by `service_role`.
- Restore row counts match the backup for every imported application table.
- Flutter analysis is pending while the local SDK dependencies are being installed. No APK build or device test has been performed.

