// Cangmo extended regression: preview, pages, categories, scheduler, API mutations.
const BASE = process.env.CANGMO_BASE || "http://127.0.0.1:18088";
const jar = new Map();

function cookies(response) {
  const list = response.headers.getSetCookie ? response.headers.getSetCookie() : [];
  for (const raw of list) {
    const pair = raw.split(";")[0].trim();
    const eq = pair.indexOf("=");
    if (eq > 0) jar.set(pair.slice(0, eq), pair.slice(eq + 1));
  }
}
function cookieHeader() {
  return [...jar.entries()].map(([k, v]) => `${k}=${v}`).join("; ");
}
async function req(path, options = {}) {
  const headers = Object.assign({}, options.headers || {});
  if (jar.size) headers.cookie = cookieHeader();
  const response = await fetch(BASE + path, { ...options, headers, redirect: "manual" });
  cookies(response);
  const text = await response.text();
  return { status: response.status, location: response.headers.get("location"), text, headers: response.headers };
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
function localDateTime(offsetMs) {
  const d = new Date(Date.now() + offsetMs);
  const p = (n) => String(n).padStart(2, "0");
  return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())}T${p(d.getHours())}:${p(d.getMinutes())}:${p(d.getSeconds())}`;
}

// Login.
let page = await req("/admin/login");
let csrf = csrfOf(page.text);
const login = await postForm("/admin/login", { username: "admin", password: "Cangmo-Test-2026!", next: "" }, csrf);
assert(login.status === 303, "login succeeds");

// Markdown preview endpoint.
page = await req("/admin/posts/new");
csrf = csrfOf(page.text);
const preview = await req("/admin/preview", {
  method: "POST",
  headers: { "content-type": "application/json", "x-csrf-token": csrf },
  body: JSON.stringify({ markdown: "## 预览标题\n\n**粗体**" })
});
assert(preview.status === 200, "preview endpoint 200");
const previewDoc = JSON.parse(preview.text);
assert(previewDoc.html.includes("<h2") && previewDoc.html.includes("<strong>粗体</strong>"), "preview renders Markdown");

// Category create.
page = await req("/admin/categories");
csrf = csrfOf(page.text);
const category = await postForm("/admin/categories/save", {
  action: "create", name: "扩展分类", slug: "extended-cat", description: "test"
}, csrf);
assert(category.status === 303, "category created");
page = await req("/admin/categories");
assert(page.text.includes("扩展分类"), "category appears in admin");
const categoryId = (page.text.match(/name="id" value="(cat_[A-Za-z0-9_]+)"/) || [])[1] || "";

// Page create.
page = await req("/admin/posts/new?type=page");
csrf = csrfOf(page.text);
const pageCreated = await postForm("/admin/posts/save", {
  id: "", type: "page", title: "扩展页面", slug: "extended-page", summary: "页面摘要",
  content: "## 页面正文\n\n内容", status: "published", category_id: "", tags: "", cover: "",
  allow_comments: "on", pinned: "", featured: "", seo_title: "", seo_description: "", scheduled_at: ""
}, csrf);
assert(pageCreated.status === 303, "page created");
page = await req("/pages/extended-page");
assert(page.status === 200 && page.text.includes("页面正文"), "page is public");

// Inline page drawer: read, save as draft, publish again without leaving the list.
page = await req("/admin/posts?type=page");
const pageRow = page.text.split('<tr class="post-row"').find((block) => block.includes("扩展页面")) || "";
const pageId = (pageRow.match(/data-post-id="(post_[^"]+)"/) || [])[1];
assert(!!pageId, "page drawer id is exposed");
let drawer = await req(`/admin/posts/${pageId}/drawer`);
let drawerData = JSON.parse(drawer.text);
assert(drawer.status === 200 && drawerData.ok && drawerData.item.content.includes("页面正文"), "page drawer data loads");
csrf = csrfOf(page.text);
const quickFields = {
  title: "扩展页面", slug: "extended-page", summary: "抽屉摘要", content: "## 抽屉正文",
  cover: "", seo_title: "", seo_description: "", allow_comments: "on", scheduled_at: ""
};
let quick = await postForm(`/admin/posts/${pageId}/quick`, Object.assign({ status: "draft" }, quickFields), csrf);
let quickData = JSON.parse(quick.text);
assert(quick.status === 200 && quickData.ok && quickData.item.status === "draft", "quick save returns updated row");
assert((await req("/pages/extended-page")).status === 404, "quick draft hides the page");
quick = await postForm(`/admin/posts/${pageId}/quick`, Object.assign({ status: "published" }, quickFields), csrf);
quickData = JSON.parse(quick.text);
assert(quickData.ok && quickData.item.status === "published", "quick save can publish");
page = await req("/pages/extended-page");
assert(page.text.includes("抽屉正文"), "quick saved content is public");

// Scheduled post: due in 20s (seconds included), then the 20s scheduler tick publishes it.
const scheduledAt = localDateTime(20000);
page = await req("/admin/posts/new");
csrf = csrfOf(page.text);
const scheduled = await postForm("/admin/posts/save", {
  id: "", type: "post", title: "定时发布测试", slug: "scheduled-test", summary: "定时",
  content: "定时正文", status: "scheduled", category_id: categoryId, tags: "定时",
  cover: "", allow_comments: "on", pinned: "", featured: "", seo_title: "", seo_description: "",
  scheduled_at: scheduledAt
}, csrf);
assert(scheduled.status === 303, "scheduled post saved");
page = await req("/admin/posts?status=scheduled");
assert(page.text.includes("定时发布测试"), "scheduled post visible in scheduled tab");
let published = false;
for (let attempt = 0; attempt < 30; attempt += 1) {
  await new Promise((resolve) => setTimeout(resolve, 2000));
  page = await req("/posts/scheduled-test");
  if (page.status === 200) { published = true; break; }
}
assert(published, "scheduler published the scheduled post");

// Duplicate a post into a fresh draft.
page = await req("/admin/posts?status=all");
csrf = csrfOf(page.text);
const scheduledId = (scheduled.location.match(/posts\/(post_[^/]+)\/edit/) || [])[1];
const duplicated = await postForm(`/admin/posts/${scheduledId}/duplicate`, { return_to: "/admin/posts?status=all" }, csrf);
assert(duplicated.status === 303, "post duplicated");
page = await req(duplicated.location);
assert(page.text.includes("定时发布测试（副本）") && page.text.includes("草稿"), "duplicate starts as a draft");

// API token + create/update/delete + API comment.
page = await req("/admin/profile");
csrf = csrfOf(page.text);
await postForm("/admin/profile/token", { name: "extended-token" }, csrf);
page = await req("/admin/profile");
const token = (page.text.match(/cmo_[A-Za-z0-9_-]{20,}/) || [])[0];
assert(!!token, "API token created");
const apiCreate = await fetch(BASE + "/api/v1/posts", {
  method: "POST",
  headers: { "content-type": "application/json", authorization: "Bearer " + token },
  body: JSON.stringify({ title: "API 扩展", slug: "api-ext", content: "# API\n\n初始", status: "published", tags: ["API"] })
});
assert(apiCreate.status === 201, "API post created");
const apiDoc = await apiCreate.json();
const apiId = apiDoc.id;
const apiUpdate = await fetch(BASE + "/api/v1/posts/" + apiId, {
  method: "PUT",
  headers: { "content-type": "application/json", authorization: "Bearer " + token },
  body: JSON.stringify({ title: "API 扩展更新", slug: "api-ext", content: "# API\n\n更新", status: "published" })
});
assert(apiUpdate.status === 200, "API post updated");
const apiRead = await fetch(BASE + "/api/v1/posts/api-ext");
const apiReadDoc = await apiRead.json();
assert(apiReadDoc.title === "API 扩展更新", "API update visible");
const welcomeList = await (await fetch(BASE + "/api/v1/posts")).json();
const welcomeId = welcomeList.data[0].id;
const apiComment = await fetch(BASE + "/api/v1/comments", {
  method: "POST",
  headers: { "content-type": "application/json", authorization: "Bearer " + token },
  body: JSON.stringify({ post_id: welcomeId, name: "API 访客", email: "api@example.com", content: "API 评论" })
});
assert(apiComment.status === 201, "API comment created");
const apiDelete = await fetch(BASE + "/api/v1/posts/" + apiId, {
  method: "DELETE",
  headers: { authorization: "Bearer " + token }
});
assert(apiDelete.status === 200, "API post deleted");
const apiGone = await fetch(BASE + "/api/v1/posts/api-ext");
assert(apiGone.status === 404, "API deleted post is 404");

// Search and theme.
page = await req("/search?q=" + encodeURIComponent("扩展页面"));
assert(page.status === 200 && page.text.includes("扩展页面"), "search finds page/post");
page = await req("/admin/themes");
csrf = csrfOf(page.text);
const theme = await postForm("/admin/themes/activate", { name: "default" }, csrf);
assert(theme.status === 303, "theme activation works");
page = await req("/categories/extended-cat");
assert(page.status === 200, "category page works");

console.log("extended test complete");
