import { readFileSync } from "node:fs";
import { strict as assert } from "node:assert";

const html = readFileSync(new URL("../index.html", import.meta.url), "utf8");
const scripts = [...html.matchAll(/<script(?:\\s[^>]*)?>([\\s\\S]*?)<\\/script>/gi)];
assert.equal(scripts.length, 1, "Expected exactly one inline application script");
new Function(scripts[0][1]);
const ids = [...html.matchAll(/\\bid="([^"]+)"/g)].map((m) => m[1]);
const duplicates = ids.filter((id, i) => ids.indexOf(id) !== i);
assert.deepEqual(duplicates, [], "HTML contains duplicate IDs");
for (const id of ["loginView", "appView", "dashboardPage", "clubsModule", "playersModule", "matchesModule"]) {
  assert.ok(ids.includes(id), `Missing required app section: ${id}`);
}
console.log("NOUN STAR MANAGER: inline JavaScript syntax and core HTML checks passed.");
