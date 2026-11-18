import { readFileSync } from "node:fs";
import { strict as assert } from "node:assert";

const html = readFileSync(new URL("../index.html", import.meta.url), "utf8");
const start = html.indexOf("<script>");
const end = html.indexOf("</script>", start);
assert.ok(start >= 0 && end > start, "Expected one inline application script");
assert.equal(html.indexOf("<script>", start + 1), -1, "Expected exactly one inline application script");
new Function(html.slice(start + 8, end));
const ids = [...html.matchAll(/id="([^"]+)"/g)].map((m) => m[1]);
const duplicates = ids.filter((id, i) => ids.indexOf(id) !== i);
assert.deepEqual(duplicates, [], "HTML contains duplicate IDs");
for (const id of ["loginView", "appView", "dashboardPage", "clubsModule", "playersModule", "matchesModule"]) {
  assert.ok(ids.includes(id), "Missing required app section: " + id);
}
console.log("NOUN STAR MANAGER: inline JavaScript syntax and core HTML checks passed.");
