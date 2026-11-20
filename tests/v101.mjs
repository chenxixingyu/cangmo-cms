// Cangmo v1.0.1 regression: attachments, editor taxonomy/cover, Halo-like admin,
// profile avatar, backup create/download/restore.
const BASE = process.env.CANGMO_BASE || "http://127.0.0.1:18090";
const jar = new Map();
function cookies(r) {
  for (const raw of (r.headers.getSetCookie ? r.headers.getSetCookie() : [])) {
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
  const buffer = Buffer.from(await response.arrayBuffer());
  return { status: response.status, location: response.headers.get("location"), headers: response.headers, text: buffer.toString("utf8"), buffer };
}
function csrfOf(html) {
  return (html.match(/name="_csrf" value="([^"]+)"/) || [])[1] || "";
}
function form(fields) {
  const params = new URLSearchParams();
  for (const [key, value] of Object.entries(fields)) params.set(key, value);
  return params.toString();
}
function assert(ok, message) {
  if (!ok) { console.error("FAIL:", message); process.exitCode = 1; } else { console.log("ok:", message); }
}

let page = await req("/admin/login");
let csrf = csrfOf(page.text);
const stamp = Date.now().toString(36);
const slug = "v101-acceptance-" + stamp;
const title = "v1.0.1 功能验收 " + stamp;
const categoryName = "中文分类";
let login = await req("/admin/login", {
  method: "POST",
  headers: { "content-type": "application/x-www-form-urlencoded" },
  body: form({ _csrf: csrf, username: "admin", password: "Cangmo-Test-2026!", next: "" })
});
assert(login.status === 303, "login succeeds");

page = await req("/admin/attachments");
assert(page.status === 200 && page.text.includes("附件库"), "attachment library page is rendered");
assert(!page.text.includes("媒体库"), "old media-library label is gone");
csrf = csrfOf(page.text);

const png = Buffer.from("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAusB9Y9Zl1sAAAAASUVORK5CYII=", "base64");
async function uploadImage(name) {
  const data = new FormData();
  data.append("_csrf", csrf);
  data.append("files", new Blob([png], { type: "image/png" }), name);
  const response = await fetch(BASE + "/admin/attachments/upload?format=json", {
    method: "POST",
    headers: { cookie: cookieHeader(), "x-csrf-token": csrf, accept: "application/json" },
    body: data
  });
  const body = await response.json();
  return { status: response.status, body };
}
const first = await uploadImage("v101-cover.png");
assert(first.status === 200 && first.body.items.length === 1, "attachment upload returns JSON item");
const coverUrl = first.body.items[0].url;
const second = await uploadImage("v101-delete.png");
assert(second.status === 200, "second attachment uploaded");

// Regression: Chromium boundaries are mixed-case; the parser must not lowercase them.
const mixedBoundary = "----CangmoBoundaryAbCdEf123456";
const mixedHead = Buffer.from(`--${mixedBoundary}\r\nContent-Disposition: form-data; name="_csrf"\r\n\r\n${csrf}\r\n--${mixedBoundary}\r\nContent-Disposition: form-data; name="files"; filename="mixed-case.png"\r\nContent-Type: image/png\r\n\r\n`);
const mixedTail = Buffer.from(`\r\n--${mixedBoundary}--\r\n`);
const mixedUpload = await req("/admin/attachments/upload?format=json", {
  method: "POST",
  headers: { "content-type": `multipart/form-data; boundary=${mixedBoundary}`, "x-csrf-token": csrf, accept: "application/json" },
  body: Buffer.concat([mixedHead, png, mixedTail])
});
assert(mixedUpload.status === 200 && mixedUpload.text.includes("mixed-case.png"), "mixed-case multipart boundary works");

const chinese = await uploadImage("测试 截图.png");
assert(chinese.status === 200 && chinese.body.items[0].original_name === "测试 截图.png", "Chinese filename preserved");
assert(/^media_[A-Za-z0-9]+\.png$/.test(chinese.body.items[0].filename), "stored filename stays ASCII");

page = await req("/admin/attachments?kind=image&q=v101-cover");
assert(page.status === 200 && page.text.includes("v101-cover.png"), "attachment filter/search works");
page = await req("/admin/attachments/data?kind=image");
const mediaData = JSON.parse(page.text);
assert(mediaData.total >= 2 && mediaData.items.some((item) => item.url === coverUrl), "attachment picker JSON works");

const victim = second.body.items[0];
csrf = csrfOf((await req("/admin/attachments")).text);
const deleted = await req("/admin/attachments/" + victim.id + "/delete", {
  method: "POST",
  headers: { "content-type": "application/x-www-form-urlencoded" },
  body: form({ _csrf: csrf, return_to: "/admin/attachments?kind=image" })
});
assert(deleted.status === 303, "attachment delete succeeds");

page = await req("/admin/posts/new");
assert(page.status === 200 && page.text.includes("cover-picker") && page.text.includes("tag-editor"), "editor has cover and tag UI");
assert(page.text.includes('id="publish-drawer"') && !page.text.includes('class="editor-side"'), "editor uses publish drawer");
csrf = csrfOf(page.text);
const category = await req("/admin/categories/quick", {
  method: "POST",
  headers: { "content-type": "application/json", "x-csrf-token": csrf },
  body: JSON.stringify({ name: categoryName })
});
const categoryDoc = JSON.parse(category.text);
assert(category.status === 200 && categoryDoc.id.startsWith("cat_"), "inline category creation works");
assert(categoryDoc.slug.startsWith("category-"), "Chinese category gets a readable fallback slug");
const saved = await req("/admin/posts/save", {
  method: "POST",
  headers: { "content-type": "application/x-www-form-urlencoded" },
  body: form({
    _csrf: csrf, id: "", type: "post", title: title, slug: slug,
    summary: "附件、分类、标签、封面", content: "## 验收\n\n这是 v1.0.1 的验收文章。", status: "published",
    category_id: categoryDoc.id, tags: "验收, v1.0.1", cover: coverUrl, allow_comments: "on",
    pinned: "", featured: "", seo_title: "", seo_description: "", scheduled_at: ""
  })
});
assert(saved.status === 303, "post with category/tags/cover saves");
page = await req("/posts/" + slug);
assert(page.status === 200 && page.text.includes(coverUrl) && page.text.includes(categoryName), "public post shows cover and category");
assert(page.text.includes("验收") && page.text.includes("v1.0.1"), "public post shows tags");
assert(!page.text.includes("还没有文章。去后台写下第一篇吧"), "frontend empty-state copy is removed");
const postId = (page.text.match(/name="post_id" value="([^"]+)"/) || [])[1];

csrf = csrfOf(page.text);
const comment = await req("/comments", {
  method: "POST",
  headers: { "content-type": "application/x-www-form-urlencoded" },
  body: form({ _csrf: csrf, post_id: postId, parent_id: "", name: "验收评论", email: "v101@example.com", url: "", content: "这是 v1.0.1 验收评论", website: "" })
});
assert(comment.status === 303, "comment submitted");
page = await req("/admin/comments?status=pending");
assert(page.status === 200 && page.text.includes("验收评论"), "comment appears in moderation queue");
const commentBlock = page.text.split('class="comment-admin"').find((block) => block.includes("验收评论")) || "";
const commentId = (commentBlock.match(/name="ids" value="([^"]+)"/) || [])[1];
assert(!!commentId, "pending comment checkbox is present");
csrf = csrfOf(page.text);
const bulk = await req("/admin/comments/bulk", {
  method: "POST",
  headers: { "content-type": "application/x-www-form-urlencoded" },
  body: form({ _csrf: csrf, ids: commentId, action: "approved", return_status: "pending" })
});
assert(bulk.status === 303, "comment bulk action succeeds");
page = await req("/admin/comments?status=approved");
assert(page.text.includes("验收评论"), "approved comment is listed");

page = await req("/admin/users?q=admin");
assert(page.status === 200 && page.text.includes("用户与权限"), "users page renders");
page = await req("/admin/profile");
csrf = csrfOf(page.text);
const profile = await req("/admin/profile/save", {
  method: "POST",
  headers: { "content-type": "application/x-www-form-urlencoded" },
  body: form({ _csrf: csrf, display_name: "管理员 v101", email: "admin@example.com", bio: "v1.0.1", avatar: coverUrl })
});
assert(profile.status === 303, "profile avatar save succeeds");
page = await req("/admin/profile");
assert(page.text.includes("avatar-img"), "avatar is shown in admin shell");

page = await req("/admin/tools");
assert(page.status === 200 && page.text.includes("运行信息"), "tools page renders");
page = await req("/admin/backups");
assert(page.status === 200 && page.text.includes("备份中心"), "backup center renders");
csrf = csrfOf(page.text);
const backup = await req("/admin/backups/action", {
  method: "POST",
  headers: { "content-type": "application/x-www-form-urlencoded" },
  body: form({ _csrf: csrf, action: "create", label: "v101-" + stamp })
});
assert(backup.status === 303, "backup creation succeeds");
page = await req("/admin/backups");
const backupName = (page.text.match(new RegExp("(v101-" + stamp + "-[A-Za-z0-9-]+\\.json)")) || [])[1];
assert(!!backupName, "backup appears in list");
const download = await req("/admin/backups/download?name=" + encodeURIComponent(backupName));
assert(download.status === 200 && download.text.includes("\"format\""), "backup download returns JSON");

csrf = csrfOf(page.text);
const restore = await req("/admin/backups/action", {
  method: "POST",
  headers: { "content-type": "application/x-www-form-urlencoded" },
  body: form({ _csrf: csrf, action: "restore_name", name: backupName, confirm: "RESTORE" })
});
assert(restore.status === 303 && (restore.location || "").includes("/admin/login"), "restore redirects to login");
jar.clear();
page = await req("/admin/login");
assert(page.status === 200, "session invalidated after restore");
csrf = csrfOf(page.text);
login = await req("/admin/login", {
  method: "POST",
  headers: { "content-type": "application/x-www-form-urlencoded" },
  body: form({ _csrf: csrf, username: "admin", password: "Cangmo-Test-2026!", next: "" })
});
assert(login.status === 303, "relogin after restore succeeds");

console.log("v1.0.1 acceptance complete");
