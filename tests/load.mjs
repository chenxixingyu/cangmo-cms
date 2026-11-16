// Cangmo light load / concurrency smoke test.
const BASE = process.env.CANGMO_BASE || "http://127.0.0.1:18085";

function assert(ok, message) {
  if (!ok) { console.error("FAIL:", message); process.exitCode = 1; } else { console.log("ok:", message); }
}

const started = Date.now();
const paths = ["/", "/posts/hello-cangmo", "/api/v1/posts", "/feed.xml", "/sitemap.xml"];
const requests = [];
for (let i = 0; i < 120; i += 1) {
  const path = paths[i % paths.length];
  requests.push(fetch(BASE + path).then(async (response) => ({
    path,
    status: response.status,
    length: (await response.arrayBuffer()).byteLength
  })).catch((error) => ({ path, status: 0, error: String(error) })));
}
const results = await Promise.all(requests);
const elapsed = Date.now() - started;
const failures = results.filter((item) => item.status < 200 || item.status >= 400);
const serverErrors = results.filter((item) => item.status >= 500);
assert(failures.length === 0, `120 concurrent requests all succeeded (${elapsed}ms)`);
assert(serverErrors.length === 0, "no 5xx under concurrency");
const byPath = {};
for (const item of results) byPath[item.path] = (byPath[item.path] || 0) + 1;
console.log("distribution", byPath, "elapsed_ms", elapsed);

// HEAD must return headers without a body.
const head = await fetch(BASE + "/", { method: "HEAD" });
const headBody = await head.text();
assert(head.status === 200, "HEAD / is 200");
assert(Number(head.headers.get("content-length") || 0) > 0, "HEAD keeps Content-Length");
assert(headBody.length === 0, "HEAD has no body");

// Keep-alive: same connection reused by undici for sequential requests.
let ok = true;
for (let i = 0; i < 20; i += 1) {
  const response = await fetch(BASE + "/healthz");
  if (response.status !== 200) ok = false;
}
assert(ok, "20 sequential keep-alive requests succeed");

console.log("load test complete");
