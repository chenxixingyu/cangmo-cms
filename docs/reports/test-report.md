# 仓墨测试报告（v1.0.0）

- 日期：2026-11-17
- 环境：Windows 11 x64 / 仓颉 1.2.1 / Node.js 22.2.0
- 结论：**通过**。128 项功能与安全断言全部通过，21 个单元测试通过，静态分析无高危项。

| 套件 | 结果 | 文件 |
| --- | --- | --- |
| 单元测试 | 21/21 | [unit-tests.txt](unit-tests.txt) |
| 初始化与公共站 | 24/24 | [smoke.txt](smoke.txt) |
| 后台与内容闭环 | 30/30 | [e2e.txt](e2e.txt) |
| 扩展功能（预览/页面/定时/API） | 20/20 | [extended.txt](extended.txt) |
| 安全回归 | 27/27 | [security.txt](security.txt) |
| 并发/协议 | 6/6 | [load.txt](load.txt) |
| 部署自检 | 通过 | [doctor.txt](doctor.txt) |
| cjlint | 710 条（689 建议 / 21 强制风格） | [cjlint.json](cjlint.json) |

详细说明、逐项覆盖与已知边界见 [../TESTING.md](../TESTING.md)。
