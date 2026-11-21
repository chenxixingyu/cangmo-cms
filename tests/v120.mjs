const BASE = process.env.CANGMO_BASE || "http://127.0.0.1:18085";
const jar = new Map();
function ck(r) { for (const x of (r.headers.getSetCookie?.() || [])) { const p = x.split(";")[0].trim(); const i = p.indexOf("="); if (i > 0) jar.set(p.slice(0, i), p.slice(i + 1)); } }
const ckH = () => [...jar.entries()].map(([k, v]) => k + "=" + v).join("; ");
async function req(p, o = {}) { const h = Object.assign({}, o.headers || {}); if (jar.size) h.cookie = ckH(); const r = await fetch(BASE + p, { ...o, headers: h, redirect: "manual" }); ck(r); return { status: r.status, location: r.headers.get("location"), text: await r.text() }; }
const csrfOf = (h) => (h.match(/name="_csrf" value="([^"]+)"/) || [])[1] || "";
const form = (o) => { const p = new URLSearchParams(); for (const [k, v] of Object.entries(o)) p.set(k, v); return p.toString(); };
function assert(ok, message) { console.log((ok ? "ok: " : "FAIL: ") + message); if (!ok) process.exitCode = 1; }

let page = await req("/admin/login");
let csrf = csrfOf(page.text);
await req("/admin/login", { method: "POST", headers: { "content-type": "application/x-www-form-urlencoded" }, body: form({ _csrf: csrf, username: "admin", password: "Cangmo-Test-2026!", next: "" }) });
page = await req("/admin/posts/new?type=page");
csrf = csrfOf(page.text);
assert(page.text.includes('name="template"') && page.text.includes("page-wide.html"), "page editor lists templates");
const created = await req("/admin/posts/save", { method: "POST", headers: { "content-type": "application/x-www-form-urlencoded" }, body: form({ _csrf: csrf, id: "", type: "page", title: "模板页", slug: "tpl-old", summary: "", content: "模板正文", status: "published", category_id: "", tags: "", cover: "", template: "page-wide.html", allow_comments: "on", pinned: "", featured: "", seo_title: "", seo_description: "", scheduled_at: "" }) });
assert(created.status === 303, "page with template created");
assert((await req("/pages/tpl-old")).text.includes("page-wide"), "page renders selected template");
page = await req("/admin/posts?type=page");
const row = page.text.split('<tr class="post-row"').find((block) => block.includes("模板页")) || "";
const pageId = (row.match(/data-post-id="(post_[^"]+)"/) || [])[1];
csrf = csrfOf(page.text);
const moved = await req("/admin/posts/save", { method: "POST", headers: { "content-type": "application/x-www-form-urlencoded" }, body: form({ _csrf: csrf, id: pageId, type: "page", title: "模板页", slug: "tpl-new", summary: "", content: "模板正文", status: "published", category_id: "", tags: "", cover: "", template: "page-wide.html", allow_comments: "on", pinned: "", featured: "", seo_title: "", seo_description: "", scheduled_at: "" }) });
assert(moved.status === 303, "page slug changed");
let old = await req("/pages/tpl-old");
assert(old.status === 301 && (old.location || "").includes("/pages/tpl-new"), "old page path 301s to new path");
old = await req("/tpl-old");
assert(old.status === 301 && (old.location || "").includes("/pages/tpl-new"), "old root page path 301s");
assert((await req("/pages/tpl-new")).status === 200, "new page path serves content");
page = await req("/admin/redirects");
assert(page.status === 200 && page.text.includes("/pages/tpl-old") && page.text.includes("/pages/tpl-new"), "redirect admin lists automatic rule");
csrf = csrfOf(page.text);
const manual = await req("/admin/redirects/save", { method: "POST", headers: { "content-type": "application/x-www-form-urlencoded" }, body: form({ _csrf: csrf, action: "create", from: "/legacy", to: "/pages/tpl-new" }) });
assert(manual.status === 303, "manual redirect saved");
const legacy = await req("/legacy");
assert(legacy.status === 301 && (legacy.location || "").includes("/pages/tpl-new"), "manual redirect works");
const bad = await req("/admin/redirects/save", { method: "POST", headers: { "content-type": "application/x-www-form-urlencoded" }, body: form({ _csrf: csrf, action: "create", from: "/bad-redirect", to: "https://example.com" }) });
assert(bad.status === 303, "external redirect rejected");
assert((await req("/bad-redirect")).status === 404, "rejected redirect not active");
console.log("v1.2 batch check complete");
