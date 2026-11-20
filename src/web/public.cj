/**
 * Cangmo - public site handlers.
 */
package cangmo.web

import cangmo.core.*
import cangmo.http.*
import cangmo.json.*
import cangmo.service.*
import std.collection.*
import std.time.*

public class PublicSite {
    private let services: Services

    public init(services: Services) {
        this.services = services
    }

    public func home(ctx: Ctx): HttpResponse {
        let page = ctx.pageNumber()
        let pageSize = services.settings.int("posts_per_page", def: services.config.postsPerPage)
        let query = PostQuery()
        query.status = STATUS_PUBLISHED
        query.postType = "post"
        let result = services.posts.list(query, page, pageSize)
        let cards = ArrayList<JsonValue>()
        let featured = ArrayList<JsonValue>()
        let featuredIds = HashMap<String, Bool>()
        for (post in result.items) {
            if (docBool(post, "featured") && featured.size < 3 && page == 1) {
                featured.add(postCard(services, post))
                featuredIds[docStr(post, "id")] = true
            }
        }
        for (post in result.items) {
            if (featuredIds.contains(docStr(post, "id"))) {
                continue
            }
            cards.add(postCard(services, post))
        }
        let data = JsonObject()
        data.set("page_title", JStr(services.settings.str("site_title")))
        data.set("posts", jsonArrayFrom(cards.toArray()))
        data.set("featured", jsonArrayFrom(featured.toArray()))
        data.set("pagination", buildPagination(result.page, result.pages, result.total, "/", pageSize))
        data.set("categories", sidebarCategories())
        data.set("tags", sidebarTags())
        data.set("archives", sidebarArchives())
        data.set("meta_description", JStr(services.settings.str("site_description")))
        ctx.renderPage("home.html", JObj(data))
    }

    public func postDetail(ctx: Ctx): HttpResponse {
        let slug = ctx.param("slug")
        let post = match (services.posts.getPublishedBySlug(slug, postType: "post")) {
            case Some(value) => value
            case None => return notFound(ctx)
        }
        services.stats.recordView(docStr(post, "id"))
        let card = postCard(services, post)
        setField(card, "content_html", JStr(docStr(post, "content_html")))
        setField(card, "headings", match (post.get("headings")) { case Some(value) => value; case None => jarr() })
        setField(card, "allow_comments", JBool(docBool(post, "allow_comments", def: true)))
        setField(card, "seo_title", JStr(docStr(post, "seo_title")))
        setField(card, "seo_description", JStr(docStr(post, "seo_description")))
        let comments = commentThread(docStr(post, "id"))
        let commentCount = comments.size
        let related = ArrayList<JsonValue>()
        if (services.settings.bool("show_related_posts", def: true)) {
            for (item in services.posts.related(post, 3)) {
                related.add(postCard(services, item))
            }
        }
        let (prevPost, nextPost) = neighborPosts(post)
        let data = JsonObject()
        data.set("page_title", JStr(docStr(post, "seo_title", def: docStr(post, "title"))))
        data.set("meta_description", JStr(docStr(post, "seo_description", def: docStr(post, "summary"))))
        data.set("post", card)
        data.set("comments", jsonArrayFrom(comments))
        data.set("comment_count", JInt(commentCount))
        data.set("comments_enabled", JBool(docBool(post, "allow_comments", def: true) &&
                                           services.settings.bool("comment_enabled", def: true)))
        data.set("related", jsonArrayFrom(related.toArray()))
        data.set("prev_post", prevPost)
        data.set("next_post", nextPost)
        data.set("categories", sidebarCategories())
        data.set("tags", sidebarTags())
        data.set("archives", sidebarArchives())
        data.set("canonical", JStr(ctx.siteUrl(postUrl(post))))
        ctx.renderPage("post.html", JObj(data))
    }

    public func pageDetail(ctx: Ctx): HttpResponse {
        let slug = ctx.param("slug")
        let page = match (services.posts.getPublishedBySlug(slug, postType: "page")) {
            case Some(value) => value
            case None => return notFound(ctx)
        }
        let card = postCard(services, page)
        setField(card, "content_html", JStr(docStr(page, "content_html")))
        setField(card, "headings", match (page.get("headings")) { case Some(value) => value; case None => jarr() })
        let data = JsonObject()
        data.set("page_title", JStr(docStr(page, "seo_title", def: docStr(page, "title"))))
        data.set("meta_description", JStr(docStr(page, "seo_description", def: docStr(page, "summary"))))
        data.set("page", card)
        data.set("canonical", JStr(ctx.siteUrl(postUrl(page))))
        ctx.renderPage("page.html", JObj(data))
    }

    public func categoryPage(ctx: Ctx): HttpResponse {
        let slug = ctx.param("slug")
        let category = match (services.taxonomy.categoryBySlug(slug)) {
            case Some(value) => value
            case None => return notFound(ctx)
        }
        let page = ctx.pageNumber()
        let pageSize = services.settings.int("posts_per_page", def: services.config.postsPerPage)
        let query = PostQuery()
        query.status = STATUS_PUBLISHED
        query.categoryId = docStr(category, "id")
        let result = services.posts.list(query, page, pageSize)
        let data = JsonObject()
        data.set("list_title", JStr("分类：" + docStr(category, "name")))
        data.set("list_description", JStr(docStr(category, "description")))
        data.set("list_kind", JStr("category"))
        data.set("posts", cardsOf(result.items))
        data.set("pagination", buildPagination(result.page, result.pages, result.total,
                                               "/categories/" + docStr(category, "slug"), pageSize))
        data.set("categories", sidebarCategories())
        data.set("tags", sidebarTags())
        data.set("archives", sidebarArchives())
        data.set("page_title", JStr(docStr(category, "name")))
        data.set("canonical", JStr(ctx.siteUrl("/categories/" + slug)))
        ctx.renderPage("list.html", JObj(data))
    }

    public func tagPage(ctx: Ctx): HttpResponse {
        let slug = ctx.param("slug")
        let tag = match (services.taxonomy.tagBySlug(slug)) {
            case Some(value) => value
            case None => return notFound(ctx)
        }
        let page = ctx.pageNumber()
        let pageSize = services.settings.int("posts_per_page", def: services.config.postsPerPage)
        let query = PostQuery()
        query.status = STATUS_PUBLISHED
        query.tagId = docStr(tag, "id")
        let result = services.posts.list(query, page, pageSize)
        let data = JsonObject()
        data.set("list_title", JStr("标签：" + docStr(tag, "name")))
        data.set("list_description", JStr(""))
        data.set("list_kind", JStr("tag"))
        data.set("posts", cardsOf(result.items))
        data.set("pagination", buildPagination(result.page, result.pages, result.total,
                                               "/tags/" + docStr(tag, "slug"), pageSize))
        data.set("categories", sidebarCategories())
        data.set("tags", sidebarTags())
        data.set("archives", sidebarArchives())
        data.set("page_title", JStr(docStr(tag, "name")))
        data.set("canonical", JStr(ctx.siteUrl("/tags/" + slug)))
        ctx.renderPage("list.html", JObj(data))
    }

    public func archivePage(ctx: Ctx): HttpResponse {
        let year = ctx.param("year")
        let month = ctx.param("month")
        let all = services.posts.publishedPosts()
        let selected = ArrayList<JsonValue>()
        let prefix = if (year.size > 0 && month.size > 0) {
            year + "-" + month
        } else if (year.size > 0) {
            year
        } else {
            ""
        }
        for (post in all) {
            let key = formatTime(docInt(post, "published_at"), "yyyy-MM")
            if (prefix.size == 0 || key.startsWith(prefix)) {
                selected.add(post)
            }
        }
        let groups = JsonArray()
        for ((label, count) in services.posts.archiveCounts()) {
            let item = JsonObject()
            item.set("label", JStr(label))
            item.set("count", JInt(count))
            let parts = label.split("-")
            let y = if (parts.size > 0) { parts[0] } else { "" }
            let m = if (parts.size > 1) { parts[1] } else { "" }
            item.set("url", JStr("/archive/" + y + "/" + m))
            groups.add(JObj(item))
        }
        let data = JsonObject()
        data.set("page_title", JStr("归档"))
        data.set("archive_groups", JArr(groups))
        data.set("posts", cardsOf(selected.toArray()))
        data.set("list_title", JStr(if (prefix.size > 0) { "归档：" + prefix } else { "全部文章" }))
        data.set("list_kind", JStr("archive"))
        data.set("categories", sidebarCategories())
        data.set("tags", sidebarTags())
        data.set("archives", sidebarArchives())
        ctx.renderPage("archive.html", JObj(data))
    }

    public func searchPage(ctx: Ctx): HttpResponse {
        let queryText = ctx.query("q").trimAscii()
        let results = if (queryText.size > 0) { services.search.search(queryText, 50) } else { Array<JsonValue>(0, repeat: JNull) }
        let data = JsonObject()
        data.set("page_title", JStr("搜索：" + queryText))
        data.set("query", JStr(queryText))
        data.set("results", cardsOf(results))
        data.set("result_count", JInt(results.size))
        data.set("categories", sidebarCategories())
        data.set("tags", sidebarTags())
        data.set("archives", sidebarArchives())
        ctx.renderPage("search.html", JObj(data))
    }

    public func commentSubmit(ctx: Ctx): HttpResponse {
        let postId = ctx.form("post_id")
        let post = match (services.store.get(COL_POSTS, postId)) {
            case Some(value) => value
            case None => return notFound(ctx)
        }
        let target = postUrl(post)
        if (docStr(post, "status") != STATUS_PUBLISHED) {
            return notFound(ctx)
        }
        // Honeypot: bots fill every input; humans never see this one.
        if (ctx.form("website").size > 0) {
            ctx.setFlash("success", "评论已提交")
            return ctx.redirect(target + "#comments", status: 303)
        }
        try {
            services.comments.create(post, ctx.form("parent_id"), ctx.form("name"), ctx.form("email"),
                                     ctx.form("url"), ctx.form("content"), ctx.clientIp(),
                                     ctx.req.header("user-agent"))
            let moderation = services.settings.bool("comment_moderation", def: true)
            if (moderation) {
                ctx.setFlash("success", "评论已提交，审核通过后会显示")
            } else {
                ctx.setFlash("success", "评论已发布")
            }
        } catch (e: AppError) {
            ctx.setFlash("error", e.message)
        } catch (e: Exception) {
            services.logger.error("comment", e.message)
            ctx.setFlash("error", "评论提交失败，请稍后再试")
        }
        ctx.redirect(target + "#comments", status: 303)
    }

    public func feed(ctx: Ctx): HttpResponse {
        let posts = services.posts.publishedPosts()
        let items = ArrayList<JsonValue>()
        var count: Int64 = 0
        for (post in posts) {
            if (count >= 20) {
                break
            }
            items.add(postCard(services, post))
            count += 1
        }
        let data = JsonObject()
        let site = JsonObject()
        site.set("title", JStr(services.settings.str("site_title")))
        site.set("subtitle", JStr(services.settings.str("site_subtitle")))
        site.set("description", JStr(services.settings.str("site_description")))
        site.set("url", JStr(services.settings.str("site_url", def: services.config.siteUrl)))
        let lastBuild = formatUtcRfc1123(nowSeconds())
        data.set("site", JObj(site))
        data.set("posts", jsonArrayFrom(items.toArray()))
        data.set("last_build", JStr(lastBuild))
        let xml = services.templates.render("feed.xml", JObj(data))
        HttpResponse().bytes(xml.toArray(), "application/rss+xml; charset=utf-8")
    }

    public func sitemap(ctx: Ctx): HttpResponse {
        let entries = JsonArray()
        let base = services.settings.str("site_url", def: services.config.siteUrl)
        let add = { path: String, lastmod: Int64 =>
            let item = JsonObject()
            item.set("loc", JStr(base + path))
            item.set("lastmod", JStr(formatDate(lastmod)))
            entries.add(JObj(item))
        }
        add("/", nowSeconds())
        for (post in services.posts.publishedPosts()) {
            add(postUrl(post), docInt(post, "updated_at"))
        }
        for (page in services.posts.publishedPages()) {
            add(postUrl(page), docInt(page, "updated_at"))
        }
        for (category in services.taxonomy.listCategories()) {
            add(categoryUrl(category), docInt(category, "created_at"))
        }
        for (tag in services.taxonomy.listTags()) {
            add(tagUrl(tag), docInt(tag, "created_at"))
        }
        let data = JsonObject()
        data.set("entries", JArr(entries))
        let xml = services.templates.render("sitemap.xml", JObj(data))
        HttpResponse().bytes(xml.toArray(), "application/xml; charset=utf-8")
    }

    public func robots(ctx: Ctx): HttpResponse {
        let base = services.settings.str("site_url", def: services.config.siteUrl)
        let text = "User-agent: *\nDisallow: /admin/\nDisallow: /api/\nDisallow: /search\n\nSitemap: ${base}/sitemap.xml\n"
        HttpResponse().bytes(text.toArray(), "text/plain; charset=utf-8")
    }

    public func healthz(ctx: Ctx): HttpResponse {
        let data = jsonObjectOf([("status", jstr("ok"))])
        let response = HttpResponse().json(data)
        response.headers.set("cache-control", "no-store")
        response
    }

    public func manifest(ctx: Ctx): HttpResponse {
        let base = services.settings.str("site_url", def: services.config.siteUrl)
        let data = jsonObjectOf([
            ("name", jstr(services.settings.str("site_title"))),
            ("short_name", jstr(services.settings.str("site_title"))),
            ("start_url", jstr("/")),
            ("scope", jstr("/")),
            ("display", jstr("standalone")),
            ("background_color", jstr("#ffffff")),
            ("theme_color", jstr(services.settings.str("theme_accent", def: "#2f6f4e"))),
            ("icons", jsonArrayOf([
                jsonObjectOf([("src", jstr("/static/icon.svg")), ("sizes", jstr("any")), ("type", jstr("image/svg+xml"))])
            ]))
        ])
        HttpResponse().json(data)
    }

    public func notFound(ctx: Ctx): HttpResponse {
        let data = JsonObject()
        data.set("page_title", JStr("页面不存在"))
        data.set("status", JInt(404))
        data.set("message", JStr("你访问的页面不存在，可能已被移动或删除。"))
        let response = HttpResponse().html(ctx.render("404.html", JObj(data)), status: 404)
        response
    }

    public func errorPage(ctx: Ctx, status: Int64, message: String): HttpResponse {
        let data = JsonObject()
        data.set("page_title", JStr("出错了"))
        data.set("status", JInt(status))
        data.set("message", JStr(message))
        let response = HttpResponse().html(ctx.render("error.html", JObj(data)), status: status)
        response
    }

    // -----------------------------------------------------------------------
    // Shared view data
    // -----------------------------------------------------------------------

    private func cardsOf(items: Array<JsonValue>): JsonValue {
        let arr = JsonArray()
        for (item in items) {
            arr.add(postCard(services, item))
        }
        JArr(arr)
    }

    private func sidebarCategories(): JsonValue {
        let arr = JsonArray()
        for (category in services.taxonomy.listCategories()) {
            let item = JsonObject()
            item.set("name", JStr(docStr(category, "name")))
            item.set("slug", JStr(docStr(category, "slug")))
            item.set("url", JStr(categoryUrl(category)))
            var count: Int64 = 0
            for (post in services.store.list(COL_POSTS)) {
                if (docStr(post, "type") == "post" && docStr(post, "status") == STATUS_PUBLISHED &&
                    docStr(post, "category_id") == docStr(category, "id")) {
                    count += 1
                }
            }
            item.set("count", JInt(count))
            arr.add(JObj(item))
        }
        JArr(arr)
    }

    private func sidebarTags(): JsonValue {
        let arr = JsonArray()
        for (tag in services.taxonomy.listTags()) {
            let item = JsonObject()
            item.set("name", JStr(docStr(tag, "name")))
            item.set("url", JStr(tagUrl(tag)))
            item.set("count", JInt(docInt(tag, "post_count")))
            arr.add(JObj(item))
        }
        JArr(arr)
    }

    private func sidebarArchives(): JsonValue {
        let arr = JsonArray()
        for ((label, count) in services.posts.archiveCounts()) {
            let item = JsonObject()
            item.set("label", JStr(label))
            item.set("count", JInt(count))
            let parts = label.split("-")
            item.set("url", JStr("/archive/" + parts[0] + "/" + parts[1]))
            arr.add(JObj(item))
        }
        JArr(arr)
    }

    private func commentThread(postId: String): Array<JsonValue> {
        let comments = services.comments.listForPost(postId)
        let depths = HashMap<String, Int64>()
        let views = ArrayList<JsonValue>()
        for (comment in comments) {
            let id = docStr(comment, "id")
            let parentId = docStr(comment, "parent_id")
            var depth: Int64 = 0
            if (parentId.size > 0) {
                depth = (depths.get(parentId) ?? 0) + 1
            }
            if (depth > 4) {
                depth = 4
            }
            depths[id] = depth
        }
        for (comment in comments) {
            let id = docStr(comment, "id")
            let view = commentView(comment, None, depths.get(id) ?? 0)
            views.add(view)
        }
        views.toArray()
    }

    private func neighborPosts(post: JsonValue): (JsonValue, JsonValue) {
        let all = services.posts.publishedPosts()
        var previous: JsonValue = JNull
        var next: JsonValue = JNull
        var found = false
        for (i in 0..all.size) {
            if (found) {
                next = postCard(services, all[i])
                break
            }
            if (docStr(all[i], "id") == docStr(post, "id")) {
                found = true
            } else {
                previous = postCard(services, all[i])
            }
        }
        (previous, next)
    }
}
