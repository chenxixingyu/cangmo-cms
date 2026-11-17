# 贡献指南 / Contributing

感谢你关注仓墨。提交代码前请阅读以下约定。

## 开发环境

- Windows 10/11 x64
- 仓颉 1.2.1（`cjc`、`cjpm`）
- Node.js 18+（仅用于端到端测试）
- Git 2.40+

```powershell
$env:CANGJIE_HOME = "C:\Program Files (x86)\Cangjie"
$env:Path = "$env:CANGJIE_HOME\runtime\lib\windows_x86_64_cjnative;$env:CANGJIE_HOME\lib\windows_x86_64_cjnative;$env:CANGJIE_HOME\bin;$env:CANGJIE_HOME\tools\bin;$env:CANGJIE_HOME\tools\lib;$env:Path"
cjpm build
cjpm test
```

## 分支与提交

- 从 `main` 拉出 `feat/<topic>`、`fix/<topic>` 或 `docs/<topic>`。
- 提交信息使用 Conventional Commits：`feat: ...`、`fix: ...`、`docs: ...`、`test: ...`、`chore: ...`。
- 一个 PR 只做一件事；避免混入格式化无关改动。
- 不要提交 `data/`、`config.json`、日志、备份、`target/` 或任何密钥。

## 代码约定

- 使用 `cjfmt` 格式化；避免无关的全局重排。
- 新功能必须有测试；修复 bug 必须补回归用例。
- 安全相关改动需在 PR 描述中说明威胁模型与验证方式。
- 不在代码中硬编码密码、令牌、邮箱、域名。
- 不引入与项目许可证不兼容的第三方代码；如引入，更新 `THIRD_PARTY_NOTICES.md`。

## 测试

```powershell
cjpm test
# 启动测试实例后：
node tests\smoke.mjs
node tests\e2e.mjs
node tests\extended.mjs
node tests\security.mjs
node tests\load.mjs
```

测试失败时请附上完整输出、操作系统版本与 Cangjie 版本。

## 文档

- 用户文档放 `docs/`，架构/安全/API/部署分别对应现有文件。
- 修改功能时同步更新 `docs/FEATURES.md`、`CHANGELOG.md`（如适用）。
- 不要复制其他项目的文案或模板；所有文档需原创或标注来源与许可证。

## 安全

发现安全问题请不要提交公开 Issue，按 [SECURITY.md](SECURITY.md) 私下报告。

## 版权

提交贡献即表示你有权提交该内容，并同意以本项目的
[Cangmo Source-Available License 1.0](LICENSE) 授权。你保留自己贡献的著作权，
项目版权归 宸熙星语 (chenxixingyu) 所有。
