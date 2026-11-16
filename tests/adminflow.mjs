const BASE = "http://127.0.0.1:18081";
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
  const res = await fetch(BASE + path, { ...options, headers, redirect: "manual" });
  cookies(res);
  const text = await res.text();
  return { status: res.status, location: res.headers.get("location"), text, headers: res.headers };
}
function csrfOf(html) {
  return (html.match(/name="_csrf" value="([^"]+)"/) || [])[1] || "";
}
function assert(ok, message) {
  if (!ok) { console.error("FAIL:", message); process.exitCode = 1; } else { console.log("ok:", message); }
}

let admin = await req("/admin");
assert(admin.status === 303, "anonymous /admin redirects");
const login = await req("/admin/login");
assert(login.status === 200, "login page 200");
const csrf = csrfOf(login.text);
const form = new URLSearchParams({ _csrf: csrf, username: "admin", password: "Cangmo-Test-2026!", next: "" });
const loginPost = await req("/admin/login", {
  method: "POST",
  headers: { "content-type": "application/x-www-form-urlencoded" },
  body: form.toString()
});
assert(loginPost.status === 303, "login redirects");
console.log("login ->", loginPost.status, loginPost.location);

admin = await req("/admin");
console.log("admin status", admin.status);
assert(admin.status === 200, "dashboard 200");
if (admin.status !== 200) console.log(admin.text.slice(0, 400));

const post = await req("/posts/hello-cangmo");
console.log("post status", post.status);
assert(post.status === 200, "post page 200");
if (post.status !== 200) console.log(post.text.slice(0, 400));

const api = await req("/api/v1/posts/hello-cangmo");
assert(api.status === 200, "API post 200");

const editor = await req("/admin/posts/new");
console.log("editor status", editor.status);
assert(editor.status === 200, "new post editor 200");
const settings = await req("/admin/settings");
assert(settings.status === 200, "settings page 200");
const media = await req("/admin/media");
assert(media.status === 200, "media page 200");
const comments = await req("/admin/comments");
assert(comments.status === 200, "comments page 200");
