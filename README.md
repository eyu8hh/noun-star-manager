# NOUN STAR MANAGER

Mobile-first football team management for a coach. Arabic RTL by default, with French LTR switching.

## Agreed product constraints
- Single self-contained `index.html` application (HTML/CSS/JavaScript; no external UI libraries).
- Supabase authentication and private cloud synchronization across the coach's devices.
- One manually created coach account; public sign-up must remain disabled.
- JSON backup and restore.
- Charcoal `#101116`, royal blue `#172D9B`, white `#FFFFFF`, ice grey `#DDE2EB`.
- Cairo interface text and Barlow Condensed display numbers, embedded only when properly licensed font files are available.
- No unapproved features outside the agreed scope.

## Planned modules
1. Dashboard and attention-needed summary.
2. Clubs, age-group teams, players, and player team-history snapshots.
3. Matches, lineups, substitutions, match events, and player minutes.
4. Competitions, standings, and target-position calculations.
5. Training sessions and attendance.
6. Player statistics and CSV export.
7. Discipline and suspension tracking.
8. Injuries, recovery, and absences.
9. Settings, Arabic/French localization, and JSON backup/restore.

## Structure
```
/
├── index.html
├── supabase/
│   └── schema.sql
└── docs/
    └── ROADMAP.md
```

## Supabase bootstrap status
`supabase/schema.sql` is the bootstrap schema for a fresh, dedicated Supabase project. It includes owner-scoped RLS, cross-owner reference checks, and a reversible suspension accounting trigger. `supabase/migrations/20261118_reversible_suspension_accounting.sql` contains the incremental suspension-ledger change for a project where the base schema was already applied. Neither SQL file has been executed against the live Supabase project or validated by a live PostgreSQL run. Review the correct path before applying; do not run the fresh bootstrap over an existing database.

After the schema is reviewed and applied:
1. Disable public sign-ups in Supabase Authentication settings.
2. Create the coach account manually in Authentication → Users.
3. Use only the publishable key in browser code. Never expose a service-role or secret key.
4. Verify authenticated access and anonymous denial before entering real player data.

## Delivery status
The responsive single-file application in `index.html` now includes the coach login shell, Arabic/French switching, dark/light theme, dashboard counts, CRUD for clubs/teams/players, player team assignment with basic transfer history, match scheduling and score entry, finish/reopen controls, match lineups (starter/substitute/not-selected, shirt numbers, and minute fields), match event logging (goals, assists, cards, substitutions, notes), and competition/team-entry screens with standings calculations for the coach's teams. Training sessions and attendance, plus injury and absence records, are now implemented at a basic CRUD level. Basic player statistics and UTF-8 CSV export are included. The discipline module now summarizes cards, applies a configurable yellow-card threshold, and records coach-confirmed suspension proposals. Automatic match-by-match suspension decrement/reversal is now implemented in SQL as a transactional, idempotent ledger: finalizing a qualifying team match consumes one match, while reopening or deleting it restores the prior state. This database behavior is not live-verified until the migration is applied. Target-position calculations, career-stat snapshots, and several deeper workflows remain pending. JSON backup/restore is implemented as merge-based import/export. A GitHub Actions check parses the inline JavaScript and checks core HTML IDs. The publishable key is embedded in the client configuration; it is intended for browser use and must be protected by correct RLS. No live deployment, database execution, Supabase end-to-end test, or mobile browser QA is claimed.
