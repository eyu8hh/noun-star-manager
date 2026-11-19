import { readFileSync } from "node:fs";
import { strict as assert } from "node:assert";

const html = readFileSync(new URL("../index.html", import.meta.url), "utf8");
const start = html.indexOf("<script>");
const end = html.indexOf("</script>", start);
assert.ok(start >= 0 && end > start, "Expected one inline application script");
assert.equal(html.indexOf("<script>", start + 1), -1, "Expected exactly one inline application script");
const script = html.slice(start + 8, end);
new Function(script);

const ids = [...html.matchAll(/id="([^"]+)"/g)].map((m) => m[1]);
const idSet = new Set(ids);
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
const htmlBeforeScript = html.slice(0, start);
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
assert.ok(html.includes("@font-face") && html.includes("data:font/woff2;base64,"), "Cairo and Barlow fonts must be embedded in the single HTML file");
assert.ok(html.includes('font-family:"Cairo"') && html.includes('font-family:"Barlow Condensed"'), "Both embedded font families must be declared");
assert.ok(!/sb_secret_|service_role/i.test(html), "A secret or service-role key must never be embedded in the public HTML");
assert.ok(!html.includes("fonts.googleapis.com") && !html.includes("fonts.gstatic.com"), "The single-file app must not depend on remote font requests");
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
assert.ok(manualMigration.includes("'manual'"), "Manual match-stat migration is missing");
assert.ok(drillMigration.includes("training_drills") && drillMigration.includes("builtin_drill_key"), "Training drill migration is missing");
assert.ok(competitionMigration.includes("remaining_matches"), "Competition migration is missing");
assert.ok(schema.includes("'suspensions','suspension_match_log','settings'"), "Suspension ledger is missing from owner RLS policy list");
assert.ok(schema.includes("nsm_suspension_log_refs") && schema.includes("revoke all on function public.nsm_account_suspensions_for_match()"), "Suspension ledger ownership or trigger execution is not secured");
assert.ok(suspensionMigration.includes("grant select,insert,update,delete on table public.suspension_match_log") && suspensionMigration.includes("nsm_suspension_log_refs"), "Suspension ledger migration is missing owner-scoped backup permissions");
assert.ok(mediaMigration.includes("public.club_media") && mediaMigration.includes("noun-star-media") && mediaMigration.includes("consent_confirmed"), "Public media gallery migration or consent safeguards are missing");
assert.ok(mediaTuningMigration.includes("drop policy if exists nsm_club_media_manager_read") && mediaTuningMigration.includes("club_media_created_by_idx"), "Media gallery policy tuning or foreign-key index is missing");
assert.ok(roleHardeningMigration.includes("revoke execute on function public.nsm_guard_profile_role_change()") && roleHardeningMigration.includes("alter function public.nsm_protect_profile_role() set search_path") && roleHardeningMigration.includes("revoke execute on function public.nsm_set_profile_role(uuid,text) from public,anon"), "Profile-role helper RPC hardening is missing");
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
assert.ok(script.includes("INVALID_CREDENTIALS") && script.includes("كود الدخول أو كلمة المرور غير صحيحين") && script.includes('$("accountModal").classList.remove("hidden")') && script.includes("toggleStaffPassword"), "Professional login must explain invalid credentials and keep the staff form visible");
assert.ok(script.includes("async function loadPublicMedia") && script.includes("async function uploadPublicMedia") && script.includes("generatePlayerPoster"), "Public media gallery and player poster studio are missing");
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
const coachProvisioning = readFileSync(new URL("../supabase/functions/nsm-create-coach/index.ts", import.meta.url), "utf8");
assert.ok(coachProvisioning.includes("coach_code?: string") && coachProvisioning.includes("club_owner_id: managerId") && coachProvisioning.includes("coach_code: coachCode"), "Manager-created coach accounts must use coach codes and belong to the manager's club");
assert.ok(html.includes('id="financeNav"') && html.includes('id="financeModule"') && html.includes('data-i18n="finance"'), "Manager finance navigation and module are missing");
assert.ok(script.includes('currentProfile?.role!=="manager"') && script.includes("async function loadFinance") && script.includes('saveRow("finance_transactions"') && script.includes('saveRow("finance_dues"'), "Finance workspace must enforce manager access and support ledger/dues");
assert.ok(script.includes("async function loadReports") && script.includes('$("reportCsvBtn").addEventListener') && script.includes('$("reportPrintBtn").addEventListener') && script.includes('currentProfile?.role!=="manager"&&(page==="finance"||page==="clubResources"||page==="reports")'), "Manager reports center must be manager-only and support CSV/print exports");
assert.ok(script.includes('await login($("email").value.trim(),$("password").value);await showApp()') && script.includes("showApp().catch(()=>logout(true))") && script.includes("throw err"), "Authentication bootstrap must await profile loading and surface failures");
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
assert.ok(serviceWorker.includes('nsm-shell-v15'), "PWA cache must refresh after media and login improvements");
assert.ok(script.includes('$("playerProfilePrintBtn").addEventListener("click",()=>window.print())') && script.includes('selectRows("finance_dues","&player_id=eq."+id+"&order=due_date.desc")'), "Printable player dossier or manager-only player finance detail is missing");

console.log("NOUN STAR MANAGER: JavaScript, HTML IDs, Arabic/French translations, and referenced schema tables passed.");
