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
async function savePost(title, slug, content, status) {
  const p = await req("/admin/posts/new");
  const c = csrfOf(p.text);
  const r = await req("/admin/posts/save", { method: "POST", headers: { "content-type": "application/x-www-form-urlencoded" }, body: form({ _csrf: c, id: "", type: "post", title, slug, summary: "", content, status, category_id: "", tags: "", cover: "", allow_comments: "on", pinned: "", featured: "", seo_title: "", seo_description: "", scheduled_at: "" }) });
  return { status: r.status, location: r.location, id: (r.location.match(/posts\/(post_[^/]+)\/edit/) || [])[1] };
}
const first = await savePost("仓颉搜索测试", "search-first", "这是正文，包含火箭关键词。", "published");
await savePost("另一篇文章", "search-second", "普通内容。", "published");
await savePost("English Search", "search-third", "Hello world content.", "published");
assert(first.status === 303, "search fixtures created");
let search = await req("/search?q=" + encodeURIComponent("仓颉"));
assert(search.text.includes("搜索测试") && search.text.includes("<mark>仓颉</mark>"), "Chinese title search works");
search = await req("/search?q=" + encodeURIComponent("火箭"));
assert(search.text.includes("仓颉搜索测试"), "Chinese content search works");
search = await req("/search?q=english");
assert(search.text.includes("Search") && search.text.includes("<mark>English</mark>"), "ASCII case-insensitive search works");
search = await req("/search?q=" + encodeURIComponent("不存在的词"));
assert(!search.text.includes("仓颉搜索测试"), "empty search has no false positives");

// Edit and hide through status; index must refresh through the WAL generation.
page = await req(`/admin/posts/${first.id}/edit`);
csrf = csrfOf(page.text);
await req("/admin/posts/save", { method: "POST", headers: { "content-type": "application/x-www-form-urlencoded" }, body: form({ _csrf: csrf, id: first.id, type: "post", title: "仓颉搜索测试", slug: "search-first", summary: "", content: "改为草稿内容。", status: "draft", category_id: "", tags: "", cover: "", allow_comments: "on", pinned: "", featured: "", seo_title: "", seo_description: "", scheduled_at: "" }) });
search = await req("/search?q=" + encodeURIComponent("仓颉"));
assert(!search.text.includes("仓颉搜索测试"), "draft disappears from search");

// Media bulk delete.
page = await req("/admin/attachments");
csrf = csrfOf(page.text);
const png = Buffer.from("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/p9sAAAAASUVORK5CYII=", "base64");
const ids = [];
for (const name of ["bulk-a.png", "bulk-b.png"]) {
  const fd = new FormData(); fd.append("_csrf", csrf); fd.append("files", new Blob([png], { type: "image/png" }), name);
  const res = await fetch(BASE + "/admin/attachments/upload?format=json", { method: "POST", headers: { cookie: ckH(), "x-csrf-token": csrf, accept: "application/json" }, body: fd });
  ids.push((await res.json()).items[0].id);
}
await req("/admin/attachments/bulk", { method: "POST", headers: { "content-type": "application/x-www-form-urlencoded" }, body: new URLSearchParams([["_csrf", csrf], ["action", "delete"], ["ids", ids[0]], ["ids", ids[1]]]).toString() });
page = await req("/admin/attachments");
assert(!page.text.includes("bulk-a.png") && !page.text.includes("bulk-b.png"), "media bulk delete removes selected items");

// User bulk suspend.
page = await req("/admin/users");
csrf = csrfOf(page.text);
await req("/admin/users/action", { method: "POST", headers: { "content-type": "application/x-www-form-urlencoded" }, body: form({ _csrf: csrf, action: "create", username: "bulk-user", email: "bulk-user@example.com", display_name: "批量用户", password: "Team-Pass-2026!", role: "contributor" }) });
page = await req("/admin/users");
csrf = csrfOf(page.text);
const row = page.text.split("<tr").find((block) => block.includes("bulk-user")) || "";
const userId = (row.match(/name="ids" value="(user_[^"]+)"/) || [])[1];
assert(!!userId, "bulk user listed");
await req("/admin/users/bulk", { method: "POST", headers: { "content-type": "application/x-www-form-urlencoded" }, body: new URLSearchParams([["_csrf", csrf], ["action", "suspend"], ["ids", userId]]).toString() });
const login = clientLogin();
page = await login.req("/admin/login");
csrf = csrfOf(page.text);
const loginRes = await login.req("/admin/login", { method: "POST", headers: { "content-type": "application/x-www-form-urlencoded" }, body: form({ _csrf: csrf, username: "bulk-user", password: "Team-Pass-2026!", next: "" }) });
assert(loginRes.status === 401, "suspended bulk user cannot log in");

function clientLogin() {
  const map = new Map();
  function c(r) { for (const x of (r.headers.getSetCookie?.() || [])) { const p = x.split(";")[0].trim(); const i = p.indexOf("="); if (i > 0) map.set(p.slice(0, i), p.slice(i + 1)); } }
  const h = () => [...map.entries()].map(([k, v]) => k + "=" + v).join("; ");
  async function rq(p, o = {}) { const hh = Object.assign({}, o.headers || {}); if (map.size) hh.cookie = h(); const r = await fetch(BASE + p, { ...o, headers: hh, redirect: "manual" }); c(r); return { status: r.status, location: r.headers.get("location"), text: await r.text() }; }
  return { req: rq };
}
console.log("v1.2.1 search/bulk check complete");
