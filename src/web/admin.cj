/**
 * Cangmo - admin handlers.
 */
package cangmo.web

import cangmo.core.*
import cangmo.http.*
import cangmo.json.*
import cangmo.markdown.*
import cangmo.service.*
import cangmo.store.*
import std.collection.*
import std.fs.*
import std.time.*

public class AdminSite {
    private let services: Services

    public init(services: Services) {
        this.services = services
    }

    // -----------------------------------------------------------------------
    // Auth
    // -----------------------------------------------------------------------

    public func loginPage(ctx: Ctx): HttpResponse {
        if (ctx.loggedIn()) {
            if (ctx.session.pending2fa) {
                return ctx.redirect("/admin/2fa")
            }
            if (ctx.isStaff()) {
                return ctx.redirect("/admin")
            }
        }
        let data = JsonObject()
        data.set("page_title", JStr("登录"))
        data.set("error", JStr(""))
        data.set("next", JStr(safeNext(ctx.query("next"))))
        ctx.renderAdminPage("login.html", JObj(data))
    }

    public func loginSubmit(ctx: Ctx): HttpResponse {
        let username = ctx.form("username")
        let password = ctx.form("password")
        let next = safeNext(ctx.form("next"))
        let result = services.auth.login(username, password, ctx.clientIp(), ctx.req.header("user-agent"))
        if (!result.ok) {
            let data = JsonObject()
            data.set("page_title", JStr("登录"))
            data.set("error", JStr(result.message))
            data.set("next", JStr(next))
            data.set("username", JStr(username))
            let response = ctx.renderAdminPage("login.html", JObj(data), status: 401)
            return response
        }
        let oldSession = ctx.session
        services.auth.destroySession(oldSession)
        match (result.session) {
            case Some(session) =>
                ctx.session = session
                ctx.sessionChanged = true
                ctx.sessionDestroyed = false
            case None => ()
        }
        if (ctx.session.pending2fa) {
            return ctx.redirect("/admin/2fa", status: 303)
        }
        ctx.redirect(if (next.size > 0) { next } else { "/admin" }, status: 303)
    }

    public func forgotPage(ctx: Ctx): HttpResponse {
        let data = JsonObject()
        data.set("page_title", JStr("找回密码"))
        data.set("error", JStr(""))
        ctx.renderAdminPage("forgot.html", JObj(data))
    }

    public func forgotSubmit(ctx: Ctx): HttpResponse {
        let email = ctx.form("email").trimAscii()
        let token = services.auth.requestPasswordReset(email, ctx.siteUrl("/"))
        if (token.size > 0) {
            let link = ctx.siteUrl("/admin/reset?token=" + urlEncode(token))
            services.mail.notifyPasswordReset(email, link)
        }
        let data = JsonObject()
        data.set("page_title", JStr("找回密码"))
        data.set("error", JStr(""))
        data.set("sent", JBool(true))
        ctx.renderAdminPage("forgot.html", JObj(data))
    }

    public func resetPage(ctx: Ctx): HttpResponse {
        let data = JsonObject()
        data.set("page_title", JStr("重置密码"))
        data.set("token", JStr(ctx.query("token")))
        data.set("error", JStr(""))
        ctx.renderAdminPage("reset.html", JObj(data))
    }

    public func resetSubmit(ctx: Ctx): HttpResponse {
        let token = ctx.form("token")
        let password = ctx.form("password")
        if (password != ctx.form("confirm")) {
            let data = JsonObject()
            data.set("page_title", JStr("重置密码"))
            data.set("token", JStr(token))
            data.set("error", JStr("两次输入的密码不一致"))
            return ctx.renderAdminPage("reset.html", JObj(data), status: 400)
        }
        try {
            services.auth.resetPasswordByToken(token, password)
            ctx.setFlash("success", "密码已重置，请使用新密码登录")
            return ctx.redirect("/admin/login", status: 303)
        } catch (e: AppError) {
            let data = JsonObject()
            data.set("page_title", JStr("重置密码"))
            data.set("token", JStr(token))
            data.set("error", JStr(e.message))
            return ctx.renderAdminPage("reset.html", JObj(data), status: 400)
        }
    }

    public func mailPage(ctx: Ctx): HttpResponse {
        match (requireAdmin(ctx)) {
            case Some(response) => return response
            case None => ()
        }
        let rows = JsonArray()
        for (item in services.mail.list()) {
            let view = cloneDoc(item)
            setField(view, "date", JStr(formatDateTime(docInt(item, "created_at"))))
            setField(view, "size_text", JStr(formatFileSize(docInt(item, "size"))))
            rows.add(view)
        }
        let data = JsonObject()
        data.set("page_title", JStr("发件箱"))
        data.set("active", JStr("tools"))
        data.set("rows", JArr(rows))
        data.set("outbox", JStr(services.mail.outboxDir()))
        ctx.renderAdminPage("mail.html", JObj(data))
    }

    public func mailView(ctx: Ctx): HttpResponse {
        match (requireAdmin(ctx)) {
            case Some(response) => return response
            case None => ()
        }
        let text = match (services.mail.read(ctx.query("name"))) {
            case Some(value) => value
            case None => return errorPage(ctx, 404, "邮件不存在")
        }
        let data = JsonObject()
        data.set("page_title", JStr("邮件内容"))
        data.set("active", JStr("tools"))
        data.set("text", JStr(text))
        ctx.renderAdminPage("mail-view.html", JObj(data))
    }

    public func twoFactorPage(ctx: Ctx): HttpResponse {
        if (!ctx.loggedIn()) {
            return ctx.redirect("/admin/login", status: 303)
        }
        if (!ctx.session.pending2fa) {
            return ctx.redirect("/admin", status: 303)
        }
        let data = JsonObject()
        data.set("page_title", JStr("两步验证"))
        data.set("error", JStr(""))
        ctx.renderAdminPage("twofa.html", JObj(data))
    }

    public func twoFactorSubmit(ctx: Ctx): HttpResponse {
        if (!ctx.loggedIn() || !ctx.session.pending2fa) {
            return ctx.redirect("/admin/login", status: 303)
        }
        let code = ctx.form("code").trimAscii()
        if (!services.auth.verifyUserTotp(docStr(ctx.userDoc(), "id"), code)) {
            let data = JsonObject()
            data.set("page_title", JStr("两步验证"))
            data.set("error", JStr("验证码不正确，请重试"))
            return ctx.renderAdminPage("twofa.html", JObj(data), status: 401)
        }
        ctx.session.pending2fa = false
        services.auth.persist(ctx.session)
        ctx.sessionChanged = true
        services.audit.log(docStr(ctx.userDoc(), "id"), docStr(ctx.userDoc(), "username"), "login_2fa", "user",
                           docStr(ctx.userDoc(), "id"), ctx.clientIp(), "TOTP verified")
        ctx.redirect("/admin", status: 303)
    }

    public func logout(ctx: Ctx): HttpResponse {
        services.auth.destroySession(ctx.session)
        ctx.sessionDestroyed = true
        ctx.redirect("/admin/login", status: 303)
    }

    public func dashboard(ctx: Ctx): HttpResponse {
        match (guard(ctx)) {
            case Some(response) => return response
            case None => ()
        }
        let data = JsonObject()
        data.set("page_title", JStr("仪表盘"))
        data.set("active", JStr("dashboard"))
        data.set("counts", services.stats.counts())
        let posts = services.posts.list(allPostsQuery(ctx), 1, 6)
        let rows = JsonArray()
        for (post in posts.items) {
            rows.add(adminPostRow(services, post))
        }
        data.set("recent_posts", JArr(rows))
        let comments = services.comments.recent(6)
        let commentRows = JsonArray()
        for (comment in comments) {
            let post = services.posts.get(docStr(comment, "post_id"))
            commentRows.add(commentView(comment, post, 0))
        }
        data.set("recent_comments", JArr(commentRows))
        let auditItems = JsonArray()
        for (entry in services.audit.list(1, 6).items) {
            let view = cloneDoc(entry)
            setField(view, "created_at", JStr(formatDateTime(docInt(entry, "created_at"))))
            auditItems.add(view)
        }
        data.set("recent_audit", JArr(auditItems))
        data.set("store_size", JInt(services.store.collectionNames().size))
        ctx.renderAdminPage("dashboard.html", JObj(data))
    }

    // -----------------------------------------------------------------------
    // Posts / pages
    // -----------------------------------------------------------------------

    public func postsList(ctx: Ctx): HttpResponse {
        match (guard(ctx)) {
            case Some(response) => return response
            case None => ()
        }
        let postType = if (ctx.query("type") == "page") { "page" } else { "post" }
        let status = ctx.query("status", def: "all")
        let search = ctx.query("search")
        let page = ctx.pageNumber()
        let query = allPostsQuery(ctx)
        query.postType = postType
        if (status != "all") {
            query.status = status
            if (status == "trash") {
                query.includeTrash = true
            }
        } else {
            query.includeTrash = true
        }
        query.search = search
        let result = services.posts.list(query, page, 20)
        let rows = JsonArray()
        for (post in result.items) {
            rows.add(adminPostRow(services, post))
        }
        let counts = statusCounts(ctx, postType)
        let categories = JsonArray()
        let allTags = JsonArray()
        if (postType == "page") {
            for (category in services.taxonomy.listCategories()) {
                categories.add(category)
            }
            for (tag in services.taxonomy.listTags()) {
                allTags.add(tag)
            }
        }
        let data = JsonObject()
        data.set("page_title", JStr(if (postType == "page") { "页面" } else { "文章" }))
        data.set("active", JStr(if (postType == "page") { "pages" } else { "posts" }))
        data.set("post_type", JStr(postType))
        data.set("status", JStr(status))
        data.set("search", JStr(search))
        data.set("rows", JArr(rows))
        data.set("counts", counts)
        data.set("categories", JArr(categories))
        data.set("all_tags", JArr(allTags))
        data.set("page_templates", jsonStringList(pageTemplateNames()))
        data.set("pagination", buildPagination(result.page, result.pages, result.total,
                                               "/admin/posts?type=${postType}&status=${status}&search=" + urlEncode(search), 20))
        ctx.renderAdminPage("posts.html", JObj(data))
    }

    public func postNew(ctx: Ctx): HttpResponse {
        match (guard(ctx)) {
            case Some(response) => return response
            case None => ()
        }
        let postType = if (ctx.query("type") == "page") { "page" } else { "post" }
        if (postType == "page" && !ctx.can("page.manage")) {
            return errorPage(ctx, 403, "无权创建页面")
        }
        let post = JsonObject()
        post.set("id", JStr(""))
        post.set("type", JStr(postType))
        post.set("title", JStr(""))
        post.set("slug", JStr(""))
        post.set("summary", JStr(""))
        post.set("content", JStr(""))
        post.set("status", JStr(STATUS_DRAFT))
        post.set("category_id", JStr(""))
        post.set("tags", JStr(""))
        post.set("cover", JStr(""))
        post.set("allow_comments", JBool(true))
        post.set("pinned", JBool(false))
        post.set("featured", JBool(false))
        post.set("seo_title", JStr(""))
        post.set("seo_description", JStr(""))
        post.set("template", JStr(""))
        post.set("scheduled_at", JStr(""))
        post.set("published_at", JStr(""))
        editorResponse(ctx, JObj(post), true, "")
    }

    public func postEdit(ctx: Ctx): HttpResponse {
        match (guard(ctx)) {
            case Some(response) => return response
            case None => ()
        }
        let id = ctx.param("id")
        let post = match (services.posts.get(id)) {
            case Some(value) => value
            case None => return errorPage(ctx, 404, "内容不存在")
        }
        if (!services.posts.canEdit(ctx.userDoc(), post)) {
            return errorPage(ctx, 403, "无权编辑此内容")
        }
        editorResponse(ctx, adminEditorPost(post), false, "")
    }

    public func postSave(ctx: Ctx): HttpResponse {
        match (guard(ctx)) {
            case Some(response) => return response
            case None => ()
        }
        let id = ctx.form("id")
        let postType = if (ctx.form("type") == "page") { "page" } else { "post" }
        let input = PostInput()
        input.title = ctx.form("title")
        input.slug = ctx.form("slug")
        input.summary = ctx.form("summary")
        input.content = ctx.form("content")
        input.postType = postType
        input.status = normalizeStatus(ctx.form("status"))
        input.categoryId = ctx.form("category_id")
        input.tagNames = splitTags(ctx.form("tags"))
        input.cover = ctx.form("cover")
        input.allowComments = isChecked(ctx, "allow_comments")
        input.pinned = isChecked(ctx, "pinned")
        input.featured = isChecked(ctx, "featured")
        input.seoTitle = ctx.form("seo_title")
        input.seoDescription = ctx.form("seo_description")
        input.template = ctx.form("template")
        input.scheduledAt = parseDateTimeInput(ctx.form("scheduled_at"))
        try {
            let savedId = services.posts.save(input, ctx.userDoc(), id, ctx.clientIp())
            ctx.setFlash("success", if (id.size > 0) { "内容已更新" } else { "内容已创建" })
            if (postType == "page") {
                return ctx.redirect("/admin/posts?type=page", status: 303)
            }
            return ctx.redirect("/admin/posts/" + savedId + "/edit", status: 303)
        } catch (e: AppError) {
            let post = JsonObject()
            post.set("id", JStr(id))
            post.set("type", JStr(postType))
            post.set("title", JStr(input.title))
            post.set("slug", JStr(input.slug))
            post.set("summary", JStr(input.summary))
            post.set("content", JStr(input.content))
            post.set("status", JStr(input.status))
            post.set("category_id", JStr(input.categoryId))
            post.set("tags", JStr(String.join(input.tagNames, delimiter: ", ")))
            post.set("cover", JStr(input.cover))
            post.set("allow_comments", JBool(input.allowComments))
            post.set("pinned", JBool(input.pinned))
            post.set("featured", JBool(input.featured))
            post.set("seo_title", JStr(input.seoTitle))
            post.set("seo_description", JStr(input.seoDescription))
            post.set("template", JStr(input.template))
            post.set("scheduled_at", JStr(ctx.form("scheduled_at")))
            post.set("published_at", JStr(""))
            return editorResponse(ctx, JObj(post), id.size == 0, e.message)
        }
    }

    public func postAction(ctx: Ctx): HttpResponse {
        match (guard(ctx)) {
            case Some(response) => return response
            case None => ()
        }
        let id = ctx.param("id")
        let action = ctx.form("action")
        let returnTo = safeNext(ctx.form("return_to"))
        try {
            if (action == "publish") {
                services.posts.publish(id, ctx.userDoc(), ctx.clientIp())
                ctx.setFlash("success", "内容已发布")
            } else if (action == "trash") {
                services.posts.moveToTrash(id, ctx.userDoc(), ctx.clientIp())
                ctx.setFlash("success", "内容已移至回收站")
            } else if (action == "restore") {
                services.posts.restore(id, ctx.userDoc(), ctx.clientIp())
                ctx.setFlash("success", "内容已恢复为草稿")
            } else if (action == "delete") {
                services.posts.deletePermanently(id, ctx.userDoc(), ctx.clientIp())
                ctx.setFlash("success", "内容已永久删除")
            } else {
                throw AppError("validation", "无效操作")
            }
        } catch (e: AppError) {
            ctx.setFlash("error", e.message)
        }
        ctx.redirect(if (returnTo.size > 0) { returnTo } else { "/admin/posts" }, status: 303)
    }

    /** Bulk publish / trash / restore / delete for the post list. */
    public func postsBulk(ctx: Ctx): HttpResponse {
        match (guard(ctx)) {
            case Some(response) => return response
            case None => ()
        }
        let ids = ctx.req.formValues("ids")
        let action = ctx.form("action")
        let returnTo = safeNext(ctx.form("return_to"))
        let fallback = if (returnTo.size > 0) { returnTo } else { "/admin/posts" }
        if (ids.size == 0) {
            ctx.setFlash("error", "请先选择内容")
            return ctx.redirect(fallback, status: 303)
        }
        if (action != "publish" && action != "trash" && action != "restore" && action != "delete") {
            ctx.setFlash("error", "无效操作")
            return ctx.redirect(fallback, status: 303)
        }
        if (ids.size > 100) {
            ctx.setFlash("error", "一次最多处理 100 项")
            return ctx.redirect(fallback, status: 303)
        }
        var changed: Int64 = 0
        var failed: Int64 = 0
        for (id in ids) {
            try {
                if (action == "publish") {
                    services.posts.publish(id, ctx.userDoc(), ctx.clientIp())
                } else if (action == "trash") {
                    services.posts.moveToTrash(id, ctx.userDoc(), ctx.clientIp())
                } else if (action == "restore") {
                    services.posts.restore(id, ctx.userDoc(), ctx.clientIp())
                } else {
                    services.posts.deletePermanently(id, ctx.userDoc(), ctx.clientIp())
                }
                changed += 1
            } catch (e: Exception) {
                failed += 1
            }
        }
        if (failed > 0) {
            ctx.setFlash("error", "已处理 ${changed} 项，${failed} 项失败")
        } else {
            ctx.setFlash("success", "已处理 ${changed} 项内容")
        }
        ctx.redirect(fallback, status: 303)
    }

    /** Copy a post/page into a fresh draft. */
    public func postDuplicate(ctx: Ctx): HttpResponse {
        match (guard(ctx)) {
            case Some(response) => return response
            case None => ()
        }
        let id = ctx.param("id")
        let returnTo = safeNext(ctx.form("return_to"))
        try {
            let copyId = services.posts.duplicate(id, ctx.userDoc(), ctx.clientIp())
            ctx.setFlash("success", "已复制为草稿")
            return ctx.redirect("/admin/posts/" + copyId + "/edit", status: 303)
        } catch (e: AppError) {
            ctx.setFlash("error", e.message)
        }
        ctx.redirect(if (returnTo.size > 0) { returnTo } else { "/admin/posts" }, status: 303)
    }

    /** JSON payload for the inline page drawer. */
    public func postDrawerData(ctx: Ctx): HttpResponse {
        match (guard(ctx)) {
            case Some(response) => return response
            case None => ()
        }
        let post = match (services.posts.get(ctx.param("id"))) {
            case Some(value) => value
            case None => return quickError(404, "内容不存在")
        }
        if (!services.posts.canEdit(ctx.userDoc(), post)) {
            return quickError(403, "无权编辑此内容")
        }
        let item = JsonObject()
        item.set("id", JStr(docStr(post, "id")))
        item.set("type", JStr(docStr(post, "type")))
        item.set("title", JStr(docStr(post, "title")))
        item.set("slug", JStr(docStr(post, "slug")))
        item.set("summary", JStr(docStr(post, "summary")))
        item.set("content", JStr(docStr(post, "content")))
        item.set("status", JStr(docStr(post, "status")))
        item.set("cover", JStr(docStr(post, "cover")))
        item.set("seo_title", JStr(docStr(post, "seo_title")))
        item.set("seo_description", JStr(docStr(post, "seo_description")))
        item.set("allow_comments", JBool(docBool(post, "allow_comments", def: true)))
        item.set("scheduled_at", JStr(formatDateTime(docInt(post, "scheduled_at"))))
        item.set("category_id", JStr(docStr(post, "category_id")))
        item.set("template", JStr(docStr(post, "template")))
        let tagNames = ArrayList<String>()
        for (tagId in docStrings(post, "tag_ids")) {
            match (services.store.get(COL_TAGS, tagId)) {
                case Some(tag) => tagNames.add(docStr(tag, "name"))
                case None => ()
            }
        }
        item.set("tags", JStr(String.join(tagNames.toArray(), delimiter: ", ")))
        let data = JsonObject()
        data.set("ok", JBool(true))
        data.set("item", JObj(item))
        HttpResponse().json(JObj(data))
    }

    /** Save from the inline page drawer without leaving the list. */
    public func postQuickSave(ctx: Ctx): HttpResponse {
        match (guard(ctx)) {
            case Some(response) => return response
            case None => ()
        }
        let id = ctx.param("id")
        let post = match (services.posts.get(id)) {
            case Some(value) => value
            case None => return quickError(404, "内容不存在")
        }
        if (!services.posts.canEdit(ctx.userDoc(), post)) {
            return quickError(403, "无权编辑此内容")
        }
        let input = PostInput()
        input.postType = docStr(post, "type", def: "post")
        input.title = ctx.form("title")
        input.slug = ctx.form("slug")
        input.summary = ctx.form("summary")
        input.content = ctx.form("content")
        input.status = normalizeStatus(ctx.form("status"))
        let categoryForm = ctx.form("category_id")
        input.categoryId = if (categoryForm.size > 0) { categoryForm } else { docStr(post, "category_id") }
        let tagForm = ctx.form("tags")
        let tagNames = ArrayList<String>()
        if (tagForm.size > 0) {
            for (name in splitTags(tagForm)) {
                tagNames.add(name)
            }
        } else {
            for (tagId in docStrings(post, "tag_ids")) {
                match (services.store.get(COL_TAGS, tagId)) {
                    case Some(tag) => tagNames.add(docStr(tag, "name"))
                    case None => ()
                }
            }
        }
        input.tagNames = tagNames.toArray()
        input.cover = ctx.form("cover")
        input.allowComments = isChecked(ctx, "allow_comments")
        input.pinned = docBool(post, "pinned")
        input.featured = docBool(post, "featured")
        input.seoTitle = ctx.form("seo_title")
        input.seoDescription = ctx.form("seo_description")
        input.template = if (input.postType == "page") { ctx.form("template") } else { docStr(post, "template") }
        input.scheduledAt = parseDateTimeInput(ctx.form("scheduled_at"))
        try {
            services.posts.save(input, ctx.userDoc(), id, ctx.clientIp())
        } catch (e: AppError) {
            return quickError(if (e.kind == "forbidden") { 403 } else { 400 }, e.message)
        }
        let saved = match (services.posts.get(id)) {
            case Some(value) => value
            case None => return quickError(500, "保存后读取失败")
        }
        let data = JsonObject()
        data.set("ok", JBool(true))
        data.set("item", adminPostRow(services, saved))
        HttpResponse().json(JObj(data))
    }

    /** JSON payload for the revision preview dialog. */
    public func postPreviewShare(ctx: Ctx): HttpResponse {
        match (guard(ctx)) {
            case Some(response) => return response
            case None => ()
        }
        try {
            let post = match (services.posts.get(ctx.param("id"))) {
                case Some(value) => value
                case None => throw AppError("not_found", "内容不存在")
            }
            if (!services.posts.canEdit(ctx.userDoc(), post)) {
                return quickError(403, "无权分享此内容")
            }
            let token = services.posts.createPreviewToken(docStr(post, "id"), docStr(ctx.userDoc(), "id"), hours: 24)
            let data = JsonObject()
            data.set("ok", JBool(true))
            data.set("url", JStr(ctx.siteUrl("/preview/" + token)))
            data.set("expires_hours", JInt(24))
            HttpResponse().json(JObj(data))
        } catch (e: AppError) {
            quickError(400, e.message)
        }
    }

    public func postRevisionData(ctx: Ctx): HttpResponse {
        match (guard(ctx)) {
            case Some(response) => return response
            case None => ()
        }
        let postId = ctx.param("id")
        let post = match (services.posts.get(postId)) {
            case Some(value) => value
            case None => return quickError(404, "内容不存在")
        }
        if (!services.posts.canEdit(ctx.userDoc(), post)) {
            return quickError(403, "无权查看此内容")
        }
        let revision = match (services.posts.revision(postId, ctx.param("rev"))) {
            case Some(value) => value
            case None => return quickError(404, "版本不存在")
        }
        let item = JsonObject()
        item.set("id", JStr(docStr(revision, "id")))
        item.set("title", JStr(docStr(revision, "title")))
        item.set("summary", JStr(docStr(revision, "summary")))
        item.set("content", JStr(docStr(revision, "content")))
        item.set("date", JStr(formatDateTime(docInt(revision, "created_at"))))
        let data = JsonObject()
        data.set("ok", JBool(true))
        data.set("item", JObj(item))
        HttpResponse().json(JObj(data))
    }

    /** Restore one revision as the current draft. */
    public func postRevisionRestore(ctx: Ctx): HttpResponse {
        match (guard(ctx)) {
            case Some(response) => return response
            case None => ()
        }
        let postId = ctx.param("id")
        let returnTo = "/admin/posts/" + postId + "/edit"
        try {
            services.posts.restoreRevision(postId, ctx.param("rev"), ctx.userDoc(), ctx.clientIp())
            ctx.setFlash("success", "已恢复该版本为草稿")
        } catch (e: AppError) {
            ctx.setFlash("error", e.message)
        }
        ctx.redirect(returnTo, status: 303)
    }

    public func importPage(ctx: Ctx): HttpResponse {
        match (guard(ctx)) {
            case Some(response) => return response
            case None => ()
        }
        if (!ctx.can("post.create")) {
            return errorPage(ctx, 403, "无权导入内容")
        }
        importResponse(ctx, JsonArray(), "")
    }

    public func importSubmit(ctx: Ctx): HttpResponse {
        match (guard(ctx)) {
            case Some(response) => return response
            case None => ()
        }
        if (!ctx.can("post.create")) {
            return errorPage(ctx, 403, "无权导入内容")
        }
        ctx.req.parseForm()
        let files = ctx.req.files
        let results = JsonArray()
        if (files.size == 0) {
            return importResponse(ctx, results, "请选择 Markdown 文件")
        }
        if (files.size > 20) {
            return importResponse(ctx, results, "单次最多导入 20 个文件")
        }
        let publish = isChecked(ctx, "publish") && ctx.can("post.publish")
        let importer = MarkdownImporter(services.posts, services.taxonomy)
        var success: Int64 = 0
        var failed: Int64 = 0
        for (file in files) {
            let ext = extensionOf(file.filename)
            if (ext != "md" && ext != "markdown") {
                failed += 1
                results.add(importResultRow(file.filename, "", "仅支持 .md / .markdown 文件"))
                continue
            }
            if (file.data.size > 1024 * 1024) {
                failed += 1
                results.add(importResultRow(file.filename, "", "文件超过 1MB"))
                continue
            }
            let text = try {
                String.fromUtf8(file.data)
            } catch (e: Exception) {
                failed += 1
                results.add(importResultRow(file.filename, "", "文件不是有效 UTF-8"))
                continue
            }
            try {
                let doc = importer.parse(text, file.filename)
                let imported = importer.importOne(doc, ctx.userDoc(), publish, ctx.clientIp())
                success += 1
                results.add(importResultRow(file.filename, imported.title, ""))
            } catch (e: AppError) {
                failed += 1
                results.add(importResultRow(file.filename, "", e.message))
            } catch (e: Exception) {
                failed += 1
                results.add(importResultRow(file.filename, "", "导入失败"))
            }
        }
        services.audit.log(docStr(ctx.userDoc(), "id"), docStr(ctx.userDoc(), "username"),
                           "posts_imported", "post", "", ctx.clientIp(),
                           "success=${success} failed=${failed}")
        let summary = "成功 ${success} 个，失败 ${failed} 个"
        importResponse(ctx, results, summary)
    }

    private func importResultRow(name: String, title: String, error: String): JsonValue {
        let row = JsonObject()
        row.set("name", JStr(name))
        row.set("title", JStr(title))
        row.set("error", JStr(error))
        row.set("ok", JBool(error.size == 0))
        JObj(row)
    }

    private func importResponse(ctx: Ctx, results: JsonArray, summary: String): HttpResponse {
        let data = JsonObject()
        data.set("page_title", JStr("Markdown 导入"))
        data.set("active", JStr("tools"))
        data.set("can_publish", JBool(ctx.can("post.publish")))
        data.set("results", JArr(results))
        data.set("summary", JStr(summary))
        ctx.renderAdminPage("import.html", JObj(data))
    }

    public func redirectsPage(ctx: Ctx): HttpResponse {
        match (requireAdmin(ctx)) {
            case Some(response) => return response
            case None => ()
        }
        let data = JsonObject()
        data.set("page_title", JStr("重定向"))
        data.set("active", JStr("tools"))
        let items = JsonArray()
        for (item in services.redirects.list()) {
            let view = cloneDoc(item)
            setField(view, "date", JStr(formatDateTime(docInt(item, "created_at"))))
            items.add(view)
        }
        data.set("items", JArr(items))
        ctx.renderAdminPage("redirects.html", JObj(data))
    }

    public func redirectSave(ctx: Ctx): HttpResponse {
        match (requireAdmin(ctx)) {
            case Some(response) => return response
            case None => ()
        }
        try {
            if (ctx.form("action") == "delete") {
                services.redirects.delete(ctx.form("id"), ctx.userDoc(), ctx.clientIp())
                ctx.setFlash("success", "重定向已删除")
            } else {
                services.redirects.create(ctx.form("from"), ctx.form("to"), ctx.userDoc(), ctx.clientIp())
                ctx.setFlash("success", "重定向已创建")
            }
        } catch (e: AppError) {
            ctx.setFlash("error", e.message)
        }
        ctx.redirect("/admin/redirects", status: 303)
    }

    private func pageTemplateNames(): Array<String> {
        let out = ArrayList<String>()
        let dir = services.themeTemplatesDir()
        if (exists(dir + "/page.html")) {
            out.add("page.html")
        }
        for (name in listDir(dir)) {
            if (name == "page.html") {
                continue
            }
            if (name.startsWith("page-") && name.endsWith(".html")) {
                out.add(name)
            }
        }
        out.toArray()
    }

    private func quickError(status: Int64, message: String): HttpResponse {
        let data = JsonObject()
        data.set("ok", JBool(false))
        data.set("error", JStr(message))
        HttpResponse().json(JObj(data), status: status)
    }

    private func editorResponse(ctx: Ctx, post: JsonValue, isNew: Bool, error: String): HttpResponse {
        let data = JsonObject()
        data.set("page_title", JStr(if (isNew) { "新建内容" } else { "编辑内容" }))
        data.set("active", JStr(if (docStr(post, "type") == "page") { "pages" } else { "posts" }))
        data.set("post", post)
        data.set("is_new", JBool(isNew))
        data.set("error", JStr(error))
        let categories = JsonArray()
        for (category in services.taxonomy.listCategories()) {
            categories.add(category)
        }
        data.set("categories", JArr(categories))
        let tags = JsonArray()
        for (tag in services.taxonomy.listTags()) {
            tags.add(tag)
        }
        data.set("all_tags", JArr(tags))
        data.set("page_templates", jsonStringList(pageTemplateNames()))
        let revisions = JsonArray()
        if (!isNew) {
            for (revision in services.posts.revisions(docStr(post, "id"))) {
                let view = cloneDoc(revision)
                setField(view, "date", JStr(formatDateTime(docInt(revision, "created_at"))))
                revisions.add(view)
            }
        }
        data.set("revisions", JArr(revisions))
        let response = ctx.renderAdminPage("editor.html", JObj(data))
        response.headers.set("cache-control", "no-store")
        response
    }

    private func adminEditorPost(post: JsonValue): JsonValue {
        let data = cloneDoc(post)
        let tags = ArrayList<String>()
        for (tag in services.taxonomy.tagsForPost(post)) {
            tags.add(docStr(tag, "name"))
        }
        setField(data, "tags", JStr(String.join(tags.toArray(), delimiter: ", ")))
        let scheduled = docInt(post, "scheduled_at")
        setField(data, "scheduled_at", JStr(if (scheduled > 0) { formatTime(scheduled, "yyyy-MM-dd'T'HH:mm") } else { "" }))
        setField(data, "published_at", JStr(formatDateTime(docInt(post, "published_at"))))
        data
    }

    private func normalizeStatus(value: String): String {
        if (value == STATUS_PUBLISHED || value == STATUS_SCHEDULED || value == STATUS_DRAFT) {
            return value
        }
        STATUS_DRAFT
    }

    private func statusCounts(ctx: Ctx, postType: String): JsonValue {
        let counts = JsonObject()
        var all: Int64 = 0
        var published: Int64 = 0
        var draft: Int64 = 0
        var scheduled: Int64 = 0
        var trash: Int64 = 0
        for (post in services.store.list(COL_POSTS)) {
            if (docStr(post, "type") != postType) {
                continue
            }
            if (!canSee(ctx.userDoc(), post)) {
                continue
            }
            all += 1
            let status = docStr(post, "status")
            if (status == STATUS_PUBLISHED) {
                published += 1
            } else if (status == STATUS_DRAFT) {
                draft += 1
            } else if (status == STATUS_SCHEDULED) {
                scheduled += 1
            } else if (status == STATUS_TRASH) {
                trash += 1
            }
        }
        counts.set("all", JInt(all))
        counts.set("published", JInt(published))
        counts.set("draft", JInt(draft))
        counts.set("scheduled", JInt(scheduled))
        counts.set("trash", JInt(trash))
        JObj(counts)
    }

    private func canSee(user: JsonValue, post: JsonValue): Bool {
        let role = docStr(user, "role")
        if (role == ROLE_ADMIN || role == ROLE_EDITOR) {
            return true
        }
        docStr(post, "author_id") == docStr(user, "id")
    }

    private func allPostsQuery(ctx: Ctx): PostQuery {
        let query = PostQuery()
        query.status = "any"
        query.postType = "post"
        let role = match (ctx.user) {
            case Some(value) => docStr(value, "role")
            case None => ""
        }
        if (role != ROLE_ADMIN && role != ROLE_EDITOR) {
            query.authorId = match (ctx.user) {
                case Some(value) => docStr(value, "id")
                case None => ""
            }
        }
        query
    }

    // -----------------------------------------------------------------------
    // Taxonomy
    // -----------------------------------------------------------------------

    public func categoriesPage(ctx: Ctx): HttpResponse {
        match (guard(ctx)) {
            case Some(response) => return response
            case None => ()
        }
        let data = JsonObject()
        data.set("page_title", JStr("分类"))
        data.set("active", JStr("categories"))
        let categories = JsonArray()
        for (category in services.taxonomy.listCategories()) {
            let item = cloneDoc(category)
            var count: Int64 = 0
            for (post in services.store.list(COL_POSTS)) {
                if (docStr(post, "category_id") == docStr(category, "id") && docStr(post, "status") != STATUS_TRASH) {
                    count += 1
                }
            }
            setField(item, "post_count", JInt(count))
            categories.add(item)
        }
        data.set("categories", JArr(categories))
        ctx.renderAdminPage("categories.html", JObj(data))
    }

    public func categorySave(ctx: Ctx): HttpResponse {
        match (guard(ctx)) {
            case Some(response) => return response
            case None => ()
        }
        let action = ctx.form("action")
        try {
            if (action == "create") {
                services.taxonomy.createCategory(ctx.form("name"), ctx.form("slug"), ctx.form("description"), ctx.clientIp())
                ctx.setFlash("success", "分类已创建")
            } else if (action == "update") {
                services.taxonomy.updateCategory(ctx.form("id"), ctx.form("name"), ctx.form("slug"),
                                                 ctx.form("description"), ctx.clientIp())
                ctx.setFlash("success", "分类已更新")
            } else if (action == "delete") {
                services.taxonomy.deleteCategory(ctx.form("id"), ctx.clientIp())
                ctx.setFlash("success", "分类已删除")
            }
        } catch (e: AppError) {
            ctx.setFlash("error", e.message)
        }
        let returnTo = safeNext(ctx.form("return_to"))
        ctx.redirect(if (returnTo.size > 0) { returnTo } else { "/admin/categories" }, status: 303)
    }

    /** Inline category creation from the post editor (JSON, CSRF header). */
    public func categoryQuick(ctx: Ctx): HttpResponse {
        match (guard(ctx)) {
            case Some(response) => return response
            case None => ()
        }
        try {
            let body = try {
                String.fromUtf8(ctx.req.body)
            } catch (e: Exception) {
                ""
            }
            let parsed = tryParseJson(body) ?? jobj()
            let name = getString(parsed, "name")
            let slug = getString(parsed, "slug")
            let id = services.taxonomy.createCategory(name, slug, "", ctx.clientIp())
            let category = match (services.taxonomy.getCategory(id)) {
                case Some(value) => value
                case None => jobj()
            }
            let data = JsonObject()
            data.set("ok", JBool(true))
            data.set("id", JStr(id))
            data.set("name", JStr(docStr(category, "name", def: name.trimAscii())))
            data.set("slug", JStr(docStr(category, "slug")))
            HttpResponse().json(JObj(data))
        } catch (e: AppError) {
            attachmentJsonError(e.message)
        } catch (e: Exception) {
            attachmentJsonError("分类创建失败")
        }
    }

    public func tagsPage(ctx: Ctx): HttpResponse {
        match (guard(ctx)) {
            case Some(response) => return response
            case None => ()
        }
        let data = JsonObject()
        data.set("page_title", JStr("标签"))
        data.set("active", JStr("tags"))
        let tags = JsonArray()
        for (tag in services.taxonomy.listTags()) {
            tags.add(tag)
        }
        data.set("tags", JArr(tags))
        ctx.renderAdminPage("tags.html", JObj(data))
    }

    public func tagDelete(ctx: Ctx): HttpResponse {
        match (guard(ctx)) {
            case Some(response) => return response
            case None => ()
        }
        try {
            services.taxonomy.deleteTag(ctx.form("id"), ctx.clientIp())
            ctx.setFlash("success", "标签已删除")
        } catch (e: AppError) {
            ctx.setFlash("error", e.message)
        }
        ctx.redirect("/admin/tags", status: 303)
    }

    // -----------------------------------------------------------------------
    // Comments
    // -----------------------------------------------------------------------

    public func commentsPage(ctx: Ctx): HttpResponse {
        match (guard(ctx)) {
            case Some(response) => return response
            case None => ()
        }
        let status = normalizeCommentStatus(ctx.query("status", def: "pending"))
        let search = ctx.query("q").trimAscii()
        let postId = ctx.query("post").trimAscii()
        let page = ctx.pageNumber()
        let result = services.comments.adminList(status, page, 30, query: search, postId: postId)
        let rows = JsonArray()
        for (comment in result.items) {
            let post = services.posts.get(docStr(comment, "post_id"))
            let view = cloneDoc(commentView(comment, post, 0))
            setField(view, "author_email", JStr(docStr(comment, "author_email")))
            setField(view, "ip_hash", JStr(docStr(comment, "ip_hash")))
            setField(view, "user_agent", JStr(docStr(comment, "user_agent")))
            setField(view, "post_id", JStr(docStr(comment, "post_id")))
            setField(view, "parent_id", JStr(docStr(comment, "parent_id")))
            rows.add(view)
        }
        let postOptions = JsonArray()
        for (post in services.posts.publishedPosts()) {
            let item = JsonObject()
            item.set("id", JStr(docStr(post, "id")))
            item.set("title", JStr(docStr(post, "title")))
            item.set("selected", JBool(docStr(post, "id") == postId))
            postOptions.add(JObj(item))
        }
        let data = JsonObject()
        data.set("page_title", JStr("评论"))
        data.set("active", JStr("comments"))
        data.set("status", JStr(status))
        data.set("search", JStr(search))
        data.set("post_filter", JStr(postId))
        data.set("rows", JArr(rows))
        data.set("counts", services.comments.statusCounts())
        data.set("post_options", JArr(postOptions))
        data.set("pagination", buildPagination(result.page, result.pages, result.total,
            "/admin/comments?status=${status}&q=" + urlEncode(search) + "&post=" + urlEncode(postId), 30))
        ctx.renderAdminPage("comments.html", JObj(data))
    }

    public func commentAction(ctx: Ctx): HttpResponse {
        match (guard(ctx)) {
            case Some(response) => return response
            case None => ()
        }
        let id = ctx.param("id")
        let action = ctx.param("action")
        try {
            if (action == "delete") {
                services.comments.delete(id, ctx.userDoc(), ctx.clientIp())
                ctx.setFlash("success", "评论已删除")
            } else {
                services.comments.moderate(id, action, ctx.userDoc(), ctx.clientIp())
                ctx.setFlash("success", "评论状态已更新")
            }
        } catch (e: AppError) {
            ctx.setFlash("error", e.message)
        }
        ctx.redirect(commentReturnUrl(ctx), status: 303)
    }

    public func commentsBulk(ctx: Ctx): HttpResponse {
        match (guard(ctx)) {
            case Some(response) => return response
            case None => ()
        }
        let ids = ctx.req.formValues("ids")
        let action = ctx.form("action")
        if (ids.size == 0) {
            ctx.setFlash("error", "请先选择评论")
            return ctx.redirect(commentReturnUrl(ctx), status: 303)
        }
        var changed: Int64 = 0
        var failed: Int64 = 0
        for (id in ids) {
            try {
                if (action == "delete") {
                    services.comments.delete(id, ctx.userDoc(), ctx.clientIp())
                } else {
                    services.comments.moderate(id, action, ctx.userDoc(), ctx.clientIp())
                }
                changed += 1
            } catch (e: Exception) {
                failed += 1
            }
        }
        if (failed > 0) {
            ctx.setFlash("error", "已处理 ${changed} 条，${failed} 条失败")
        } else {
            ctx.setFlash("success", "已处理 ${changed} 条评论")
        }
        ctx.redirect(commentReturnUrl(ctx), status: 303)
    }

    private func commentReturnUrl(ctx: Ctx): String {
        let status = normalizeCommentStatus(ctx.form("return_status",
            def: ctx.form("status", def: ctx.query("status", def: "pending"))))
        let search = ctx.form("return_q", def: ctx.query("q"))
        let postId = ctx.form("return_post", def: ctx.query("post"))
        "/admin/comments?status=${status}&q=" + urlEncode(search) + "&post=" + urlEncode(postId)
    }

    private func normalizeCommentStatus(value: String): String {
        if (value == "approved" || value == "spam" || value == "trash" || value == "all") {
            return value
        }
        "pending"
    }

    // -----------------------------------------------------------------------
    // Attachments (formerly media library)
    // -----------------------------------------------------------------------

    public func mediaPage(ctx: Ctx): HttpResponse {
        // Legacy URL: render the renamed attachment library in place.
        attachmentsPage(ctx)
    }

    public func attachmentsPage(ctx: Ctx): HttpResponse {
        match (guard(ctx)) {
            case Some(response) => return response
            case None => ()
        }
        let kind = normalizeAttachmentKind(ctx.query("kind", def: "all"))
        let search = ctx.query("q").trimAscii()
        let result = services.media.list(ctx.pageNumber(), 36, kind: kind, query: search)
        let items = JsonArray()
        for (item in result.items) {
            items.add(attachmentView(item))
        }
        let counts = services.media.counts()
        let data = JsonObject()
        data.set("page_title", JStr("附件库"))
        data.set("active", JStr("attachments"))
        data.set("items", JArr(items))
        data.set("counts", counts)
        data.set("kind", JStr(kind))
        data.set("search", JStr(search))
        data.set("total_size", JStr(formatFileSize(docInt(counts, "bytes"))))
        data.set("can_manage_media", JBool(ctx.can("media.manage")))
        data.set("pagination", buildPagination(result.page, result.pages, result.total,
            "/admin/attachments?kind=${kind}&q=" + urlEncode(search), 36))
        ctx.renderAdminPage("attachments.html", JObj(data))
    }

    public func attachmentsData(ctx: Ctx): HttpResponse {
        match (guard(ctx)) {
            case Some(response) => return response
            case None => ()
        }
        let kind = normalizeAttachmentKind(ctx.query("kind", def: "image"))
        let search = ctx.query("q").trimAscii()
        let page = ctx.pageNumber()
        let result = services.media.list(page, 24, kind: kind, query: search)
        let items = JsonArray()
        for (item in result.items) {
            items.add(attachmentView(item))
        }
        let data = JsonObject()
        data.set("items", JArr(items))
        data.set("page", JInt(result.page))
        data.set("pages", JInt(result.pages))
        data.set("total", JInt(result.total))
        data.set("has_more", JBool(result.page < result.pages))
        HttpResponse().json(JObj(data))
    }

    public func attachmentsUpload(ctx: Ctx): HttpResponse {        match (guard(ctx)) {
            case Some(response) => return response
            case None => ()
        }
        let wantsJson = ctx.query("format") == "json" ||
            ctx.req.header("accept").toAsciiLower().contains("application/json")
        if (!ctx.can("media.manage")) {
            if (wantsJson) {
                return quickError(403, "无权上传附件")
            }
            ctx.setFlash("error", "无权上传附件")
            return ctx.redirect("/admin/attachments", status: 303)
        }
        try {
            ctx.req.parseForm()
            if (ctx.req.files.size == 0) {
                if (wantsJson) {
                    return attachmentJsonError("没有选择文件")
                }
                ctx.setFlash("error", "没有选择文件")
                return ctx.redirect("/admin/attachments", status: 303)
            }
            var count: Int64 = 0
            var index: Int64 = 0
            let uploaded = JsonArray()
            while (index < ctx.req.files.size && count < 10) {
                let file = ctx.req.files[index]
                let saved = services.media.upload(file, docStr(ctx.userDoc(), "id"), ctx.clientIp(), folder: ctx.form("folder"))
                uploaded.add(attachmentView(saved))
                count += 1
                index += 1
            }
            if (wantsJson) {
                let data = JsonObject()
                data.set("ok", JBool(true))
                data.set("items", JArr(uploaded))
                return HttpResponse().json(JObj(data))
            }
            ctx.setFlash("success", "已上传 ${count} 个附件")
        } catch (e: AppError) {
            if (wantsJson) {
                return attachmentJsonError(e.message)
            }
            ctx.setFlash("error", e.message)
        } catch (e: Exception) {
            services.logger.error("attachments", e.message)
            if (wantsJson) {
                return attachmentJsonError("上传失败")
            }
            ctx.setFlash("error", "上传失败")
        }
        ctx.redirect("/admin/attachments", status: 303)
    }

    public func attachmentsDelete(ctx: Ctx): HttpResponse {
        match (guard(ctx)) {
            case Some(response) => return response
            case None => ()
        }
        let returnTo = safeNext(ctx.form("return_to"))
        if (!ctx.can("media.manage")) {
            ctx.setFlash("error", "无权删除附件")
            return ctx.redirect(if (returnTo.size > 0) { returnTo } else { "/admin/attachments" }, status: 303)
        }
        try {
            let force = ctx.form("force") == "1"
            services.media.delete(ctx.param("id"), ctx.userDoc(), ctx.clientIp(), force: force)
            ctx.setFlash("success", "附件已删除")
        } catch (e: AppError) {
            ctx.setFlash("error", e.message)
        }
        ctx.redirect(if (returnTo.size > 0) { returnTo } else { "/admin/attachments" }, status: 303)
    }

    public func attachmentsVariant(ctx: Ctx): HttpResponse {
        match (guard(ctx)) {
            case Some(response) => return response
            case None => ()
        }
        if (!ctx.can("media.manage")) {
            return quickError(403, "无权生成缩略图")
        }
        try {
            ctx.req.parseForm()
            if (ctx.req.files.size == 0) {
                return quickError(400, "没有选择缩略图文件")
            }
            services.media.addVariant(ctx.param("id"), ctx.req.files[0], ctx.userDoc(), ctx.clientIp())
            let data = JsonObject()
            data.set("ok", JBool(true))
            return HttpResponse().json(JObj(data))
        } catch (e: AppError) {
            return quickError(400, e.message)
        } catch (e: Exception) {
            return quickError(500, "缩略图生成失败")
        }
    }

    public func attachmentsBulk(ctx: Ctx): HttpResponse {        match (guard(ctx)) {
            case Some(response) => return response
            case None => ()
        }
        if (!ctx.can("media.manage")) {
            ctx.setFlash("error", "无权批量操作附件")
            return ctx.redirect("/admin/attachments", status: 303)
        }
        let ids = ctx.req.formValues("ids")
        var deleted: Int64 = 0
        var skipped: Int64 = 0
        for (id in ids) {
            try {
                services.media.delete(id, ctx.userDoc(), ctx.clientIp(), force: false)
                deleted += 1
            } catch (e: AppError) {
                skipped += 1
            }
        }
        ctx.setFlash("success", "已删除 ${deleted} 个附件" + if (skipped > 0) { "，跳过 ${skipped} 个被引用或无效项" } else { "" })
        ctx.redirect("/admin/attachments", status: 303)
    }

    public func attachmentsReplace(ctx: Ctx): HttpResponse {        match (guard(ctx)) {
            case Some(response) => return response
            case None => ()
        }
        if (!ctx.can("media.manage")) {
            ctx.setFlash("error", "无权替换附件")
            return ctx.redirect("/admin/attachments", status: 303)
        }
        try {
            ctx.req.parseForm()
            if (ctx.req.files.size == 0) {
                ctx.setFlash("error", "没有选择文件")
                return ctx.redirect("/admin/attachments", status: 303)
            }
            services.media.replace(ctx.param("id"), ctx.req.files[0], ctx.userDoc(), ctx.clientIp())
            ctx.setFlash("success", "附件文件已替换，访问地址不变")
        } catch (e: AppError) {
            ctx.setFlash("error", e.message)
        } catch (e: Exception) {
            services.logger.error("attachments", e.message)
            ctx.setFlash("error", "替换失败")
        }
        ctx.redirect("/admin/attachments", status: 303)
    }

    public func attachmentsRename(ctx: Ctx): HttpResponse {        match (guard(ctx)) {
            case Some(response) => return response
            case None => ()
        }
        let returnTo = safeNext(ctx.form("return_to"))
        let fallback = if (returnTo.size > 0) { returnTo } else { "/admin/attachments" }
        if (!ctx.can("media.manage")) {
            ctx.setFlash("error", "无权重命名附件")
            return ctx.redirect(fallback, status: 303)
        }
        try {
            services.media.rename(ctx.param("id"), ctx.form("name"), ctx.userDoc(), ctx.clientIp())
            ctx.setFlash("success", "附件名称已更新")
        } catch (e: AppError) {
            ctx.setFlash("error", e.message)
        }
        ctx.redirect(fallback, status: 303)
    }

    public func attachmentsUsage(ctx: Ctx): HttpResponse {
        match (guard(ctx)) {
            case Some(response) => return response
            case None => ()
        }
        try {
            HttpResponse().json(services.media.usage(ctx.param("id")))
        } catch (e: AppError) {
            quickError(if (e.kind == "not_found") { 404 } else { 400 }, e.message)
        }
    }

    public func mediaUpload(ctx: Ctx): HttpResponse {
        attachmentsUpload(ctx)
    }

    public func mediaDelete(ctx: Ctx): HttpResponse {
        attachmentsDelete(ctx)
    }

    private func attachmentView(item: JsonValue): JsonValue {
        let view = cloneDoc(item)
        let kind = mediaKindOfService(item)
        setField(view, "kind", JStr(kind))
        setField(view, "kind_label", JStr(matchKindLabel(kind)))
        setField(view, "size_text", JStr(formatFileSize(docInt(item, "size"))))
        setField(view, "date", JStr(formatDate(docInt(item, "created_at"))))
        setField(view, "date_time", JStr(formatDateTime(docInt(item, "created_at"))))
        setField(view, "thumb_url", JStr(docStr(item, "thumb_url", def: docStr(item, "url"))))
        if (docInt(item, "width") > 0) {
            setField(view, "dimensions", JStr("${docInt(item, "width")} × ${docInt(item, "height")}"))
        } else {
            setField(view, "dimensions", JStr(""))
        }
        view
    }

    private func normalizeAttachmentKind(value: String): String {
        if (value == "image" || value == "video" || value == "audio" || value == "document") {
            return value
        }
        "all"
    }

    private func matchKindLabel(kind: String): String {
        if (kind == "image") { "图片" } else if (kind == "video") { "视频" } else if (kind == "audio") { "音频" } else if (kind == "document") { "文档" } else { "附件" }
    }

    // -----------------------------------------------------------------------
    // Users
    // -----------------------------------------------------------------------

    public func usersPage(ctx: Ctx): HttpResponse {
        match (requireAdmin(ctx)) {
            case Some(response) => return response
            case None => ()
        }
        let search = ctx.query("q").trimAscii().toAsciiLower()
        let roleFilter = ctx.query("role").trimAscii()
        let statusFilter = ctx.query("status").trimAscii()
        let users = JsonArray()
        let counts = JsonObject()
        var all: Int64 = 0
        var active: Int64 = 0
        var suspended: Int64 = 0
        var admins: Int64 = 0
        var editors: Int64 = 0
        var authors: Int64 = 0
        var contributors: Int64 = 0
        var subscribers: Int64 = 0
        for (user in services.auth.listUsers()) {
            all += 1
            let role = docStr(user, "role")
            if (role == ROLE_ADMIN) { admins += 1 } else if (role == ROLE_EDITOR) { editors += 1 } else if (role == ROLE_AUTHOR) { authors += 1 } else if (role == ROLE_CONTRIBUTOR) { contributors += 1 } else if (role == ROLE_SUBSCRIBER) { subscribers += 1 }
            if (docStr(user, "status") == "active") { active += 1 } else { suspended += 1 }
            if (roleFilter.size > 0 && role != roleFilter) {
                continue
            }
            if (statusFilter.size > 0 && docStr(user, "status") != statusFilter) {
                continue
            }
            if (search.size > 0) {
                let haystack = (docStr(user, "username") + " " + docStr(user, "display_name") + " " +
                                docStr(user, "email")).toAsciiLower()
                if (!haystack.contains(search)) {
                    continue
                }
            }
            let view = cloneDoc(user)
            var postCount: Int64 = 0
            for (post in services.store.list(COL_POSTS)) {
                if (docStr(post, "author_id") == docStr(user, "id") && docStr(post, "status") != STATUS_TRASH) {
                    postCount += 1
                }
            }
            setField(view, "post_count", JInt(postCount))
            setField(view, "created", JStr(formatDate(docInt(user, "created_at"))))
            setField(view, "last_login", JStr(formatDateTime(docInt(user, "last_login_at"))))
            setField(view, "initial", JStr(initialOf(docStr(user, "display_name", def: docStr(user, "username")))))
            setField(view, "is_self", JBool(docStr(user, "id") == docStr(ctx.userDoc(), "id")))
            users.add(view)
        }
        counts.set("all", JInt(all))
        counts.set("active", JInt(active))
        counts.set("suspended", JInt(suspended))
        counts.set("admin", JInt(admins))
        counts.set("editor", JInt(editors))
        counts.set("author", JInt(authors))
        counts.set("contributor", JInt(contributors))
        counts.set("subscriber", JInt(subscribers))
        let data = JsonObject()
        data.set("page_title", JStr("用户"))
        data.set("active", JStr("users"))
        data.set("users", JArr(users))
        data.set("counts", JObj(counts))
        data.set("q", JStr(ctx.query("q")))
        data.set("role_filter", JStr(roleFilter))
        data.set("status_filter", JStr(statusFilter))
        data.set("roles", jsonStringList(["admin", "editor", "author", "contributor", "subscriber"]))
        ctx.renderAdminPage("users.html", JObj(data))
    }

    public func userAction(ctx: Ctx): HttpResponse {
        match (requireAdmin(ctx)) {
            case Some(response) => return response
            case None => ()
        }
        let action = ctx.form("action")
        try {
            if (action == "create") {
                services.auth.createUser(ctx.form("username"), ctx.form("email"), ctx.form("password"),
                                         ctx.form("display_name"), ctx.form("role"), ctx.clientIp())
                ctx.setFlash("success", "用户已创建")
            } else if (action == "update") {
                services.auth.adminUpdateUser(ctx.form("id"), ctx.form("role"), ctx.form("status"),
                                              ctx.form("display_name"), ctx.clientIp())
                ctx.setFlash("success", "用户已更新")
            } else if (action == "reset") {
                let newPassword = "Cm-" + randomToken(bytes: 9)
                services.auth.resetPassword(ctx.form("id"), newPassword, ctx.clientIp())
                ctx.setFlash("success", "密码已重置为：${newPassword}（请立即转告用户）")
            }
        } catch (e: AppError) {
            ctx.setFlash("error", e.message)
        }
        ctx.redirect("/admin/users", status: 303)
    }

    public func userBulk(ctx: Ctx): HttpResponse {
        match (requireAdmin(ctx)) {
            case Some(response) => return response
            case None => ()
        }
        let status = if (ctx.form("action") == "activate") { "active" } else { "suspended" }
        let ids = ctx.req.formValues("ids")
        var changed: Int64 = 0
        for (id in ids) {
            match (services.auth.userById(id)) {
                case Some(user) =>
                    try {
                        services.auth.adminUpdateUser(id, docStr(user, "role"), status,
                                                      docStr(user, "display_name"), ctx.clientIp())
                        changed += 1
                    } catch (e: AppError) {}
                case None => ()
            }
        }
        ctx.setFlash("success", "已处理 ${changed} 个用户")
        ctx.redirect("/admin/users", status: 303)
    }

    // -----------------------------------------------------------------------
    // Settings
    // -----------------------------------------------------------------------

    public func settingsPage(ctx: Ctx): HttpResponse {
        match (requireAdmin(ctx)) {
            case Some(response) => return response
            case None => ()
        }
        let data = JsonObject()
        data.set("page_title", JStr("设置"))
        data.set("active", JStr("settings"))
        data.set("settings", services.settings.all())
        data.set("nav_text", JStr(navText()))
        data.set("social_text", JStr(socialText()))
        ctx.renderAdminPage("settings.html", JObj(data))
    }

    public func settingsSave(ctx: Ctx): HttpResponse {
        match (requireAdmin(ctx)) {
            case Some(response) => return response
            case None => ()
        }
        try {
            services.settings.setString("site_title", requireText(ctx.form("site_title"), "站点标题", 1, 100))
            services.settings.setString("site_subtitle", truncateUtf8(ctx.form("site_subtitle").trimAscii(), 150))
            services.settings.setString("site_description", truncateUtf8(ctx.form("site_description").trimAscii(), 300))
            services.settings.setString("site_keywords", truncateUtf8(ctx.form("site_keywords").trimAscii(), 200))
            let siteUrlValue = ctx.form("site_url").trimAscii()
            if (siteUrlValue.size > 0 && !isValidWebUrl(siteUrlValue)) {
                throw AppError("validation", "站点地址格式无效")
            }
            services.settings.setString("site_url", if (siteUrlValue.size > 0) { siteUrlValue } else { services.config.siteUrl })
            services.settings.setString("footer_text", truncateUtf8(ctx.form("footer_text").trimAscii(), 300))
            services.settings.setInt("posts_per_page", clampInt(ctx.form("posts_per_page"), 1, 50, 10))
            services.settings.setString("theme_accent", safeColor(ctx.form("theme_accent")))
            services.settings.setString("theme_mode", if (ctx.form("theme_mode") == "dark" || ctx.form("theme_mode") == "light") { ctx.form("theme_mode") } else { "auto" })
            services.settings.setBool("comment_enabled", isChecked(ctx, "comment_enabled"))
            services.settings.setBool("comment_moderation", isChecked(ctx, "comment_moderation"))
            services.settings.setInt("comment_max_links", clampInt(ctx.form("comment_max_links"), 0, 20, 3))
            services.settings.setBool("show_toc", isChecked(ctx, "show_toc"))
            // Preserve the default when an older/automated form omits the new toggle.
            if (ctx.form("show_related_posts_present") == "1") {
                services.settings.setBool("show_related_posts", isChecked(ctx, "show_related_posts"))
            }
            services.settings.setBool("show_reading_time", isChecked(ctx, "show_reading_time"))
            services.settings.set("nav", JStr(navJson(ctx.form("nav_text"))))
            services.settings.set("social_links", JStr(socialJson(ctx.form("social_text"))))
            if (ctx.form("settings_v2_present") == "1") {
                services.settings.setString("site_logo", safeAssetUrl(ctx.form("site_logo"), "站点 Logo"))
                services.settings.setString("site_favicon", safeAssetUrl(ctx.form("site_favicon"), "站点图标"))
                services.settings.setString("footer_copyright", truncateUtf8(ctx.form("footer_copyright").trimAscii(), 200))
                services.settings.setString("footer_icp", truncateUtf8(ctx.form("footer_icp").trimAscii(), 100))
                services.settings.setString("home_hero_title", truncateUtf8(ctx.form("home_hero_title").trimAscii(), 120))
                services.settings.setString("home_hero_subtitle", truncateUtf8(ctx.form("home_hero_subtitle").trimAscii(), 200))
                services.settings.setString("home_hero_image", safeAssetUrl(ctx.form("home_hero_image"), "首页主图"))
                services.settings.setString("seo_image", safeAssetUrl(ctx.form("seo_image"), "分享图"))
                services.settings.setString("seo_twitter", truncateUtf8(ctx.form("seo_twitter").trimAscii(), 50))
                services.settings.setBool("home_show_featured", isChecked(ctx, "home_show_featured"))
                services.settings.setBool("show_author", isChecked(ctx, "show_author"))
                services.settings.setBool("show_date", isChecked(ctx, "show_date"))
                services.settings.setBool("show_category", isChecked(ctx, "show_category"))
                services.settings.setBool("show_tags", isChecked(ctx, "show_tags"))
                services.settings.setInt("excerpt_length", clampInt(ctx.form("excerpt_length"), 40, 300, 120))
                services.settings.setInt("related_count", clampInt(ctx.form("related_count"), 1, 12, 3))
                services.settings.setInt("theme_font_size", clampInt(ctx.form("theme_font_size"), 14, 22, 17))
                services.settings.setInt("theme_width", clampInt(ctx.form("theme_width"), 900, 1400, 1120))
                services.settings.setInt("theme_radius", clampInt(ctx.form("theme_radius"), 0, 28, 12))
                services.settings.setString("custom_css", truncateUtf8(ctx.form("custom_css"), 20000))
                services.settings.setBool("maintenance", isChecked(ctx, "maintenance"))
                services.settings.setString("maintenance_message", truncateUtf8(ctx.form("maintenance_message").trimAscii(), 200))
            }
            services.audit.log(docStr(ctx.userDoc(), "id"), docStr(ctx.userDoc(), "username"),
                               "settings_updated", "settings", "", ctx.clientIp(), "")
            ctx.setFlash("success", "设置已保存")
        } catch (e: AppError) {
            ctx.setFlash("error", e.message)
        }
        ctx.redirect("/admin/settings", status: 303)
    }

    private func safeAssetUrl(value: String, label: String): String {
        let url = value.trimAscii()
        if (url.size == 0) {
            return ""
        }
        if (url.startsWith("/") && !url.contains("..") && !url.contains("\\")) {
            return truncateUtf8(url, 300)
        }
        if (isValidWebUrl(url)) {
            return truncateUtf8(url, 300)
        }
        throw AppError("validation", "${label}地址无效")
    }

    private func navText(): String {        let sb = StringBuilder()
        for (item in services.settings.navItems()) {
            sb.append(docStr(item, "label"))
            sb.append("|")
            sb.append(docStr(item, "url"))
            sb.append("\n")
        }
        sb.toString()
    }

    private func socialText(): String {
        let sb = StringBuilder()
        match (services.settings.json("social_links")) {
            case JArr(arr) =>
                for (item in arr.items) {
                    sb.append(docStr(item, "label"))
                    sb.append("|")
                    sb.append(docStr(item, "url"))
                    sb.append("\n")
                }
            case _ => ()
        }
        sb.toString()
    }

    private func navJson(text: String): String {
        let arr = JsonArray()
        for (line in text.split("\n")) {
            let trimmed = line.trimAscii()
            if (trimmed.size == 0) {
                continue
            }
            let parts = trimmed.split("|")
            if (parts.size < 2) {
                continue
            }
            let label = parts[0].trimAscii()
            let url = parts[1].trimAscii()
            if (label.size == 0 || url.size == 0) {
                continue
            }
            if (!(url.startsWith("/") || url.startsWith("http://") || url.startsWith("https://"))) {
                continue
            }
            let item = JsonObject()
            item.set("label", JStr(truncateUtf8(label, 30)))
            item.set("url", JStr(truncateUtf8(url, 300)))
            arr.add(JObj(item))
        }
        toJsonCompact(JArr(arr))
    }

    private func socialJson(text: String): String {
        let arr = JsonArray()
        for (line in text.split("\n")) {
            let trimmed = line.trimAscii()
            if (trimmed.size == 0) {
                continue
            }
            let parts = trimmed.split("|")
            if (parts.size < 2) {
                continue
            }
            let label = parts[0].trimAscii()
            let url = parts[1].trimAscii()
            if (label.size == 0 || !isValidWebUrl(url)) {
                continue
            }
            let item = JsonObject()
            item.set("label", JStr(truncateUtf8(label, 30)))
            item.set("url", JStr(truncateUtf8(url, 300)))
            arr.add(JObj(item))
        }
        toJsonCompact(JArr(arr))
    }

    // -----------------------------------------------------------------------
    // Theme
    // -----------------------------------------------------------------------

    public func themesPage(ctx: Ctx): HttpResponse {
        match (requireAdmin(ctx)) {
            case Some(response) => return response
            case None => ()
        }
        let activeTheme = services.settings.str("theme", def: services.config.theme)
        let themes = JsonArray()
        let dirs = listDir(services.config.themesDir)
        for (name in dirs) {
            let dir = services.config.themesDir + "/" + name
            if (!isDirectory(dir)) {
                continue
            }
            let item = JsonObject()
            item.set("name", JStr(name))
            item.set("active", JBool(name == activeTheme))
            item.set("title", JStr(name))
            item.set("version", JStr(""))
            item.set("author", JStr(""))
            item.set("description", JStr(""))
            if (exists(dir + "/theme.json")) {
                match (tryParseJson(readTextFile(dir + "/theme.json"))) {
                    case Some(manifest) =>
                        item.set("title", JStr(docStr(manifest, "name", def: name)))
                        item.set("version", JStr(docStr(manifest, "version")))
                        item.set("author", JStr(docStr(manifest, "author")))
                        item.set("description", JStr(docStr(manifest, "description")))
                    case None => ()
                }
            }
            themes.add(JObj(item))
        }
        let data = JsonObject()
        data.set("page_title", JStr("主题"))
        data.set("active", JStr("themes"))
        data.set("active_theme", JStr(activeTheme))
        data.set("themes", JArr(themes))
        ctx.renderAdminPage("themes.html", JObj(data))
    }

    public func themeActivate(ctx: Ctx): HttpResponse {
        match (requireAdmin(ctx)) {
            case Some(response) => return response
            case None => ()
        }
        let name = ctx.form("name").trimAscii()
        if (!isSafeName(name) || !isDirectory(services.config.themesDir + "/" + name)) {
            ctx.setFlash("error", "主题不存在")
            return ctx.redirect("/admin/themes", status: 303)
        }
        services.settings.setString("theme", name)
        services.reloadTheme()
        services.audit.log(docStr(ctx.userDoc(), "id"), docStr(ctx.userDoc(), "username"),
                           "theme_activated", "theme", name, ctx.clientIp(), "")
        ctx.setFlash("success", "主题已切换为 ${name}")
        ctx.redirect("/admin/themes", status: 303)
    }

    // -----------------------------------------------------------------------
    // Audit
    // -----------------------------------------------------------------------

    public func auditPage(ctx: Ctx): HttpResponse {
        match (requireAdmin(ctx)) {
            case Some(response) => return response
            case None => ()
        }
        let actor = ctx.query("actor")
        let action = ctx.query("action")
        let fromDate = ctx.query("from")
        let toDate = ctx.query("to")
        let text = ctx.query("text")
        let result = services.audit.search(ctx.pageNumber(), 50, actor: actor, action: action,
                                           fromDate: fromDate, toDate: toDate, text: text)
        let rows = JsonArray()
        for (entry in result.items) {
            let item = cloneDoc(entry)
            setField(item, "date", JStr(formatDateTimeSeconds(docInt(entry, "created_at"))))
            rows.add(item)
        }
        let query = auditQuery(actor, action, fromDate, toDate, text)
        let data = JsonObject()
        data.set("page_title", JStr("审计日志"))
        data.set("active", JStr("audit"))
        data.set("rows", JArr(rows))
        data.set("filter_actor", JStr(actor))
        data.set("filter_action", JStr(action))
        data.set("filter_from", JStr(fromDate))
        data.set("filter_to", JStr(toDate))
        data.set("filter_text", JStr(text))
        data.set("export_query", JStr(query))
        data.set("pagination", buildPagination(result.page, result.pages, result.total,
                                               "/admin/audit" + if (query.size > 0) { "?" + query } else { "" }, 50))
        ctx.renderAdminPage("audit.html", JObj(data))
    }

    public func auditExport(ctx: Ctx): HttpResponse {
        match (requireAdmin(ctx)) {
            case Some(response) => return response
            case None => ()
        }
        let result = services.audit.search(1, 5000, actor: ctx.query("actor"), action: ctx.query("action"),
                                           fromDate: ctx.query("from"), toDate: ctx.query("to"), text: ctx.query("text"))
        let sb = StringBuilder()
        sb.append("time,action,actor,target,ip,detail\n")
        for (entry in result.items) {
            sb.append(csvCell(formatDateTimeSeconds(docInt(entry, "created_at"))))
            sb.append(",")
            sb.append(csvCell(docStr(entry, "action")))
            sb.append(",")
            sb.append(csvCell(docStr(entry, "actor_name")))
            sb.append(",")
            sb.append(csvCell(docStr(entry, "target_type") + " " + docStr(entry, "target_id")))
            sb.append(",")
            sb.append(csvCell(docStr(entry, "ip")))
            sb.append(",")
            sb.append(csvCell(docStr(entry, "detail")))
            sb.append("\n")
        }
        let response = HttpResponse().bytes(sb.toString().toArray(), "text/csv; charset=utf-8")
        response.headers.set("content-disposition", "attachment; filename=\"cangmo-audit.csv\"")
        response
    }

    private func auditQuery(actor: String, action: String, fromDate: String, toDate: String, text: String): String {
        let parts = ArrayList<String>()
        if (actor.size > 0) { parts.add("actor=" + urlEncode(actor)) }
        if (action.size > 0) { parts.add("action=" + urlEncode(action)) }
        if (fromDate.size > 0) { parts.add("from=" + urlEncode(fromDate)) }
        if (toDate.size > 0) { parts.add("to=" + urlEncode(toDate)) }
        if (text.size > 0) { parts.add("text=" + urlEncode(text)) }
        String.join(parts.toArray(), delimiter: "&")
    }

    private func csvCell(value: String): String {
        "\"" + value.replace("\"", "\"\"") + "\""
    }

    // -----------------------------------------------------------------------
    // Tools
    // -----------------------------------------------------------------------

    public func toolsPage(ctx: Ctx): HttpResponse {
        match (requireAdmin(ctx)) {
            case Some(response) => return response
            case None => ()
        }
        let counts = services.stats.counts()
        let config = JsonObject()
        config.set("version", JStr(APP_VERSION))
        config.set("data_dir", JStr(services.config.dataDir))
        config.set("uploads_dir", JStr(services.config.uploadsDir()))
        config.set("backup_dir", JStr(services.config.backupDir()))
        config.set("pbkdf2_iterations", JInt(services.config.pbkdf2Iterations))
        config.set("wal_pending", JInt(services.store.pendingWalEntries()))
        config.set("theme", JStr(services.settings.str("theme", def: services.config.theme)))
        config.set("log_level", JInt(services.config.logLevel))
        let checks = JsonArray()
        let checksList = [
            ("默认主题首页", services.templates.hasTemplate("home.html")),
            ("后台登录模板", services.adminTemplates.hasTemplate("login.html")),
            ("文章编辑器", services.adminTemplates.hasTemplate("editor.html")),
            ("附件库", services.adminTemplates.hasTemplate("attachments.html")),
            ("备份中心", services.adminTemplates.hasTemplate("backups.html")),
            ("上传目录", isDirectory(services.config.uploadsDir())),
            ("备份目录", isDirectory(services.config.backupDir()))
        ]
        for ((label, ok) in checksList) {
            let item = JsonObject()
            item.set("label", JStr(label))
            item.set("ok", JBool(ok))
            checks.add(JObj(item))
        }
        let data = JsonObject()
        data.set("page_title", JStr("工具"))
        data.set("active", JStr("tools"))
        data.set("counts", counts)
        data.set("config", JObj(config))
        data.set("checks", JArr(checks))
        data.set("backup_count", JInt(services.backup.list().size))
        ctx.renderAdminPage("tools.html", JObj(data))
    }

    public func exportJson(ctx: Ctx): HttpResponse {
        match (requireAdmin(ctx)) {
            case Some(response) => return response
            case None => ()
        }
        let text = services.backup.exportJson(pretty: true)
        let response = HttpResponse().bytes(text.toArray(), "application/json; charset=utf-8")
        response.headers.set("content-disposition", "attachment; filename=\"cangmo-export.json\"")
        response
    }

    // -----------------------------------------------------------------------
    // Backup center
    // -----------------------------------------------------------------------

    public func backupsPage(ctx: Ctx): HttpResponse {
        match (requireAdmin(ctx)) {
            case Some(response) => return response
            case None => ()
        }
        let backups = JsonArray()
        var totalBytes: Int64 = 0
        for (item in services.backup.list()) {
            let view = cloneDoc(item)
            let size = docInt(item, "size")
            totalBytes += size
            setField(view, "size_text", JStr(formatFileSize(size)))
            setField(view, "date", JStr(formatDateTime(docInt(item, "created_at"))))
            backups.add(view)
        }
        let data = JsonObject()
        data.set("page_title", JStr("备份"))
        data.set("active", JStr("backups"))
        data.set("backups", JArr(backups))
        data.set("backup_count", JInt(backups.items.size))
        data.set("total_size", JStr(formatFileSize(totalBytes)))
        data.set("backup_dir", JStr(services.config.backupDir()))
        data.set("backup_auto", JBool(services.settings.bool("backup_auto", def: false)))
        data.set("backup_interval", JInt(services.settings.int("backup_interval_hours", def: 24)))
        data.set("backup_keep", JInt(services.settings.int("backup_keep", def: 7)))
        data.set("backup_encrypt", JBool(services.settings.bool("backup_encrypt", def: false)))
        data.set("backup_last", JStr(if (services.settings.int("backup_last_at", def: 0) > 0) {
            formatDateTime(services.settings.int("backup_last_at", def: 0))
        } else {
            "尚未执行"
        }))
        data.set("counts", services.stats.counts())
        ctx.renderAdminPage("backups.html", JObj(data))
    }

    public func backupAutoSave(ctx: Ctx): HttpResponse {
        match (requireAdmin(ctx)) {
            case Some(response) => return response
            case None => ()
        }
        services.settings.setBool("backup_auto", ctx.form("backup_auto") == "on")
        services.settings.setInt("backup_interval_hours", clampInt(ctx.form("backup_interval_hours"), 1, 720, 24))
        services.settings.setInt("backup_keep", clampInt(ctx.form("backup_keep"), 1, 100, 7))
        services.settings.setBool("backup_encrypt", ctx.form("backup_encrypt") == "on")
        ctx.setFlash("success", "自动备份设置已保存")
        ctx.redirect("/admin/backups", status: 303)
    }

    public func backupAction(ctx: Ctx): HttpResponse {
        match (requireAdmin(ctx)) {
            case Some(response) => return response
            case None => ()
        }
        let action = ctx.form("action")
        try {
            if (action == "create") {
                let result = services.backup.createBackup(ctx.form("label"), encrypt: services.settings.bool("backup_encrypt", def: false))
                services.audit.log(docStr(ctx.userDoc(), "id"), docStr(ctx.userDoc(), "username"),
                                   "backup_created", "backup", docStr(result, "name"), ctx.clientIp(), "")
                ctx.setFlash("success", "备份已创建：${docStr(result, "name")}")
            } else if (action == "delete") {
                services.backup.deleteBackup(ctx.form("name"))
                ctx.setFlash("success", "备份已删除")
            } else if (action == "restore" || action == "restore_name") {
                if (ctx.form("confirm") != "RESTORE") {
                    throw AppError("validation", "请输入 RESTORE 以确认恢复操作")
                }
                let text = if (action == "restore_name") {
                    let name = ctx.form("name")
                    match (services.backup.readBackup(name)) {
                        case Some(value) => value
                        case None => throw AppError("not_found", "备份不存在")
                    }
                } else {
                    ctx.req.parseForm()
                    if (ctx.req.files.size == 0) {
                        throw AppError("validation", "请选择备份 JSON 文件")
                    }
                    try {
                        String.fromUtf8(ctx.req.files[0].data)
                    } catch (e: Exception) {
                        throw AppError("validation", "备份文件编码无效")
                    }
                }
                let count = services.backup.restore(text)
                services.audit.log(docStr(ctx.userDoc(), "id"), docStr(ctx.userDoc(), "username"),
                                   "backup_restored", "backup", ctx.form("name"), ctx.clientIp(), "${count} docs")
                ctx.setFlash("success", "数据已恢复（${count} 个文档），请重新登录")
                return ctx.redirect("/admin/login", status: 303)
            } else {
                throw AppError("validation", "无效操作")
            }
        } catch (e: AppError) {
            ctx.setFlash("error", e.message)
        } catch (e: Exception) {
            services.logger.error("backup", e.message)
            ctx.setFlash("error", "操作失败：${e.message}")
        }
        ctx.redirect("/admin/backups", status: 303)
    }

    public func backupDownload(ctx: Ctx): HttpResponse {
        match (requireAdmin(ctx)) {
            case Some(response) => return response
            case None => ()
        }
        let name = ctx.query("name")
        let text = match (services.backup.readBackup(name)) {
            case Some(value) => value
            case None => return errorPage(ctx, 404, "备份不存在")
        }
        let response = HttpResponse().bytes(text.toArray(), "application/json; charset=utf-8")
        response.headers.set("content-disposition", "attachment; filename=\"${sanitizeFilename(name)}\"")
        response
    }

    // -----------------------------------------------------------------------
    // Profile
    // -----------------------------------------------------------------------

    public func profilePage(ctx: Ctx): HttpResponse {
        match (guard(ctx)) {
            case Some(response) => return response
            case None => ()
        }
        let tokens = JsonArray()
        for (token in services.auth.listApiTokens(docStr(ctx.userDoc(), "id"))) {
            let view = cloneDoc(token)
            setField(view, "created", JStr(formatDate(docInt(token, "created_at"))))
            setField(view, "last_used", JStr(formatDateTime(docInt(token, "last_used_at"))))
            setField(view, "scopes_text", JStr(String.join(docStrings(token, "scopes"), delimiter: ", ")))
            setField(view, "expires_text", JStr(if (docInt(token, "expires_at") > 0) { formatDate(docInt(token, "expires_at")) } else { "永不过期" }))
            setField(view, "last_ip", JStr(docStr(token, "last_used_ip")))
            tokens.add(view)
        }
        let data = JsonObject()
        data.set("page_title", JStr("个人资料"))
        data.set("active", JStr(""))
        data.set("profile", ctx.userDoc())
        data.set("tokens", JArr(tokens))
        let sessions = JsonArray()
        for (session in services.auth.listSessions(docStr(ctx.userDoc(), "id"))) {
            let view = cloneDoc(session)
            let current = docStr(session, "id") == ctx.session.id
            setField(view, "current", JBool(current))
            setField(view, "created", JStr(formatDateTime(docInt(session, "created_at"))))
            setField(view, "last_seen", JStr(formatDateTime(docInt(session, "last_seen_at"))))
            setField(view, "expires", JStr(formatDate(docInt(session, "expires_at"))))
            sessions.add(view)
        }
        data.set("sessions", JArr(sessions))
        data.set("totp_enabled", JBool(services.auth.totpEnabled(docStr(ctx.userDoc(), "id"))))
        ctx.renderAdminPage("profile.html", JObj(data))
    }

    public func totpSetupPage(ctx: Ctx): HttpResponse {
        match (guard(ctx)) {
            case Some(response) => return response
            case None => ()
        }
        let userId = docStr(ctx.userDoc(), "id")
        if (services.auth.totpEnabled(userId)) {
            ctx.setFlash("error", "两步验证已启用")
            return ctx.redirect("/admin/profile", status: 303)
        }
        let setup = services.auth.startTotpSetup(userId)
        let data = JsonObject()
        data.set("page_title", JStr("启用两步验证"))
        data.set("active", JStr(""))
        data.set("secret", JStr(docStr(setup, "secret")))
        data.set("uri", JStr(docStr(setup, "uri")))
        ctx.renderAdminPage("totp.html", JObj(data))
    }

    public func totpEnable(ctx: Ctx): HttpResponse {
        match (guard(ctx)) {
            case Some(response) => return response
            case None => ()
        }
        try {
            let codes = services.auth.enableTotp(docStr(ctx.userDoc(), "id"), ctx.form("code"))
            ctx.setFlash("success", "两步验证已启用。恢复码（只显示一次）：" + String.join(codes, delimiter: "、"))
        } catch (e: AppError) {
            ctx.setFlash("error", e.message)
            return ctx.redirect("/admin/profile/totp", status: 303)
        }
        ctx.redirect("/admin/profile", status: 303)
    }

    public func totpDisable(ctx: Ctx): HttpResponse {
        match (guard(ctx)) {
            case Some(response) => return response
            case None => ()
        }
        try {
            services.auth.disableTotp(docStr(ctx.userDoc(), "id"), ctx.form("password"))
            ctx.setFlash("success", "两步验证已关闭")
        } catch (e: AppError) {
            ctx.setFlash("error", e.message)
        }
        ctx.redirect("/admin/profile", status: 303)
    }

    public func sessionRevoke(ctx: Ctx): HttpResponse {
        match (guard(ctx)) {
            case Some(response) => return response
            case None => ()
        }
        let id = ctx.form("id")
        if (id == ctx.session.id) {
            ctx.setFlash("error", "不能撤销当前会话")
            return ctx.redirect("/admin/profile", status: 303)
        }
        services.auth.revokeSessionById(id, docStr(ctx.userDoc(), "id"))
        ctx.setFlash("success", "会话已撤销")
        ctx.redirect("/admin/profile", status: 303)
    }

    public func profileSave(ctx: Ctx): HttpResponse {
        match (guard(ctx)) {
            case Some(response) => return response
            case None => ()
        }
        try {
            let avatar = ctx.form("avatar").trimAscii()
            if (avatar.size > 0 && !avatar.startsWith("/media/") && !isValidWebUrl(avatar)) {
                throw AppError("validation", "头像地址需为附件库链接或 http(s) 地址")
            }
            if (avatar.startsWith("/media/") && services.media.pathForUrl(avatar).isNone()) {
                throw AppError("validation", "头像附件不存在")
            }
            services.auth.updateProfile(docStr(ctx.userDoc(), "id"), ctx.form("display_name"),
                                        ctx.form("email"), ctx.form("bio"), avatar: avatar)
            ctx.setFlash("success", "个人资料已保存")
        } catch (e: AppError) {
            ctx.setFlash("error", e.message)
        }
        ctx.redirect("/admin/profile", status: 303)
    }

    public func passwordSave(ctx: Ctx): HttpResponse {
        match (guard(ctx)) {
            case Some(response) => return response
            case None => ()
        }
        try {
            services.auth.changePassword(docStr(ctx.userDoc(), "id"), ctx.form("old_password"),
                                         ctx.form("new_password"), ctx.session.id)
            ctx.setFlash("success", "密码已修改，其他会话已退出")
        } catch (e: AppError) {
            ctx.setFlash("error", e.message)
        }
        ctx.redirect("/admin/profile", status: 303)
    }

    public func apiTokenCreate(ctx: Ctx): HttpResponse {
        match (guard(ctx)) {
            case Some(response) => return response
            case None => ()
        }
        if (!ctx.isAdmin()) {
            ctx.setFlash("error", "只有管理员可以创建 API 令牌")
            return ctx.redirect("/admin/profile", status: 303)
        }
        let scopes = ArrayList<String>()
        for (scope in ctx.req.formValues("scopes")) {
            scopes.add(scope)
        }
        if (scopes.size == 0) {
            scopes.add("admin")
        }
        let days = clampInt(ctx.form("expires_days"), 0, 3650, 0)
        let expiresAt = if (days > 0) { nowSeconds() + days * 86400 } else { 0 }
        let ips = ArrayList<String>()
        for (part in ctx.form("allowed_ips").replace("，", ",").replace("\n", ",").split(",")) {
            let ip = part.trimAscii()
            if (ip.size > 0 && ip.size <= 64) {
                ips.add(ip)
            }
        }
        let token = services.auth.createApiToken(docStr(ctx.userDoc(), "id"),
                                                 requireText(ctx.form("name"), "令牌名称", 1, 80),
                                                 scopes: scopes.toArray(), expiresAt: expiresAt,
                                                 allowedIps: ips.toArray())
        ctx.setFlash("success", "新令牌（仅显示一次）：${token}")
        ctx.redirect("/admin/profile", status: 303)
    }

    public func apiTokenRevoke(ctx: Ctx): HttpResponse {
        match (guard(ctx)) {
            case Some(response) => return response
            case None => ()
        }
        services.auth.revokeApiToken(ctx.form("id"), docStr(ctx.userDoc(), "id"))
        ctx.setFlash("success", "令牌已撤销")
        ctx.redirect("/admin/profile", status: 303)
    }

    // -----------------------------------------------------------------------
    // Preview
    // -----------------------------------------------------------------------

    public func preview(ctx: Ctx): HttpResponse {
        match (guard(ctx)) {
            case Some(response) => return response
            case None => ()
        }
        let body = try {
            String.fromUtf8(ctx.req.body)
        } catch (e: Exception) {
            throw AppError("validation", "预览内容编码无效")
        }
        let parsed = match (tryParseJson(body)) {
            case Some(value) => value
            case None => throw AppError("validation", "预览请求格式错误")
        }
        let markdown = getString(parsed, "markdown")
        let result = MarkdownRenderer(allowRawHtml: services.config.allowRawHtml).render(markdown)
        let headings = JsonArray()
        for (heading in result.headings) {
            let item = JsonObject()
            item.set("level", JInt(heading.level))
            item.set("text", JStr(heading.text))
            item.set("id", JStr(heading.id))
            headings.add(JObj(item))
        }
        let data = jsonObjectOf([("html", jstr(result.html)), ("headings", JArr(headings))])
        HttpResponse().json(data)
    }

    // -----------------------------------------------------------------------
    // Guards / errors
    // -----------------------------------------------------------------------

    private func guard(ctx: Ctx): ?HttpResponse {
        if (!ctx.loggedIn()) {
            return Some(ctx.redirect("/admin/login?next=" + urlEncode(ctx.req.path), status: 303))
        }
        if (ctx.session.pending2fa) {
            return Some(ctx.redirect("/admin/2fa", status: 303))
        }
        if (!ctx.isStaff()) {
            return Some(errorPage(ctx, 403, "你的账户没有后台访问权限"))
        }
        None
    }

    private func requireAdmin(ctx: Ctx): ?HttpResponse {
        match (guard(ctx)) {
            case Some(response) => return Some(response)
            case None => ()
        }
        if (!ctx.isAdmin()) {
            return Some(errorPage(ctx, 403, "只有系统管理员可以访问此页面"))
        }
        None
    }

    private func errorPage(ctx: Ctx, status: Int64, message: String): HttpResponse {
        let data = JsonObject()
        data.set("page_title", JStr("出错了"))
        data.set("status", JInt(status))
        data.set("message", JStr(message))
        ctx.renderAdminPage("error.html", JObj(data), status: status)
    }
}

func mediaKindOfService(item: JsonValue): String {
    let mime = docStr(item, "mime").toAsciiLower()
    if (mime.startsWith("audio/")) {
        return "audio"
    }
    if (mime.startsWith("video/")) {
        return "video"
    }
    if (mime == "application/pdf") {
        return "document"
    }
    let kind = docStr(item, "kind")
    if (kind == "audio" || kind == "video" || kind == "document") {
        return kind
    }
    "image"
}

func attachmentJsonError(message: String): HttpResponse {
    let data = jsonObjectOf([("ok", JBool(false)), ("error", JStr(message))])
    HttpResponse().json(data, status: 400)
}

func safeNext(value: String): String {    if (value.size == 0 || value.size > 500) {
        return ""
    }
    if (!value.startsWith("/") || value.startsWith("//")) {
        return ""
    }
    if (value.contains("\r") || value.contains("\n")) {
        return ""
    }
    value
}

func isChecked(ctx: Ctx, name: String): Bool {
    let value = ctx.form(name).trimAscii().toAsciiLower()
    value == "on" || value == "1" || value == "true" || value == "yes"
}

func splitTags(text: String): Array<String> {
    let out = ArrayList<String>()
    for (part in text.split(",")) {
        let trimmed = part.trimAscii()
        if (trimmed.size > 0 && trimmed.size <= 40 && !out.contains(trimmed)) {
            out.add(trimmed)
        }
    }
    out.toArray()
}

func parseDateTimeInput(text: String): Int64 {
    let value = text.trimAscii()
    if (value.size == 0) {
        return 0
    }
    // <input type="datetime-local"> submits "yyyy-MM-ddTHH:mm"; Cangjie's
    // DateTime.parse pattern treats a bare T as a format error, so normalize
    // it to a space and use the space-separated pattern.
    let normalized = value.replace("T", " ")
    let patterns = ["yyyy-MM-dd HH:mm", "yyyy-MM-dd HH:mm:ss"]
    for (pattern in patterns) {
        try {
            let dt = DateTime.parse(normalized, pattern)
            return dt.toUnixTimeStamp().toSeconds()
        } catch (e: Exception) {}
    }
    throw AppError("validation", "定时发布时间格式无效")
}

func requireText(value: String, fieldName: String, minLength: Int64, maxLength: Int64): String {
    let trimmed = value.trimAscii()
    if (trimmed.size < minLength || trimmed.size > maxLength) {
        throw AppError("validation", "${fieldName}长度需在 ${minLength}-${maxLength} 字之间")
    }
    trimmed
}

func clampInt(value: String, minValue: Int64, maxValue: Int64, fallback: Int64): Int64 {
    let parsed = parseIntOr(value, fallback)
    if (parsed < minValue) {
        return minValue
    }
    if (parsed > maxValue) {
        return maxValue
    }
    parsed
}

func safeColor(value: String): String {
    let text = value.trimAscii()
    if (text.size != 7 || text[0] != 0x23) {
        return "#2f6f4e"
    }
    for (i in 1..7) {
        let b = text.toArray()[i]
        let ok = (b >= 0x30 && b <= 0x39) || (b >= 0x61 && b <= 0x66) || (b >= 0x41 && b <= 0x46)
        if (!ok) {
            return "#2f6f4e"
        }
    }
    text
}
