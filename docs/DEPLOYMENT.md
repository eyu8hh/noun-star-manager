# Deployment and first-run checklist

## 1. Supabase (one-time)

This repository is configured for a dedicated Supabase project.

1. Open the project's SQL Editor.
2. Review supabase/schema.sql, then run it once on a fresh project. It creates the tables, owner-scoped RLS policies, ownership-check triggers, auth bootstrap trigger, and the training, competition, and suspension structures.
3. Run supabase/verify.sql and inspect the results:
   - all expected public tables should exist and have RLS enabled;
   - each business table should have an owner-only policy, and profiles should be self-scoped;
   - security-definer trigger functions should have an empty search_path and no direct EXECUTE permission for anon or authenticated.
4. In Authentication → Settings, disable public sign-ups. Keep the coach account as a manually created user. The schema backfills profiles and settings for existing Auth users.
5. Never place a service-role or secret key in index.html. The browser uses only the publishable key.

Important: schema.sql is a bootstrap for a fresh dedicated project. Do not run it over an existing installation. For an older installation, apply the incremental migrations listed in README.md in order after reviewing them.

## 2. GitHub Pages

1. Open repository settings: https://github.com/eyu8hh/noun-star-manager/settings/pages.
2. Under Build and deployment, choose GitHub Actions as the source.
3. Open the Actions tab, select Deploy NOUN STAR MANAGER to GitHub Pages, and run Run workflow on main.
4. When the workflow completes, open the Pages URL shown in its deployment summary.

The deployment workflow publishes only index.html; all fonts and front-end code are embedded in that file. Supabase remains the cloud backend.

## 3. Acceptance checks after deployment

- Sign in with the coach account on both the phone and computer.
- Create a temporary club, team, and player; confirm they appear on the other device after refresh.
- Create and finish a test match, then reopen it; verify the score, events, and suspension ledger behave correctly.
- Create a custom drill, draw and animate its stages, attach it to a training session, and confirm it appears on the other device.
- Export and restore a JSON backup, then test drill-bank JSON export/import.
- Test Arabic RTL and French LTR at a 400px mobile viewport.
- Load the demo dataset, inspect it, then use the confirmed reset and verify that coach login/preferences remain.

Do not enter real player data until the SQL verification and cross-device tests pass.
