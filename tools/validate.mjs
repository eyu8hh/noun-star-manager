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
for (const id of ["loginView", "appView", "dashboardPage", "clubsModule", "playersModule", "matchesModule", "competitionsModule", "trainingModule", "healthModule", "statisticsModule", "disciplineModule", "settingsModule", "lineupPanel", "loadDemoData", "clearAllData", "exportDrillBank", "importDrillBankBtn", "copyDrillToBank", "playerProfilePanel", "playerPortalNav", "playerPortalModule", "playerCorrectionForm", "playerRequestsManagerCard", "playerAccountCard", "playerPortalStats", "playerPortalEvaluations", "playerEvaluationForm", "playerEvaluationHistory", "evaluationPlayerId", "playerMonthlyVoteForm", "monthlyVoteCandidate", "audiencePollForm", "audiencePollManagerCard", "monthlyVotesManagerCard", "manualStatsPanel", "manualStatsForm", "playerFilterPosition", "playerFilterTeam"]) {
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
for (const id of ["clubsModule", "playersModule", "competitionsModule", "trainingModule", "matchesModule", "statisticsModule", "healthModule", "disciplineModule", "settingsModule"]) {
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
assert.ok(script.includes("clearCoachTeamData") && script.includes("insertDemoRow"), "Demo loader and safe team-data reset are missing");
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
assert.ok(manualMigration.includes("'manual'"), "Manual match-stat migration is missing");
assert.ok(drillMigration.includes("training_drills") && drillMigration.includes("builtin_drill_key"), "Training drill migration is missing");
assert.ok(competitionMigration.includes("remaining_matches"), "Competition migration is missing");
assert.ok(schema.includes("'suspensions','suspension_match_log','settings'"), "Suspension ledger is missing from owner RLS policy list");
assert.ok(schema.includes("nsm_suspension_log_refs") && schema.includes("revoke all on function public.nsm_account_suspensions_for_match()"), "Suspension ledger ownership or trigger execution is not secured");
assert.ok(suspensionMigration.includes("grant select,insert,update,delete on table public.suspension_match_log") && suspensionMigration.includes("nsm_suspension_log_refs"), "Suspension ledger migration is missing owner-scoped backup permissions");
assert.ok(script.includes('"suspension_match_log"'), "Backup/restore must include the suspension ledger");


const ownerPolicyStart = schema.indexOf("create policy nsm_owner_only on public.%I");
assert.ok(ownerPolicyStart > 0, "Missing dynamic owner-only RLS policy");
const ownerPolicyListStart = schema.lastIndexOf("foreach t in array array[", ownerPolicyStart);
const ownerPolicyListEnd = schema.indexOf("] loop", ownerPolicyListStart);
assert.ok(ownerPolicyListStart >= 0 && ownerPolicyListEnd > ownerPolicyListStart, "Cannot inspect owner RLS table list");
const ownerPolicyList = schema.slice(ownerPolicyListStart, ownerPolicyListEnd);
for (const table of schemaTables) {
  if (table === "profiles" || ["player_evaluations","player_monthly_votes","audience_polls","audience_poll_options","audience_poll_votes","audience_members","public_site_admins","public_posts","audience_notifications","audience_notification_reads","audience_signup_attempts"].includes(table)) continue;
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
assert.ok(html.includes("publicPostsFeed") && html.includes("accountModal") && html.includes("joinFansBtn"), "Public-first homepage and unified account center are missing");
assert.ok(html.includes("publicMatchesFeed") && html.includes("matchPublic") && script.includes("nsm_public_match_feed"), "Explicitly published public match schedule/results are missing");
assert.ok(script.includes("nsm-create-fan") && script.includes("loadFanNotifications") && script.includes("publicSiteAdmin"), "Fan registration, in-app notifications, or gated publishing tools are missing");
assert.ok(schema.includes("audience_members") && schema.includes("public_site_admins") && schema.includes("public_posts") && schema.includes("audience_notifications"), "Public community schema is incomplete");
assert.ok(schema.includes("alter column role set default 'fan'") && schema.includes("role in ('manager','coach','player','fan')"), "Public registrations must default to fan role");
const fanFunction = readFileSync(new URL("../supabase/functions/nsm-create-fan/index.ts", import.meta.url), "utf8");
assert.ok(fanFunction.includes("email_confirm:true") && fanFunction.includes("audience_members") && fanFunction.includes("audience_signup_attempts"), "Fan signup must create a username account with rate limiting");
assert.ok(script.includes('currentProfile?.role==="player"') && script.includes('setPage("playerPortal")'), "Player accounts must be routed to the read-only portal");
assert.ok(script.includes('playerCorrectionForm").addEventListener("submit"') && script.includes('saveRow("player_profile_change_requests"'), "Player corrections must be submitted as review requests, not direct profile edits");
assert.ok(schema.includes("nsm_player_read_own_profile") && schema.includes("nsm_player_change_request_insert") && schema.includes("nsm_player_read_own_team_details"), "Player profile, correction, and team read policies are required");
const playerAccountFunction = readFileSync(new URL("../supabase/functions/nsm-create-player/index.ts", import.meta.url), "utf8");
assert.ok(playerAccountFunction.includes('profile?.role!=="manager"') && playerAccountFunction.includes('.eq("owner_id",data.user.id)'), "Player account creation must be manager-only and owner-scoped");
assert.ok(playerAccountFunction.includes('role:"player"') && playerAccountFunction.includes('user_id:user.user.id'), "Player account must be linked to the existing player record");

console.log("NOUN STAR MANAGER: JavaScript, HTML IDs, Arabic/French translations, and referenced schema tables passed.");
