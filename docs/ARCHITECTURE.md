# 仓墨架构设计

## 1. 设计目标

| 目标 | 取舍 |
| --- | --- |
| 仓颉原生、零 Web 框架依赖 | 自己实现 HTTP、模板、Markdown、JSON、存储 |
| 单文件数据、易备份 | JSON 文档 + WAL，而不是 MySQL/PostgreSQL |
| 安全默认 | 严格 CSP、CSRF、上传白名单、路径归一化、限流 |
| 可读、可审计 | 核心模块文件少、无代码生成、无反射魔法 |
| 中小站点性能 | 内存数据 + 线程池式连接；不为百万级数据设计 |

## 2. 分层

```
┌──────────────────────────────────────────────────────────────┐
│  main.cj  CLI: serve / init / doctor / user / backup / export │
├──────────────────────────────────────────────────────────────┤
│  web/       WebApp · Ctx · WebRouter · PublicSite · AdminSite│
│             · ApiSite · 静态文件 · 会话/CSRF/安全头            │
├──────────────────────────────────────────────────────────────┤
│  service/   Auth · Post · Taxonomy · Comment · Media · Stats  │
│             · Search · Audit · Backup · Scheduler            │
├──────────────────────────────────────────────────────────────┤
│  store/     Store: 内存 Map + WAL + 原子快照 + 压缩            │
├──────────────────────────────────────────────────────────────┤
│  http/      HttpServer · HttpRequest/Response · Headers       │
│             · Cookie · Multipart · Router                    │
├──────────────────────────────────────────────────────────────┤
│  template/  Lexer · Parser · AST · RenderContext · Filters    │
│  markdown/  Block/Inline Parser · HTML Escaper · TOC          │
│  json/      RFC 8259 Parser/Serializer                        │
│  core/      Config · Logger · SHA-256/HMAC/PBKDF2 · Util     │
└──────────────────────────────────────────────────────────────┘
```

依赖方向严格向下：`web → service → store → json/core`；`http` 不依赖 `service`；`template` 只依赖 `json/core`。没有循环依赖。

## 3. 请求生命周期

```
TCP accept (HttpServer)
  └─ 连接线程: 读请求头（≤64KB）
       ├─ 解析请求行 / 头 / Host / Content-Length / Chunked
       ├─ 读请求体（≤25MB）
       ├─ 组装 HttpRequest（查询串、Cookie）
       └─ WebApp.handle
            ├─ 静态资源 → 直接返回（ETag / Range / 安全头）
            ├─ 载入会话（Cookie cangmo_sid → SHA-256 → sessions）
            ├─ CSRF 校验（写方法）
            ├─ 限流（API）
            ├─ WebRouter 匹配 → Ctx(params)
            ├─ PublicSite / AdminSite / ApiSite 处理
            ├─ AppError → 4xx/5xx 页面或 JSON
            └─ 会话 Cookie、安全头、缓存头
  └─ 写响应（HEAD 自动去 body）
```

### 连接与并发

- `TcpServerSocket` 单接受线程；每个连接一个 `spawn` 线程。
- `maxConnections` 控制并发连接数，超出直接关闭。
- 读超时 15s、写超时 15s、keep-alive 空闲 10s、单连接最多 100 个请求，抵御慢速攻击。
- 请求体、请求头、URL 均有硬上限。
- 不支持 HTTP/2、WebSocket、TLS；生产建议由反向代理终结 TLS/HTTP2。

## 4. 存储引擎

### 4.1 内存模型

```text
HashMap<collection, HashMap<id, JsonValue>>
例如：
  posts      → post_xxx → { title, content, status, ... }
  users      → user_xxx → { username, password_hash, ... }
  settings   → site_title → { value: "仓墨", updated_at: ... }
```

集合：`users`、`posts`、`categories`、`tags`、`comments`、`media`、`sessions`、`settings`、`audit`、`revisions`、`api_tokens`。

### 4.2 持久化

```
data/
├─ db.json        原子快照（temp + rename，保留 db.json.bak）
├─ wal.log        追加日志，一行一个 JSON 记录
├─ uploads/       媒体文件（按年/月）
├─ logs/          每日日志
└─ backups/       备份 JSON
```

写路径：

1. 内存更新；
2. 追加 WAL（`put` / `del` 记录，包含完整文档）；
3. WAL 超过 2,000 条或 4MB 时压缩：写快照 → 清空 WAL。

启动路径：

1. 读 `db.json`；损坏则尝试 `db.json.bak`；
2. 逐行重放 `wal.log`；损坏尾行忽略并立即压缩修复；
3. 对非法集合名/ID/文档类型给出启动警告。

> 说明：WAL 使用 `File.appendTo`，依赖操作系统写缓存；进程崩溃不会丢已提交记录，断电可能丢最后若干条。对博客场景可接受；对强一致场景应替换为数据库。

### 4.3 并发

- `Store` 内部单 `Mutex`，所有读写串行化；读返回只读引用，写做深拷贝。
- 服务层无状态，可被多线程安全调用。
- 统计浏览量在内存聚合，由调度线程每 40 秒落盘，避免每访问一次写盘。

## 5. HTTP 层

- 请求行只接受 `GET/HEAD/POST/PUT/PATCH/DELETE/OPTIONS`，版本仅 `HTTP/1.0/1.1`。
- 请求头按 RFC 7230 严格校验：拒绝折行、重复 `Content-Length`、`CL+TE` 同时出现。
- 目标路径逐段百分号解码，拒绝 `..`、编码斜杠/反斜杠、NUL。
- 响应统一加 `Date`、`Server`、`Content-Length`、`Connection`；HEAD 保留 Content-Length 不发 body。
- 静态资源支持 `ETag`、`If-None-Match`、单段 `Range`（206）；媒体缓存 30 天，主题资源 1 小时。
- 错误页分为主题化 HTML 与 JSON（API）；生产环境 5xx 不泄漏内部信息。

## 6. 模板引擎

原创语法，避免引入 Twig/Jinja 兼容层：

```html
{{ value }}            转义输出
{{{ value }}}          原始 HTML
{{ value|raw }}        原始 HTML
{% if post.status == "published" %}...{% elif ... %}...{% else %}...{% endif %}
{% for post in posts %}...{% endfor %}
{% include "partials/card.html" %}
{# 注释 #}
```

- 表达式支持点访问、索引、`== != > < >= <=`、`and/or/not`、`+`、字符串/数字/布尔/null。
- 过滤器：`default`、`upper`、`lower`、`trim`、`length`、`truncate`、`strip`、`date`、`relative`、`json`、`urlencode`、`join`、`first`、`last`、`raw`。
- 默认自动 HTML 转义；只有显式 `raw` / 三花括号才输出原始 HTML。
- 模板按名称缓存；开发模式（`CANGMO_DEV=true`）每次重新读取。
- 模板名做白名单校验，禁止 `..`、反斜杠、绝对路径。

## 7. Markdown 渲染器

- 块级：ATX 标题、围栏代码、引用、有序/无序列表（含嵌套）、表格、分隔线、段落。
- 行内：粗体、斜体、删除线、行内代码、链接、图片、自动链接、硬换行、反斜杠转义。
- 安全：默认转义原始 HTML；链接协议白名单（http/https/mailto/相对路径）；拦截 `javascript:`、`data:`、`vbscript:`、`file:`、`jar:`。
- 标题生成稳定锚点：ASCII 标题用 slug，中文标题用 `h-<sha256 前 8 位>`，并处理重名。
- 输出 `MarkdownResult { html, headings }`，标题列表用于文章目录。

## 8. 认证与会话

```
Cookie: cangmo_sid=<32字节随机 base64url>
DB: sessions[sha256(token)] = { user_id, csrf, expires_at, last_seen_at, flash[] }
```

- 登录成功：删除旧会话 → 新建会话 → 下发新 Cookie（防会话固定）。
- 空闲 48h / 绝对 7 天过期；每 5 分钟最多回写一次 `last_seen_at`。
- CSRF 令牌随会话生成，写请求比较 `_csrf` 表单字段或 `X-CSRF-Token` 头。
- API Bearer 令牌独立于会话：`api_tokens[sha256(token)]`，支持撤销与最近使用时间。

## 9. 数据模型（主要字段）

```text
User:    id, username, email, password_hash, display_name, role, status,
         created_at, updated_at, last_login_at, failed_logins, locked_until
Post:    id, type(post|page), title, slug, summary, content, content_html,
         headings[], status, author_id, category_id, tag_ids[], cover,
         allow_comments, pinned, featured, seo_title, seo_description,
         scheduled_at, published_at, created_at, updated_at, views,
         reading_minutes
Comment: id, post_id, parent_id, author_name, author_email, author_url,
         content, status(pending|approved|spam|trash), ip_hash, user_agent,
         created_at, updated_at
Media:   id, kind, path, url, filename, original_name, mime, size, width,
         height, sha256, created_at, uploaded_by
Session: user_id, csrf, created_at, expires_at, last_seen_at, ip_hash,
         user_agent, flash[]
```

## 10. 权限模型

| 能力 | admin | editor | author | contributor | subscriber |
| --- | --- | --- | --- | --- | --- |
| 阅读 | ✅ | ✅ | ✅ | ✅ | ✅ |
| 创建文章 | ✅ | ✅ | ✅ | ✅ | ❌ |
| 发布文章 | ✅ | ✅ | ✅ | ❌ | ❌ |
| 编辑他人文章 | ✅ | ✅ | ❌ | ❌ | ❌ |
| 页面管理 | ✅ | ✅ | ❌ | ❌ | ❌ |
| 评论审核 | ✅ | ✅ | ❌ | ❌ | ❌ |
| 媒体上传 | ✅ | ✅ | ✅ | ❌ | ❌ |
| 用户/设置/主题/备份 | ✅ | ❌ | ❌ | ❌ | ❌ |

投稿者只能编辑自己的草稿；管理员不能被降级/停用为最后一个管理员。

## 11. 扩展点

- **主题**：新增 `themes/<name>/theme.json` + `templates/` + `static/`，后台切换立即生效。
- **模板局部**：`partials/` 目录，`{% include %}` 复用。
- **路由**：在 `WebApp.registerRoutes()` 注册 `WebHandler`。
- **服务**：服务类只依赖 `Store`/`Config`，可单独测试。
- **规划**：插件动态库、Webhook、对象存储、多站点。

## 12. 已知限制

1. 仅 Windows x64（CNG 依赖）；Linux 需替换 `crypto.cj` 中 FFI。
2. 无进程内 TLS/HTTP2；用 Caddy/Nginx。
3. 单进程、单写锁；写吞吐受限于磁盘追加。
4. 搜索为线性扫描；大数据量需外部索引。
5. 无插件运行时；主题只能改展示，不能扩展业务逻辑。
6. WAL 非 fsync 每条；强一致场景需数据库。
