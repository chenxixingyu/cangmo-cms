# GitHub 仓库发布清单

## 当前状态（2026-11-22）

- ✅ 仓库：<https://github.com/chenxixingyu/cangmo-cms>（2026-11-18 由 `cangmo-blog` 更名，旧地址 301 重定向）
- ✅ `main` 已推送（最新提交以仓库为准）
- ✅ 标签 `v1.1.0` 已推送
- ✅ CI 双平台：Windows + Ubuntu，`cjpm build` + `cjpm test`（run 44923991922 全绿）
- ✅ Release `v1.1.0` 已发布，附 `cangmo-v1.1.0-source.zip` 与 `cangmo-v1.1.0.bundle`
- ✅ 私密漏洞报告、Secret scanning、Push protection、Dependabot alerts 已启用
- ✅ Topics、描述、Discussions 已配置
- ⚠️ 许可证为自定义许可证，GitHub 识别为 “Other”（非 OSI 认证）

## 仓库信息

- Owner：`chenxixingyu`
- 仓库名：`cangmo-cms`
- URL：<https://github.com/chenxixingyu/cangmo-cms>
- 可见性：Public
- 默认分支：`main`
- 描述：

  > 仓墨 Cangmo — 用仓颉语言原生构建的现代、安全博客系统 / A secure blog engine written in Cangjie.

- Topics：
  `cangjie`、`cangjie-language`、`blog`、`blog-engine`、`cms`、`self-hosted`、
  `markdown`、`security`、`windows`、`chinese`

## 首次推送

```powershell
cd E:\mianban\cangmo
git remote add origin https://github.com/chenxixingyu/cangmo-cms.git
git push -u origin main
git push origin v1.1.0
```

推送 `main` 会触发 CI（`.github/workflows/ci.yml`）。  
推送 `v1.1.0` 标签会触发 `.github/workflows/release.yml`，自动创建
GitHub Release 并附加源码 zip 与 git bundle。

## 发布后检查

- [ ] Actions 中 `CI` 为绿色
- [ ] Actions 中 `Release` 成功，Release 页面有 `cangmo-v1.1.0-source.zip`
      与 `cangmo-v1.1.0.bundle`
- [ ] 仓库 About 描述与 Topics 已填写
- [ ] Issues / Discussions 已启用
- [ ] 分支保护：`main` 要求 PR、至少 1 个审查、禁止强推
- [ ] 私密漏洞报告（Private vulnerability reporting）已启用
- [ ] Releases 中 v1.1.0 标记为 Latest
- [ ] README 徽章显示正常

## 版本发布流程

1. 更新 `CHANGELOG.md` 与 `docs/releases/<version>.md`
2. 提交并推送 `main`
3. 创建带注释标签：

   ```powershell
   git tag -a v1.1.0 -m "Cangmo v1.1.0"
   git push origin v1.1.0
   ```

4. 等待 Release workflow，检查附件与说明
5. 如 Actions 不可用，可手动创建 Release 并上传：

   ```powershell
   git archive --format=zip --output=cangmo-v1.1.0-source.zip HEAD
   git bundle create cangmo-v1.1.0.bundle --all
   ```

## 仓库设置建议

- General → Features：Issues ✅、Discussions ✅、Projects ❌、Wiki ❌
- Security → Private vulnerability reporting ✅
- Security → Dependabot alerts：无运行时依赖，可选
- Branches → `main` 保护：Require PR、Require approvals 1、Dismiss stale approvals、
  Require conversation resolution、Do not allow force pushes
- Actions → General：允许 GitHub Actions；Workflow permissions 选择
  “Read repository contents and packages permissions”（Release job 单独声明 `contents: write`）

## 版权与许可证

- 版权：`宸熙星语 (chenxixingyu)`
- 许可证：Cangmo Source-Available License 1.0
- GitHub 会将自定义许可证显示为 “View license”，不是 OSI 认证许可证；
  如需 OSI 许可证，可在获得版权人同意后切换为 Apache-2.0 或 MPL-2.0。

## 可选增强

- 添加 `CITATION.cff`
- 添加 `FUNDING.yml`
- 发布 Docker 镜像（当前路线图）
- 增加 Linux 构建矩阵（需先完成加密适配层）
