# NOUN STAR MANAGER

Mobile-first football team management for a coach. Arabic RTL by default, with French LTR switching.

## Agreed product constraints
- Single self-contained `index.html` application (HTML/CSS/JavaScript; no external UI libraries).
- Supabase authentication and private cloud synchronization across the coach's devices, with safe refresh on focus and a 60-second refresh interval when no form is being edited.
- One manually created coach account; public sign-up must remain disabled.
- JSON backup and restore.
- Charcoal `#101116`, royal blue `#172D9B`, white `#FFFFFF`, ice grey `#DDE2EB`.
- Cairo interface text and Barlow Condensed display numbers are embedded as WOFF2 in the single HTML file; their SIL Open Font License notices are included under `LICENSES/`.
- No unapproved features outside the agreed scope.

## Planned modules
1. Dashboard and attention-needed summary.
2. Clubs, age-group teams, players, and player team-history snapshots.
3. Matches, lineups, substitutions, match events, and player minutes.
4. Competitions, standings, and target-position calculations.
5. Training sessions, attendance, a tactical drill library, and a custom drill-board builder.
6. Player statistics and CSV export.
7. Discipline and suspension tracking.
8. Injuries, recovery, and absences.
9. Settings, Arabic/French localization, and JSON backup/restore.

## Embedded fonts and licensing
The single-file app embeds Cairo Arabic/Latin (400 and 700) and Barlow Condensed Latin (600 and 700) as WOFF2 data. The original SIL Open Font License notices are included in `LICENSES/Cairo-OFL.txt` and `LICENSES/Barlow-Condensed-OFL.txt`.

## Structure
```
/
├── index.html
├── supabase/
│   ├── schema.sql
│   └── migrations/
│       ├── 20261118_reversible_suspension_accounting.sql
│       ├── 20261118_manual_match_stats.sql
│       ├── 20261118_competition_manual_results.sql
│       └── 20261118_training_drill_library.sql
└── docs/
    └── ROADMAP.md
```


## Training centre
- Sixteen original bilingual Arabic/French drills are bundled in the single HTML app: rondo 4v2, third-man combination, counter-pressing, build-up from the back, fast attacking transition, crossing/finishing, reaction speed, and compact defensive block.
- Each drill includes its objective, organisation, player count, age group, duration, equipment, coaching points, match application, progressive stages, and an SVG tactical board.
- Coaches can place and drag player/defender/ball/cone markers, draw movement arrows, and step through animated explanations. Coaches can create drills, copy a built-in drill into their own library, and import/export their personal drill bank as JSON. Custom drills are stored in the coach-owned Supabase library after the training migration is applied.
- Training sessions can be linked to multiple drills through training_session_drills.
- External learning references: [FIFA Training Centre — Grassroots](https://www.fifatrainingcentre.com/en/practice/grassroots.php), [FIFA Training Centre — Talent Development](https://www.fifatrainingcentre.com/en/practice/talent_development.php), and [UEFA Grassroots Coaching](https://www.uefa.com/grassroots-coaching/). The app links to these sources rather than copying protected content.
- Settings include an opt-in demo dataset and a separately confirmed full team-data reset that preserves the coach login and preferences. The tactical board is an animated SVG stage navigator, not a full physics-based animation or video editor.

## Supabase bootstrap status
`supabase/schema.sql` is the complete bootstrap schema for a fresh, dedicated Supabase project. It includes owner-scoped RLS, cross-owner reference checks, reversible suspension accounting, the private drill library, session-to-drill links, and manually tracked opponent fixtures. For a fresh project, review and apply this bootstrap once. For a project that already has the earlier base schema, review and apply the incremental migrations in order: `20261118_reversible_suspension_accounting.sql`, `20261118_manual_match_stats.sql`, `20261118_competition_manual_results.sql`, then `20261118_training_drill_library.sql`. Do not run the fresh bootstrap over an existing database. None of these SQL changes has been executed against the live Supabase project or validated by a live PostgreSQL run.

After the schema is reviewed and applied:
1. Disable public sign-ups in Supabase Authentication settings.
2. Create the coach account manually in Authentication → Users.
3. Use only the publishable key in browser code. Never expose a service-role or secret key.
4. Verify authenticated access and anonymous denial before entering real player data.

## Delivery status
The responsive single-file application in `index.html` now includes the coach login shell, Arabic/French switching, dark/light theme, dashboard counts, CRUD for clubs/teams/players, player team assignment with basic transfer history, match scheduling and score entry, finish/reopen controls, match lineups (starter/substitute/not-selected/manual-stat rows, shirt numbers, and minute fields), match event logging (goals, assists, cards, substitutions, notes) with substitution-event-driven lineup minute reconciliation, and competition/team-entry screens with editable manual opponent results (played, W/D/L, goals, remaining fixtures, point adjustments), standings calculations for the coach's teams, and a conservative target-position feasibility estimate based on registered remaining fixtures (not a statistical probability). Training sessions and attendance, plus injury and absence records, are implemented at a basic CRUD level. The health and discipline flows also synchronize player availability with active injury/suspension records when those records or match outcomes change. The training module now also contains an original multi-category drill bank, interactive SVG tactical board with draggable tokens and movement arrows, per-stage Arabic/French descriptions, animated movement between stages, coach-created drills, and multi-drill session linking; custom drill persistence and session links require the new SQL migration. Basic player statistics and UTF-8 CSV export are included; appearance counts now use finished matches and count actual participation rather than every selected substitute. The player list is grouped by position with team/position filters and opens a career profile with appearances, minutes, goals, assists, cards, team history, health/absence history, and match-event log. The discipline module now summarizes cards, applies a configurable yellow-card threshold, records coach-confirmed suspension proposals, and synchronizes player availability with active/served suspensions. Automatic match-by-match suspension decrement/reversal is now implemented in SQL as a transactional, idempotent ledger: finalizing a qualifying team match consumes one match, while reopening or deleting it restores the prior state. This database behavior is not live-verified until the migration is applied. Player team-transfer snapshots now capture appearances, minutes, goals, assists, and cards from finished matches. Career profiles aggregate finished-match appearances, minutes, goals, assists, cards, and event history. Manual player minutes/goals/assists/cards can also be entered without a lineup; these workflows still need live-browser verification. Advanced season-by-season comparisons remain pending. JSON backup/restore is implemented as merge-based import/export. GitHub Actions validates inline JavaScript syntax, all literal DOM IDs referenced by the app, duplicate IDs, Arabic/French translation coverage, and the existence of statically referenced database tables. The publishable key is embedded in the client configuration; it is intended for browser use and must be protected by correct RLS. Cloud saves are shared through Supabase; other open devices refresh when focused and every 60 seconds when idle (this is polling, not push-based realtime). No live deployment, database execution, Supabase end-to-end test, or mobile browser QA is claimed.


## Training library
The training area includes 16 original bilingual Arabic/French drills across technical, tactical, physical, finishing, and transition themes. Each drill contains its objective, organisation, coaching points, match application, and staged pitch diagrams with animated player/ball movement. Coaches can create their own drills, copy a built-in drill into their editable library, and import/export personal drills as JSON. The training session planner supports multiple ordered drills and a duration estimate. External learning links point to the official [FIFA Training Centre grassroots library](https://www.fifatrainingcentre.com/en/practice/grassroots.php), [FIFA talent-development practices](https://www.fifatrainingcentre.com/en/practice/talent_development.php), and [UEFA grassroots coaching](https://www.uefa.com/grassroots-coaching/); external material is referenced rather than copied.

Settings also provide an opt-in demo dataset and a separately confirmed full team-data reset. The reset preserves the coach account and settings. These workflows still require live Supabase verification.
