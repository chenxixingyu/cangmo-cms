# 仓墨测试报告（v1.2.0）

- 日期：2026-11-22
- 本地环境：Windows 11 x64 / 仓颉 1.2.1 / Node.js 22.2.0
- Linux：GitHub Actions Ubuntu（`cjpm build` + `cjpm test`）
- 结论：**通过**。24 个单元测试 + 200 项集成/安全断言，合计 **224 项**；另 11 项 v1.2 浏览器审计通过；静态分析无高危项。

| 套件 | 结果 | 文件 |
| --- | --- | --- |
| 单元测试 | 24/24 | [unit-tests-v101.txt](unit-tests-v101.txt) |
| 初始化与公共站 | 24/24 | [smoke-v101.txt](smoke-v101.txt) |
| 后台与内容闭环 | 31/31 | [e2e-v101.txt](e2e-v101.txt) |
| 扩展功能 | 29/29 | [extended-v101.txt](extended-v101.txt) |
| v1.0.1 验收 | 35/35 | [v101-final.txt](v101-final.txt) |
| v1.1 功能 | 32/32 | [v110.txt](v110.txt) |
| v1.2 功能 | 12/12 | [v120.txt](v120.txt) |
| 并发/协议 | 6/6 | [load-v101.txt](load-v101.txt) |
| 安全回归 | 31/31 | [security-v101.txt](security-v101.txt) |
| 部署自检 | 通过（17/17 模板） | [doctor-v101.txt](doctor-v101.txt) |
| cjlint | 807 条（785 建议 / 22 强制风格） | [cjlint.json](cjlint.json) |

详细覆盖、修复项与已知边界见 [../TESTING.md](../TESTING.md)。
