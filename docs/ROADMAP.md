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
- [ ] Add session handling, login, logout, loading, empty, and error states.
- [ ] Add safe local draft handling and JSON backup/restore.

## Phase 2 — Club, team, and player management
- [x] Clubs and multiple age-group teams (CRUD, linked deletion).
- [x] Player CRUD, position, search, status, and team assignment. Player profile detail view and position-group filters remain pending.
- [x] Current team assignment and basic transfer-history snapshots (career-stat snapshots still pending).
- [ ] Availability, injury, and suspension indicators.

## Phase 3 — Matches
- [x] Fixture scheduling, match reports, score entry, and finish/reopen controls. Reversible downstream accounting remains pending.
- [ ] Starter/substitute/not-selected lineups.
- [ ] Goals, assists, cards, substitutions, and minute calculations.
- [ ] Manual player statistics when no lineup is entered.

## Phase 4 — Competitions and discipline
- [x] Competition CRUD and team entries.
- [ ] Standings from finished team matches and manual opponent points (target-position calculations remain pending).
- [ ] Confirmed suspension workflow with reversible match accounting.
- [ ] Yellow-card threshold configurable by the coach.

## Phase 5 — Training, health, and statistics
- [x] Training sessions and attendance (per-player status; injured players default to injured rather than present).
- [x] Injury/recovery records and dated absences (basic CRUD; player status synchronization and archive refinements remain pending).
- [ ] Player statistics table and Arabic-safe CSV export.

## Phase 6 — QA and handoff
- [ ] Test core create/edit/delete workflows and related-record cleanup.
- [ ] Test match finish/reopen and suspension reversal.
- [ ] Test Arabic/French switching and mobile layout at 400px.
- [ ] Verify backup/restore and two-device synchronization.
- [ ] Document deployment and coach setup.

## Acceptance rule
A phase is not considered complete until its implementation is present in the repository and the relevant checks have actually been run. A schema draft or a code review is not evidence of a live Supabase test.
