# 仓墨 REST API v1

基础地址：`http://<host>:<port>/api/v1`  
默认返回 `application/json; charset=utf-8`。所有时间戳为 Unix 秒（UTC）。

## 认证

两种方式：

1. **API 令牌（推荐）**

```http
Authorization: Bearer cmo_xxxxxxxxxxxxxxxxxxxxxxxx
```

在后台「个人资料 → API 令牌」创建，令牌只显示一次，数据库仅存 SHA-256 哈希。

2. **后台会话 Cookie**

先登录 `/admin/login`，后续请求携带 `cangmo_sid`，并在写请求中附带 `X-CSRF-Token`（取自页面隐藏字段 `_csrf`）。

公开读取接口（`GET /site`、`GET /posts`、`GET /posts/:slug`、`GET /comments`）无需认证。

## 通用响应

### 分页

```json
{
  "data": [ ... ],
  "meta": { "page": 1, "per_page": 10, "total": 42, "pages": 5 }
}
```

### 错误

```json
{
  "error": {
    "code": "validation",
    "message": "标题长度需在 1-200 字之间"
  }
}
```

| HTTP | code | 含义 |
| --- | --- | --- |
| 400 | validation | 参数/请求体校验失败 |
| 401 | unauthorized | 缺少或无效令牌 |
| 403 | forbidden | 权限不足 / CSRF |
| 404 | not_found | 资源不存在 |
| 409 | conflict | 唯一性冲突 |
| 413 | payload | 请求体过大 |
| 429 | rate_limited | 限流 |
| 500 | internal | 服务器内部错误 |

默认 API 限流：每 IP 每分钟 120 次（`security.apiRateLimitPerMinute`）。

## 站点

### `GET /site`

```json
{
  "name": "仓墨",
  "description": "……",
  "url": "https://example.com",
  "version": "1.0.3",
  "locale": "zh-CN"
}
```

## 文章

### `GET /posts`

查询参数：

| 参数 | 说明 |
| --- | --- |
| `type` | `post`（默认）或 `page` |
| `status` | 公开只返回 `published`；工作人员可用 `any/draft/published/scheduled/trash` |
| `category_id` | 分类 ID |
| `page` | 页码，默认 1 |
| `per_page` | 每页数量，1–50，默认 10 |

返回卡片字段：`id/title/slug/url/summary/cover/status/type/pinned/featured/views/reading_minutes/published_at/date/date_iso/date_rfc/author/category/tags/content_md`。

### `GET /posts/{slug}`

公开仅返回已发布文章；工作人员可读取任意状态。额外包含 `content_html`。

### `POST /posts`（需认证）

```json
{
  "title": "标题",
  "slug": "optional-slug",
  "summary": "摘要",
  "content": "# Markdown 正文",
  "type": "post",
  "status": "draft",
  "category_id": "cat_xxx",
  "tags": ["仓颉", "教程"],
  "cover": "/media/2026/01/cover.png",
  "allow_comments": true,
  "pinned": false,
  "featured": false,
  "seo_title": "",
  "seo_description": "",
  "scheduled_at": 0
}
```

成功返回 `201` + 文章对象。`status` 可为 `draft/published/scheduled`；`scheduled` 需 `scheduled_at` 为未来时间。

### `PUT /posts/{id}`（需认证）

字段同上，未传字段按空值处理（建议完整提交）。作者/投稿者只能改自己的内容；投稿者只能改草稿。

### `DELETE /posts/{id}`（需管理员或编辑）

永久删除，同时删除关联评论与版本历史。

## 评论

### `GET /comments?post_id=...`

返回该文章已通过审核的评论：

```json
{
  "data": [
    {
      "id": "comment_xxx",
      "author_name": "访客",
      "content": "……",
      "created_at": 1794860000,
      "date": "2026-11-17 04:00",
      "relative": "3 分钟前",
      "depth": 0,
      "post_id": "post_xxx",
      "parent_id": ""
    }
  ]
}
```

### `POST /comments`

公开评论接口。使用 Cookie 会话时必须带 `X-CSRF-Token`；或使用 Bearer 令牌。受评论限流与审核策略约束。

```json
{
  "post_id": "post_xxx",
  "parent_id": "",
  "name": "访客",
  "email": "visitor@example.com",
  "url": "",
  "content": "你好"
}
```

返回 `201` + 评论对象，`status` 可能是 `pending` 或 `approved`。

## 附件

> 后台界面已更名为「附件库」。API 同时保留 `/media` 与 `/attachments` 两个路径。

### `GET /attachments?page=1&per_page=20`（需认证）

返回附件对象数组与 `total`。`GET /media` 为兼容别名。

### `POST /attachments`（需认证，multipart/form-data）

字段名任意，文件字段示例：

```bash
curl -X POST https://example.com/api/v1/attachments \
  -H "Authorization: Bearer $TOKEN" \
  -F "file=@cover.png"
```

返回 `201` + 附件对象（含 `url`、`width`、`height`、`sha256`）。`POST /media` 为兼容别名。

## 分类与标签

### `GET /categories`

```json
{ "data": [ { "id": "cat_xxx", "name": "未分类", "slug": "uncategorized" } ] }
```

### `GET /tags`

```json
{ "data": [ { "id": "tag_xxx", "name": "仓颉", "slug": "cangjie", "post_count": 3 } ] }
```

## 统计

### `GET /stats`（需工作人员认证）

```json
{
  "posts": 12,
  "pages": 2,
  "drafts": 3,
  "scheduled": 0,
  "comments": 8,
  "comments_approved": 6,
  "comments_pending": 2,
  "users": 2,
  "media": 15,
  "views": 1234
}
```

## 示例

```bash
# 读取站点
curl https://example.com/api/v1/site

# 创建文章
curl -X POST https://example.com/api/v1/posts \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"title":"Hello","content":"# Hi\n\n正文","status":"published","tags":["公告"]}'

# 列出文章
curl "https://example.com/api/v1/posts?page=1&per_page=5"
```

## 版本与兼容性

- 路径版本：`/api/v1`。
- 新增字段视为兼容变更；删除/改名字段会升版本。
- 时间统一 Unix 秒；本地化展示由前端处理。
