# 仓墨测试报告（v1.6.0）

- 日期：2026-11-24
- 本地环境：Windows 11 x64 / 仓颉 1.2.1 / Node.js 22.2.0
- Linux：GitHub Actions Ubuntu（`cjpm build` + `cjpm test`）
- 结论：**通过**。26 个单元测试 + 236 项基线 + 51 项定向，合计 **313 项**；另 10 项 v1.3 浏览器审计通过；静态分析无高危项。

| 套件 | 结果 | 文件 |
| --- | --- | --- |
| 单元测试 | 26/26 | [unit-tests-v101.txt](unit-tests-v101.txt) |
| 初始化与公共站 | 24/24 | [smoke-v101.txt](smoke-v101.txt) |
| 后台与内容闭环 | 31/31 | [e2e-v101.txt](e2e-v101.txt) |
| 扩展功能 | 29/29 | [extended-v101.txt](extended-v101.txt) |
| v1.0.1 验收 | 35/35 | [v101-final.txt](v101-final.txt) |
| v1.1 功能 | 32/32 | [v110.txt](v110.txt) |
| v1.2 功能 | 12/12 | [v120.txt](v120.txt) |
| v1.2.1 令牌 | 8/8 | [v121-token.txt](v121-token.txt) |
| v1.2.1 搜索/批量 | 9/9 | [v121-search.txt](v121-search.txt) |
| v1.2.1 加密/变体 | 7/7 | [v121-crypto.txt](v121-crypto.txt) |
| v1.3 设置/主题 | 12/12 | [v130.txt](v130.txt) |
| 并发/协议 | 6/6 | [load-v101.txt](load-v101.txt) |
| 安全回归 | 31/31 | [security-v101.txt](security-v101.txt) |
| 部署自检 | 通过（17/17 模板） | [doctor-v101.txt](doctor-v101.txt) |
| cjlint | 947 条（921 建议 / 26 强制风格） | [cjlint.json](cjlint.json) |

详细覆盖、修复项与已知边界见 [../TESTING.md](../TESTING.md)。
