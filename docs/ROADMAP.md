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
- [ ] Add safe local draft handling and JSON backup/restore.

## Phase 2 — Club, team, and player management
- [x] Clubs and multiple age-group teams (CRUD, linked deletion).
- [x] Player CRUD, position, search, status, and team assignment.
- [x] Player career profile with appearances, minutes, goals, assists, cards, team-transfer snapshots, injury/absence history, and match-event log; player lists are grouped by position with team/position filters.
- [x] Current team assignment and transfer-history snapshots of appearances, minutes, goals, assists, and cards; career-wide aggregation view remains pending.
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
- [x] Training sessions and attendance (per-player status; injured players default to injured rather than present).
- [x] Original Arabic-first drill bank across technical, tactical, transition, finishing, and physical categories.
- [x] Interactive SVG tactical board: add/drag players, defenders, ball and cones; draw movement arrows.
- [x] Stage-by-stage drill explanation and guided playback.
- [x] Coach-created drill form with diagram/stage data; custom cloud storage schema and migration committed (live persistence awaits migration).
- [x] Link multiple drills to one training session (live persistence awaits migration).
- [x] Injury/recovery records and dated absences; injury and suspension changes update player availability. Health archive/report refinements remain pending.
- [x] Player statistics table and UTF-8 CSV export (goals, assists, cards, appearances, and lineup minutes; career/team history aggregation remains pending).

## Phase 6 — QA and handoff
- [ ] Test core create/edit/delete workflows and related-record cleanup in a real browser and live Supabase project.
- [ ] Test match finish/reopen and suspension reversal.
- [ ] Test Arabic/French switching and mobile layout at 400px.
- [ ] Test tactical board pointer/touch dragging, arrows, stage navigation, custom drill CRUD, multi-drill session linking, and manual match-stat entry in a real browser.
- [ ] Verify backup/restore (including custom drills and session links) and two-device synchronization; focus/idle refresh is implemented but not yet live-tested.
- [x] Add coach profile settings and JSON backup/restore (merge-based restore), including the new training tables. Deployment and coach setup documentation remain pending.
- [x] Restore and validate the markup for lineup, health, statistics, discipline, and settings screens.
- [x] Extend CI checks to cover every referenced DOM ID, duplicate IDs, Arabic/French translation keys, static database table references, and module-parent hierarchy.

## Acceptance rule
A phase is not considered complete until its implementation is present in the repository and the relevant checks have actually been run. A schema draft or a code review is not evidence of a live Supabase test.
