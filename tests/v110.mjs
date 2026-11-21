// v1.1 feature checks: revisions, attachment governance, Markdown import.
const BASE = process.env.CANGMO_BASE || "http://127.0.0.1:18085";
function client() {
  const jar = new Map();
  function ck(r) { for (const x of (r.headers.getSetCookie?.() || [])) { const p = x.split(";")[0].trim(); const i = p.indexOf("="); if (i > 0) jar.set(p.slice(0, i), p.slice(i + 1)); } }
  const ckH = () => [...jar.entries()].map(([k, v]) => k + "=" + v).join("; ");
  async function req(p, o = {}) {
    const h = Object.assign({}, o.headers || {});
    if (jar.size) h.cookie = ckH();
    const r = await fetch(BASE + p, { ...o, headers: h, redirect: "manual" });
    ck(r);
    return { status: r.status, location: r.headers.get("location"), text: await r.text() };
  }
  return { req, ckH };
}
const csrfOf = (h) => (h.match(/name="_csrf" value="([^"]+)"/) || [])[1] || "";
const form = (o) => { const p = new URLSearchParams(); for (const [k, v] of Object.entries(o)) p.set(k, v); return p.toString(); };
const admin = client();
function assert(ok, message) { console.log((ok ? "ok: " : "FAIL: ") + message); if (!ok) process.exitCode = 1; }

let page = await admin.req("/admin/login");
let csrf = csrfOf(page.text);
await admin.req("/admin/login", { method: "POST", headers: { "content-type": "application/x-www-form-urlencoded" }, body: form({ _csrf: csrf, username: "admin", password: "Cangmo-Test-2026!", next: "" }) });

// --- Revisions ---
page = await admin.req("/admin/posts/new");
csrf = csrfOf(page.text);
const create = await admin.req("/admin/posts/save", { method: "POST", headers: { "content-type": "application/x-www-form-urlencoded" }, body: form({ _csrf: csrf, id: "", type: "post", title: "版本旧标题", slug: "revision-test", summary: "旧摘要", content: "旧正文", status: "published", category_id: "", tags: "版本", cover: "", allow_comments: "on", pinned: "", featured: "", seo_title: "", seo_description: "", scheduled_at: "" }) });
const postId = (create.location.match(/posts\/(post_[^/]+)\/edit/) || [])[1];
assert(!!postId, "revision post created");
page = await admin.req(`/admin/posts/${postId}/edit`);
csrf = csrfOf(page.text);
await admin.req("/admin/posts/save", { method: "POST", headers: { "content-type": "application/x-www-form-urlencoded" }, body: form({ _csrf: csrf, id: postId, type: "post", title: "版本新标题", slug: "revision-test", summary: "新摘要", content: "新正文", status: "published", category_id: "", tags: "版本", cover: "", allow_comments: "on", pinned: "", featured: "", seo_title: "", seo_description: "", scheduled_at: "" }) });
page = await admin.req(`/admin/posts/${postId}/edit`);
let revUrl = (page.text.match(/data-revision-url="([^"]+)"/) || [])[1];
assert(!!revUrl, "revision entry rendered");
let rev = JSON.parse((await admin.req(revUrl)).text);
assert(rev.ok && rev.item.title === "版本旧标题" && rev.item.content === "旧正文", "revision JSON returns snapshot");
let restored = await admin.req(revUrl + "/restore", { method: "POST", headers: { "content-type": "application/x-www-form-urlencoded" }, body: form({ _csrf: csrf }) });
assert(restored.status === 303, "revision restore redirects");
page = await admin.req(`/admin/posts/${postId}/edit`);
assert(page.text.includes("版本旧标题") && page.text.includes("旧正文"), "revision content restored");
assert(page.text.includes('option value="draft" selected'), "revision restore is a draft");
assert(page.text.includes("/revision-test"), "revision restore keeps the current slug");

// Cross-post revision access is hidden.
page = await admin.req("/admin/posts/new");
csrf = csrfOf(page.text);
const other = await admin.req("/admin/posts/save", { method: "POST", headers: { "content-type": "application/x-www-form-urlencoded" }, body: form({ _csrf: csrf, id: "", type: "post", title: "另一篇文章", slug: "revision-other", summary: "", content: "other", status: "draft", category_id: "", tags: "", cover: "", allow_comments: "on", pinned: "", featured: "", seo_title: "", seo_description: "", scheduled_at: "" }) });
const otherId = (other.location.match(/posts\/(post_[^/]+)\/edit/) || [])[1];
const cross = await admin.req(`/admin/posts/${otherId}/revisions/${rev.item.id}`);
assert(cross.status === 404, "cross-post revision is hidden");

// --- Attachments ---
page = await admin.req("/admin/attachments");
csrf = csrfOf(page.text);
const png = Buffer.from("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/p9sAAAAASUVORK5CYII=", "base64");
const up = new FormData();
up.append("_csrf", csrf);
up.append("files", new Blob([png], { type: "image/png" }), "original.png");
const uploadResponse = await fetch(BASE + "/admin/attachments/upload?format=json", { method: "POST", headers: { cookie: admin.ckH(), "x-csrf-token": csrf, accept: "application/json" }, body: up });
const uploadData = await uploadResponse.json();
const mediaId = uploadData.items[0].id;
const mediaUrl = uploadData.items[0].url;
assert(!!mediaId && !!mediaUrl, "attachment uploaded");
const renamed = await admin.req(`/admin/attachments/${mediaId}/rename`, { method: "POST", headers: { "content-type": "application/x-www-form-urlencoded" }, body: form({ _csrf: csrf, name: "测试 改名.png", return_to: "/admin/attachments" }) });
assert(renamed.status === 303, "attachment rename redirects");
page = await admin.req("/admin/attachments");
assert(page.text.includes("测试 改名.png"), "attachment shows renamed display name");
assert(page.text.includes(mediaUrl), "attachment URL unchanged after rename");
const badRename = await admin.req(`/admin/attachments/${mediaId}/rename`, { method: "POST", headers: { "content-type": "application/x-www-form-urlencoded" }, body: form({ _csrf: csrf, name: "bad.jpg", return_to: "/admin/attachments" }) });
assert(badRename.status === 303, "extension mismatch handled");
page = await admin.req("/admin/attachments");
assert(page.text.includes("测试 改名.png"), "extension mismatch keeps the original name");

// Create a post that references the attachment as cover.
page = await admin.req("/admin/posts/new");
csrf = csrfOf(page.text);
const ref = await admin.req("/admin/posts/save", { method: "POST", headers: { "content-type": "application/x-www-form-urlencoded" }, body: form({ _csrf: csrf, id: "", type: "post", title: "引用附件文章", slug: "media-usage", summary: "", content: "正文", status: "published", category_id: "", tags: "", cover: mediaUrl, allow_comments: "on", pinned: "", featured: "", seo_title: "", seo_description: "", scheduled_at: "" }) });
assert(ref.status === 303, "referencing post created");
const usage = JSON.parse((await admin.req(`/admin/attachments/${mediaId}/usage`)).text);
assert(usage.count >= 1 && usage.items.some((item) => item.title === "引用附件文章"), "attachment usage detects cover reference");
const blocked = await admin.req(`/admin/attachments/${mediaId}/delete`, { method: "POST", headers: { "content-type": "application/x-www-form-urlencoded" }, body: form({ _csrf: csrf, return_to: "/admin/attachments" }) });
assert(blocked.status === 303, "referenced attachment delete handled");
page = await admin.req("/admin/attachments");
assert(page.text.includes("测试 改名.png"), "referenced attachment not deleted without force");

// Contributor cannot upload or delete media.
page = await admin.req("/admin/users");
csrf = csrfOf(page.text);
await admin.req("/admin/users/action", { method: "POST", headers: { "content-type": "application/x-www-form-urlencoded" }, body: form({ _csrf: csrf, action: "create", username: "media-contrib", email: "media-contrib@example.com", display_name: "附件投稿者", password: "Contrib-Test-2026!", role: "contributor" }) });
const contrib = client();
page = await contrib.req("/admin/login");
csrf = csrfOf(page.text);
await contrib.req("/admin/login", { method: "POST", headers: { "content-type": "application/x-www-form-urlencoded" }, body: form({ _csrf: csrf, username: "media-contrib", password: "Contrib-Test-2026!", next: "" }) });
page = await contrib.req("/admin/attachments");
const contribCsrf = csrfOf(page.text);
assert(!page.text.includes('id="attachment-upload-form"'), "contributor sees no upload panel");
const contribUp = new FormData();
contribUp.append("_csrf", contribCsrf);
contribUp.append("files", new Blob([png], { type: "image/png" }), "contrib.png");
const contribUpload = await fetch(BASE + "/admin/attachments/upload", { method: "POST", headers: { cookie: contrib.ckH() }, body: contribUp, redirect: "manual" });
assert(contribUpload.status === 303, "contributor upload rejected");
const contribDelete = await contrib.req(`/admin/attachments/${mediaId}/delete`, { method: "POST", headers: { "content-type": "application/x-www-form-urlencoded" }, body: form({ _csrf: contribCsrf, return_to: "/admin/attachments" }) });
assert(contribDelete.status === 303, "contributor delete rejected");
page = await admin.req("/admin/attachments");
assert(page.text.includes("测试 改名.png"), "contributor could not delete the attachment");

// Contributor cannot even read an admin revision.
const contribRevision = await contrib.req(`/admin/posts/${postId}/revisions/${rev.item.id}`);
assert(contribRevision.status === 403, "contributor cannot read another author's revision");

// An API token keeps working after its admin owner is demoted, but media upload is denied.
page = await admin.req("/admin/users");
csrf = csrfOf(page.text);
await admin.req("/admin/users/action", { method: "POST", headers: { "content-type": "application/x-www-form-urlencoded" }, body: form({ _csrf: csrf, action: "create", username: "media-admin", email: "media-admin@example.com", display_name: "附件管理员", password: "Strong-Pass-2026!", role: "admin" }) });
const mediaAdmin = client();
page = await mediaAdmin.req("/admin/login");
let mediaAdminCsrf = csrfOf(page.text);
await mediaAdmin.req("/admin/login", { method: "POST", headers: { "content-type": "application/x-www-form-urlencoded" }, body: form({ _csrf: mediaAdminCsrf, username: "media-admin", password: "Strong-Pass-2026!", next: "" }) });
page = await mediaAdmin.req("/admin/profile");
mediaAdminCsrf = csrfOf(page.text);
await mediaAdmin.req("/admin/profile/token", { method: "POST", headers: { "content-type": "application/x-www-form-urlencoded" }, body: form({ _csrf: mediaAdminCsrf, name: "media-api" }) });
page = await mediaAdmin.req("/admin/profile");
const apiToken = (page.text.match(/cmo_[A-Za-z0-9_-]{20,}/) || [])[0];
assert(!!apiToken, "API token created for demotion test");
page = await admin.req("/admin/users");
csrf = csrfOf(page.text);
const mediaAdminRow = page.text.split("<tr").find((block) => block.includes("media-admin")) || "";
const mediaAdminId = (mediaAdminRow.match(/name="id" value="(user_[^"]+)"/) || [])[1];
await admin.req("/admin/users/action", { method: "POST", headers: { "content-type": "application/x-www-form-urlencoded" }, body: form({ _csrf: csrf, action: "update", id: mediaAdminId, role: "contributor", status: "active", display_name: "附件管理员" }) });
const apiForm = new FormData();
apiForm.append("files", new Blob([png], { type: "image/png" }), "api-contrib.png");
const apiUpload = await fetch(BASE + "/api/v1/attachments", { method: "POST", headers: { authorization: "Bearer " + apiToken }, body: apiForm });
assert(apiUpload.status === 403, "demoted API token cannot upload media");

// Contributor import cannot publish even when the form asks for it.
page = await contrib.req("/admin/import");
const importCsrf = csrfOf(page.text);
const contribImport = new FormData();
contribImport.append("_csrf", importCsrf);
contribImport.append("publish", "on");
contribImport.append("files", new Blob(["---\ntitle: 投稿导入\n---\n\n正文"], { type: "text/markdown" }), "contrib-import.md");
const contribImportResp = await fetch(BASE + "/admin/import", { method: "POST", headers: { cookie: contrib.ckH() }, body: contribImport, redirect: "manual" });
assert(contribImportResp.status === 200, "contributor markdown import handled");
page = await admin.req("/admin/posts?status=draft");
assert(page.text.includes("投稿导入"), "contributor import is a draft");

// Force delete.
page = await admin.req("/admin/attachments");
const adminCsrf = csrfOf(page.text);
const forced = await admin.req(`/admin/attachments/${mediaId}/delete`, { method: "POST", headers: { "content-type": "application/x-www-form-urlencoded" }, body: form({ _csrf: adminCsrf, force: "1", return_to: "/admin/attachments" }) });
assert(forced.status === 303, "force delete accepted");
page = await admin.req("/admin/attachments");
assert(!page.text.includes("测试 改名.png"), "force delete removed the attachment");

// --- Markdown import ---
page = await admin.req("/admin/import");
csrf = csrfOf(page.text);
const md = "---\ntitle: 导入标题\ntags: 导入, 测试\ncategory: 不存在\n---\n\n## 导入正文\n\n内容";
const imp = new FormData();
imp.append("_csrf", csrf);
imp.append("files", new Blob([md], { type: "text/markdown" }), "imported.md");
imp.append("files", new Blob(["# 无头标题\n\n正文"], { type: "text/markdown" }), "plain.md");
imp.append("files", new Blob(["bad"], { type: "text/plain" }), "note.txt");
const imported = await fetch(BASE + "/admin/import", { method: "POST", headers: { cookie: admin.ckH() }, body: imp, redirect: "manual" });
const importedText = await imported.text();
assert(imported.status === 200 && importedText.includes("成功 2 个，失败 1 个"), "markdown import counts results");
assert(importedText.includes("导入标题"), "front matter title imported");
page = await admin.req("/admin/posts?status=draft");
assert(page.text.includes("导入标题") && page.text.includes("plain"), "imported posts are drafts");

console.log("v1.1 feature check complete");
