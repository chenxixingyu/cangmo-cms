# 安全策略 / Security Policy

## 支持版本

| 版本 | 状态 |
| --- | --- |
| 1.0.x | 支持（当前） |
| < 1.0 | 不支持 |

v1.0 面向 Windows x64。Linux 移植、进程内 TLS、插件运行时等尚未发布的功能不在支持范围内。

## 报告安全问题

**请不要在公开 Issue 中披露漏洞细节。**

优先使用 GitHub 的私密漏洞报告：

<https://github.com/chenxixingyu/cangmo-cms/security/advisories/new>

如果无法使用该功能，请通过 GitHub 私信联系
[@chenxixingyu](https://github.com/chenxixingyu)。

请尽量包含：

- 受影响版本与提交
- 复现步骤、请求/响应样本
- 影响评估（读取、写入、越权、拒绝服务等）
- 建议修复方向
- 是否已公开、是否涉及第三方

## 处理流程

1. 确认并复现；
2. 评估影响与修复方案；
3. 在私密渠道修复、验证、准备公告；
4. 发布补丁版本并在 CHANGELOG 中说明；
5. 如需 CVE，协助申请。

维护者会尽力在 72 小时内确认收到，修复时间取决于严重程度。请在修复发布前保密。

## 安全基线

- 密码：PBKDF2-HMAC-SHA256，12 万次迭代，随机盐，常量时间比较
- 会话：256-bit 随机令牌，哈希存储，登录轮换，空闲/绝对过期
- CSRF：同步令牌，写请求校验
- XSS：模板默认转义，Markdown 原始 HTML 转义，链接协议白名单
- 上传：扩展名 + 魔数、随机文件名、禁 SVG、大小限制
- 请求：头部/请求体/URL 上限、读超时、连接数限制、重复 CL / CL+TE 拒绝
- 响应头：CSP、X-Frame-Options、nosniff、Referrer-Policy、HSTS（HTTPS）
- 限流：登录、评论、API

完整威胁模型、部署检查表与已知边界见 [docs/SECURITY.md](docs/SECURITY.md)。

## 部署建议

- 使用 Caddy/Nginx 终止 HTTPS，并设置 `CANGMO_COOKIE_SECURE=true`
- 设置 `CANGMO_TRUST_PROXY=true` 与 `security.allowedHosts`
- 修改默认管理员密码；数据目录与备份目录仅服务账户可读
- 定期备份并验证恢复
- 不要安装不可信主题；主题模板等同于受信代码
