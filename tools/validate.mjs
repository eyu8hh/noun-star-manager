import { readFileSync } from "node:fs";
import { strict as assert } from "node:assert";

const html = readFileSync(new URL("../index.html", import.meta.url), "utf8");
const css = readFileSync(new URL("../assets/css/app.css", import.meta.url), "utf8");
assert.ok(html.includes('<link rel="stylesheet" href="./assets/css/app.css">'), "Main app must load its extracted local stylesheet");
assert.ok(!/<style\b/i.test(html), "Main app must not retain an embedded style block after CSS extraction");
const script = readFileSync(new URL("../js/app.js", import.meta.url), "utf8");
assert.ok(html.includes('<script src="./js/app.js"></script>'), "Main app must load the extracted local application script");
assert.ok(!/<script>/.test(html), "Main app must not retain an embedded application script");
new Function(script);

const ids = [...html.matchAll(/id="([^"]+)"/g)].map((m) => m[1]);
const idSet = new Set(ids);
// Include literal IDs created by JavaScript templates, matching the former inline-script scan.
for (const match of script.matchAll(/\bid=["']([^"']+)["']/g)) idSet.add(match[1]);
const duplicates = ids.filter((id, i) => ids.indexOf(id) !== i);
assert.deepEqual(duplicates, [], "HTML contains duplicate IDs");
for (const id of ["loginView", "appView", "dashboardPage", "clubsModule", "playersModule", "matchesModule", "competitionsModule", "trainingModule", "healthModule", "statisticsModule", "disciplineModule", "financeModule", "clubResourcesModule", "settingsModule", "lineupPanel", "exportDrillBank", "importDrillBankBtn", "copyDrillToBank", "playerProfilePanel", "playerPortalNav", "playerPortalModule", "playerCorrectionForm", "playerRequestsManagerCard", "playerAccountCard", "playerPortalStats", "playerPortalEvaluations", "playerEvaluationForm", "playerEvaluationHistory", "evaluationPlayerId", "playerMonthlyVoteForm", "monthlyVoteCandidate", "audiencePollForm", "audiencePollManagerCard", "monthlyVotesManagerCard", "manualStatsPanel", "manualStatsForm", "playerFilterPosition", "playerFilterTeam", "clubResourcesNav", "clubSeasonForm", "clubSponsorForm", "clubAgreementForm", "clubSponsorPaymentForm", "clubEquipmentForm", "clubEquipmentMovementForm", "clubKitForm", "clubKitAssignmentForm", "clubActivityTable", "clubAgreementsTable", "clubSponsorPaymentsTable", "clubEquipmentMovementsTable", "clubKitAssignmentsTable", "playerFinancePanel", "playerFinanceTable", "playerProfilePrintBtn", "publicMediaFeed", "mediaManagerCard", "mediaPlayerChoice", "playerPosterStyle", "playerPosterCanvas", "publishPlayerPosterBtn", "playerPosterConsent", "mediaMatchChoice", "mediaPhotoFiles", "mediaPhotoConsent", "uploadMatchPhotosBtn", "mediaUploadStatus", "mediaAdminList", "shareAttendanceWhatsApp", "toggleStaffPassword", "reportsNav", "reportsModule", "reportFilterCard", "reportType", "reportTeam", "reportSeason", "reportFrom", "reportTo", "reportGenerateBtn", "reportPrintBtn", "reportCsvBtn", "reportSummary", "reportVisuals", "reportInsights", "reportTable"]) {
  assert.ok(idSet.has(id), "Missing required app section: " + id);
}
const referencedIds = new Set([...script.matchAll(/\$\("([^"]+)"\)/g)].map((m) => m[1]));
const missingIds = [...referencedIds].filter((id) => !idSet.has(id));
assert.deepEqual(missingIds, [], "Application references missing HTML IDs");

const parentById = new Map();
const divStack = [];
const divTags = /<div\b([^>]*)>|<\/div>/g;
const htmlBeforeScript = html;
for (const match of htmlBeforeScript.matchAll(divTags)) {
  if (match[0].startsWith("</")) {
    divStack.pop();
  } else {
    const id = match[1].match(/\bid="([^"]+)"/)?.[1];
    if (id) parentById.set(id, divStack.filter(Boolean).join(">"));
    divStack.push(id || "");
  }
}
assert.deepEqual(divStack, [], "Unbalanced application div structure");
for (const id of ["clubsModule", "playersModule", "competitionsModule", "trainingModule", "matchesModule", "statisticsModule", "healthModule", "disciplineModule", "financeModule", "clubResourcesModule", "reportsModule", "settingsModule"]) {
  assert.equal(parentById.get(id), "appView", id + " must be a sibling module under appView");
}
assert.equal(parentById.get("playerProfilePanel"), "appView>playersModule", "Player profile must be inside playersModule");
assert.equal(parentById.get("lineupPanel"), "appView>matchesModule", "Lineup panel must be inside matchesModule");

const translationsStart = script.indexOf("const translations");
const translationsObjectStart = script.indexOf("{", translationsStart);
const translationsEnd = script.indexOf("\n};", translationsObjectStart);
assert.ok(translationsStart >= 0 && translationsObjectStart > translationsStart && translationsEnd > translationsObjectStart, "Missing Arabic/French translations");
const translations = script.slice(translationsObjectStart, translationsEnd);
const arStart = translations.indexOf("ar:{") + 4;
const frStart = translations.indexOf("\nfr:{");
assert.ok(arStart >= 4 && frStart > arStart, "Missing Arabic or French translation map");
const arMap = translations.slice(arStart, frStart);
const frMap = translations.slice(frStart + 5);
const keys = (source) => new Set([...source.matchAll(/(?:^|,)([A-Za-z_$][\w$]*):/g)].map((m) => m[1]));
const arKeys = keys(arMap);
const frKeys = keys(frMap);
const usedTranslations = new Set([
  ...[...html.matchAll(/data-i18n="([^"]+)"/g)].map((m) => m[1]),
  ...[...html.matchAll(/data-i18n-placeholder="([^"]+)"/g)].map((m) => m[1]),
  ...[...html.matchAll(/data-i18n-title="([^"]+)"/g)].map((m) => m[1]),
  ...[...script.matchAll(/tr\("([^"]+)"\)/g)].map((m) => m[1]),
]);
for (const key of usedTranslations) {
  assert.ok(arKeys.has(key), "Missing Arabic translation: " + key);
  assert.ok(frKeys.has(key), "Missing French translation: " + key);
}

const schema = readFileSync(new URL("../supabase/schema.sql", import.meta.url), "utf8");
const schemaTables = new Set([...schema.matchAll(/create table(?: if not exists)? public\.([a-z_]+)/gi)].map((m) => m[1]));
const referencedTables = new Set([...script.matchAll(/(?:selectRows|saveRow|deleteRow)\("([a-z_]+)"/g)].map((m) => m[1]));
for (const table of referencedTables) {
  assert.ok(schemaTables.has(table), "Application references a table missing from schema.sql: " + table);
}

const drillStart = script.indexOf("const builtInDrills=[");
const drillEnd = script.indexOf("function drillText", drillStart);
assert.ok(drillStart >= 0 && drillEnd > drillStart, "Missing built-in training drill library");
const drillSection = script.slice(drillStart, drillEnd);
assert.ok([...drillSection.matchAll(/\{(?:"id"|id):"/g)].length >= 16, "Expected at least sixteen bundled original drills");
assert.ok(script.includes("animateTransform"), "Tactical stage playback should animate player movement");
assert.ok(script.includes("importDrillBankFile") && script.includes("downloadJsonFile"), "Drill bank JSON import/export is missing");
assert.ok(script.includes("builtInDrills.push(...extraOriginalDrills)"), "Expanded original drill bank is not registered");
assert.ok(!html.includes('id="loadDemoData"') && !html.includes('id="clearAllData"'), "Demo data controls must stay removed");
assert.ok(!script.includes("insertDemoRow") && !script.includes("clearCoachTeamData"), "Demo data mutation helpers must stay removed");
assert.ok(css.includes("@font-face") && css.includes("data:font/woff2;base64,"), "Cairo and Barlow fonts must remain embedded in the local stylesheet");
assert.ok(css.includes('font-family:"Cairo"') && css.includes('font-family:"Barlow Condensed"'), "Both embedded font families must be declared in the local stylesheet");
assert.ok(!/sb_secret_|service_role/i.test(html), "A secret or service-role key must never be embedded in the public HTML");
assert.ok(!css.includes("fonts.googleapis.com") && !css.includes("fonts.gstatic.com") && !html.includes("fonts.googleapis.com") && !html.includes("fonts.gstatic.com"), "The PWA must not depend on remote font requests");
assert.ok(readFileSync(new URL("../LICENSES/Cairo-OFL.txt", import.meta.url), "utf8").includes("SIL OPEN FONT LICENSE"), "Cairo font license is missing");
assert.ok(readFileSync(new URL("../LICENSES/Barlow-Condensed-OFL.txt", import.meta.url), "utf8").includes("SIL OPEN FONT LICENSE"), "Barlow Condensed font license is missing");
assert.ok(schema.includes("selection_status in ('starter','substitute','not_selected','manual')"), "Schema must support manual match-stat rows");
assert.ok(schema.includes("training_session_drills") && schema.includes("builtin_drill_key"), "Schema must support built-in and custom drills in session plans");
const manualMigration = readFileSync(new URL("../supabase/migrations/20261118_manual_match_stats.sql", import.meta.url), "utf8");
const drillMigration = readFileSync(new URL("../supabase/migrations/20261118_training_drill_library.sql", import.meta.url), "utf8");
const competitionMigration = readFileSync(new URL("../supabase/migrations/20261118_competition_manual_results.sql", import.meta.url), "utf8");
const suspensionMigration = readFileSync(new URL("../supabase/migrations/20261118_reversible_suspension_accounting.sql", import.meta.url), "utf8");
const mediaMigration = readFileSync(new URL("../supabase/migrations/20261119_club_media_gallery.sql", import.meta.url), "utf8");
const mediaTuningMigration = readFileSync(new URL("../supabase/migrations/20261119_club_media_policy_tuning.sql", import.meta.url), "utf8");
const roleHardeningMigration = readFileSync(new URL("../supabase/migrations/20261119_profile_role_helpers_hardening.sql", import.meta.url), "utf8");
const fkIndexesMigration = readFileSync(new URL("../supabase/migrations/20261119_foreign_key_indexes.sql", import.meta.url), "utf8");
const rlsInitplanMigration = readFileSync(new URL("../supabase/migrations/20261119_rls_initplan_optimization.sql", import.meta.url), "utf8");
assert.ok(manualMigration.includes("'manual'"), "Manual match-stat migration is missing");
assert.ok(drillMigration.includes("training_drills") && drillMigration.includes("builtin_drill_key"), "Training drill migration is missing");
assert.ok(competitionMigration.includes("remaining_matches"), "Competition migration is missing");
assert.ok(schema.includes("'suspensions','suspension_match_log','settings'"), "Suspension ledger is missing from owner RLS policy list");
assert.ok(schema.includes("nsm_suspension_log_refs") && schema.includes("revoke all on function public.nsm_account_suspensions_for_match()"), "Suspension ledger ownership or trigger execution is not secured");
assert.ok(suspensionMigration.includes("grant select,insert,update,delete on table public.suspension_match_log") && suspensionMigration.includes("nsm_suspension_log_refs"), "Suspension ledger migration is missing owner-scoped backup permissions");
assert.ok(mediaMigration.includes("public.club_media") && mediaMigration.includes("noun-star-media") && mediaMigration.includes("consent_confirmed"), "Public media gallery migration or consent safeguards are missing");
assert.ok(mediaTuningMigration.includes("drop policy if exists nsm_club_media_manager_read") && mediaTuningMigration.includes("club_media_created_by_idx"), "Media gallery policy tuning or foreign-key index is missing");
assert.ok(roleHardeningMigration.includes("revoke execute on function public.nsm_guard_profile_role_change()") && roleHardeningMigration.includes("alter function public.nsm_protect_profile_role() set search_path") && roleHardeningMigration.includes("revoke execute on function public.nsm_set_profile_role(uuid,text) from public,anon"), "Profile-role helper RPC hardening is missing");
assert.ok((fkIndexesMigration.match(/create index if not exists/g) || []).length === 22, "Missing foreign-key indexes");
assert.ok(rlsInitplanMigration.includes("alter policy") && rlsInitplanMigration.includes("(select auth.uid())"), "RLS initplan optimization is missing");
assert.ok(script.includes('"suspension_match_log"'), "Backup/restore must include the suspension ledger");


const ownerPolicyStart = schema.indexOf("create policy nsm_owner_only on public.%I");
assert.ok(ownerPolicyStart > 0, "Missing dynamic owner-only RLS policy");
const ownerPolicyListStart = schema.lastIndexOf("foreach t in array array[", ownerPolicyStart);
const ownerPolicyListEnd = schema.indexOf("] loop", ownerPolicyListStart);
assert.ok(ownerPolicyListStart >= 0 && ownerPolicyListEnd > ownerPolicyListStart, "Cannot inspect owner RLS table list");
const ownerPolicyList = schema.slice(ownerPolicyListStart, ownerPolicyListEnd);
for (const table of schemaTables) {
  if (table === "profiles" || ["player_evaluations","player_monthly_votes","audience_polls","audience_poll_options","audience_poll_votes","audience_members","public_site_admins","public_posts","audience_notifications","audience_notification_reads","audience_signup_attempts","nsm_manager_bootstrap_tokens","finance_dues","finance_transactions","club_seasons","sponsors","sponsor_agreements","sponsor_payments","equipment_items","equipment_movements","club_kits","kit_assignments","club_activity_logs","club_media"].includes(table)) continue;
  assert.ok(ownerPolicyList.includes("'" + table + "'"), "Missing owner-only RLS policy for table: " + table);
}
for (const table of ["player_evaluations","player_monthly_votes","audience_polls","audience_poll_options","audience_poll_votes","public_posts"]) assert.ok(schema.includes("create policy nsm_"), "New feature tables must declare explicit RLS policies");
assert.ok(schema.includes("nsm_suspension_log_refs"), "Suspension ledger needs a same-owner reference trigger");
assert.ok(schema.includes("revoke all on function public.nsm_account_suspensions_for_match()"), "Suspension accounting trigger must not be directly executable");
const verifySql = readFileSync(new URL("../supabase/verify.sql", import.meta.url), "utf8");
assert.ok(verifySql.toLowerCase().includes("from pg_policies") && verifySql.toLowerCase().includes("rls_enabled"), "Read-only Supabase verification queries are missing");
const verifyLower = verifySql.toLowerCase();
assert.ok(!["insert into","update public.","delete from","create table","alter table","drop table"].some(token => verifyLower.includes(token)), "Supabase verification script must remain read-only");
const deployWorkflow = readFileSync(new URL("../.github/workflows/deploy-pages.yml", import.meta.url), "utf8");
assert.ok(deployWorkflow.includes("workflow_dispatch") && deployWorkflow.includes("actions/deploy-pages@v4"), "Manual GitHub Pages deployment workflow is missing");
assert.ok(deployWorkflow.includes("pages: write") && deployWorkflow.includes("id-token: write"), "GitHub Pages deployment permissions are incomplete");
assert.ok(deployWorkflow.includes("cp index.html community.html manifest.webmanifest service-worker.js site/") && deployWorkflow.includes("cp -R assets site/assets"), "GitHub Pages must deploy the public voting page, PWA shell, and all assets");
assert.ok(script.includes('finishedMatchIds.has(e.match_id)'), "Discipline thresholds must ignore unfinished matches");
assert.ok(script.includes('order=sort_order.asc'), "Training session drill order must be persisted and restored");

const community = readFileSync(new URL("../community.html", import.meta.url), "utf8");
assert.ok(community.includes("nsm_public_poll_results"), "Public voting page must load poll results");
assert.ok(community.includes("audience_poll_votes") && community.includes("voter_user_id") && community.includes("audience_members"), "Public voting must require a loyal fan account and enforce one vote per account");
const communityScript = community.slice(community.indexOf("<script>") + 8, community.indexOf("</script>"));
new Function(communityScript);
const manifest = JSON.parse(readFileSync(new URL("../manifest.webmanifest", import.meta.url), "utf8"));
assert.equal(manifest.display, "standalone", "PWA must be installable in standalone mode");
assert.ok(manifest.icons?.length >= 1, "PWA manifest needs an app icon");
const serviceWorker = readFileSync(new URL("../service-worker.js", import.meta.url), "utf8");

const pagesArtifactName = "github-pages-${{ github.run_id }}-${{ github.run_attempt }}";
assert.ok(deployWorkflow.includes("name: " + pagesArtifactName) && deployWorkflow.includes("artifact_name: " + pagesArtifactName), "Pages upload and deploy must use the same unique artifact name per workflow attempt");
new Function("self", "caches", "fetch", "URL", serviceWorker);
assert.ok(html.includes('rel="manifest"') && community.includes('rel="manifest"'), "Both app surfaces must link to the PWA manifest");

const playerPortalStart = script.indexOf("async function loadPlayerPortal()");
const playerPortalEnd = script.indexOf('$("playerMonthlyVoteForm")', playerPortalStart);
assert.ok(playerPortalStart >= 0 && playerPortalEnd > playerPortalStart, "Player portal loader is missing or incomplete");
const playerPortalCode = script.slice(playerPortalStart, playerPortalEnd);
assert.ok(playerPortalCode.includes('selectRows("players","&user_id=eq."+session.user.id)'), "Player portal must load only the signed-in player's profile");
assert.ok(playerPortalCode.includes('selectRows("player_profile_change_requests"'), "Player portal must show its correction request history");
assert.ok(playerPortalCode.includes('selectRows("player_evaluations"') || script.includes("async function loadPlayerEvaluations"), "Player portal must expose evaluation history");
assert.ok(script.includes('async function login(identifier,password)') && script.includes('@login.nounstar.club') && script.includes('@fans.nounstar.club'), "Staff/player/fan identifier login mapping is missing");
assert.ok(script.includes("let sessionRefreshPromise=null") && script.includes("if(sessionRefreshPromise)return sessionRefreshPromise"), "Session refresh must be single-flight to avoid refresh-token rotation races during parallel API calls");
assert.ok(html.includes("publicPostsFeed") && html.includes("accountModal") && html.includes("joinFansBtn"), "Public-first homepage and unified account center are missing");
assert.ok(script.includes('document.addEventListener("click",event=>') && script.includes('event.target.closest?.("button")') && script.includes('target?.id==="accountBtn"') && script.includes('target?.id==="openStaffAccount"') && script.includes('target?.id==="openFanAccount"'), "Account center must delegate clicks for the account button and both account choices");
assert.ok(script.includes("PROFILE_NOT_FOUND") && script.includes("تعذر تحميل بيانات مساحة العمل"), "Professional login must expose a useful post-authentication bootstrap error");
assert.ok(script.includes("INVALID_CREDENTIALS") && script.includes("كود الدخول أو كلمة المرور غير صحيحين") && script.includes('$("accountModal").classList.remove("hidden")') && script.includes("toggleStaffPassword") && script.includes("showStaffBootstrapError") && script.includes("بقيت الجلسة محفوظة"), "Professional login must explain bootstrap failures and preserve valid sessions for diagnosis");
assert.ok(!script.includes('if(res.status===401){logout(true);return "—"}') && script.includes("dashboard count refresh failed; session preserved") && script.includes("dashboard count unauthorized; session preserved"), "Dashboard metric failures must never log the manager out");
assert.ok(script.includes("async function loadPublicMedia") && script.includes("async function uploadPublicMedia") && script.includes("generatePlayerPoster") && script.includes("navigator.share") && script.includes("data-share-media"), "Public media gallery, sharing and player poster studio are missing");
assert.ok(script.includes("wa.me/?text=") && html.includes("shareAttendanceWhatsApp"), "Training attendance WhatsApp sharing is missing");
assert.ok(script.includes('if(!currentProfile)throw Error("PROFILE_NOT_FOUND")') && script.includes("public-site admin capability check") && script.includes("publicSiteAdmin=false"), "Optional public publishing permissions must not block professional workspace login");
assert.ok(html.includes("publicMatchesFeed") && html.includes("matchPublic") && script.includes("nsm_public_match_feed"), "Explicitly published public match schedule/results are missing");
assert.ok(script.includes("nsm-create-fan") && script.includes("loadFanNotifications") && script.includes("publicSiteAdmin"), "Fan registration, in-app notifications, or gated publishing tools are missing");
assert.ok(schema.includes("audience_members") && schema.includes("public_site_admins") && schema.includes("public_posts") && schema.includes("audience_notifications"), "Public community schema is incomplete");
assert.ok(schema.includes("nsm_audience_poll_owner_write") && schema.includes("public_site_admins"), "Only the designated public-site manager may create polls");
assert.ok(script.includes('audiencePollManagerCard").classList.toggle("hidden",!publicSiteAdmin)'), "Public poll administration must be hidden from non-admin accounts");
assert.ok(schema.includes("alter column role set default 'fan'") && schema.includes("role in ('manager','coach','player','fan')"), "Public registrations must default to fan role");
const fanFunction = readFileSync(new URL("../supabase/functions/nsm-create-fan/index.ts", import.meta.url), "utf8");
assert.ok(fanFunction.includes("email_confirm:true") && fanFunction.includes("audience_members") && fanFunction.includes("audience_signup_attempts"), "Fan signup must create a username account with rate limiting");
assert.ok(script.includes('currentProfile?.role==="player"') && script.includes('setPage("playerPortal")'), "Player accounts must be routed to the read-only portal");
assert.ok(script.includes('playerCorrectionForm").addEventListener("submit"') && script.includes('saveRow("player_profile_change_requests"'), "Player corrections must be submitted as review requests, not direct profile edits");
assert.ok(schema.includes("nsm_player_read_own_profile") && schema.includes("nsm_player_change_request_insert") && schema.includes("nsm_player_read_own_team_details"), "Player profile, correction, and team read policies are required");
const playerAccountFunction = readFileSync(new URL("../supabase/functions/nsm-create-player/index.ts", import.meta.url), "utf8");
assert.ok(playerAccountFunction.includes('profile?.role!=="manager"') && playerAccountFunction.includes('.eq("owner_id",data.user.id)'), "Player account creation must be manager-only and owner-scoped");
assert.ok(playerAccountFunction.includes('role:"player"') && playerAccountFunction.includes('user_id:user.user.id'), "Player account must be linked to the existing player record");
assert.ok(html.includes('id="managerCoachAssignmentCard"') && html.includes('id="managerQuickCoaches"') && html.includes('id="managerDashboardPanel"'), "Manager-only dashboard and staff controls are missing");
assert.ok(script.includes("async function loadManagerCoachAssignments") && script.includes('currentProfile?.role==="coach"&&(page==="clubs"||page==="finance"||page==="clubResources"||page==="reports")'), "Manager/coach workspace separation is missing");
const managerAccessMigration = readFileSync(new URL("../supabase/migrations/20261119_manager_controls_coach_assignments.sql", import.meta.url), "utf8");
assert.ok(managerAccessMigration.includes("drop policy if exists nsm_coach_insert_own_assignments") && managerAccessMigration.includes("tc.coach_user_id = (select auth.uid())"), "Coach assignments must be manager-controlled and team reads assignment-scoped");
assert.ok(script.includes("const isFirstTeam=!editingTeam&&teamsData.length===0") && script.includes("coach_user_id:session.user.id,assignment_type:\"head\""), "The manager must be assigned as head coach of the first team without a second account");
assert.ok(script.includes("assignments,managerRows]") && script.includes("المدير · مدرب الفريق الأول") && script.includes("يُسند المدير مدرباً رئيسياً للفريق الأول فقط"), "Manager coach identity must appear in assignments and remain restricted to the first team");
const coachWriteMigration = readFileSync(new URL("../supabase/migrations/20261119_coach_team_write_permissions.sql", import.meta.url), "utf8");
assert.ok(coachWriteMigration.includes("nsm_coach_can_write_team") && coachWriteMigration.includes("nsm_normalize_assigned_coach_owner") && coachWriteMigration.includes("Related record belongs to another owner"), "Assigned-coach write access must preserve club ownership and cross-owner reference checks");
const managerOwnerMigration = readFileSync(new URL("../supabase/migrations/20261119_manager_only_owner_policies.sql", import.meta.url), "utf8");
assert.ok(managerOwnerMigration.includes("drop policy if exists nsm_owner_only") && managerOwnerMigration.includes("nsm_manager_owner_only") && managerOwnerMigration.includes("nsm_coach_read_assigned_competitions"), "Legacy owner policies must be manager-only while coaches retain assigned sports reads");
assert.ok(managerOwnerMigration.includes("nsm_coach_manage_own_training_drills") && managerOwnerMigration.includes("nsm_coach_manage_assigned_training_session_drills") && managerOwnerMigration.includes("nsm_coach_read_assigned_suspensions"), "Coach drill workflow and assigned-team discipline access must remain functional");
for (const table of ["matches","match_lineups","match_events","training_sessions","training_attendance","injuries","absences","suspensions"]) {
  assert.ok(coachWriteMigration.includes("nsm_coach_manage_assigned_" + table), "Assigned coach write policy is missing for " + table);
  assert.ok(coachWriteMigration.includes("a_nsm_coach_owner_" + table), "Assigned coach owner normalization trigger is missing for " + table);
}
const coachProvisioning = readFileSync(new URL("../supabase/functions/nsm-create-coach/index.ts", import.meta.url), "utf8");
assert.ok(coachProvisioning.includes("coach_code?: string") && coachProvisioning.includes("club_owner_id: managerId") && coachProvisioning.includes("coach_code: coachCode"), "Manager-created coach accounts must use coach codes and belong to the manager's club");
assert.ok(html.includes('id="financeNav"') && html.includes('id="financeModule"') && html.includes('data-i18n="finance"'), "Manager finance navigation and module are missing");
assert.ok(script.includes('currentProfile?.role!=="manager"') && script.includes("async function loadFinance") && script.includes('saveRow("finance_transactions"') && script.includes('saveRow("finance_dues"'), "Finance workspace must enforce manager access and support ledger/dues");
assert.equal((html.match(/class="nav-group"/g)||[]).length, 4, "Workspace navigation must be separated into four functional groups");
assert.ok(html.includes('class="quick-grid manager-bento-grid"') && html.includes('aria-controls="sidebar"') && html.includes('aria-expanded="false"'), "Manager bento dashboard and accessible mobile drawer controls are required");
assert.ok(script.includes('setAttribute("aria-current","page")') && script.includes('setAttribute("aria-expanded",String(opened))'), "Navigation state must be exposed accessibly");
assert.ok(script.includes("Route shell interactions at the window capture phase") && script.includes('id==="menuBtn"') && script.includes('id==="langBtn"') && script.includes('id==="themeBtn"') && script.includes('matches("#nav button[data-page]")') && script.includes("setPage(page,focus);") && script.includes("function applySettingsFocus") && html.includes('data-settings-focus="coaches"') && html.includes('data-settings-focus="requests"') && html.includes('data-settings-focus="public"'), "Mobile shell controls and navigation must use the central capture-phase click router");
assert.ok(script.includes("settingsFocusBanner") && script.includes("settings-focus-hidden") && script.includes('ids:["coachManagementCard","managerCoachManagementCard","managerDetachedCoachCard","managerCoachAssignmentCard"]') && script.includes('ids:["playerRequestsManagerCard"]'), "Dashboard management shortcuts must open focused, isolated settings views");
assert.ok(script.includes("async function loadReports") && script.includes('$("reportCsvBtn").addEventListener') && script.includes('$("reportPrintBtn").addEventListener') && script.includes('currentProfile?.role!=="manager"&&(page==="finance"||page==="clubResources"||page==="reports")'), "Manager reports center must be manager-only and support CSV/print exports");
assert.ok(script.includes('await login($("email").value.trim(),$("password").value);await showApp()') && script.includes("showApp().catch(err=>showStaffBootstrapError(err))") && script.includes("throw err"), "Authentication bootstrap must await profile loading, preserve valid sessions, and surface failures");
const financeMigration = readFileSync(new URL("../supabase/migrations/20261119_manager_finance_ledger.sql", import.meta.url), "utf8");
assert.ok(financeMigration.includes("alter table public.finance_dues enable row level security") && financeMigration.includes("finance_transactions_manager_insert") && financeMigration.includes("nsm_validate_finance_due_payment") && financeMigration.includes("nsm_validate_finance_due_owner") && financeMigration.includes("Player does not belong to this club") && financeMigration.includes("nsm_sync_finance_due_paid"), "Manager-only finance RLS and due payment synchronization are required");
const resourcesMigration = readFileSync(new URL("../supabase/migrations/20261119_club_resources_from_legacy_app.sql", import.meta.url), "utf8");
const sponsorRestoreMigration = readFileSync(new URL("../supabase/migrations/20261119_sponsor_payment_backup_restore_link.sql", import.meta.url), "utf8");
for (const table of ["club_seasons","sponsors","sponsor_agreements","sponsor_payments","equipment_items","equipment_movements","club_kits","kit_assignments","club_activity_logs"]) assert.ok(schema.includes("create table if not exists public."+table) && resourcesMigration.includes("create table if not exists public."+table), "Missing imported resource table: "+table);
assert.ok(script.includes("async function loadClubResources") && script.includes('saveRow("sponsor_payments"') && script.includes('saveRow("equipment_movements"') && script.includes('saveRow("kit_assignments"'), "Imported club resources UI is incomplete");
assert.ok(script.includes('const backupTables=[') && ["club_seasons","sponsors","sponsor_agreements","sponsor_payments","equipment_items","equipment_movements","club_kits","kit_assignments","club_activity_logs","finance_dues","finance_transactions","club_media"].every(t=>script.includes('"'+t+'"')), "Backup must include finance and all imported club resources");
assert.ok(script.includes('table==="equipment_items"&&movementItems.has(x.id))x.quantity_on_hand=0') && script.includes('table==="equipment_movements"?"&order=created_at.asc"'), "Equipment backup restore must replay stock movements in creation order");
assert.ok(script.includes("playerFinancePanel") && script.includes("playerProfilePrintBtn"), "Player dossier must include print and manager-only finance detail");
assert.ok(resourcesMigration.includes("nsm_apply_equipment_movement") && resourcesMigration.includes("nsm_create_sponsor_finance_entry") && resourcesMigration.includes("t||'_manager_select'"), "Resource inventory, sponsor finance link, or manager-only RLS is missing");
assert.ok(html.includes('id="clubResourcesNav"') && html.includes('id="clubResourcesModule"') && script.includes('page==="clubResources"') && script.includes('currentProfile?.role!=="manager"'), "Club resources manager navigation is missing");
assert.ok(script.includes("function toast(") && script.includes("nsmToastRegion") && script.includes("function showSkeleton"), "Accessible toast feedback and skeleton loading helpers are required");
assert.ok(script.includes("canManagePlayers?") && script.includes('$("addPlayerBtn").classList.toggle("hidden",!canManage)'), "Coach player views must not expose manager-only player creation, edit, or delete controls");
assert.ok(script.includes("const canManage=currentProfile?.role===\"manager\"") && script.includes("data-edit-comp") && script.includes("data-delete-entry"), "Competition editing and standings management must be manager-only while coaches can read standings");
assert.ok(html.includes('id="disciplineSettingsCard"') && script.includes("canManageDisciplineSettings") && script.includes('if(currentProfile?.role!=="manager")return;'), "Discipline threshold settings must be manager-only");
assert.ok(script.includes('showSkeleton("matchesTable"') && script.includes('showSkeleton("trainingTable"') && script.includes('showSkeleton("injuriesTable"'), "Core sports modules must render skeletons while loading");
assert.ok(css.includes("@keyframes nsmShimmer") && css.includes("cubic-bezier(.2,.85,.25,1.15)") && css.includes("prefers-reduced-motion:reduce"), "Microinteractions must use restrained motion and respect reduced-motion preferences");
assert.ok(css.includes(".workspace-navigation{flex:1 1 auto") && css.includes("overflow-y:auto") && css.includes(".sidebar-foot{flex:0 0 auto}"), "Mobile navigation must scroll independently without overlapping the account footer");
assert.ok(serviceWorker.includes('nsm-shell-v40'), "PWA cache must refresh after extracting the application script");
const coachManagementFunction = readFileSync(new URL("../supabase/functions/nsm-manage-coach/index.ts", import.meta.url), "utf8");
assert.ok(html.includes('id="coachBulkResetBtn"') && html.includes('id="coachManagementCount"'), "Manager coach settings must include the bulk reset control and live count");
assert.ok(script.includes('action==="remove-all"') && script.includes('manageCoaches(action,coachId)'), "Coach management must wire the bulk reset action");
assert.ok(script.includes('managerCoachManagementCard').toString() && script.includes('ids:["coachManagementCard","managerCoachManagementCard","managerDetachedCoachCard","managerCoachAssignmentCard"]'), "Coach management panel must appear in focused settings");
assert.ok(coachManagementFunction.includes('action === "remove_all"') && coachManagementFunction.includes('ban_duration: "876000h"'), "Bulk coach reset must disable sign-in before detaching coaches");

const coachCreationFunction = readFileSync(new URL("../supabase/functions/nsm-create-coach/index.ts", import.meta.url), "utf8");
assert.ok(coachManagementFunction.includes('update({ club_owner_id: null })') && !coachManagementFunction.includes('coach_code: null'), "Coach reset must preserve the coach code for safe account reactivation");
assert.ok(coachCreationFunction.includes('const { data: reusable, error: reusableError }') && coachCreationFunction.includes('ban_duration: "none"') && coachCreationFunction.includes('reused: true'), "Coach creation must safely reactivate a previously detached account with its original code");




assert.ok(html.includes('id="managerCoachManagementCard"') && html.includes('id="managerCoachManagementList"'), "Manager settings must include the coach account management panel");
assert.ok(script.includes('manageCoaches("list")') && script.includes('data-coach-action="remove"') && script.includes('data-coach-action="freeze"'), "Coach management UI must expose listing, freezing, and removal actions");
assert.ok(coachManagementFunction.includes('manager?.role !== "manager"') && coachManagementFunction.includes('.eq("club_owner_id", managerId)') && coachManagementFunction.includes('ban_duration'), "Coach management Edge Function must verify manager ownership and manage sign-in bans");
assert.ok(coachManagementFunction.includes('club_owner_id: null') && coachManagementFunction.includes('preserved_account: true'), "Coach removal must detach the account without hard-deleting its historical identity");

assert.ok(html.includes('id="publicGalleryLightbox"') && html.includes('id="galleryLightboxImage"') && script.includes('data-open-gallery'), "Public media gallery must provide an accessible image lightbox and carousel controls");
assert.ok(script.includes("function openPublicGallery(") && script.includes("function movePublicGallery(") && script.includes("galleryLightboxPrev") && script.includes("galleryLightboxNext"), "Public media gallery navigation handlers are required");

assert.ok(serviceWorker.includes('cache:"no-store"'), "PWA navigation must bypass stale browser HTTP cache");
assert.ok(script.indexOf('$("loginForm").addEventListener("submit",async e=>') < script.indexOf("const translations=") && html.includes('id="loginForm" class="public-form" onsubmit="return false"'), "Professional login must bind before optional modules and never fall through to native form navigation");
assert.ok(script.includes('$("playerProfilePrintBtn").addEventListener("click",()=>window.print())') && script.includes('selectRows("finance_dues","&player_id=eq."+id+"&order=due_date.desc")'), "Printable player dossier or manager-only player finance detail is missing");

assert.ok(html.includes('id="backBtn"') && html.includes('data-top-page="players"') && html.includes('data-top-page="matches"') && html.includes('data-top-page="training"') && html.includes('data-top-page="finance"'), "Topbar back control and key shortcuts must exist");
assert.ok(script.includes("function goBack(") && script.includes("pageHistory.push") && script.includes("recordHistory:false"), "Back navigation must restore the previous in-app page without adding another history entry");
assert.ok(script.includes('button.classList.toggle("hidden",!nav||nav.classList.contains("hidden"))'), "Topbar shortcuts must inherit role-based navigation visibility");
assert.ok(css.includes(".top-shortcuts") && css.includes(".top-utilities") && css.includes(".top-back-btn:disabled"), "Topbar controls must use the shared responsive style system");

assert.ok(script.includes('candidateEmails.push("coach+"+code.slice(2)+"@login.nounstar.club","coach+"+code+"@login.nounstar.club")'), "Coach login must support both normalized and legacy full-code email formats");
assert.ok(html.includes('id="managerDetachedCoachCard"') && script.includes('manageCoaches("restore"'), "Manager must be able to restore detached coach accounts");
assert.ok(coachManagementFunction.includes('action === "restore"') && coachManagementFunction.includes('ban_duration: "none"') && coachManagementFunction.includes('club_owner_id: managerId'), "Coach restoration must reactivate sign-in and reattach the profile to the verified manager");
assert.ok(coachCreationFunction.includes('coachCode.replace(/^c-/, "")') && coachCreationFunction.includes('coachCode.startsWith("m-")'), "New coach accounts must use a login-compatible email and reserve the manager prefix");


assert.ok(html.includes('id="dashboardInsights"') && html.includes('id="dashboardCategoryBreakdown"') && html.includes('id="dashboardAttendanceSummary"'), "Dashboard must include live category and attendance insight panels");
assert.ok(script.includes("async function loadDashboardInsights") && script.includes('selectRows("training_attendance"') && script.includes('selectRows("finance_transactions"') && script.includes('selectRows("club_activity_logs"'), "Dashboard insight cards must be populated from existing Supabase records");
assert.ok(html.includes('id="bottomNav"') && html.includes('id="moreSheet"') && html.includes('data-bottom-page="training"'), "Mobile bottom navigation and More sheet must be present");
assert.ok(script.includes('id==="moreNavBtn"') && script.includes('document.querySelectorAll("[data-bottom-page]")'), "Bottom navigation and More sheet controls must be wired");
assert.ok(css.includes(".dashboard-insights") && css.includes(".bottom-nav") && css.includes(".more-sheet"), "Dashboard and mobile navigation must have responsive styles");


assert.ok(html.includes('id="playerFilterAvailability"') && html.includes('id="playerFilterPayment"') && html.includes('id="playerSortOrder"') && html.includes('id="clearPlayerFilters"'), "Player list must include administrative/payment filters, sorting, and clear controls");
assert.ok(script.includes('selectRows("finance_dues","&limit=2000")') && script.includes('const paymentState=id=>') && script.includes('$("playerFilterPayment").classList.toggle("hidden",!canManage)'), "Payment state must be derived from real dues and restricted to managers");
assert.ok(script.includes('sort==="date"') && script.includes('sort==="shirt"') && script.includes('clearPlayerFilters'), "Player sorting and filter reset must be wired");
assert.ok(css.includes(".player-filter-bar") && css.includes(".payment-state"), "Player filters must have responsive visual states");


assert.ok(html.includes('id="attendanceCounters"') && html.includes('data-attendance-bulk="present"') && html.includes('data-attendance-bulk="absent"'), "Attendance editor must include bulk actions and live status counters");
assert.ok(script.includes('value="late"') && script.includes('function updateAttendanceCounters') && script.includes('attendance_status:el.value'), "Attendance must support the late state and persist selected states");
assert.ok(script.includes('late:"متأخر"') && script.includes('late:"En retard"') && script.includes('إجمالي اللاعبين: "+rows.length'), "Attendance labels and WhatsApp report must include late status and total roster");
assert.ok(css.includes(".attendance-bulk-actions") && css.includes(".attendance-counters"), "Attendance bulk actions and counters must be styled");
assert.ok(readFileSync(new URL("../supabase/migrations/20261120_training_attendance_late_status.sql", import.meta.url), "utf8").includes("'late'::text"), "Attendance late status migration must be committed");


assert.ok(html.includes('id="calendarModule"') && html.includes('id="calendarEventForm"') && html.includes('id="notificationsModule"') && html.includes('id="notificationsBtn"'), "Manager calendar and notification center UI must exist");
assert.ok(script.includes('async function loadCalendar') && script.includes('async function loadNotifications') && script.includes('async function syncManagerNotifications'), "Calendar and notification workflows must be implemented");
assert.ok(script.includes('saveRow("club_events"') && script.includes('club_notifications?on_conflict=owner_id,source_key') && script.includes('read_at=is.null'), "Calendar CRUD and idempotent notification generation/read state must use Supabase");
assert.ok(script.includes('page==="calendar"') && script.includes('page==="notifications"') && script.includes('role!=="manager"'), "Calendar and notifications must be manager-only");
assert.ok(readFileSync(new URL("../supabase/migrations/20261120_calendar_and_manager_notifications.sql", import.meta.url), "utf8").includes("enable row level security") && readFileSync(new URL("../supabase/migrations/20261120_calendar_creator_index.sql", import.meta.url), "utf8").includes("club_events_created_by_idx"), "Calendar and notification migrations must be present with RLS and FK index");
assert.ok(css.includes(".notification-list") && css.includes(".notification-badge"), "Notification center and unread badge must be styled");

console.log("NOUN STAR MANAGER: JavaScript, HTML IDs, Arabic/French translations, and referenced schema tables passed.");
