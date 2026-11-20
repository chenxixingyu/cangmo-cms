// Cangmo end-to-end test: login, CRUD, upload, comments, settings, backups, API tokens, CSRF.
const BASE = process.env.CANGMO_BASE || "http://127.0.0.1:18081";
const jar = new Map();

function storeCookies(response) {
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
  storeCookies(response);
  const text = await response.text();
  return { status: response.status, location: response.headers.get("location"), text, headers: response.headers };
}
function csrfOf(html) {
  return (html.match(/name="_csrf" value="([^"]+)"/) || [])[1] || "";
}
function assert(ok, message) {
  if (!ok) { console.error("FAIL:", message); process.exitCode = 1; } else { console.log("ok:", message); }
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

// 1. Login.
let page = await req("/admin/login");
let csrf = csrfOf(page.text);
assert(page.status === 200, "login page 200");
let login = await postForm("/admin/login", { username: "admin", password: "Cangmo-Test-2026!", next: "" }, csrf);
assert(login.status === 303 && login.location === "/admin", "login succeeds");
page = await req("/admin");
assert(page.status === 200 && page.text.includes("仪表盘"), "dashboard 200");

// 2. Create a published post through the admin form.
page = await req("/admin/posts/new");
csrf = csrfOf(page.text);
const content = "# E2E 标题\n\n这是 **端到端** 测试。\n\n<script>alert('xss')</script>\n\n- 一\n- 二\n";
const created = await postForm("/admin/posts/save", {
  id: "",
  type: "post",
  title: "端到端测试文章",
  slug: "e2e-test",
  summary: "E2E 摘要",
  content,
  status: "published",
  category_id: "",
  tags: "测试, 安全",
  cover: "",
  allow_comments: "on",
  pinned: "on",
  featured: "on",
  seo_title: "",
  seo_description: "",
  scheduled_at: ""
}, csrf);
assert(created.status === 303, "post created (303)");
console.log("create ->", created.location);
const postPath = "/posts/e2e-test";
page = await req(postPath);
assert(page.status === 200, "created post page 200");
assert(page.text.includes("E2E 标题"), "post content rendered");
assert(page.text.includes("&lt;script&gt;") && !page.text.includes("<script>alert"), "markdown raw HTML escaped");
assert(page.text.includes("端到端测试文章"), "post title rendered");

// 3. Public comment with XSS payload.
csrf = csrfOf(page.text);
const postId = (page.text.match(/name="post_id" value="([^"]+)"/) || [])[1];
assert(!!postId, "comment form has post id");
const comment = await postForm("/comments", {
  post_id: postId,
  parent_id: "",
  name: "访客",
  email: "visitor@example.com",
  url: "",
  content: "评论 <script>alert(1)</script>",
  website: ""
}, csrf);
assert(comment.status === 303, "comment submitted (303)");
page = await req("/admin/comments?status=pending");
assert(page.status === 200, "pending comments page 200");
const commentId = (page.text.match(/\/admin\/comments\/([^/]+)\/approved/) || [])[1];
assert(!!commentId, "pending comment visible");
csrf = csrfOf(page.text);
const approved = await postForm(`/admin/comments/${commentId}/approved`, { status: "pending" }, csrf);
assert(approved.status === 303, "comment approved (303)");
page = await req(postPath);
assert(page.text.includes("评论 &lt;script&gt;alert(1)&lt;/script&gt;"), "comment escaped on post page");

// 4. Upload a PNG.
page = await req("/admin/media");
csrf = csrfOf(page.text);
const png = Buffer.from("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/p9sAAAAASUVORK5CYII=", "base64");
const uploadForm = new FormData();
uploadForm.set("_csrf", csrf);
uploadForm.set("files", new Blob([png], { type: "image/png" }), "pixel.png");
const upload = await req("/admin/media/upload", { method: "POST", body: uploadForm });
assert(upload.status === 303, "media upload 303");
page = await req("/admin/media");
assert(page.text.includes("/media/") && page.text.includes("pixel.png"), "media listed");
const mediaPath = (page.text.match(/src="(\/media\/[^"]+)"/) || [])[1];
assert(!!mediaPath, "media URL present");
const media = await req(mediaPath);
assert(media.status === 200 && media.headers.get("content-type") === "image/png", "media served as PNG");

// 5. Settings.
page = await req("/admin/settings");
assert(page.text.includes('data-settings-tab="appearance"') && page.text.includes('data-settings-panel="comments"'), "settings render horizontal tabs");
csrf = csrfOf(page.text);
const saved = await postForm("/admin/settings/save", {
  site_title: "仓墨测试站",
  site_subtitle: "新的副标题",
  site_description: "端到端测试描述",
  site_keywords: "仓颉,测试",
  site_url: "http://127.0.0.1:18081",
  footer_text: "页脚",
  posts_per_page: "9",
  theme_accent: "#2f6f4e",
  theme_mode: "auto",
  comment_enabled: "on",
  comment_moderation: "on",
  comment_max_links: "3",
  show_toc: "on",
  show_reading_time: "on",
  nav_text: "首页|/\n归档|/archive",
  social_text: "GitHub|https://example.com"
}, csrf);
assert(saved.status === 303, "settings saved");
page = await req("/");
assert(page.text.includes("新的副标题"), "home shows new subtitle");

// 6. Backup.
page = await req("/admin/tools");
csrf = csrfOf(page.text);
const backup = await postForm("/admin/tools/action", { action: "create", label: "e2e" }, csrf);
assert(backup.status === 303, "backup created");
page = await req("/admin/tools");
const backupName = (page.text.match(/(e2e-[A-Za-z0-9_-]+\.json)/) || [])[1];
assert(!!backupName, "backup listed");
const download = await req("/admin/tools/backup?name=" + encodeURIComponent(backupName));
assert(download.status === 200 && download.headers.get("content-disposition")?.includes("attachment"), "backup downloadable");

// 7. API token.
page = await req("/admin/profile");
csrf = csrfOf(page.text);
const tokenPost = await postForm("/admin/profile/token", { name: "e2e-token" }, csrf);
assert(tokenPost.status === 303, "token created");
page = await req("/admin/profile");
const token = (page.text.match(/cmo_[A-Za-z0-9_-]+/) || [])[0];
assert(!!token, "token shown once");
const apiCreate = await fetch(BASE + "/api/v1/posts", {
  method: "POST",
  headers: { "content-type": "application/json", authorization: "Bearer " + token },
  body: JSON.stringify({
    title: "API 文章",
    slug: "e2e-api",
    summary: "API 摘要",
    content: "# API\n\n通过令牌创建。",
    status: "published",
    tags: ["API"]
  })
});
assert(apiCreate.status === 201, "API post created");
const apiPost = await fetch(BASE + "/api/v1/posts/e2e-api");
assert(apiPost.status === 200, "API post readable");

// 8. CSRF rejection.
const noCsrf = await fetch(BASE + "/admin/posts/save", {
  method: "POST",
  headers: { cookie: cookieHeader(), "content-type": "application/x-www-form-urlencoded" },
  body: form({ title: "no csrf" }),
  redirect: "manual"
});
assert(noCsrf.status === 403, "CSRF-less POST rejected (403)");

// 9. Logout.
page = await req("/admin/profile");
csrf = csrfOf(page.text);
const logout = await postForm("/admin/logout", {}, csrf);
assert(logout.status === 303, "logout redirects");
page = await req("/admin");
assert(page.status === 303, "admin requires login after logout");

console.log("e2e test complete");
