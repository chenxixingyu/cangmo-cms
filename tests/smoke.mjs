// Cangmo smoke test: setup wizard, login session, public pages, security headers.
const BASE = process.env.CANGMO_BASE || "http://127.0.0.1:18081";
const TOKEN = process.env.CANGMO_SETUP_TOKEN || "test-setup-token-123456";

function cookiesFrom(response, jar) {
  const raw = response.headers.get("set-cookie");
  if (!raw) return;
  for (const part of raw.split(/,(?=[^;]+=)/)) {
    const pair = part.split(";")[0].trim();
    const eq = pair.indexOf("=");
    if (eq > 0) jar.set(pair.slice(0, eq), pair.slice(eq + 1));
  }
}

function cookieHeader(jar) {
  return [...jar.entries()].map(([k, v]) => `${k}=${v}`).join("; ");
}

async function req(path, options = {}, jar) {
  const headers = Object.assign({}, options.headers || {});
  if (jar && jar.size) headers["cookie"] = cookieHeader(jar);
  const response = await fetch(BASE + path, { ...options, headers, redirect: "manual" });
  if (jar) cookiesFrom(response, jar);
  const text = await response.text();
  return { status: response.status, headers: response.headers, text, location: response.headers.get("location") };
}

function assert(condition, message) {
  if (!condition) {
    console.error("FAIL:", message);
    process.exitCode = 1;
  } else {
    console.log("ok:", message);
  }
}

function csrfOf(html) {
  const match = html.match(/name="_csrf" value="([^"]+)"/);
  return match ? match[1] : "";
}

const jar = new Map();

const setup = await req("/setup", {}, jar);
assert(setup.status === 200, "GET /setup is 200");
assert(setup.headers.get("content-security-policy")?.includes("default-src"), "CSP header present");
assert(setup.headers.get("x-frame-options") === "DENY", "X-Frame-Options DENY");
assert(setup.headers.get("x-content-type-options") === "nosniff", "nosniff present");
const csrf = csrfOf(setup.text);
assert(csrf.length > 10, "setup page carries CSRF token");

const form = new URLSearchParams();
form.set("_csrf", csrf);
form.set("token", TOKEN);
form.set("site_title", "仓墨测试站");
form.set("username", "admin");
form.set("email", "admin@example.com");
form.set("password", "Cangmo-Test-2026!");
form.set("password_confirm", "Cangmo-Test-2026!");
const setupPost = await req("/setup", {
  method: "POST",
  headers: { "content-type": "application/x-www-form-urlencoded" },
  body: form.toString(),
}, jar);
assert(setupPost.status === 303, "POST /setup redirects (303)");
assert((setupPost.location || "").startsWith("/admin"), "setup redirects to admin");

const home = await req("/", {}, jar);
assert(home.status === 200, "GET / is 200");
assert(home.text.includes("仓墨测试站"), "home contains site title");
assert(home.text.includes("欢迎使用仓墨"), "welcome post is visible");
assert(home.headers.get("set-cookie") === null, "no repeated session cookie on subsequent requests");

const admin = await req("/admin", {}, jar);
assert(admin.status === 200, "GET /admin is 200 after setup");
assert(admin.text.includes("仪表盘"), "dashboard rendered");

const postPage = await req("/posts/hello-cangmo", {}, jar);
assert(postPage.status === 200, "welcome post page is 200");
assert(postPage.text.includes("欢迎使用仓墨"), "post title rendered");
assert(!postPage.text.includes("<script>alert"), "no injected script");

const feed = await req("/feed.xml", {}, jar);
assert(feed.status === 200 && feed.text.startsWith("<?xml"), "RSS feed is XML");
assert(feed.text.includes("<item>"), "RSS feed has items");

const sitemap = await req("/sitemap.xml", {}, jar);
assert(sitemap.status === 200 && sitemap.text.includes("<urlset"), "sitemap is valid");

const robots = await req("/robots.txt", {}, jar);
assert(robots.status === 200 && robots.text.includes("Sitemap:"), "robots.txt present");

const health = await req("/healthz", {}, jar);
assert(health.status === 200 && health.text.includes("\"ok\""), "healthz ok");

const missing = await req("/nope", {}, jar);
assert(missing.status === 404, "unknown page is 404");

const traversal = await req("/static/../config.json", {}, jar);
assert(traversal.status === 404 || traversal.status === 400, "path traversal rejected");

const api = await req("/api/v1/posts", {}, jar);
assert(api.status === 200 && api.text.includes("hello-cangmo"), "API lists posts");

console.log("smoke test complete");
