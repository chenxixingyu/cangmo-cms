# 仓墨安全设计

> 本文描述 v1.0 的威胁模型、已实施控制、部署检查表与已知边界。  
> 安全不是「声明」，而是可验证的代码与测试；对应测试见 [TESTING.md](TESTING.md)。

## 1. 资产与威胁模型

需要保护的资产：

- 管理员/作者账户与会话
- 文章草稿、页面、私密设置
- 用户邮箱、IP 哈希、审计日志
- 媒体文件与备份
- 站点可用性

主要威胁：

| 威胁 | 场景 | 控制 |
| --- | --- | --- |
| 账户接管 | 弱口令、撞库、暴力破解 | PBKDF2 12 万次、登录限流、失败锁定、密码策略 |
| 会话劫持 | XSS 偷 Cookie、固定会话 | HttpOnly、SameSite、登录轮换、严格 CSP、模板转义 |
| CSRF | 诱导管理员提交表单 | 同步令牌 + Origin 无关校验 + SameSite |
| XSS | 评论/文章/标题注入脚本 | 默认转义、Markdown 原始 HTML 转义、协议白名单 |
| 路径穿越 | `/static/../../config.json` | 统一解码、点段拒绝、目录白名单、二次校验 |
| 恶意上传 | 伪装图片、SVG 脚本、超大文件 | 扩展名 + 魔数、大小限制、随机名、禁 SVG、nosniff |
| 请求走私 | 重复 CL / CL+TE | 重复头拒绝、CL+TE 拒绝、仅支持 chunked |
| 慢速攻击 | 慢头发送、长连接占用 | 读超时、头部上限、单连接请求上限、连接上限 |
| 暴力枚举 | 登录/评论/API | IP 滑动窗口限流、账户锁定、评论蜜罐 |
| 信息泄漏 | 500 堆栈、Host 头注入 | 生产泛化错误、配置化 site_url、Host 白名单 |
| 数据丢失 | 崩溃、误删 | WAL、原子快照、`.bak`、备份/恢复 |

## 2. 密码与随机数

- **CSPRNG**：Windows CNG `BCryptGenRandom(BCRYPT_USE_SYSTEM_PREFERRED_RNG)`，失败即抛错，不降级到时间种子。
- **PBKDF2-HMAC-SHA256**：默认 120,000 次迭代，16 字节盐，32 字节输出；通过 CNG `BCryptDeriveKeyPBKDF2` 加速（约 40–80ms/次）。
- **端口回退**：CNG 不可用时使用纯仓颉 PBKDF2（正确但慢），不降低迭代次数。
- **存储格式**：`pbkdf2_sha256$<iterations>$<salt_b64>$<hash_b64>`，便于未来升级迭代次数。
- **比较**：常量时间比较，避免计时侧信道。
- **重哈希**：登录时若迭代次数低于当前配置，自动重哈希。
- **密码策略**：≥10 字符，至少两类字符，禁止包含用户名/邮箱，拒绝常见弱口令。

## 3. 会话

| 项 | 值 |
| --- | --- |
| Cookie 名 | `cangmo_sid` |
| 令牌 | 32 字节 CSPRNG，base64url |
| 存储 | 仅存 `sha256(token)`；数据库泄漏不能直接复用会话 |
| 属性 | `HttpOnly; SameSite=Lax; Path=/; Max-Age=604800`；HTTPS 时加 `Secure` |
| 绝对过期 | 7 天（`sessionTtlHours`） |
| 空闲过期 | 48 小时（`sessionIdleHours`） |
| 轮换 | 登录成功、初始化完成后销毁旧会话并新建 |
| 登出 | 删除服务端会话 + 清 Cookie |
| CSRF | 每会话 24 字节随机令牌，写请求校验 |

## 4. CSRF

- 所有 `POST/PUT/PATCH/DELETE` 默认校验。
- 令牌来源：表单字段 `_csrf` 或请求头 `X-CSRF-Token`。
- 比对使用常量时间比较。
- API 使用 `Authorization: Bearer` 时跳过 CSRF（无 Cookie 语义）；使用 Cookie 调用 API 仍需令牌。
- 登录、初始化、评论、后台所有表单均带令牌；缺失返回 403。

## 5. XSS 与内容安全

- 模板 `{{ }}` 默认 HTML 转义；只有 `{{{ }}}` / `|raw` 输出原始 HTML。
- Markdown 默认**转义**原始 HTML（`allowRawHtml=false`）；管理员可在配置中开启，但默认关闭。
- 链接/图片 URL 协议白名单；`javascript:`、`data:`、`vbscript:`、`file:`、`jar:` 一律替换为 `#`。
- JSON 序列化转义 `<`、`>`、`&`，避免嵌入 `<script>` 时截断。
- 评论内容纯文本存储、渲染时转义，换行由 CSS `white-space: pre-line` 保留。
- CSP：`default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline'; img-src 'self' data:; frame-ancestors 'none'; base-uri 'self'; form-action 'self'`。
- 不使用任何内联 `<script>`、`onclick` 或第三方 CDN；后台/前台 JS 均为同源外部文件。

## 6. 文件上传

- 白名单：`jpg/jpeg/png/gif/webp/avif/pdf/mp4/webm/mp3`。
- 扩展名 + 文件头魔数双重校验。
- 文件名随机化（`media_<time><random>.<ext>`），保留原始名仅用于展示。
- 单文件 ≤ `maxBodyBytes`（默认 25MB）；表单最多 200 个分片；字段 ≤1MB。
- 禁止 SVG（可执行脚本）。
- 响应 `X-Content-Type-Options: nosniff`；媒体不设置 `Content-Disposition: inline` 之外的脚本能力。
- 上传目录不在静态根目录下，只能通过 `/media/...` 只读访问。

## 7. 路径与请求

- 路径逐段解码；拒绝 `.`、`..`、编码 `/`、`\`、NUL、超长段。
- 静态资源二次校验：拒绝 `..`、反斜杠、绝对路径、空段、非常规字符。
- 请求头 ≤64KB、请求体 ≤25MB、URL ≤2048、单连接 ≤100 请求。
- 拒绝折行头、重复 `Content-Length`、`CL+TE` 并存、非法方法/版本。
- HTTP/1.1 必须带 Host；配置 `allowedHosts` 后校验 Host，防止 Host 头攻击。
- `X-Forwarded-For/Proto` 仅在 `trustProxy=true` 时生效，且 IPv4/IPv6 字符校验。

## 8. 速率限制与锁定

| 场景 | 默认 |
| --- | --- |
| 登录 | 每 IP 15 分钟最多 20 次尝试；账户连续失败 5 次锁定 15 分钟 |
| 评论 | 每 IP 每小时 10 条（可配置） |
| API | 每 IP 每分钟 120 次（可配置） |
| 上传 | 单请求最多 10 个文件（后台） |

滑动窗口实现：内存 `HashMap<key, timestamps>` + 互斥锁，定期清理。

## 9. 安全响应头

```
Content-Security-Policy: default-src 'self'; script-src 'self'; ...
X-Frame-Options: DENY
X-Content-Type-Options: nosniff
Referrer-Policy: strict-origin-when-cross-origin
Permissions-Policy: camera=(), microphone=(), geolocation=(), interest-cohort=()
Cross-Origin-Opener-Policy: same-origin
Cross-Origin-Resource-Policy: same-origin
Strict-Transport-Security: max-age=31536000; includeSubDomains   (HTTPS)
Cache-Control: no-store (admin/api), no-cache (HTML)
```

## 10. 配置与密钥

- `config.json` 首次启动自动生成 64 位十六进制 `security.secret`，用于 IP 哈希等。
- 可用 `CANGMO_SECRET` 覆盖；容器部署建议由 Secret 管理器注入。
- 配置文件包含密钥，**不要提交到 Git**；`.gitignore` 已排除 `config.json`。
- 初始化令牌可通过 `CANGMO_SETUP_TOKEN` 固定，避免从日志读取；初始化完成后建议不设置。
- 生产环境建议：
  - `CANGMO_COOKIE_SECURE=true`
  - 反向代理设置 `X-Forwarded-Proto: https` 与 `CANGMO_TRUST_PROXY=true`
  - `allowedHosts` 填写站点域名
  - 数据目录 ACL 仅服务账户可读写

## 11. 部署检查表

- [ ] 使用 HTTPS（Caddy/Nginx 终止 TLS），HTTP 301 跳转
- [ ] `CANGMO_COOKIE_SECURE=true`
- [ ] 修改默认管理员密码，删除无用账户
- [ ] 关闭不需要的 API（`api_enabled=false`）或限制网络访问
- [ ] 数据目录、备份目录仅服务账户可读
- [ ] 定期备份 `data/`（至少每日），并验证可恢复
- [ ] 监控 `/healthz`、磁盘、日志错误
- [ ] 不在公网暴露 `127.0.0.1` 以外的管理端口
- [ ] 保留 `config.json` 与 `data/` 的离线副本
- [ ] 升级前先备份，按 [DEPLOYMENT.md](DEPLOYMENT.md) 灰度

## 12. 已知边界与不在范围

- v1.0 **不含**：TOTP 双因素、邮件找回密码、OAuth 登录、WAF、DDoS 防护、进程内 TLS。
- 密码哈希使用 PBKDF2（非 Argon2id）；如需更高抗 GPU 能力，可在后续版本替换。
- WAL 非每条 fsync；断电可能丢最后少量写入。
- 单进程单写锁；高并发写场景需数据库。
- 主题模板由管理员安装，**主题代码等同于受信代码**；不要安装不可信主题。
- 备份包含用户邮箱、IP 哈希、设置与密钥派生信息，请按敏感数据保管。

## 13. 漏洞报告

如发现安全问题，请勿公开提交 Issue。请通过项目维护者提供的私密渠道联系，并附：

- 受影响版本/提交
- 复现步骤与请求样本
- 影响评估（读取/写入/越权/DoS）
- 建议修复方向

维护者会在确认后尽快修复并在 CHANGELOG 中致谢（如你愿意署名）。
