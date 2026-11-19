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
const session = {
  access_token: "browser-test-access-token",
  refresh_token: "browser-test-refresh-token",
  token_type: "bearer",
  expires_in: 3600,
  expires_at: 4102444800,
  user: {
    id: userId,
    email: "manager+1234@login.nounstar.club",
    aud: "authenticated",
    role: "authenticated",
  },
};

await page.route("https://fatjyhoscjtwthbwiefo.supabase.co/**", async (route) => {
  const request = route.request();
  const url = new URL(request.url());
  const path = url.pathname;

  if (path === "/auth/v1/token") {
    await route.fulfill({ status: 200, contentType: "application/json", body: JSON.stringify(session) });
    return;
  }

  if (path === "/rest/v1/profiles") {
    await route.fulfill({
      status: 200,
      contentType: "application/json",
      body: JSON.stringify([{ role: "manager", display_name: "Browser Test Manager" }]),
    });
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
    await page.waitForFunction(() => window.__nsmBootReady === true, { timeout: 10000 });
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

  // Simulate a manager login without using or storing any real credentials.
  await page.locator("#accountBtn").click();
  await page.locator("#openStaffAccount").click();
  await page.locator("#email").fill("M-1234");
  await page.locator("#password").fill("test-password-only");
  await page.locator("#loginBtn").click();
  await page.locator("#appView:not(.hidden)").waitFor({ timeout: 15000 });
  await page.locator("#managerDashboardPanel:not(.hidden)").waitFor();

  // Mobile navigation drawer must open and close, then navigate to a module.
  await page.locator("#menuBtn").click();
  await page.locator("#sidebar.open").waitFor();
  await page.locator('#nav button[data-page="players"]').click();
  await page.locator("#sidebar:not(.open)").waitFor();
  await page.locator("#playersModule:not(.hidden)").waitFor();

  // Dashboard quick actions must use the same navigation path.
  await page.locator("#menuBtn").click();
  await page.locator('#nav button[data-page="dashboard"]').click();
  await page.locator("#dashboardPage:not(.hidden)").waitFor();
  await page.locator('#dashboardPage [data-goto="matches"]').click();
  await page.locator("#matchesModule:not(.hidden)").waitFor();

  // RTL/LTR switching must continue working inside the authenticated app.
  await page.locator("#langBtn").click();
  await page.waitForFunction(() => document.documentElement.dir === "ltr");
  await page.locator("#menuBtn").click();
  await page.locator("#sidebar.open").waitFor();

  assert.deepEqual(pageErrors, [], "Browser console reported uncaught JavaScript errors");
  assert.deepEqual(consoleErrors, [], "Browser console reported console errors");
  process.stdout.write("PASS: public account, language, manager login, mobile drawer, nav, quick actions, and authenticated language switch.\n");
} finally {
  await context.close();
  await browser.close();
  await new Promise((resolveClose, rejectClose) => server.close((error) => error ? rejectClose(error) : resolveClose()));
}
