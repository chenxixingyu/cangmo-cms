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
page = await req("/admin/backups");
csrf = csrfOf(page.text);
await req("/admin/backups/auto", { method: "POST", headers: { "content-type": "application/x-www-form-urlencoded" }, body: form({ _csrf: csrf, backup_interval_hours: "1", backup_keep: "2", backup_encrypt: "on" }) });
const created = await req("/admin/backups/action", { method: "POST", headers: { "content-type": "application/x-www-form-urlencoded" }, body: form({ _csrf: csrf, action: "create", label: "enc" }) });
assert(created.status === 303, "encrypted backup created");
page = await req("/admin/backups");
const name = (page.text.match(/enc-[0-9-]+-[a-f0-9]+\.json/) || [])[0];
assert(!!name, "encrypted backup listed");
const encrypted = await req("/admin/backups/download?name=" + encodeURIComponent(name));
console.log("download", encrypted.status, encrypted.text.slice(0, 80));
assert(encrypted.text.includes('"format": 1'), "encrypted backup downloads decrypted JSON");

// The scheduler creates an encrypted auto backup on its next tick.
page = await req("/admin/backups");
csrf = csrfOf(page.text);
await req("/admin/backups/auto", { method: "POST", headers: { "content-type": "application/x-www-form-urlencoded" }, body: form({ _csrf: csrf, backup_auto: "on", backup_interval_hours: "1", backup_keep: "2", backup_encrypt: "on" }) });
await new Promise((resolve) => setTimeout(resolve, 22000));
page = await req("/admin/backups");
assert(page.text.includes("auto-"), "scheduled auto backup exists");
assert(page.text.includes("加密备份"), "backup page exposes encryption setting");

// Client-side style WebP variant endpoint.
page = await req("/admin/attachments");
csrf = csrfOf(page.text);
const png = Buffer.from("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/p9sAAAAASUVORK5CYII=", "base64");
const up = new FormData(); up.append("_csrf", csrf); up.append("files", new Blob([png], { type: "image/png" }), "variant.png");
const uploaded = await fetch(BASE + "/admin/attachments/upload?format=json", { method: "POST", headers: { cookie: ckH(), "x-csrf-token": csrf, accept: "application/json" }, body: up });
const media = (await uploaded.json()).items[0];
const webp = Buffer.from("UklGRiIAAABXRUJQVlA4IBYAAAAwAQCdASoBAAEAAUAmJaQAA3AA/vuUAAA=", "base64");
const vf = new FormData(); vf.append("file", new Blob([webp], { type: "image/webp" }), "thumb.webp");
const variant = await fetch(BASE + media.id ? BASE + "/admin/attachments/" + media.id + "/variant" : "", { method: "POST", headers: { cookie: ckH(), "x-csrf-token": csrf }, body: vf });
assert(variant.status === 200, "WebP variant accepted");
page = await req("/admin/attachments");
assert(page.text.includes("-thumb.webp"), "attachment card uses the variant thumbnail");
console.log("v1.2.1 encryption/variant check complete");
