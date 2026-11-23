/**
 * Cangmo - JSON API v1.
 */
package cangmo.web

import cangmo.core.*
import cangmo.http.*
import cangmo.json.*
import cangmo.service.*
import std.collection.*

public class ApiSite {
    private let services: Services

    public init(services: Services) {
        this.services = services
    }

    public func openapi(ctx: Ctx): HttpResponse {
        let spec = JsonObject()
        spec.set("openapi", JStr("3.0.3"))
        let info = JsonObject()
        info.set("title", JStr("仓墨 API"))
        info.set("version", JStr(APP_VERSION))
        info.set("description", JStr("仓墨博客 REST API；写操作使用 Bearer Token，可配置 scopes。"))
        spec.set("info", JObj(info))
        let servers = JsonArray()
        let server = JsonObject()
        server.set("url", JStr("/api/v1"))
        servers.add(JObj(server))
        spec.set("servers", JArr(servers))
        let schemes = JsonObject()
        let bearer = JsonObject()
        bearer.set("type", JStr("http"))
        bearer.set("scheme", JStr("bearer"))
        schemes.set("bearerAuth", JObj(bearer))
        spec.set("components", jsonObjectOf([("securitySchemes", JObj(schemes))]))
        let paths = JsonObject()
        paths.set("/site", jsonObjectOf([("get", operation("站点信息", "site.read"))]))
        paths.set("/posts", jsonObjectOf([
            ("get", operation("文章列表", "posts.read")),
            ("post", operation("创建文章", "posts.write"))
        ]))
        paths.set("/posts/{slug}", jsonObjectOf([("get", operation("文章详情", "posts.read"))]))
        paths.set("/comments", jsonObjectOf([
            ("get", operation("评论列表", "comments.read")),
            ("post", operation("发表评论", "comments.write"))
        ]))
        paths.set("/attachments", jsonObjectOf([
            ("get", operation("附件列表", "media.read")),
            ("post", operation("上传附件", "media.write"))
        ]))
        paths.set("/categories", jsonObjectOf([("get", operation("分类列表", "posts.read"))]))
        paths.set("/tags", jsonObjectOf([("get", operation("标签列表", "posts.read"))]))
        paths.set("/stats", jsonObjectOf([("get", operation("站点统计", "admin"))]))
        spec.set("paths", JObj(paths))
        HttpResponse().json(JObj(spec))
    }

    private func operation(summary: String, scope: String): JsonValue {
        let item = JsonObject()
        item.set("summary", JStr(summary))
        let responses = JsonObject()
        let ok = JsonObject()
        ok.set("description", JStr("成功"))
        responses.set("200", JObj(ok))
        item.set("responses", JObj(responses))
        if (scope != "site.read") {
            let security = JsonArray()
            let requirement = JsonObject()
            requirement.set("bearerAuth", JArr(JsonArray()))
            security.add(JObj(requirement))
            item.set("security", JArr(security))
            item.set("x-cangmo-scope", JStr(scope))
        }
        JObj(item)
    }

    public func site(ctx: Ctx): HttpResponse {
        let data = jsonObjectOf([
            ("name", jstr(services.settings.str("site_title"))),
            ("description", jstr(services.settings.str("site_description"))),
            ("url", jstr(services.settings.str("site_url", def: services.config.siteUrl))),
            ("version", jstr(APP_VERSION)),
            ("locale", jstr(services.config.locale))
        ])
        HttpResponse().json(data)
    }

    public func posts(ctx: Ctx): HttpResponse {
        requireScope(ctx, "posts.read")
        let user = authenticatedUser(ctx)
        let staffView = match (user) {
            case Some(value) => isStaff(value)
            case None => false
        }
        let page = maxInt(1, ctx.req.queryInt("page", def: 1))
        let perPage = clamp(pageSize(ctx.req.queryInt("per_page", def: 10)), 1, 50)
        let query = PostQuery()
        query.postType = if (ctx.query("type") == "page") { "page" } else { "post" }
        let requestedStatus = ctx.query("status")
        if (staffView) {
            query.status = if (requestedStatus.size > 0) { requestedStatus } else { "any" }
            query.includeTrash = query.status == "any" || query.status == STATUS_TRASH
        } else {
            query.status = STATUS_PUBLISHED
        }
        query.categoryId = ctx.query("category_id")
        let result = services.posts.list(query, page, perPage)
        let items = JsonArray()
        for (post in result.items) {
            items.add(publicPostJson(post, includeContent: false))
        }
        let meta = jsonObjectOf([
            ("page", jint(result.page)),
            ("per_page", jint(perPage)),
            ("total", jint(result.total)),
            ("pages", jint(result.pages))
        ])
        HttpResponse().json(jsonObjectOf([("data", JArr(items)), ("meta", meta)]))
    }

    public func postBySlug(ctx: Ctx): HttpResponse {
        requireScope(ctx, "posts.read")
        let user = authenticatedUser(ctx)
        let staffView = match (user) {
            case Some(value) => isStaff(value)
            case None => false
        }
        let slug = ctx.param("slug")
        if (staffView) {
            for (post in services.store.list(COL_POSTS)) {
                if (docStr(post, "slug") == slug) {
                    return HttpResponse().json(publicPostJson(post, includeContent: true))
                }
            }
            throw AppError("not_found", "内容不存在")
        }
        let post = match (services.posts.getPublishedBySlug(slug)) {
            case Some(value) => value
            case None => throw AppError("not_found", "内容不存在")
        }
        HttpResponse().json(publicPostJson(post, includeContent: true))
    }

    public func createPost(ctx: Ctx): HttpResponse {
        requireScope(ctx, "posts.write")
        let user = requireUser(ctx)
        let body = jsonBody(ctx)
        let input = postInputFrom(body, ctx.siteId)
        let id = services.posts.save(input, user, "", ctx.clientIp())
        let post = services.posts.get(id)
        let data = match (post) {
            case Some(value) => publicPostJson(value, includeContent: true)
            case None => jobj()
        }
        HttpResponse().json(data, status: 201)
    }

    public func updatePost(ctx: Ctx): HttpResponse {
        requireScope(ctx, "posts.write")
        let user = requireUser(ctx)
        let id = ctx.param("id")
        let existing = match (services.posts.get(id)) {
            case Some(value) => value
            case None => throw AppError("not_found", "内容不存在")
        }
        if (!services.posts.canEdit(user, existing)) {
            throw AppError("forbidden", "无权编辑此内容")
        }
        let body = jsonBody(ctx)
        let input = postInputFrom(body, ctx.siteId)
        services.posts.save(input, user, id, ctx.clientIp())
        let updated = match (services.posts.get(id)) {
            case Some(value) => value
            case None => throw AppError("not_found", "内容不存在")
        }
        HttpResponse().json(publicPostJson(updated, includeContent: true))
    }

    public func deletePost(ctx: Ctx): HttpResponse {
        requireScope(ctx, "posts.write")
        let user = requireUser(ctx)
        if (!isAdminOrEditor(user)) {
            throw AppError("forbidden", "只有管理员或编辑可以删除")
        }
        services.posts.deletePermanently(ctx.param("id"), user, ctx.clientIp())
        HttpResponse().json(jsonObjectOf([("deleted", jbool(true))]))
    }

    public func comments(ctx: Ctx): HttpResponse {
        requireScope(ctx, "comments.read")
        let postId = ctx.query("post_id")
        if (postId.size == 0) {
            throw AppError("validation", "缺少 post_id")
        }
        let items = JsonArray()
        for (comment in services.comments.listForPost(postId)) {
            items.add(commentJson(comment, 0))
        }
        HttpResponse().json(jsonObjectOf([("data", JArr(items))]))
    }

    public func createComment(ctx: Ctx): HttpResponse {
        requireScope(ctx, "comments.write")
        let body = jsonBody(ctx)
        let postId = getString(body, "post_id")
        let post = match (services.store.get(COL_POSTS, postId)) {
            case Some(value) => value
            case None => throw AppError("not_found", "文章不存在")
        }
        let id = services.comments.create(post, getString(body, "parent_id"), getString(body, "name"),
                                          getString(body, "email"), getString(body, "url"),
                                          getString(body, "content"), ctx.clientIp(),
                                          ctx.req.header("user-agent"))
        let comment = match (services.comments.get(id)) {
            case Some(value) => value
            case None => throw AppError("internal", "评论创建失败")
        }
        HttpResponse().json(commentJson(comment, 0), status: 201)
    }

    public func media(ctx: Ctx): HttpResponse {
        requireScope(ctx, "media.read")
        let user = requireUser(ctx)
        let result = services.media.list(maxInt(1, ctx.req.queryInt("page", def: 1)),
                                         clamp(pageSize(ctx.req.queryInt("per_page", def: 20)), 1, 50))
        let items = JsonArray()
        for (item in result.items) {
            items.add(item)
        }
        HttpResponse().json(jsonObjectOf([("data", JArr(items)), ("total", jint(result.total))]))
    }

    public func uploadMedia(ctx: Ctx): HttpResponse {
        requireScope(ctx, "media.write")
        let user = requireUser(ctx)
        if (!services.auth.can(user, "media.manage")) {
            throw AppError("forbidden", "无权上传附件")
        }
        ctx.req.parseForm()
        if (ctx.req.files.size == 0) {
            throw AppError("validation", "没有文件")
        }
        let doc = services.media.upload(ctx.req.files[0], docStr(user, "id"), ctx.clientIp())
        HttpResponse().json(doc, status: 201)
    }

    public func categories(ctx: Ctx): HttpResponse {
        requireScope(ctx, "posts.read")
        let items = JsonArray()
        for (category in services.taxonomy.listCategories(siteId: ctx.siteId)) {
            items.add(category)
        }
        HttpResponse().json(jsonObjectOf([("data", JArr(items))]))
    }

    public func tags(ctx: Ctx): HttpResponse {
        requireScope(ctx, "posts.read")
        let items = JsonArray()
        for (tag in services.taxonomy.listTags(siteId: ctx.siteId)) {
            items.add(tag)
        }
        HttpResponse().json(jsonObjectOf([("data", JArr(items))]))
    }

    public func stats(ctx: Ctx): HttpResponse {
        let user = requireUser(ctx)
        if (!isStaff(user)) {
            throw AppError("forbidden", "需要工作人员权限")
        }
        HttpResponse().json(services.stats.counts())
    }

    // -----------------------------------------------------------------------
    // Helpers
    // -----------------------------------------------------------------------

    private func publicPostJson(post: JsonValue, includeContent!: Bool = false): JsonValue {
        let card = postCard(services, post)
        setField(card, "content_md", JStr(docStr(post, "content")))
        if (includeContent) {
            setField(card, "content_html", JStr(docStr(post, "content_html")))
        }
        setField(card, "allow_comments", JBool(docBool(post, "allow_comments", def: true)))
        return card
    }

    private func commentJson(comment: JsonValue, depth: Int64): JsonValue {
        let view = commentView(comment, None, depth)
        setField(view, "post_id", JStr(docStr(comment, "post_id")))
        setField(view, "parent_id", JStr(docStr(comment, "parent_id")))
        view
    }

    private func postInputFrom(body: JsonValue, siteId: String): PostInput {
        let input = PostInput()
        input.title = getString(body, "title")
        input.slug = getString(body, "slug")
        input.summary = getString(body, "summary")
        input.content = getString(body, "content")
        input.postType = if (getString(body, "type") == "page") { "page" } else { "post" }
        input.status = getString(body, "status", def: STATUS_DRAFT)
        input.siteId = siteId
        input.access = getString(body, "access", def: "public")
        input.categoryId = getString(body, "category_id")
        input.tagNames = getStrings(body, "tags")
        input.cover = getString(body, "cover")
        input.allowComments = getBool(body, "allow_comments", def: true)
        input.pinned = getBool(body, "pinned")
        input.featured = getBool(body, "featured")
        input.seoTitle = getString(body, "seo_title")
        input.seoDescription = getString(body, "seo_description")
        input.scheduledAt = getInt(body, "scheduled_at")
        input
    }

    private func jsonBody(ctx: Ctx): JsonValue {
        let text = try {
            String.fromUtf8(ctx.req.body)
        } catch (e: Exception) {
            throw AppError("validation", "请求体编码无效")
        }
        match (tryParseJson(text)) {
            case Some(value) =>
                match (value) {
                    case JObj(_) => value
                    case _ => throw AppError("validation", "请求体必须是 JSON 对象")
                }
            case None => throw AppError("validation", "请求体不是有效 JSON")
        }
    }

    private func requireScope(ctx: Ctx, scope: String): Unit {
        let token = bearerToken(ctx)
        if (token.size == 0) {
            return
        }
        let doc = match (services.auth.validateApiToken(token, ctx.clientIp())) {
            case Some(value) => value
            case None => throw AppError("unauthorized", "令牌无效或已过期")
        }
        let scopes = docStrings(doc, "scopes")
        if (scopes.size == 0) {
            return
        }
        if (!scopes.contains(scope) && !scopes.contains("admin")) {
            throw AppError("forbidden", "令牌缺少 ${scope} 权限")
        }
    }

    private func requireUser(ctx: Ctx): JsonValue {
        match (authenticatedUser(ctx)) {
            case Some(user) => user
            case None => throw AppError("unauthorized", "需要认证")
        }
    }

    private func authenticatedUser(ctx: Ctx): ?JsonValue {
        let token = bearerToken(ctx)
        if (token.size > 0) {
            return services.auth.userByApiToken(token, ip: ctx.clientIp())
        }
        match (ctx.user) {
            case Some(user) =>
                if (isStaff(user)) {
                    return Some(user)
                }
                None
            case None => None
        }
    }

    private func isStaff(user: JsonValue): Bool {
        let role = docStr(user, "role")
        role == ROLE_ADMIN || role == ROLE_EDITOR || role == ROLE_AUTHOR || role == ROLE_CONTRIBUTOR
    }

    private func isAdminOrEditor(user: JsonValue): Bool {
        let role = docStr(user, "role")
        role == ROLE_ADMIN || role == ROLE_EDITOR
    }

    private func pageSize(value: Int64): Int64 {
        if (value <= 0) { 10 } else { value }
    }

    private func clamp(value: Int64, minValue: Int64, maxValue: Int64): Int64 {
        if (value < minValue) { minValue } else if (value > maxValue) { maxValue } else { value }
    }

    private func maxInt(a: Int64, b: Int64): Int64 {
        if (a > b) { a } else { b }
    }
}

public func bearerToken(ctx: Ctx): String {
    let header = ctx.req.header("authorization")
    if (header.size < 8) {
        return ""
    }
    let lower = header.toAsciiLower()
    if (!lower.startsWith("bearer ")) {
        return ""
    }
    header[7..header.size].trimAscii()
}
