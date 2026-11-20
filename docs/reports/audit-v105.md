# 仓墨 v1.0.5 排查、修复与验收报告

- 日期：2026-11-21
- 范围：`src/service/posts.cj`、`src/core/util.cj`、`src/http/types.cj`、`src/service/content.cj`、`src/web/admin.cj`、`src/web/public.cj`、后台模板/CSS
- 结论：**通过**。2 个确认缺陷已修复，1 个兼容性问题在实现中修复；168 项测试与 12 项浏览器审计全绿。

## 1. 问题根因

### P0 定时发布越权（安全）

复现：以 `contributor` 角色登录，提交 `status=scheduled`、`scheduled_at=2020-01-01 00:00`。

结果：请求 303 成功，文章立即以已发布状态可访问（`/posts/...` 返回 200）。

根因：

```cangjie
// src/service/posts.cj
if (input.status == STATUS_PUBLISHED && !canPublish(actor)) { ... }
...
if (status == STATUS_SCHEDULED) {
    if (scheduledAt <= nowSeconds()) {
        status = STATUS_PUBLISHED   // 未再次校验发布权限
        scheduledAt = 0
    }
}
```

`canPublish` 只允许 admin / editor / author，但校验只覆盖 `published`。`contributor` 可创建内容，且 `scheduled` 在允许状态内，因此“过去时间的定时发布”等价于直接发布。

影响范围：所有具备 `post.create` 但无 `post.publish` 的角色（当前为 contributor）；同样影响 API 创建路径，因为共用 `PostService.save`。

### P1 中文文件名丢失

复现：上传 `测试 截图.png`，附件库显示 `.png`。

根因：`sanitizeFilename` 对 `b >= 0x80` 的每个字节写入 `-`，UTF-8 中文被整体抹除；随后前导 `-` 被裁剪，只剩扩展名。

影响范围：附件库显示名、封面/头像选择器、附件搜索与 `original_name` 元数据；磁盘文件名不受影响（始终为 `media_<id>.<ext>`）。

### P2 新增设置项向后兼容

复现：新开关加入后，旧版设置表单（e2e/脚本）提交时不含该字段，`isChecked` 将开关写成 false。

根因：复选框“未勾选”和“字段不存在”在表单编码中不可区分。

## 2. 修复方案

### 2.1 发布权限前置校验

在 `save` 中把 `scheduled` 与 `published` 一并纳入 `canPublish` 校验。定时发布是延迟发布，必须与直接发布同权限。

- 兼容性：author 及以上不受影响；contributor 只能保存草稿，符合角色定义。
- 风险：已存在的 contributor 定时任务若存在，将不再被新提交；历史数据由调度器继续处理（见同类隐患）。

### 2.2 显示名与磁盘名分离

新增 `sanitizeDisplayName`：

- 保留合法 UTF-8 多字节序列（中文、日文、emoji 等）；
- 去除控制字符与路径分隔符（先 `baseName`）；
- 不安全 ASCII 标点替换为 `-`，空格保留；
- 按字节预算 180 截断，且只在 UTF-8 字符边界截断；
- 解码失败回退 `file`。

`sanitizeFilename` 保持原样，继续用于备份文件名与 `Content-Disposition`，避免 HTTP 头出现原始 UTF-8。

### 2.3 设置项存在性标记

模板增加隐藏字段 `show_related_posts_present=1`；`settingsSave` 仅在该标记存在时写入开关。旧表单/脚本省略字段时保留原值（默认开启）。

## 3. 修复代码

### 3.1 权限

```cangjie
if ((input.status == STATUS_PUBLISHED || input.status == STATUS_SCHEDULED) && !canPublish(actor)) {
    throw AppError("forbidden", "你的角色不能发布或定时发布内容，请先保存为草稿")
}
```

### 3.2 文件名

```cangjie
// src/http/types.cj
let safeName = sanitizeDisplayName(filenameRaw)

// src/service/content.cj
let original = sanitizeDisplayName(file.filename)
```

`sanitizeDisplayName` 核心逻辑：

```cangjie
while (i < src.size && budget > 0) {
    let b = src[i]
    if (b < 0x80) {
        if (b < 0x20 || b == 0x7F) { i += 1; continue }
        let safe = /* 字母/数字/._-/空格 */
        out.add(if (safe) { b } else { 0x2D })
        budget -= 1
        i += 1
        continue
    }
    let width = if (b >= 0xF0) { 4 } else if (b >= 0xE0) { 3 } else if (b >= 0xC0) { 2 } else { 1 }
    if (i + width > src.size || budget < width) { break }
    for (j in 0..width) { out.add(src[i + j]) }
    budget -= width
    i += width
}
```

### 3.3 设置项

```html
<input type="hidden" name="show_related_posts_present" value="1">
```

```cangjie
if (ctx.form("show_related_posts_present") == "1") {
    services.settings.setBool("show_related_posts", isChecked(ctx, "show_related_posts"))
}
```

### 3.4 新增功能：复制为草稿

```cangjie
public func duplicate(id: String, actor: JsonValue, ip: String): String {
    let post = match (get(id)) {
        case Some(value) => value
        case None => throw AppError("not_found", "内容不存在")
    }
    if (!canEdit(actor, post)) { throw AppError("forbidden", "无权复制此内容") }
    let postType = docStr(post, "type", def: "post")
    if (!canCreate(actor, postType)) { throw AppError("forbidden", "无权创建内容") }
    // 标题追加「（副本）」、slug 留空、状态草稿、定时清空；
    // 分类/标签被删除时自动降级；复用 save() 完成校验与审计。
}
```

路由 `POST /admin/posts/:id/duplicate`，文章行菜单入口，成功后跳转副本编辑页。

### 3.5 布局

- 编辑器 SEO、历史版本改为 `<details class="side-panel side-fold">`，默认收起。
- 字段仍在同一 `<form>` 内，隐藏时照常提交，无功能变化。

## 4. 回归验证点

| 编号 | 断言 | 覆盖 |
| --- | --- | --- |
| R1 | contributor 创建成功、登录成功 | security |
| R2 | contributor 提交过去时间定时 → 200 + “不能发布或定时发布” | security |
| R3 | 越权文章前台 404 | security |
| R4 | 中文文件名 `测试 截图.png` 原样保留 | v101 |
| R5 | 磁盘文件名仍匹配 `media_<ascii>.png` | v101 |
| R6 | 复制成功 303，副本标题含「（副本）」且状态为草稿 | extended |
| R7 | 旧设置表单提交后相关文章开关仍为开启 | UI 审计 |
| R8 | 相关文章开/关/恢复三态 | UI 审计 |
| R9 | SEO 折叠默认关闭、可展开、字段仍在表单 | UI 审计 |

完整输出：

- [security-v101.txt](security-v101.txt)（31/31）
- [v101-final.txt](v101-final.txt)（34/34）
- [extended-v101.txt](extended-v101.txt)（22/22）
- [ui-v105.txt](ui-v105.txt)（12/12）

## 5. 同类隐患与加固建议

| 等级 | 隐患 | 建议 |
| --- | --- | --- |
| P2 | 调度器 `publishDue` 直接改状态，不校验作者当前角色；作者被降级/停用后，已排期内容仍会发布 | 发布前读取作者，校验 `status=active` 且角色仍可发布；失败则转草稿并记审计 |
| P2 | 备份文件名仍走 ASCII `sanitizeFilename`，中文备注会退化为 `-` | 如需中文备份名，使用 RFC 5987 `filename*=UTF-8''...`，不要直接写原始 UTF-8 头 |
| P3 | `show_toc` / `show_reading_time` 同样存在“旧表单即关闭”的语义 | 后续统一采用 `*_present` 标记或三态表单 |
| P3 | 定时时间输入为分钟精度，秒级测试需直接提交带秒字符串 | 编辑器可加 `step=1`，或在 UI 明示分钟粒度 |

## 6. 五维验收

| 维度 | 结论 | 依据 |
| --- | --- | --- |
| 功能正确性 | 通过 | 168 项测试；复制、权限、文件名、开关均有断言 |
| UI 一致性 | 通过 | 12 项浏览器审计；沿用现有配色、圆角、按钮与折叠样式 |
| 性能稳定性 | 通过 | 并发/协议 6 项；`related` 仅在开启时计算，复制为单次写入 |
| 接口兼容性 | 通过 | 原有路由/字段不变；新增 `duplicate`；设置字段缺省保留默认值 |
| 安全性 | 通过 | 权限绕过修复；文件名保留 UTF-8 但去除控制字符/路径；CSRF 与审计沿用现有链路 |

## 7. 分级问题清单

| 等级 | 问题 | 状态 |
| --- | --- | --- |
| P0 | contributor 定时发布越权 | 已修复 |
| P1 | 中文文件名被抹除 | 已修复 |
| P2 | 新设置项被旧表单误关闭 | 已修复 |
| P2 | 调度器不校验作者当前角色 | 待后续加固 |
| P3 | 备份名/旧开关的兼容语义 | 待后续统一 |
