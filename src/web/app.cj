/**
 * Cangmo - web application: routing, session/CSRF handling, static files,
 * setup wizard and error pages.
 */
package cangmo.web

import cangmo.core.*
import cangmo.http.*
import cangmo.json.*
import cangmo.markdown.*
import cangmo.service.*
import std.collection.*
import std.env.*
import std.fs.*
import std.time.*

public class WebApp {
    private let services: Services
    private let router: WebRouter
    private let publicSite: PublicSite
    private let adminSite: AdminSite
    private let apiSite: ApiSite

    public init(config: Config) {
        this.services = Services(config)
        this.publicSite = PublicSite(services)
        this.adminSite = AdminSite(services)
        this.apiSite = ApiSite(services)
        this.router = WebRouter()
        registerRoutes()
    }

    public func serviceRegistry(): Services {
        services
    }

    public func setupToken(): String {
        services.setupToken
    }

    private func registerRoutes(): Unit {
        // Public site.
        router.get("/", { ctx: Ctx => publicSite.home(ctx) })
        router.get("/posts/:slug", { ctx: Ctx => publicSite.postDetail(ctx) })
        router.get("/pages/:slug", { ctx: Ctx => publicSite.pageDetail(ctx) })
        router.get("/categories/:slug", { ctx: Ctx => publicSite.categoryPage(ctx) })
        router.get("/tags/:slug", { ctx: Ctx => publicSite.tagPage(ctx) })
        router.get("/archive", { ctx: Ctx => publicSite.archivePage(ctx) })
        router.get("/archive/:year", { ctx: Ctx => publicSite.archivePage(ctx) })
        router.get("/archive/:year/:month", { ctx: Ctx => publicSite.archivePage(ctx) })
        router.get("/search", { ctx: Ctx => publicSite.searchPage(ctx) })
        router.post("/comments", { ctx: Ctx => publicSite.commentSubmit(ctx) })
        router.get("/feed.xml", { ctx: Ctx => publicSite.feed(ctx) })
        router.get("/rss.xml", { ctx: Ctx => publicSite.feed(ctx) })
        router.get("/sitemap.xml", { ctx: Ctx => publicSite.sitemap(ctx) })
        router.get("/robots.txt", { ctx: Ctx => publicSite.robots(ctx) })
        router.get("/healthz", { ctx: Ctx => publicSite.healthz(ctx) })
        router.get("/manifest.webmanifest", { ctx: Ctx => publicSite.manifest(ctx) })

        // Setup.
        router.get("/setup", { ctx: Ctx => setupPage(ctx) })
        router.post("/setup", { ctx: Ctx => setupSubmit(ctx) })

        // Admin.
        router.get("/admin/login", { ctx: Ctx => adminSite.loginPage(ctx) })
        router.post("/admin/login", { ctx: Ctx => adminSite.loginSubmit(ctx) })
        router.post("/admin/logout", { ctx: Ctx => adminSite.logout(ctx) })
        router.get("/admin", { ctx: Ctx => adminSite.dashboard(ctx) })
        router.get("/admin/posts", { ctx: Ctx => adminSite.postsList(ctx) })
        router.get("/admin/posts/new", { ctx: Ctx => adminSite.postNew(ctx) })
        router.get("/admin/posts/:id/edit", { ctx: Ctx => adminSite.postEdit(ctx) })
        router.post("/admin/posts/save", { ctx: Ctx => adminSite.postSave(ctx) })
        router.post("/admin/posts/bulk", { ctx: Ctx => adminSite.postsBulk(ctx) })
        router.post("/admin/posts/:id/action", { ctx: Ctx => adminSite.postAction(ctx) })
        router.post("/admin/posts/:id/duplicate", { ctx: Ctx => adminSite.postDuplicate(ctx) })
        router.get("/admin/posts/:id/drawer", { ctx: Ctx => adminSite.postDrawerData(ctx) })
        router.post("/admin/posts/:id/quick", { ctx: Ctx => adminSite.postQuickSave(ctx) })
        router.get("/admin/posts/:id/revisions/:rev", { ctx: Ctx => adminSite.postRevisionData(ctx) })
        router.post("/admin/posts/:id/revisions/:rev/restore", { ctx: Ctx => adminSite.postRevisionRestore(ctx) })
        router.get("/admin/categories", { ctx: Ctx => adminSite.categoriesPage(ctx) })
        router.post("/admin/categories/save", { ctx: Ctx => adminSite.categorySave(ctx) })
        router.post("/admin/categories/quick", { ctx: Ctx => adminSite.categoryQuick(ctx) })
        router.get("/admin/tags", { ctx: Ctx => adminSite.tagsPage(ctx) })
        router.post("/admin/tags/delete", { ctx: Ctx => adminSite.tagDelete(ctx) })
        router.get("/admin/comments", { ctx: Ctx => adminSite.commentsPage(ctx) })
        router.post("/admin/comments/bulk", { ctx: Ctx => adminSite.commentsBulk(ctx) })
        router.post("/admin/comments/:id/:action", { ctx: Ctx => adminSite.commentAction(ctx) })
        router.get("/admin/attachments", { ctx: Ctx => adminSite.attachmentsPage(ctx) })
        router.get("/admin/attachments/data", { ctx: Ctx => adminSite.attachmentsData(ctx) })
        router.post("/admin/attachments/upload", { ctx: Ctx => adminSite.attachmentsUpload(ctx) })
        router.post("/admin/attachments/:id/delete", { ctx: Ctx => adminSite.attachmentsDelete(ctx) })
        router.post("/admin/attachments/:id/rename", { ctx: Ctx => adminSite.attachmentsRename(ctx) })
        router.get("/admin/attachments/:id/usage", { ctx: Ctx => adminSite.attachmentsUsage(ctx) })
        // Legacy media URLs keep working through redirects/aliases.
        router.get("/admin/media", { ctx: Ctx => adminSite.mediaPage(ctx) })
        router.post("/admin/media/upload", { ctx: Ctx => adminSite.mediaUpload(ctx) })
        router.post("/admin/media/:id/delete", { ctx: Ctx => adminSite.mediaDelete(ctx) })
        router.get("/admin/users", { ctx: Ctx => adminSite.usersPage(ctx) })
        router.post("/admin/users/action", { ctx: Ctx => adminSite.userAction(ctx) })
        router.get("/admin/settings", { ctx: Ctx => adminSite.settingsPage(ctx) })
        router.post("/admin/settings/save", { ctx: Ctx => adminSite.settingsSave(ctx) })
        router.get("/admin/themes", { ctx: Ctx => adminSite.themesPage(ctx) })
        router.post("/admin/themes/activate", { ctx: Ctx => adminSite.themeActivate(ctx) })
        router.get("/admin/audit", { ctx: Ctx => adminSite.auditPage(ctx) })
        router.get("/admin/tools", { ctx: Ctx => adminSite.toolsPage(ctx) })
        router.get("/admin/tools/export", { ctx: Ctx => adminSite.exportJson(ctx) })
        router.get("/admin/import", { ctx: Ctx => adminSite.importPage(ctx) })
        router.post("/admin/import", { ctx: Ctx => adminSite.importSubmit(ctx) })
        router.get("/admin/backups", { ctx: Ctx => adminSite.backupsPage(ctx) })
        router.post("/admin/backups/action", { ctx: Ctx => adminSite.backupAction(ctx) })
        router.get("/admin/backups/download", { ctx: Ctx => adminSite.backupDownload(ctx) })
        // Legacy tool/backup URLs.
        router.post("/admin/tools/action", { ctx: Ctx => adminSite.backupAction(ctx) })
        router.get("/admin/tools/backup", { ctx: Ctx => adminSite.backupDownload(ctx) })
        router.get("/admin/profile", { ctx: Ctx => adminSite.profilePage(ctx) })
        router.post("/admin/profile/save", { ctx: Ctx => adminSite.profileSave(ctx) })
        router.post("/admin/profile/password", { ctx: Ctx => adminSite.passwordSave(ctx) })
        router.post("/admin/profile/token", { ctx: Ctx => adminSite.apiTokenCreate(ctx) })
        router.post("/admin/profile/token/revoke", { ctx: Ctx => adminSite.apiTokenRevoke(ctx) })
        router.post("/admin/preview", { ctx: Ctx => adminSite.preview(ctx) })

        // API v1.
        router.get("/api/v1/site", { ctx: Ctx => apiSite.site(ctx) })
        router.get("/api/v1/posts", { ctx: Ctx => apiSite.posts(ctx) })
        router.get("/api/v1/posts/:slug", { ctx: Ctx => apiSite.postBySlug(ctx) })
        router.post("/api/v1/posts", { ctx: Ctx => apiSite.createPost(ctx) })
        router.put("/api/v1/posts/:id", { ctx: Ctx => apiSite.updatePost(ctx) })
        router.delete("/api/v1/posts/:id", { ctx: Ctx => apiSite.deletePost(ctx) })
        router.get("/api/v1/comments", { ctx: Ctx => apiSite.comments(ctx) })
        router.post("/api/v1/comments", { ctx: Ctx => apiSite.createComment(ctx) })
        router.get("/api/v1/media", { ctx: Ctx => apiSite.media(ctx) })
        router.post("/api/v1/media", { ctx: Ctx => apiSite.uploadMedia(ctx) })
        router.get("/api/v1/attachments", { ctx: Ctx => apiSite.media(ctx) })
        router.post("/api/v1/attachments", { ctx: Ctx => apiSite.uploadMedia(ctx) })
        router.get("/api/v1/categories", { ctx: Ctx => apiSite.categories(ctx) })
        router.get("/api/v1/tags", { ctx: Ctx => apiSite.tags(ctx) })
        router.get("/api/v1/stats", { ctx: Ctx => apiSite.stats(ctx) })
        // Keep legacy root-level page URLs working; registered last so explicit routes win.
        router.get("/:slug", { ctx: Ctx => publicSite.pageShortcut(ctx) })
    }

    public func handle(req: HttpRequest): HttpResponse {
        if (isStaticPath(req.path)) {
            let staticResponse = serveStatic(req)
            staticResponse.withSecurityHeaders(req.isSecure())
            return staticResponse
        }
        let bearer = req.header("authorization")
        let isApi = req.path.startsWith("/api/")
        let tokenAuth = isApi && bearer.toAsciiLower().startsWith("bearer ")
        let token = req.cookieValue("cangmo_sid")
        let loaded: ?SessionData = if (token.size > 0) { services.auth.loadSession(token) } else { None }
        let stateless = tokenAuth || req.path == "/healthz" || req.path == "/robots.txt" ||
                        req.path == "/feed.xml" || req.path == "/rss.xml" ||
                        req.path == "/sitemap.xml" || req.path == "/manifest.webmanifest" ||
                        (isApi && req.method == "GET" && token.size == 0)
        var session: SessionData
        var newSession = false
        if (stateless) {
            session = SessionData()
            session.token = ""
            session.csrf = ""
        } else {
            match (loaded) {
                case Some(value) => session = value
                case None =>
                    session = services.auth.createSession("", req.remoteIp, req.header("user-agent"))
                    newSession = true
            }
        }
        var user: ?JsonValue = None
        if (session.userId.size > 0) {
            user = services.auth.userById(session.userId)
        }
        let ctx = Ctx(req, services, session, user, newSession)
        if (!tokenAuth) {
            let unsafeMethod = req.method == "POST" || req.method == "PUT" || req.method == "PATCH" || req.method == "DELETE"
            let skipCsrf = isApi && token.size == 0
            if (unsafeMethod && !skipCsrf) {
                var supplied = req.header("x-csrf-token").trimAscii()
                try {
                    if (supplied.size == 0) {
                        let ct = req.contentType().toAsciiLower()
                        if (ct.startsWith("application/x-www-form-urlencoded") || ct.startsWith("multipart/form-data")) {
                            supplied = req.formValue("_csrf")
                        }
                    }
                } catch (e: AppError) {
                    return errorFromApp(ctx, e)
                } catch (e: Exception) {
                    return errorFromApp(ctx, AppError("validation", "表单数据无法解析"))
                }
                if (!secureEqualsText(supplied, session.csrf)) {
                    return csrfFailure(ctx)
                }
            }
        }
        if (!services.auth.hasUsers() && req.path != "/setup" && req.path != "/healthz") {
            if (isApi) {
                return apiError(200, 503, "not_initialized", "系统尚未初始化")
            }
            return HttpResponse().redirect("/setup", status: 303)
        }
        if (services.auth.hasUsers() && req.path == "/setup") {
            return HttpResponse().redirect("/admin/login", status: 303)
        }
        if (isApi && !services.limiter.allow("api:" + req.remoteIp, services.config.apiRateLimitPerMinute, 60)) {
            return apiError(429, 429, "rate_limited", "请求过于频繁，请稍后再试")
        }
        var response: HttpResponse
        let params = HashMap<String, String>()
        let matched = router.dispatch(req.method, req.path, params)
        match (matched) {
            case Some(handler) =>
                ctx.params = params
                try {
                    response = handler(ctx)
                } catch (e: AppError) {
                    response = errorFromApp(ctx, e)
                } catch (e: Exception) {
                    services.logger.error("web", "unhandled error on ${req.method} ${req.path}: ${e.message}")
                    response = errorFromApp(ctx, AppError("internal", "服务器内部错误"))
                }
            case None =>
                if (isApi) {
                    response = apiError(404, 404, "not_found", "接口不存在")
                } else {
                    response = publicSite.notFound(ctx)
                }
        }
        // Session cookie lifecycle.
        if (ctx.sessionDestroyed) {
            response.deleteCookie("cangmo_sid")
        } else if (ctx.newSession || ctx.sessionChanged) {
            let maxAge = services.config.sessionTtlHours * 3600
            response.cookie("cangmo_sid", ctx.session.token, maxAge: maxAge, httpOnly: true,
                            secure: services.config.cookieSecure, sameSite: "Lax")
        }
        response.withSecurityHeaders(req.isSecure())
        if (response.headers.get("cache-control").size == 0) {
            if (req.path.startsWith("/admin")) {
                response.headers.set("cache-control", "no-store")
            } else if (isApi) {
                response.headers.set("cache-control", "no-store")
            } else if (response.headers.get("content-type").contains("text/html")) {
                response.headers.set("cache-control", "no-cache")
                response.headers.set("vary", "Cookie")
            }
        }
        if (req.path.startsWith("/admin")) {
            response.headers.set("x-robots-tag", "noindex, nofollow")
        }
        response.headers.set("content-language", services.config.locale)
        response
    }

    // -----------------------------------------------------------------------
    // Setup
    // -----------------------------------------------------------------------

    private func setupPage(ctx: Ctx): HttpResponse {
        if (services.auth.hasUsers()) {
            return ctx.redirect("/admin/login", status: 303)
        }
        let data = JsonObject()
        data.set("page_title", JStr("初始化"))
        data.set("error", JStr(""))
        data.set("site_title", JStr("仓墨"))
        data.set("username", JStr("admin"))
        data.set("email", JStr(""))
        data.set("requires_token", JBool(true))
        ctx.renderAdminPage("setup.html", JObj(data))
    }

    private func setupSubmit(ctx: Ctx): HttpResponse {
        if (services.auth.hasUsers()) {
            return ctx.redirect("/admin/login", status: 303)
        }
        let providedToken = ctx.form("token").trimAscii()
        if (!secureEqualsText(providedToken, services.setupToken)) {
            return setupError(ctx, "初始化令牌不正确，请查看服务端启动日志", 403)
        }
        let siteTitle = ctx.form("site_title").trimAscii()
        let username = ctx.form("username").trimAscii()
        let email = ctx.form("email").trimAscii()
        let password = ctx.form("password")
        let confirm = ctx.form("password_confirm")
        if (siteTitle.size == 0 || siteTitle.size > 100) {
            return setupError(ctx, "站点标题需在 1-100 字之间", 400)
        }
        if (password != confirm) {
            return setupError(ctx, "两次输入的密码不一致", 400)
        }
        try {
            let adminId = services.auth.createUser(username, email, password, "管理员", ROLE_ADMIN, ctx.clientIp())
            services.settings.setString("site_title", siteTitle)
            services.settings.setString("site_url", services.config.siteUrl)
            services.settings.setBool("setup_completed", true)
            let admin = match (services.auth.userById(adminId)) {
                case Some(value) => value
                case None => throw AppError("internal", "管理员创建失败")
            }
            seedWelcomeContent(admin)
            services.auth.destroySession(ctx.session)
            ctx.session = services.auth.createSession(adminId, ctx.clientIp(), ctx.req.header("user-agent"))
            ctx.sessionChanged = true
            services.audit.log(adminId, username, "setup_completed", "system", "", ctx.clientIp(), "")
            ctx.setFlash("success", "初始化完成，欢迎使用仓墨！")
            return ctx.redirect("/admin", status: 303)
        } catch (e: AppError) {
            return setupError(ctx, e.message, 400)
        } catch (e: Exception) {
            services.logger.error("setup", e.message)
            return setupError(ctx, "初始化失败：${e.message}", 500)
        }
    }

    private func setupError(ctx: Ctx, message: String, status: Int64): HttpResponse {
        let data = JsonObject()
        data.set("page_title", JStr("初始化"))
        data.set("error", JStr(message))
        data.set("site_title", JStr(ctx.form("site_title")))
        data.set("username", JStr(ctx.form("username")))
        data.set("email", JStr(ctx.form("email")))
        data.set("requires_token", JBool(true))
        ctx.renderAdminPage("setup.html", JObj(data), status: status)
    }

    private func seedWelcomeContent(admin: JsonValue): Unit {
        let welcome = PostInput()
        welcome.title = "欢迎使用仓墨"
        welcome.slug = "hello-cangmo"
        welcome.summary = "这是一篇由系统自动创建的文章，你可以编辑或删除它。"
        welcome.content = "# 欢迎使用仓墨\n\n" +
            "仓墨是一个用 **仓颉语言** 原生构建的博客系统。它没有依赖任何现成的 Web 框架，HTTP 服务器、模板引擎、Markdown 渲染器、JSON 解析器和存储引擎都是为这个项目编写的。\n\n" +
            "## 开始写作\n\n" +
            "1. 打开后台的「文章」页面\n" +
            "2. 点击「新建文章」\n" +
            "3. 使用 Markdown 编写内容并发布\n\n" +
            "> 提示：你可以在「设置」中调整站点标题、导航和评论策略。\n\n" +
            "```cangjie\nmain() {\n    println(\"Hello, Cangmo\")\n}\n```\n\n" +
            "祝你写作愉快。"
        welcome.postType = "post"
        welcome.status = STATUS_PUBLISHED
        welcome.featured = true
        welcome.tagNames = ["公告", "开始"]
        services.posts.save(welcome, admin, "", "127.0.0.1")

        let about = PostInput()
        about.title = "关于"
        about.slug = "about"
        about.summary = "关于本站"
        about.content = "## 关于本站\n\n这是「仓墨」博客的关于页面，你可以在后台编辑它。\n\n" +
            "本站使用仓颉语言编写，所有代码均为原创实现。"
        about.postType = "page"
        about.status = STATUS_PUBLISHED
        services.posts.save(about, admin, "", "127.0.0.1")
    }

    // -----------------------------------------------------------------------
    // Errors
    // -----------------------------------------------------------------------

    private func csrfFailure(ctx: Ctx): HttpResponse {
        if (ctx.req.path.startsWith("/api/")) {
            return apiError(403, 403, "csrf", "CSRF 校验失败")
        }
        errorPage(ctx, 403, "表单已过期或来源无效，请刷新页面后重试。")
    }

    private func errorFromApp(ctx: Ctx, error: AppError): HttpResponse {
        let status = statusForKind(error.kind)
        if (ctx.req.path.startsWith("/api/")) {
            return apiError(status, status, error.kind, error.message)
        }
        if (status >= 500) {
            services.logger.error("web", "${error.kind}: ${error.message} on ${ctx.req.path}")
        }
        let message = if (status >= 500 && !services.config.devMode) {
            "服务器内部错误，请稍后再试。"
        } else {
            error.message
        }
        errorPage(ctx, status, message)
    }

    private func errorPage(ctx: Ctx, status: Int64, message: String): HttpResponse {
        let data = JsonObject()
        data.set("page_title", JStr("出错了"))
        data.set("status", JInt(status))
        data.set("message", JStr(message))
        try {
            if (ctx.req.path.startsWith("/admin")) {
                return ctx.renderAdminPage("error.html", JObj(data), status: status)
            }
            return ctx.renderPage("error.html", JObj(data), status: status)
        } catch (e: Exception) {            return HttpResponse().html("<!doctype html><meta charset=\"utf-8\"><h1>${status}</h1><p>${escapeHtml(message)}</p>",
                                       status: status)
        }
    }

    private func apiError(webStatus: Int64, status: Int64, code: String, message: String): HttpResponse {
        let error = jsonObjectOf([
            ("error", jsonObjectOf([("code", jstr(code)), ("message", jstr(message))]))
        ])
        HttpResponse().json(error, status: status)
    }

    // -----------------------------------------------------------------------
    // Static files
    // -----------------------------------------------------------------------

    private func isStaticPath(path: String): Bool {
        path.startsWith("/static/") || path.startsWith("/admin/static/") || path.startsWith("/media/") ||
        path == "/favicon.ico" || path == "/sw.js"
    }

    private func serveStatic(req: HttpRequest): HttpResponse {
        var filePath: ?String = None
        var cacheSeconds: Int64 = 3600
        if (req.path.startsWith("/static/")) {
            filePath = safeAssetPath(services.themeAssetDir(), req.path[8..req.path.size])
        } else if (req.path.startsWith("/admin/static/")) {
            filePath = safeAssetPath(services.config.adminStaticDir(), req.path[14..req.path.size])
        } else if (req.path.startsWith("/media/")) {
            filePath = services.media.pathForUrl(req.path)
            cacheSeconds = 2592000
        } else if (req.path == "/favicon.ico") {
            let icon = services.themeAssetDir() + "/icon.svg"
            if (exists(icon)) {
                return serveFile(icon, req, 86400, "image/svg+xml")
            }
            return HttpResponse().empty(204)
        } else if (req.path == "/sw.js") {
            let worker = services.themeAssetDir() + "/sw.js"
            if (exists(worker)) {
                return serveFile(worker, req, 0, "application/javascript; charset=utf-8")
            }
            return HttpResponse().text("// no service worker", status: 404)
        }
        match (filePath) {
            case Some(value) => serveFile(value, req, cacheSeconds, mimeTypeFor(value))
            case None => HttpResponse().text("Not Found", status: 404)
        }
    }

    private func safeAssetPath(root: String, relative: String): ?String {
        if (relative.size == 0 || relative.size > 300) {
            return None
        }
        if (relative.startsWith("/") || relative.contains("..") || relative.contains("\\") ||
            relative.contains("\u{0}")) {
            return None
        }
        let segments = relative.split("/")
        for (segment in segments) {
            if (segment.size == 0) {
                return None
            }
            for (b in segment.toArray()) {
                let ok = (b >= 0x61 && b <= 0x7A) || (b >= 0x41 && b <= 0x5A) ||
                         (b >= 0x30 && b <= 0x39) || b == 0x2D || b == 0x5F || b == 0x2E
                if (!ok) {
                    return None
                }
            }
        }
        let full = root + "/" + relative
        if (!exists(full) || isDirectory(full)) {
            return None
        }
        Some(full)
    }

    private func serveFile(path: String, req: HttpRequest, cacheSeconds: Int64, contentType: String): HttpResponse {
        let data = try {
            File.readFrom(path)
        } catch (e: Exception) {
            return HttpResponse().text("Not Found", status: 404)
        }
        let size = data.size
        let mtime = try {
            FileInfo(path).lastModificationTime.toUnixTimeStamp().toSeconds()
        } catch (e: Exception) {
            0
        }
        let etag = "\"" + sha256Hex("${size}:${mtime}:" + path)[0..20] + "\""
        let ifNoneMatch = req.header("if-none-match")
        if (ifNoneMatch.size > 0 && ifNoneMatch == etag) {
            let response = HttpResponse().empty(304)
            response.headers.set("etag", etag)
            response.headers.set("cache-control", if (cacheSeconds > 0) { "public, max-age=${cacheSeconds}" } else { "no-cache" })
            return response
        }
        let range = req.header("range")
        if (range.startsWith("bytes=") && size > 0) {
            let spec = range[6..range.size].trimAscii()
            let dash = findSub(spec, "-")
            if (dash >= 0) {
                let start = parseIntOr(spec[0..dash], -1)
                let endText = spec[dash + 1..spec.size]
                var end = if (endText.size > 0) { parseIntOr(endText, -1) } else { size - 1 }
                if (start >= 0 && start < size) {
                    if (end < 0 || end >= size) {
                        end = size - 1
                    }
                    if (end >= start) {
                        let chunk = data[start..end + 1]
                        let response = HttpResponse().bytes(chunk, contentType, status: 206)
                        response.headers.set("content-range", "bytes ${start}-${end}/${size}")
                        response.headers.set("accept-ranges", "bytes")
                        response.headers.set("etag", etag)
                        response.headers.set("cache-control", "public, max-age=${cacheSeconds}")
                        return response
                    }
                }
            }
        }
        let response = HttpResponse().bytes(data, contentType)
        response.headers.set("etag", etag)
        response.headers.set("accept-ranges", "bytes")
        response.headers.set("cache-control", if (cacheSeconds > 0) { "public, max-age=${cacheSeconds}" } else { "no-cache" })
        response
    }
}

func statusForKind(kind: String): Int64 {
    match (kind) {
        case "validation" => 400
        case "unauthorized" => 401
        case "forbidden" => 403
        case "not_found" => 404
        case "method" => 405
        case "conflict" => 409
        case "payload" => 413
        case "rate_limited" => 429
        case _ => 500
    }
}
