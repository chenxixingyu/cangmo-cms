const BASE = process.env.CANGMO_BASE || "http://127.0.0.1:18085";
const jar = new Map();
function ck(r) { for (const x of (r.headers.getSetCookie?.() || [])) { const p = x.split(";")[0].trim(); const i = p.indexOf("="); if (i > 0) jar.set(p.slice(0, i), p.slice(i + 1)); } }
const ckH = () => [...jar.entries()].map(([k, v]) => k + "=" + v).join("; ");
async function req(p, o = {}) { const h = Object.assign({}, o.headers || {}); if (jar.size) h.cookie = ckH(); const r = await fetch(BASE + p, { ...o, headers: h, redirect: "manual" }); ck(r); return { status: r.status, location: r.headers.get("location"), text: await r.text() }; }
const csrfOf = (h) => (h.match(/name="_csrf" value="([^"]+)"/) || [])[1] || "";
const form = (o) => { const p = new URLSearchParams(); for (const [k, v] of Object.entries(o)) p.set(k, v); return p.toString(); };
function tokenOf(html) { return (html.match(/cmo_[A-Za-z0-9_-]{20,}/) || [])[0]; }
function assert(ok, message) { console.log((ok ? "ok: " : "FAIL: ") + message); if (!ok) process.exitCode = 1; }

let page = await req("/admin/login");
let csrf = csrfOf(page.text);
await req("/admin/login", { method: "POST", headers: { "content-type": "application/x-www-form-urlencoded" }, body: form({ _csrf: csrf, username: "admin", password: "Cangmo-Test-2026!", next: "" }) });
page = await req("/admin/profile");
csrf = csrfOf(page.text);
assert(page.text.includes('name="scopes"') && page.text.includes("valid") === false, "token form exposes scopes");
await req("/admin/profile/token", { method: "POST", headers: { "content-type": "application/x-www-form-urlencoded" }, body: new URLSearchParams([["_csrf", csrf], ["name", "posts-only"], ["scopes", "posts.write"], ["expires_days", "0"], ["allowed_ips", ""]]).toString() });
page = await req("/admin/profile");
const postsToken = tokenOf(page.text);
assert(!!postsToken, "scoped posts token created");
const postBody = JSON.stringify({ title: "令牌文章", content: "正文", status: "draft" });
const postRes = await fetch(BASE + "/api/v1/posts", { method: "POST", headers: { authorization: "Bearer " + postsToken, "content-type": "application/json" }, body: postBody });
assert(postRes.status === 201 || postRes.status === 200, "posts.write token can create a post");
const png = Buffer.from("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/p9sAAAAASUVORK5CYII=", "base64");
const up = new FormData(); up.append("files", new Blob([png], { type: "image/png" }), "scope.png");
const denied = await fetch(BASE + "/api/v1/attachments", { method: "POST", headers: { authorization: "Bearer " + postsToken }, body: up });
assert(denied.status === 403, "posts.write token cannot upload media");

await req("/admin/profile/token", { method: "POST", headers: { "content-type": "application/x-www-form-urlencoded" }, body: new URLSearchParams([["_csrf", csrf], ["name", "media-only"], ["scopes", "media.write"], ["expires_days", "0"], ["allowed_ips", ""]]).toString() });
page = await req("/admin/profile");
const mediaToken = tokenOf(page.text);
assert(!!mediaToken, "scoped media token created");
const up2 = new FormData(); up2.append("files", new Blob([png], { type: "image/png" }), "scope2.png");
const mediaRes = await fetch(BASE + "/api/v1/attachments", { method: "POST", headers: { authorization: "Bearer " + mediaToken }, body: up2 });
assert(mediaRes.status === 200 || mediaRes.status === 201, "media.write token can upload");
const postDenied = await fetch(BASE + "/api/v1/posts", { method: "POST", headers: { authorization: "Bearer " + mediaToken, "content-type": "application/json" }, body: postBody });
assert(postDenied.status === 403, "media.write token cannot create posts");

await req("/admin/profile/token", { method: "POST", headers: { "content-type": "application/x-www-form-urlencoded" }, body: new URLSearchParams([["_csrf", csrf], ["name", "ip-only"], ["scopes", "posts.write"], ["expires_days", "0"], ["allowed_ips", "10.1.2.3"]]).toString() });
page = await req("/admin/profile");
const ipToken = tokenOf(page.text);
const ipDenied = await fetch(BASE + "/api/v1/posts", { method: "POST", headers: { authorization: "Bearer " + ipToken, "content-type": "application/json" }, body: postBody });
assert(ipDenied.status === 401 || ipDenied.status === 403, "IP-restricted token rejects another IP");
console.log("token scope check complete");
