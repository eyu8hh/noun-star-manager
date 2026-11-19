import assert from "node:assert/strict";
import { createServer } from "node:http";
import { readFile } from "node:fs/promises";
import { extname, resolve, sep } from "node:path";
import { fileURLToPath } from "node:url";
import { chromium } from "playwright";

const root = resolve(fileURLToPath(new URL("..", import.meta.url)));
const mime = {
  ".html": "text/html; charset=utf-8",
  ".js": "text/javascript; charset=utf-8",
  ".css": "text/css; charset=utf-8",
  ".json": "application/json; charset=utf-8",
  ".webmanifest": "application/manifest+json",
  ".png": "image/png",
  ".svg": "image/svg+xml",
};

const server = createServer(async (req, res) => {
  try {
    const pathname = decodeURIComponent(new URL(req.url, "http://127.0.0.1").pathname);
    const relative = pathname === "/" ? "index.html" : pathname.replace(/^\/+/, "");
    const file = resolve(root, relative);
    if (file !== root && !file.startsWith(root + sep)) {
      res.writeHead(403).end("Forbidden");
      return;
    }
    const body = await readFile(file);
    res.writeHead(200, { "content-type": mime[extname(file)] || "application/octet-stream" });
    res.end(body);
  } catch {
    res.writeHead(404).end("Not found");
  }
});

await new Promise((resolveListen) => server.listen(0, "127.0.0.1", resolveListen));
const address = server.address();
const baseUrl = `http://127.0.0.1:${address.port}/`;
const browser = await chromium.launch({ headless: true });
const context = await browser.newContext({
  viewport: { width: 390, height: 844 },
  isMobile: true,
  hasTouch: true,
  serviceWorkers: "block",
});
const page = await context.newPage();
const pageErrors = [];
const consoleErrors = [];
page.on("pageerror", (error) => pageErrors.push(error.stack || error.message));
page.on("console", (message) => { if (message.type() === "error") consoleErrors.push(message.text()); });

const userId = "11111111-1111-4111-8111-111111111111";
let activeRole = "manager";
const sessionForRole = () => ({
  access_token: "browser-test-access-token",
  refresh_token: "browser-test-refresh-token",
  token_type: "bearer",
  expires_in: 3600,
  expires_at: 4102444800,
  user: {
    id: userId,
    email: activeRole === "fan" ? "fan+testuser@fans.nounstar.club" : `${activeRole}+1234@login.nounstar.club`,
    aud: "authenticated",
    role: "authenticated",
  },
});

await page.route("https://fatjyhoscjtwthbwiefo.supabase.co/**", async (route) => {
  const request = route.request();
  const url = new URL(request.url());
  const path = url.pathname;

  if (path === "/auth/v1/token") {
    await route.fulfill({ status: 200, contentType: "application/json", body: JSON.stringify(sessionForRole()) });
    return;
  }

  if (path === "/rest/v1/profiles") {
    await route.fulfill({
      status: 200,
      contentType: "application/json",
      body: JSON.stringify([{ role: activeRole, display_name: `Browser Test ${activeRole}` }]),
    });
    return;
  }

  if (path === "/rest/v1/audience_members" && activeRole === "fan") {
    await route.fulfill({ status: 200, contentType: "application/json", body: JSON.stringify([{ user_id: userId, username: "testuser", display_name: "Browser Test Fan", notifications_enabled: true }]) });
    return;
  }

  if (path === "/rest/v1/players" && activeRole === "player" && url.searchParams.get("user_id") === `eq.${userId}`) {
    await route.fulfill({ status: 200, contentType: "application/json", body: JSON.stringify([{ id: "22222222-2222-4222-8222-222222222222", user_id: userId, full_name: "Browser Test Player", shirt_number: 9, primary_position: "FW", availability: "available" }]) });
    return;
  }

  if (path.startsWith("/rest/v1/")) {
    const headers = { "content-type": "application/json" };
    if (request.headers()["prefer"]?.includes("count=exact")) headers["content-range"] = "*/0";
    await route.fulfill({ status: 200, headers, body: "[]" });
    return;
  }

  await route.fulfill({ status: 200, contentType: "application/json", body: "{}" });
});

try {
  await page.goto(baseUrl, { waitUntil: "domcontentloaded" });
  try {
    await page.waitForFunction(() => window.__nsmBootReady === true, null, { timeout: 10000 });
  } catch {
    const loginError = await page.locator("#loginError").textContent().catch(() => "unavailable");
    const diagnostics = { pageErrors, consoleErrors, loginError, ready: await page.evaluate(() => window.__nsmBootReady ?? false) };
    throw new Error("Application bootstrap did not complete: " + JSON.stringify(diagnostics));
  }

  // Public account center and language switch must be interactive before sign-in.
  await page.locator("#accountBtn").click();
  await page.locator("#accountModal:not(.hidden)").waitFor();
  await page.locator("#closeAccountModal").click();
  await page.locator("#accountModal").waitFor({ state: "hidden" });

  await page.locator("#publicLangBtn").click();
  await page.waitForFunction(() => document.documentElement.dir === "ltr");
  await page.locator("#publicLangBtn").click();
  await page.waitForFunction(() => document.documentElement.dir === "rtl");

  async function staffLogin(role, code) {
    activeRole = role;
    await page.locator("#accountBtn").click();
    await page.locator("#openStaffAccount").click();
    await page.locator("#email").fill(code);
    await page.locator("#password").fill("test-password-only");
    await page.locator("#loginBtn").click();
    await page.locator("#appView:not(.hidden)").waitFor({ timeout: 15000 });
  }
  async function staffLogout() {
    const logoutGeometry = await page.locator("#logoutBtn").evaluate((el) => { const r = el.getBoundingClientRect(); const hit = document.elementFromPoint(r.x + r.width / 2, r.y + r.height / 2); return { rect: { x: r.x, y: r.y, width: r.width, height: r.height }, hitId: hit?.id || "", hitClass: typeof hit?.className === "string" ? hit.className : "", dir: document.documentElement.dir }; });
    if (logoutGeometry.hitId !== "logoutBtn") throw new Error("Logout button is covered on mobile: " + JSON.stringify(logoutGeometry));
    await page.locator("#logoutBtn").click();
    await page.locator("#loginView:not(.hidden)").waitFor();
  }

  // Manager: dashboard, drawer, sidebar navigation, quick actions, and language.
  await staffLogin("manager", "M-1234");
  await page.locator("#managerDashboardPanel:not(.hidden)").waitFor();
  await page.locator("#menuBtn").click();
  await page.locator("#sidebar.open").waitFor();
  await page.locator('#nav button[data-page="players"]').click();
  await page.locator("#sidebar:not(.open)").waitFor();
  await page.locator("#playersModule:not(.hidden)").waitFor();
  await page.locator("#menuBtn").click();
  await page.locator('#nav button[data-page="dashboard"]').click();
  await page.locator("#dashboardPage:not(.hidden)").waitFor();
  await page.locator('#dashboardPage [data-goto="matches"]').click();
  await page.locator("#matchesModule:not(.hidden)").waitFor();
  await page.locator("#langBtn").click();
  await page.waitForFunction(() => document.documentElement.dir === "ltr");
  await staffLogout();

  // Coach: manager-only workspaces must remain hidden; training remains usable.
  await staffLogin("coach", "C-1234");
  await page.locator("#managerDashboardPanel").waitFor({ state: "hidden" });
  await page.locator("#financeNav").waitFor({ state: "hidden" });
  await page.locator('#nav button[data-page="clubs"]').waitFor({ state: "hidden" });
  await page.locator("#menuBtn").click();
  await page.locator("#sidebar.open").waitFor();
  await page.waitForFunction(() => getComputedStyle(document.getElementById("sidebar")).transform === "matrix(1, 0, 0, 1, 0, 0)", null, { timeout: 2000 });
  const drawerState = await page.locator("#sidebar").evaluate((el) => ({ rect: (() => { const r = el.getBoundingClientRect(); return { x: r.x, width: r.width }; })(), transform: getComputedStyle(el).transform, dir: document.documentElement.dir }));
  const drawerBox = await page.locator("#sidebar").boundingBox();
  assert.ok(drawerBox && drawerBox.x < 390 && drawerBox.x + drawerBox.width > 0, "LTR mobile drawer must intersect the visible viewport: " + JSON.stringify(drawerState));
  await page.locator('#nav button[data-page="training"]').click();
  await page.locator("#trainingModule:not(.hidden)").waitFor();
  await staffLogout();

  // Player: the player portal is the only workspace exposed to this role.
  await staffLogin("player", "P-1234");
  await page.locator("#playerPortalNav:not(.hidden)").waitFor();
  await page.locator('#nav button[data-page="dashboard"]').waitFor({ state: "hidden" });
  await page.locator("#playerPortalProfile").getByText("Browser Test Player").waitFor();
  await staffLogout();

  // Fan: public username/password login returns to the public account center.
  activeRole = "fan";
  await page.locator("#accountBtn").click();
  await page.locator("#openFanAccount").click();
  await page.locator("#fanLoginUsername").fill("testuser");
  await page.locator("#fanLoginPassword").fill("test-password-only");
  await page.locator("#fanLoginSubmit").click();
  await page.waitForFunction(() => document.getElementById("accountBtnLabel")?.textContent === "Browser Test Fan");
  await page.locator("#accountBtn").click();
  await page.locator("#fanSignedInPanel:not(.hidden)").waitFor();
  await page.locator("#fanLogoutBtn").click();
  await page.locator("#loginView:not(.hidden)").waitFor();

  assert.deepEqual(pageErrors, [], "Browser console reported uncaught JavaScript errors");
  assert.deepEqual(consoleErrors, [], "Browser console reported console errors");
  process.stdout.write("PASS: public account, RTL/LTR, manager, coach, player, fan login, role permissions, mobile drawer, navigation, and quick actions.\n");
} finally {
  await context.close();
  await browser.close();
  await new Promise((resolveClose, rejectClose) => server.close((error) => error ? rejectClose(error) : resolveClose()));
}
