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
for (const id of ["loginView", "appView", "dashboardPage", "clubsModule", "playersModule", "matchesModule", "competitionsModule", "trainingModule", "healthModule", "statisticsModule", "disciplineModule", "settingsModule", "lineupPanel", "playerProfilePanel", "manualStatsPanel", "manualStatsForm", "playerFilterPosition", "playerFilterTeam"]) {
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
assert.ok([...drillSection.matchAll(/\{id:"/g)].length >= 16, "Expected at least sixteen bundled original drills");
assert.ok(script.includes("animateTransform"), "Tactical stage playback should animate player movement");
assert.ok(schema.includes("selection_status in ('starter','substitute','not_selected','manual')"), "Schema must support manual match-stat rows");
assert.ok(schema.includes("training_session_drills") && schema.includes("builtin_drill_key"), "Schema must support built-in and custom drills in session plans");
const manualMigration = readFileSync(new URL("../supabase/migrations/20261118_manual_match_stats.sql", import.meta.url), "utf8");
const drillMigration = readFileSync(new URL("../supabase/migrations/20261118_training_drill_library.sql", import.meta.url), "utf8");
const competitionMigration = readFileSync(new URL("../supabase/migrations/20261118_competition_manual_results.sql", import.meta.url), "utf8");
assert.ok(manualMigration.includes("'manual'"), "Manual match-stat migration is missing");
assert.ok(drillMigration.includes("training_drills") && drillMigration.includes("builtin_drill_key"), "Training drill migration is missing");
assert.ok(competitionMigration.includes("remaining_matches"), "Competition migration is missing");

console.log("NOUN STAR MANAGER: JavaScript, HTML IDs, Arabic/French translations, and referenced schema tables passed.");
