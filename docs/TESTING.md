# 仓墨测试与验收（v1.6.0）

> 本地环境：Windows 11 x64 · 仓颉 1.2.1 (cjnative) · Node.js 22.2.0 · Microsoft Edge  
> 测试对象：v1.6.0。所有集成测试均在**全新数据目录**上执行，原始输出保存在 `docs/reports/`。  
> Linux：GitHub Actions `ubuntu-latest` 已通过 `cjpm build` + `cjpm test`（run 45223833805）。

## 1. 一键运行

```powershell
# 终端 1：启动测试实例（必须用独立 --data，避免污染现有数据）
$env:CANGMO_SETUP_TOKEN = "test-setup-token-123456"
.\target\release\bin\main.exe serve --config .\data\v101final2\config.json `
  --data .\data\v101final2 --port 18090

# 终端 2
$env:CANGMO_BASE = "http://127.0.0.1:18090"
$env:CANGMO_SETUP_TOKEN = "test-setup-token-123456"
cjpm test
node tests\smoke.mjs
node tests\e2e.mjs
node tests\extended.mjs
node tests\v101.mjs
node tests\load.mjs
node tests\security.mjs
```

或使用 `.\scripts\test-all.ps1`（PowerShell） / `./scripts/test-all.sh`（Linux）。  
> 顺序说明：`load` 必须在 `security` 之前，避免 API 限流影响并发测试。

## 2. 结果总览

| 套件 | 断言数 | 结果 | 原始输出 |
| --- | --- | --- | --- |
| 单元测试 `cjpm test` | 26 | **26 / 26** | [unit-tests-v101.txt](reports/unit-tests-v101.txt) |
| 初始化与公共站 `smoke.mjs` | 24 | **24 / 24** | [smoke-v101.txt](reports/smoke-v101.txt) |
| 后台与内容闭环 `e2e.mjs` | 31 | **31 / 31** | [e2e-v101.txt](reports/e2e-v101.txt) |
| 扩展功能 `extended.mjs` | 29 | **29 / 29** | [extended-v101.txt](reports/extended-v101.txt) |
| v1.0.1 验收 `v101.mjs` | 35 | **35 / 35** | [v101-final.txt](reports/v101-final.txt) |
| v1.1 功能 `v110.mjs` | 32 | **32 / 32** | [v110.txt](reports/v110.txt) |
| v1.2 功能 `v120.mjs` | 12 | **12 / 12** | [v120.txt](reports/v120.txt) |
| v1.2.1 令牌 `v121-token.mjs` | 8 | **8 / 8** | [v121-token.txt](reports/v121-token.txt) |
| v1.2.1 搜索/批量 `v121-search.mjs` | 9 | **9 / 9** | [v121-search.txt](reports/v121-search.txt) |
| v1.2.1 加密/变体 `v121-crypto.mjs` | 7 | **7 / 7** | [v121-crypto.txt](reports/v121-crypto.txt) |
| v1.3 设置/主题 `v130.mjs` | 12 | **12 / 12** | [v130.txt](reports/v130.txt) |
| v1.4 API/预览 | 5 | **5 / 5** | [v140-api.txt](reports/v140-api.txt) |
| v1.4 审计/会话 | 7 | **7 / 7** | [v140-audit.txt](reports/v140-audit.txt) |
| v1.4 邮件/重置 | 8 | **8 / 8** | [v140-mail.txt](reports/v140-mail.txt) |
| v1.4 TOTP | 9 | **9 / 9** | [v140-totp.txt](reports/v140-totp.txt) |
| v1.5 OpenAPI/文件夹 | 3 | **3 / 3** | [v150-openapi.txt](reports/v150-openapi.txt) |
| v1.5 主题选项/去重 | 3 | **3 / 3** | [v150-theme.txt](reports/v150-theme.txt) |
| v1.5 日历 | 1 | **1 / 1** | [v150-calendar.txt](reports/v150-calendar.txt) |
| v1.5 审核流 | 3 | **3 / 3** | [v150-review.txt](reports/v150-review.txt) |
| v1.5 主题安装 | 4 | **4 / 4** | [v150-install.txt](reports/v150-install.txt) |
| v1.6 指标 | 2 | **2 / 2** | [v160-metrics.txt](reports/v160-metrics.txt) |
| v1.6 搜索分析 | 1 | **1 / 1** | [v160-search.txt](reports/v160-search.txt) |
| v1.6 任务队列 | 1 | **1 / 1** | [v160-jobs.txt](reports/v160-jobs.txt) |
| v1.6 增量备份 | 4 | **4 / 4** | [v160-inc.txt](reports/v160-inc.txt) |
| 并发/协议 `load.mjs` | 6 | **6 / 6** | [load-v101.txt](reports/load-v101.txt) |
| 安全回归 `security.mjs` | 31 | **31 / 31** | [security-v101.txt](reports/security-v101.txt) |
| 部署自检 `doctor` | 17 模板 | **通过，17/17** | [doctor-v101.txt](reports/doctor-v101.txt) |
| 静态分析 `cjlint` | 947 条 | 921 建议 + 26 强制风格项 | [cjlint.json](reports/cjlint.json) |

**合计：26 个单元测试 + 236 项基线 + 51 项定向 = 313 项，全部通过。**

> 本轮功能与兼容说明见 [v1.1.0 发布说明](releases/v1.1.0.md)。

另执行 **10 项 v1.3 浏览器审计**（Edge/CDP）：六个设置标签、hash 定位、主题入口、首页主标题、Logo、自定义 CSS 与全局 JS 异常，全部通过，见 [ui-v130.txt](reports/ui-v130.txt)。

### v1.0.1 ~ v1.6.0 新增与回归覆盖

- 附件库：页面渲染、旧“媒体库”文案移除、JSON 上传、类型筛选、文件名搜索、选择器数据、删除
- 编辑器：封面/标签 UI、AJAX 新建分类、带分类/标签/封面的文章保存
- 前台：文章封面、分类、标签、空状态文案移除
- 评论：提交、待审核、批量通过、已通过列表
- 用户与个人资料：用户页渲染、头像保存、顶栏头像显示
- 工具/备份：工具页、备份中心、创建、列表、下载、从现有备份恢复
- v1.0.4 布局：侧栏无标签入口、系统管理折叠、文章批量操作、行操作菜单、分类弹窗
- v1.0.5：定时发布权限、中文文件名、复制为草稿、相关文章开关、设置项向后兼容
- v1.0.6：发布抽屉、页面内联抽屉、快速保存接口、设置横向标签、附件/用户密度
- v1.0.7：页面抽屉补路径/分类/标签，宽度收窄至 420px
- v1.0.8：行菜单改视口浮层、自动避让/翻转，移除侧栏「系统管理」折叠
- v1.0.9：admin.js 版本缓存、页面根路径 301、列表真实路径、菜单无 JS 回退
- v1.1.0：版本查看/恢复、附件重命名/引用保护/权限、Markdown 批量导入
- v1.2.0：行级 diff、页面模板、301 重定向、搜索高亮、命令面板
- v1.2.1：Token scopes/过期/IP、自动备份/加密、附件替换/变体、媒体/用户批量、倒排索引
- v1.3.0：站点/首页/外观/阅读/SEO 设置、Logo/主图/版权/备案、自定义 CSS、维护模式、主题预览入口
- 恢复后会话失效，必须重新登录

### 既有覆盖

- 初始化、登录、会话轮换、登出、CSRF
- 文章/页面 CRUD、Markdown 渲染、XSS 转义、评论审核、设置、API 令牌
- 定时发布（调度线程 20 秒内）
- 媒体兼容路径 `/admin/media` 仍返回 200
- 路径穿越、请求走私、超大请求、上传伪装、API 限流
- 120 并发 0 个 5xx；HEAD；Keep-Alive

## 3. 本轮修复与加固

1. 附件库上传接口增加 JSON 模式，供编辑器封面/头像选择器复用。
2. 文章编辑器内新建分类改为 AJAX，避免丢失未保存正文。
3. 封面支持上传 / 附件库 / 链接三种来源，并实时预览。
4. 标签改为 Chip 编辑，避免逗号分隔输入错误。
5. 评论管理增加批量操作、搜索、按文章筛选。
6. 用户页增加角色/状态/文章数统计与筛选。
7. 个人资料合并到顶栏用户菜单，支持头像与简介。
8. 工具与备份拆分为两个页面；备份中心支持从现有备份恢复。
9. **恢复备份后清空 sessions**，修复旧会话复活问题。
10. Linux 加密适配：OpenSSL PBKDF2 + `getrandom(2)`；`cjpm.toml` target 级链接。
11. 移除前台“还没有文章。去后台写下第一篇吧”空状态块。

## 4. 静态分析

```powershell
cjlint -f .\src -o .\docs\reports\cjlint -r json
```

结果：**947 条**（`MANDATORY` 26、`SUGGESTIONS` 921）。强制项仍集中在：

| 类型 | 数量 | 说明 |
| --- | --- | --- |
| `G_EXP_03` 副作用表达式 | 5 | 风格建议 |
| `G_FUN_02` 未使用参数 | 13 | 路由处理器统一签名 |
| `G_OTH_02` 敏感字段名硬编码 | 3 | 表单字段名 `password` 误报 |

这些是静态风格规则，不是漏洞；高风险项由 27 项安全回归覆盖。

## 5. 已知边界

- **Linux**：需要 OpenSSL 开发库；本地 Windows 测试机无法执行 Linux 二进制，Linux 构建/单测由 GitHub Actions 验证。
- **HTTPS/HSTS**：进程内无 TLS；由 Caddy/Nginx 终止。
- **邮件/TOTP/OAuth/插件/对象存储**：v1.2.0 不含。
- **长时间浸泡**：未做 24h 稳定性测试。
- **恶意文件**：未做图片解码模糊测试。
- **浏览器兼容**：Edge/Chromium 验证；Firefox/Safari 未逐一测试。
- **高并发写**：单写锁，未做写压力测试。

## 6. 验收清单

- [x] `cjpm build` 成功
- [x] `cjpm test` 21/21
- [x] 全新数据目录初始化成功
- [x] 前台首页/文章/分类/标签/搜索/归档/RSS/Sitemap/robots 可访问
- [x] 后台登录/仪表盘/文章/页面/分类/标签/评论/附件库/用户/设置/主题/审计/工具/备份/个人资料可访问
- [x] 文章 CRUD、封面、分类、标签、定时发布
- [x] 附件上传/筛选/搜索/预览/删除
- [x] 评论批量审核
- [x] 个人资料与头像
- [x] 备份创建/下载/恢复/删除，恢复后强制重新登录
- [x] API 令牌、文章创建/更新/删除、评论创建、附件兼容别名
- [x] CSRF/XSS/路径穿越/请求走私/上传伪装/限流
- [x] `doctor` 17/17 模板
- [x] Windows 构建与测试
- [x] Linux CI（GitHub Actions Ubuntu 构建 + 单测通过）
