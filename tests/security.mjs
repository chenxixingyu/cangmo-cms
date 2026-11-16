// Cangmo security regression tests.
import net from "node:net";

const BASE = process.env.CANGMO_BASE || "http://127.0.0.1:18085";
const HOST = new URL(BASE).hostname;
const PORT = Number(new URL(BASE).port || 80);
const jar = new Map();

function storeCookies(response) {
  const list = response.headers.getSetCookie ? response.headers.getSetCookie() : [];
  for (const raw of list) {
    const pair = raw.split(";")[0].trim();
    const eq = pair.indexOf("=");
    if (eq > 0) jar.set(pair.slice(0, eq), pair.slice(eq + 1));
  }
  return list;
}
function cookieHeader() {
  return [...jar.entries()].map(([k, v]) => `${k}=${v}`).join("; ");
}
async function req(path, options = {}) {
  const headers = Object.assign({}, options.headers || {});
  if (jar.size) headers.cookie = cookieHeader();
  const response = await fetch(BASE + path, { ...options, headers, redirect: "manual" });
  const setCookies = storeCookies(response);
  const text = await response.text();
  return { status: response.status, location: response.headers.get("location"), text, headers: response.headers, setCookies };
}
function csrfOf(html) {
  return (html.match(/name="_csrf" value="([^"]+)"/) || [])[1] || "";
}
function form(fields) {
  const params = new URLSearchParams();
  for (const [key, value] of Object.entries(fields)) params.set(key, value);
  return params.toString();
}
async function postForm(path, fields, csrf) {
  return req(path, {
    method: "POST",
    headers: { "content-type": "application/x-www-form-urlencoded" },
    body: form(Object.assign({ _csrf: csrf }, fields))
  });
}
function assert(ok, message) {
  if (!ok) { console.error("FAIL:", message); process.exitCode = 1; } else { console.log("ok:", message); }
}
function rawRequest(payload) {
  return new Promise((resolve) => {
    const socket = net.connect(PORT, HOST);
    let data = "";
    const timer = setTimeout(() => { socket.destroy(); resolve(data); }, 2500);
    socket.on("connect", () => socket.write(payload));
    socket.on("data", (chunk) => { data += chunk.toString("latin1"); });
    socket.on("close", () => { clearTimeout(timer); resolve(data); });
    socket.on("error", () => { clearTimeout(timer); resolve(data); });
  });
}

// Login and capture cookie flags / rotation.
let page = await req("/admin/login");
const firstCookies = page.setCookies;
const firstSession = [...jar.entries()].find(([k]) => k === "cangmo_sid")?.[1];
const cookieText = firstCookies.join(";");
assert(firstCookies.length > 0, "login page sets a session cookie");
assert(cookieText.includes("HttpOnly"), "session cookie is HttpOnly");
assert(cookieText.includes("SameSite=Lax"), "session cookie is SameSite=Lax");
let csrf = csrfOf(page.text);
const login = await postForm("/admin/login", { username: "admin", password: "Cangmo-Test-2026!", next: "" }, csrf);
assert(login.status === 303, "login succeeds");
const secondSession = [...jar.entries()].find(([k]) => k === "cangmo_sid")?.[1];
assert(firstSession && secondSession && firstSession !== secondSession, "session rotates on login");

// CSRF protection.
const noCsrf = await fetch(BASE + "/admin/posts/save", {
  method: "POST",
  headers: { cookie: cookieHeader(), "content-type": "application/x-www-form-urlencoded" },
  body: form({ title: "csrf" }),
  redirect: "manual"
});
assert(noCsrf.status === 403, "admin write without CSRF is rejected");
const apiNoAuth = await fetch(BASE + "/api/v1/posts", {
  method: "POST",
  headers: { "content-type": "application/json" },
  body: JSON.stringify({ title: "x", content: "x" })
});
assert(apiNoAuth.status === 401, "API write without token is rejected");

// XSS: title with HTML must be escaped.
page = await req("/admin/posts/new");
csrf = csrfOf(page.text);
const xssTitle = "<img src=x onerror=alert(1)>";
const created = await postForm("/admin/posts/save", {
  id: "", type: "post", title: xssTitle, slug: "xss-title", summary: "xss",
  content: "正文", status: "published", category_id: "", tags: "", cover: "",
  allow_comments: "on", pinned: "", featured: "", seo_title: "", seo_description: "", scheduled_at: ""
}, csrf);
assert(created.status === 303, "XSS test post created");
page = await req("/posts/xss-title");
assert(page.status === 200, "XSS test post is readable");
assert(!page.text.includes("<img src=x onerror=alert(1)>"), "title HTML is escaped");
assert(page.text.includes("&lt;img src=x onerror=alert(1)&gt;"), "escaped title is visible as text");

// Path traversal, encoded and raw.
for (const path of ["/static/../config.json", "/static/%2e%2e/%2e%2e/config.json", "/media/../db.json", "/media/%2e%2e/db.json"]) {
  const response = await req(path);
  assert(response.status === 400 || response.status === 404, `path traversal blocked: ${path} (${response.status})`);
}

// Raw HTTP hardening.
const dupCL = await rawRequest(
  "POST / HTTP/1.1\r\nHost: test\r\nContent-Length: 3\r\nContent-Length: 3\r\nConnection: close\r\n\r\nabc"
);
assert(/^HTTP\/1\.1 400/.test(dupCL), "duplicate Content-Length rejected");
const clTe = await rawRequest(
  "POST / HTTP/1.1\r\nHost: test\r\nContent-Length: 3\r\nTransfer-Encoding: chunked\r\nConnection: close\r\n\r\n0\r\n\r\n"
);
assert(/^HTTP\/1\.1 400/.test(clTe), "Content-Length + Transfer-Encoding rejected");
const bigBody = await rawRequest(
  "POST / HTTP/1.1\r\nHost: test\r\nContent-Length: 30000000\r\nConnection: close\r\n\r\n"
);
assert(/^HTTP\/1\.1 413/.test(bigBody), "oversized body rejected with 413");
const noHost = await rawRequest("GET / HTTP/1.1\r\nConnection: close\r\n\r\n");
assert(/^HTTP\/1\.1 400/.test(noHost), "HTTP/1.1 without Host rejected");
const badMethod = await rawRequest("TRACE / HTTP/1.1\r\nHost: test\r\nConnection: close\r\n\r\n");
assert(/^HTTP\/1\.1 400/.test(badMethod), "TRACE method rejected");
const hugeHeader = await rawRequest(
  "GET / HTTP/1.1\r\nHost: test\r\nX-Big: " + "a".repeat(70000) + "\r\nConnection: close\r\n\r\n"
);
assert(/^HTTP\/1\.1 400/.test(hugeHeader), "oversized headers rejected");

// Fake image upload (magic mismatch).
page = await req("/admin/media");
csrf = csrfOf(page.text);
const uploadForm = new FormData();
uploadForm.set("_csrf", csrf);
uploadForm.set("files", new Blob(["<script>alert(1)</script>"], { type: "image/png" }), "evil.png");
const fakeUpload = await req("/admin/media/upload", { method: "POST", body: uploadForm });
assert(fakeUpload.status === 303, "fake upload handled");
page = await req("/admin/media");
assert(!page.text.includes("evil.png"), "fake PNG rejected by magic check");

// Token leakage: after creation page must not contain the raw token again.
page = await req("/admin/profile");
csrf = csrfOf(page.text);
await postForm("/admin/profile/token", { name: "security-test" }, csrf);
page = await req("/admin/profile"); // first view: token is shown once
page = await req("/admin/profile"); // reload: token must be gone
assert(!/cmo_[A-Za-z0-9_-]{20,}/.test(page.text), "API token is not shown again after creation");

// Generic login failure using a fresh session (not the logged-in one).
jar.clear();
page = await req("/admin/login");
const bad = await postForm("/admin/login", { username: "admin", password: "definitely-wrong", next: "" }, csrfOf(page.text));
assert(bad.status === 401, "bad password returns 401");
assert(bad.text.includes("用户名或密码错误"), "login failure is generic");

// API rate limit (run last: 130 requests).
let limited = 0;
for (let i = 0; i < 130; i += 1) {
  const response = await fetch(BASE + "/api/v1/site");
  if (response.status === 429) limited += 1;
}
assert(limited > 0, "API rate limiting triggers (429 observed)");

console.log("security test complete");
