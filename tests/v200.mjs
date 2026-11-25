// Cangmo v2.0 regression: multi-site, plugins, members, newsletter, admin pages.
const BASE = process.env.CANGMO_BASE || "http://127.0.0.1:18090";
const jar = new Map();
function cookies(response) {
  for (const raw of (response.headers.getSetCookie?.() || [])) {
    const pair = raw.split(";")[0].trim();
    const eq = pair.indexOf("=");
    if (eq > 0) jar.set(pair.slice(0, eq), pair.slice(eq + 1));
  }
}
const cookieHeader = () => [...jar.entries()].map(([k, v]) => `${k}=${v}`).join("; ");
async function req(path, options = {}) {
  const headers = Object.assign({}, options.headers || {});
  if (jar.size) headers.cookie = cookieHeader();
  const response = await fetch(BASE + path, { ...options, headers, redirect: "manual" });
  cookies(response);
  return { status: response.status, location: response.headers.get("location"), text: await response.text() };
}
const csrfOf = (html) => (html.match(/name="_csrf" value="([^"]+)"/) || [])[1] || "";
const form = (obj) => { const p = new URLSearchParams(); for (const [k, v] of Object.entries(obj)) p.set(k, v); return p.toString(); };
function assert(ok, message) { console.log((ok ? "ok: " : "FAIL: ") + message); if (!ok) process.exitCode = 1; }

let page = await req("/admin/login");
let csrf = csrfOf(page.text);
await req("/admin/login", { method: "POST", headers: { "content-type": "application/x-www-form-urlencoded" }, body: form({ _csrf: csrf, username: "admin", password: "Cangmo-Test-2026!", next: "" }) });
for (const path of ["/admin/sites", "/admin/plugins", "/admin/members", "/admin/newsletter", "/admin/oauth", "/admin/themes/market"]) {
  page = await req(path);
  assert(page.status === 200, `admin page renders: ${path}`);
}
page = await req("/admin/sites");
csrf = csrfOf(page.text);
await req("/admin/sites/create", { method: "POST", headers: { "content-type": "application/x-www-form-urlencoded" }, body: form({ _csrf: csrf, name: "Second Site", domain: "second.example" }) });
page = await req("/admin/sites");
const siteId = page.text.split("<code>site_").slice(1).map((p) => "site_" + p.split("</code>")[0]).find((id) => id !== "site_default");
assert(!!siteId, "second site created");
csrf = csrfOf(page.text);
await req("/admin/site/switch", { method: "POST", headers: { "content-type": "application/x-www-form-urlencoded" }, body: form({ _csrf: csrf, site_id: siteId, return_to: "/admin" }) });
page = await req("/admin/posts");
assert(!page.text.includes("欢迎使用仓墨"), "admin scoped to second site");
csrf = csrfOf(page.text);
await req("/admin/site/switch", { method: "POST", headers: { "content-type": "application/x-www-form-urlencoded" }, body: form({ _csrf: csrf, site_id: "site_default", return_to: "/admin" }) });

page = await req("/admin/members"); csrf = csrfOf(page.text);
await req("/admin/members/action", { method: "POST", headers: { "content-type": "application/x-www-form-urlencoded" }, body: form({ _csrf: csrf, action: "plan", name: "Test Plan", price_cents: "100", interval: "month" }) });
page = await req("/admin/members");
const planId = (page.text.match(/<option value="(plan_[^"]+)"/) || [])[1];
assert(!!planId, "membership plan created");
await req("/admin/members/action", { method: "POST", headers: { "content-type": "application/x-www-form-urlencoded" }, body: form({ _csrf: csrf, action: "grant", email: "admin@example.com", plan_id: planId, days: "30" }) });
page = await req("/admin/members");
assert(page.text.includes("admin@example.com") && page.text.includes("active"), "membership granted");
page = await req("/admin/posts/new"); csrf = csrfOf(page.text);
await req("/admin/posts/save", { method: "POST", headers: { "content-type": "application/x-www-form-urlencoded" }, body: form({ _csrf: csrf, id: "", type: "post", title: "Members Only", slug: "members-only", summary: "", content: "PAYWALL-BODY", status: "published", access: "members", category_id: "", tags: "", cover: "", allow_comments: "on", pinned: "", featured: "", seo_title: "", seo_description: "", scheduled_at: "" }) });
const anon = await fetch(BASE + "/posts/members-only");
const anonText = await anon.text();
assert(anon.status === 200 && anonText.includes("会员内容") && !anonText.includes("PAYWALL-BODY"), "anonymous paywall");
const member = await req("/posts/members-only");
assert(member.text.includes("PAYWALL-BODY"), "member reads full post");

page = await req("/newsletter"); csrf = csrfOf(page.text);
const subscribe = await req("/newsletter/subscribe", { method: "POST", headers: { "content-type": "application/x-www-form-urlencoded" }, body: form({ _csrf: csrf, email: "reader@example.com", name: "Reader" }) });
assert(subscribe.status === 200 && subscribe.text.includes("确认邮件已发送"), "newsletter subscribe queued");

page = await req("/admin/plugins"); csrf = csrfOf(page.text);
await req("/admin/plugins/save", { method: "POST", headers: { "content-type": "application/x-www-form-urlencoded" }, body: new URLSearchParams([["_csrf", csrf], ["action", "create"], ["name", "Dead"], ["endpoint", "http://127.0.0.1:18099/dead"], ["secret", "s"], ["events", "post.published"], ["capabilities", "posts.read"]]).toString() });
page = await req("/admin/posts/new"); csrf = csrfOf(page.text);
const created = await req("/admin/posts/save", { method: "POST", headers: { "content-type": "application/x-www-form-urlencoded" }, body: form({ _csrf: csrf, id: "", type: "post", title: "Event", slug: "event", summary: "", content: "Body", status: "draft", access: "public", category_id: "", tags: "", cover: "", allow_comments: "on", pinned: "", featured: "", seo_title: "", seo_description: "", scheduled_at: "" }) });
const postId = (created.location.match(/posts\/(post_[^/]+)\/edit/) || [])[1];
page = await req(`/admin/posts/${postId}/edit`); csrf = csrfOf(page.text);
await req(`/admin/posts/${postId}/action`, { method: "POST", headers: { "content-type": "application/x-www-form-urlencoded" }, body: form({ _csrf: csrf, action: "publish" }) });
page = await req("/admin/jobs");
assert(page.text.includes("plugin") && page.text.includes("pending"), "plugin retry job queued");
console.log("v2.0 regression complete");
