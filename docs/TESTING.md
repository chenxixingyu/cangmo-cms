# 仓墨测试与验收

> 测试环境：Windows 11 x64 · 仓颉 1.2.1 (cjnative) · Node.js 22.2.0 · Microsoft Edge（截图）  
> 测试对象：v1.0.0，commit 为本次交付源码。  
> 所有测试均在 `data/test6` 的**全新数据目录**上执行，完成后保留原始输出在 `docs/reports/`。

## 1. 一键运行

```powershell
# 终端 1：启动测试实例
$env:CANGMO_SETUP_TOKEN = "test-setup-token-123456"
$env:CANGMO_DATA_DIR = "./data/test6"
.\target\release\bin\main.exe serve --config .\data\test6\config.json --port 18086

# 终端 2
$env:CANGMO_BASE = "http://127.0.0.1:18086"
$env:CANGMO_SETUP_TOKEN = "test-setup-token-123456"
cjpm test
node tests\smoke.mjs
node tests\e2e.mjs
node tests\load.mjs
node tests\security.mjs
```

或：

```powershell
.\scripts\test-all.ps1
```

## 2. 结果总览

| 套件 | 断言数 | 结果 | 原始输出 |
| --- | --- | --- | --- |
| 单元测试 `cjpm test` | 17 | **17 / 17 通过** | [unit-tests.txt](reports/unit-tests.txt) |
| 初始化与公共站点 `smoke.mjs` | 24 | **24 / 24 通过** | [smoke.txt](reports/smoke.txt) |
| 后台与内容闭环 `e2e.mjs` | 30 | **30 / 30 通过** | [e2e.txt](reports/e2e.txt) |
| 安全回归 `security.mjs` | 27 | **27 / 27 通过** | [security.txt](reports/security.txt) |
| 并发/HEAD/Keep-Alive `load.mjs` | 6 | **6 / 6 通过** | [load.txt](reports/load.txt) |
| 部署自检 `doctor` | 12 项检查 | **通过，模板 16/16** | [doctor.txt](reports/doctor.txt) |
| 静态分析 `cjlint` | 680 条 | 659 建议 + 21 强制（均为风格类，见 §5） | [cjlint.json](reports/cjlint.json) |

**合计：104 项功能/安全断言全部通过。**

### 单元测试覆盖

- SHA-256 已知向量（`abc`）
- HMAC-SHA256 已知向量
- PBKDF2 密码哈希与校验、错误密码拒绝
- Base64 / URL 编码往返
- UTF-8 字符数、截断、HTML 转义
- 密码策略
- JSON 解析/序列化、转义、深度限制、代理对、非法输入
- Markdown 标题/粗体/代码/列表/表格/代码围栏、原始 HTML 转义、`javascript:` 链接拦截、TOC 生成

### 端到端覆盖

- 初始化令牌 → 管理员创建 → 示例文章/页面
- 登录、会话轮换、登出
- 后台仪表盘、文章/页面列表、编辑器
- 文章创建 → 前台可见 → Markdown 渲染 → XSS 转义
- 评论提交 → 待审核 → 审核通过 → 前台展示
- 媒体上传 → 列表 → 图片以 `image/png` 提供
- 设置保存 → 前台副标题更新
- 备份创建 → 列表 → 下载（`Content-Disposition: attachment`）
- API 令牌创建 → Bearer 创建文章 → 公开读取
- 无 CSRF 写请求 403
- 登出后后台 303

### 安全回归覆盖

| 用例 | 结果 |
| --- | --- |
| 会话 Cookie HttpOnly / SameSite | ✅ |
| 登录后会话轮换 | ✅ |
| 无 CSRF 后台写请求 403 | ✅ |
| 无令牌 API 写请求 401 | ✅ |
| 标题 HTML 转义（XSS） | ✅ |
| 4 种路径穿越（原样/编码，static/media） | ✅ |
| 重复 Content-Length 拒绝 | ✅ |
| CL + Transfer-Encoding 拒绝 | ✅ |
| 超大请求体 413 | ✅ |
| HTTP/1.1 缺 Host 拒绝 | ✅ |
| TRACE 方法拒绝 | ✅ |
| 超大请求头拒绝 | ✅ |
| 伪装 PNG（魔数不符）拒绝 | ✅ |
| API 令牌仅显示一次 | ✅ |
| 错误密码 401 且提示不泄漏用户是否存在 | ✅ |
| API 限流触发 429 | ✅ |

### 并发

| 指标 | 结果 |
| --- | --- |
| 120 个并发请求（5 类页面） | 全部 2xx，0 个 5xx，314ms |
| HEAD | 保留 Content-Length，无 body |
| Keep-Alive | 20 次顺序请求全部成功 |

## 3. 测试中发现并修复的问题

以下问题由本次测试暴露，已修复并回归：

1. **匿名会话被误判过期**：`loadSession` 把 `user_id` 为空当成无效会话，导致每次请求新建会话、CSRF 永远失败。修复：只按绝对/空闲过期判断。
2. **模板表达式 `|default("中文")` 崩溃**：`parseOutput` 为检测 `|raw` 无条件截取最后 4 字节，中文多字节被切断触发 `String.fromUtf8` 异常。修复：按 ASCII 字节判断。
3. **中文文本被按字节转 Rune**：`normalizeWhitespace` / `safeUrl` / 响应头清洗逐字节构造 Rune，导致中文乱码。修复：保留原始 UTF-8 字节或按切片转换。
4. **路由参数未生效**：`Ctx.param` 读取了未填充的 `HttpRequest.params`，导致 `/posts/:slug` 404。修复：读取 `Ctx.params`。
5. **超大请求头无响应**：`readHeaderBlock` 抛出的异常未被捕获，连接直接关闭。修复：捕获并返回 400。
6. **中文标题 TOC 乱码**：标题 plain text 经过上述逐字节转换；修复后使用 `h-<hash>` 稳定锚点。

## 4. 静态分析

```powershell
cjlint -f .\src -o .\docs\reports\cjlint -r json
```

结果：**680 条**，其中 `MANDATORY` 21 条、`SUGGESTIONS` 659 条。

21 条强制项集中在：

| 类型 | 数量 | 说明 |
| --- | --- | --- |
| `G_EXP_03` 副作用表达式 | 6 | `a && f()` 形式，风格建议 |
| `G_FUN_02` 未使用参数 | 13 | 路由处理器统一签名 `ctx`、`webStatus` 等 |
| `G_OTH_02` 敏感字段名硬编码 | 3 | 表单字段名 `password` 被误报 |

> 这些是静态风格规则，不是漏洞。真正的高风险项（注入、越权、路径穿越、XSS、CSRF）已由 27 项安全回归覆盖。  
> 我们不会为了“清零告警”而改变路由签名或误导性重命名；相关告警在代码审查中逐条评估。

## 5. 未自动覆盖 / 已知边界

- **Windows CNG**：测试机自带 `bcrypt.dll`；无 CNG 时纯仓颉回退路径仅做单元级验证，未做性能基准。
- **HTTPS/HSTS**：进程内无 TLS，HTTPS 相关头由反向代理触发，未在 CI 中自动化。
- **邮件/TOTP/OAuth/插件**：v1.0 不含。
- **长时间浸泡**：未做 24h 稳定性测试；调度线程、WAL 压缩有单元/集成覆盖，但未做长跑。
- **恶意大文件/压缩炸弹**：上传有大小与类型限制，但未做图片解码模糊测试。
- **浏览器兼容**：使用 Edge/Chromium 截图验证；Firefox/Safari 未逐一测试，CSS 使用标准特性。
- **高并发写**：单写锁，未做写压力测试；读并发已覆盖 120 并发。

## 6. 验收清单

- [x] `cjpm build` 成功
- [x] `cjpm test` 17/17
- [x] 全新数据目录初始化成功
- [x] 前台首页/文章/分类/标签/搜索/归档/RSS/Sitemap/robots 可访问
- [x] 后台登录/仪表盘/文章/页面/分类/标签/评论/媒体/用户/设置/主题/审计/工具/个人资料可访问
- [x] 文章 CRUD 与发布闭环
- [x] 评论提交与审核闭环
- [x] 媒体上传与访问
- [x] 备份创建/下载/恢复接口
- [x] API 令牌与 REST API
- [x] CSRF/XSS/路径穿越/请求走私/上传伪装/限流
- [x] `doctor` 自检
- [x] 截图与文档
