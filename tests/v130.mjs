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
page = await req("/admin/settings");
csrf = csrfOf(page.text);
assert(page.text.includes('data-settings-tab="home"') && page.text.includes('name="custom_css"'), "settings tabs and fields render");
const saved = await req("/admin/settings/save", { method: "POST", headers: { "content-type": "application/x-www-form-urlencoded" }, body: form({
  _csrf: csrf, settings_v2_present: "1", show_related_posts_present: "1",
  site_title: "仓墨测试站", site_subtitle: "副标题", site_description: "描述", site_keywords: "仓颉,博客", site_url: BASE,
  site_logo: "/static/icon.svg", site_favicon: "/static/icon.svg", footer_text: "页脚", footer_copyright: "© 测试版权", footer_icp: "京ICP备00000000号",
  posts_per_page: "10", home_hero_title: "首页主标题", home_hero_subtitle: "首页副标题", home_hero_image: "", home_show_featured: "on",
  theme_accent: "#336655", theme_mode: "light", theme_font_size: "18", theme_width: "1080", theme_radius: "16",
  nav_text: "首页|/\n关于|/pages/about", social_text: "GitHub|https://github.com/example",
  show_toc: "on", show_reading_time: "on", show_related_posts: "on", show_author: "on", show_date: "on", show_category: "on", show_tags: "on",
  excerpt_length: "100", related_count: "4", seo_image: "/static/icon.svg", seo_twitter: "@cangmo",
  comment_enabled: "on", comment_moderation: "on", comment_max_links: "3",
  custom_css: "body { letter-spacing: .01em; }", maintenance_message: "维护中"
}) });
assert(saved.status === 303, "settings save redirects");
page = await req("/");
assert(page.text.includes("首页主标题") && page.text.includes("首页副标题"), "home hero settings render");
assert(page.text.includes("/custom.css?v="), "custom css link renders");
assert(page.text.includes("--wrap: 1080px") && page.text.includes("--font-size: 18px"), "appearance variables render");
assert(page.text.includes("© 测试版权") && page.text.includes("京ICP备00000000号"), "footer settings render");
assert(page.text.includes('rel="icon" href="/static/icon.svg"') && page.text.includes('class="brand-logo"'), "logo and favicon render");
const css = await req("/custom.css");
assert(css.status === 200 && css.text.includes("letter-spacing"), "custom css endpoint serves css");
page = await req("/admin/themes");
assert(page.text.includes("当前主题") && page.text.includes('href="/admin/settings#appearance"'), "theme page links to appearance");

// Maintenance mode blocks anonymous visitors but keeps admin access.
page = await req("/admin/settings");
csrf = csrfOf(page.text);
await req("/admin/settings/save", { method: "POST", headers: { "content-type": "application/x-www-form-urlencoded" }, body: form({
  _csrf: csrf, settings_v2_present: "1", show_related_posts_present: "1",
  site_title: "仓墨测试站", site_subtitle: "副标题", site_description: "描述", site_keywords: "仓颉,博客", site_url: BASE,
  site_logo: "/static/icon.svg", site_favicon: "/static/icon.svg", footer_text: "页脚", footer_copyright: "© 测试版权", footer_icp: "京ICP备00000000号",
  posts_per_page: "10", home_hero_title: "首页主标题", home_hero_subtitle: "首页副标题", home_hero_image: "", home_show_featured: "on",
  theme_accent: "#336655", theme_mode: "light", theme_font_size: "18", theme_width: "1080", theme_radius: "16",
  nav_text: "首页|/\n关于|/pages/about", social_text: "GitHub|https://github.com/example",
  show_toc: "on", show_reading_time: "on", show_related_posts: "on", show_author: "on", show_date: "on", show_category: "on", show_tags: "on",
  excerpt_length: "100", related_count: "4", seo_image: "/static/icon.svg", seo_twitter: "@cangmo",
  comment_enabled: "on", comment_moderation: "on", comment_max_links: "3",
  custom_css: "body { letter-spacing: .01em; }", maintenance: "on", maintenance_message: "维护中"
}) });
const maintenance = await fetch(BASE + "/");
assert(maintenance.status === 503, "maintenance mode returns 503 to visitors");
const adminStill = await req("/admin");
assert(adminStill.status === 200, "admin bypasses maintenance mode");
assert((await req("/healthz")).status === 200, "health check bypasses maintenance");
console.log("v1.3 settings/theme check complete");
