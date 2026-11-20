# Implementation roadmap

## Phase 0 — Foundation
- [x] Confirm product scope, single-file frontend, Arabic/French, and cloud-sync requirement.
- [x] Create the public GitHub repository.
- [x] Add project overview and initial Supabase schema draft.
- [ ] Review and apply the schema in the dedicated Supabase project.
- [ ] Verify coach authentication, RLS isolation, and cross-device persistence.

## Phase 1 — Application shell
- [x] Build the initial single-file `index.html` shell and visual identity (first implementation; module screens remain placeholders).
- [x] Add Arabic RTL / French LTR switching and responsive navigation.
- [x] Add direct Supabase Auth/REST initialization using the publishable key only (live connection not yet verified).
- [x] Add coach login/logout, refresh-token session handling, loading, empty, and error states (live Auth verification pending).
- [ ] Add safe local draft handling for unsaved forms; JSON backup/restore is implemented.

## Phase 2 — Club, team, and player management
- [x] Clubs and multiple age-group teams (CRUD, linked deletion).
- [x] Player CRUD, position, search, status, and team assignment.
- [x] Player career profile with appearances, minutes, goals, assists, cards, team-transfer snapshots, injury/absence history, and match-event log; player lists are grouped by position with team/position filters.
- [x] Current team assignment and transfer-history snapshots of appearances, minutes, goals, assists, and cards; player profiles aggregate career totals across finished matches.
- [x] Injury and suspension records synchronize the player's availability state (live data verification pending).

## Phase 3 — Matches
- [x] Fixture scheduling, match reports, score entry, and finish/reopen controls; reversible suspension accounting is implemented in SQL (live database test pending).
- [x] Starter/substitute/not-selected lineups with player positions, shirt numbers, and minute fields.
- [x] Manual goal, assist, card, substitution, and note events.
- [x] Substitution events reconcile entry/exit minutes into the lineup; unused substitutes do not count as appearances, and statistics are scoped to finished matches.
- [x] Manual player minutes, goals, assists, and cards when no tactical lineup is entered; schema migration committed (live test pending).

## Phase 4 — Competitions and discipline
- [x] Competition CRUD and team entries.
- [x] Standings from finished team matches and editable manual opponent W/D/L, goals, remaining fixtures, and point adjustments.
- [x] Target-position feasibility estimate using the team's recorded remaining fixtures and maximum attainable points; clearly labels the result as mathematical feasibility, not a probability.
- [x] Card threshold warnings and coach-confirmed suspension proposals.
- [x] SQL ledger for idempotent suspension decrement on match finalization and exact reversal on reopening/deletion (implementation committed; live database test pending).
- [x] Yellow-card threshold configurable by the coach.

## Phase 5 — Training, health, and statistics
- [x] Training sessions and attendance (per-player status; injured players default to injured rather than present; session list displays attendance rates).
- [x] Original Arabic-first bilingual drill bank expanded to 16 illustrated drills across technical, tactical, transition, finishing, and physical categories.
- [x] Copy a built-in drill into the coach’s own editable library; import/export the personal drill bank as validated JSON.
- [x] Add official FIFA Training Centre and UEFA grassroots learning links without copying their protected drill text or artwork.
- [x] Interactive SVG tactical board: add/drag players, defenders, ball and cones; draw movement arrows.
- [x] Stage-by-stage drill explanation and guided playback.
- [x] Coach-created drill form with diagram/stage data; custom cloud storage schema and migration committed (live persistence awaits migration).
- [x] Link multiple drills to one training session (live persistence awaits migration).
- [x] Injury/recovery records and dated absences; injury and suspension changes update player availability. Health archive/report refinements remain pending.
- [x] Player statistics table and UTF-8 CSV export (goals, assists, cards, appearances, and lineup minutes; career/team history aggregation remains pending).

## Phase 6 — Calendar and notifications
- [x] Add manager calendar events in PostgreSQL with manager-only RLS, date indexes, and CRUD UI.
- [x] Add monthly and weekly calendar views combining club events, scheduled matches, and training sessions, with team/type filters and local-time-safe editing.
- [x] Add idempotent in-app manager notifications for due payments, low inventory, calendar events, and upcoming training; support unread count, mark read, dismiss, and opening the linked section.
- [ ] Add real Web Push delivery to mobile devices, including subscription storage, VAPID secrets, and a server-side event/reminder trigger. Browser notification permission alone is not background push.

## Phase 7 — QA and handoff
- [ ] Test core create/edit/delete workflows, demo loading/reset, and related-record cleanup in a real browser and live Supabase project.
- [ ] Test match finish/reopen and suspension reversal.
- [ ] Test Arabic/French switching and mobile layout at 400px.
- [ ] Test tactical board pointer/touch dragging, arrows, stage navigation, custom drill CRUD, multi-drill session linking, and manual match-stat entry in a real browser.
- [ ] Verify backup/restore (including custom drills and session links) and two-device synchronization; focus/idle refresh is implemented but not yet live-tested.
- [x] Add coach profile settings and JSON backup/restore (merge-based restore), including the training tables and suspension accounting ledger.
- [x] Add an opt-in demo club/team dataset and a separately confirmed team-data reset that preserves coach login and preferences. Supabase verification SQL, deployment documentation, and a manual GitHub Pages workflow are committed; Pages activation and live deployment remain pending.
- [x] Restore and validate the markup for lineup, health, statistics, discipline, and settings screens.
- [x] Embed licensed Cairo and Barlow Condensed WOFF2 subsets in the single HTML file and include their OFL license texts.
- [x] Extend CI checks to cover every referenced DOM ID, duplicate IDs, Arabic/French translation keys, static database table references, and module-parent hierarchy.

## Acceptance rule
A phase is not considered complete until its implementation is present in the repository and the relevant checks have actually been run. A schema draft or a code review is not evidence of a live Supabase test.
