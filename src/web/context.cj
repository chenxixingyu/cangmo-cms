/**
 * Cangmo - web application context, service registry, routing and view helpers.
 */
package cangmo.web

import cangmo.core.*
import cangmo.http.*
import cangmo.json.*
import cangmo.service.*
import cangmo.store.*
import cangmo.template.*
import std.collection.*
import std.env.*
import std.fs.*
import std.time.*

public class Services {
    public let config: Config
    public let logger: Logger
    public let store: Store
    public let settings: SettingsService
    public let audit: AuditService
    public let limiter: RateLimiter
    public let auth: AuthService
    public let posts: PostService
    public let taxonomy: TaxonomyService
    public let comments: CommentService
    public let media: MediaService
    public let stats: StatsService
    public let search: SearchService
    public let backup: BackupService
    public let redirects: RedirectService
    public var templates: TemplateEngine
    public let adminTemplates: TemplateEngine
    public let setupToken: String

    public init(config: Config) {
        this.config = config
        ensureDir(config.dataDir)
        ensureDir(config.uploadsDir())
        ensureDir(config.logsDir())
        ensureDir(config.backupDir())
        this.logger = Logger(config.logsDir(), threshold: config.logLevel, alsoConsole: true)
        this.store = Store(config.dataDir)
        this.settings = SettingsService(store)
        this.audit = AuditService(store)
        this.limiter = RateLimiter()
        this.auth = AuthService(store, config, settings, audit, limiter)
        this.posts = PostService(store, config, settings, audit)
        this.taxonomy = TaxonomyService(store, audit)
        this.comments = CommentService(store, config, settings, audit, limiter)
        this.media = MediaService(store, config, audit)
        this.stats = StatsService(store)
        this.search = SearchService(store, config)
        this.backup = BackupService(store, config)
        this.redirects = RedirectService(store, audit)
        this.templates = TemplateEngine(config.themesDir + "/" + config.theme + "/templates", devMode: config.devMode)
        this.adminTemplates = TemplateEngine(config.adminTemplatesDir(), devMode: config.devMode)
        let envToken = getVariable("CANGMO_SETUP_TOKEN") ?? ""
        this.setupToken = if (envToken.size >= 8) { envToken } else { randomToken(bytes: 18) }
        settings.ensureDefaults(config)
        taxonomy.ensureDefaultCategory(settings)
        this.templates = TemplateEngine(themeTemplatesDir(), devMode: config.devMode)
        for (warning in store.warnings()) {
            logger.warn("store", warning)
        }
        if (!auth.hasUsers()) {
            logger.warn("setup", "系统尚未初始化。请打开 http://${config.host}:${config.port}/setup")
            logger.warn("setup", "初始化令牌（Setup token）: ${setupToken}")
        }
    }

    public func reloadTheme(): Unit {
        templates = TemplateEngine(themeTemplatesDir(), devMode: config.devMode)
    }

    public func themeAssetDir(): String {
        config.themesDir + "/" + settings.str("theme", def: config.theme) + "/static"
    }

    public func themeTemplatesDir(): String {
        config.themesDir + "/" + settings.str("theme", def: config.theme) + "/templates"
    }
}

public class Ctx {
    public let req: HttpRequest
    public let services: Services
    public var session: SessionData
    public var user: ?JsonValue
    public var params: HashMap<String, String> = HashMap<String, String>()
    public var newSession: Bool = false
    public var sessionChanged: Bool = false
    public var sessionDestroyed: Bool = false

    public init(req: HttpRequest, services: Services, session: SessionData, user: ?JsonValue, newSession: Bool) {
        this.req = req
        this.services = services
        this.session = session
        this.user = user
        this.newSession = newSession
    }

    public func loggedIn(): Bool {
        user.isSome()
    }

    public func userDoc(): JsonValue {
        match (user) {
            case Some(value) => value
            case None => JNull
        }
    }

    public func isAdmin(): Bool {
        match (user) {
            case Some(value) => docStr(value, "role") == ROLE_ADMIN
            case None => false
        }
    }

    public func isStaff(): Bool {
        match (user) {
            case Some(value) =>
                let role = docStr(value, "role")
                role == ROLE_ADMIN || role == ROLE_EDITOR || role == ROLE_AUTHOR || role == ROLE_CONTRIBUTOR
            case None => false
        }
    }

    public func can(capability: String): Bool {
        match (user) {
            case Some(value) => services.auth.can(value, capability)
            case None => false
        }
    }

    public func clientIp(): String {
        req.remoteIp
    }

    public func flashMessages(): JsonValue {
        let arr = JsonArray()
        for (message in services.auth.consumeFlash(session)) {
            let item = JsonObject()
            item.set("kind", JStr(message.kind))
            item.set("text", JStr(message.text))
            arr.add(JObj(item))
        }
        JArr(arr)
    }

    public func setFlash(kind: String, text: String): Unit {
        services.auth.setFlash(session, kind, text)
    }

    public func csrf(): String {
        session.csrf
    }

    public func form(name: String, def!: String = ""): String {
        req.formValue(name, def: def)
    }

    public func query(name: String, def!: String = ""): String {
        req.queryValue(name, def: def)
    }

    public func param(name: String, def!: String = ""): String {
        match (params.get(name)) {
            case Some(value) => value
            case None => def
        }
    }

    public func pageNumber(): Int64 {
        let value = req.queryInt("page", def: 1)
        if (value < 1) { 1 } else { value }
    }

    public func redirect(location: String, status!: Int64 = 302): HttpResponse {
        HttpResponse().redirect(location, status: status)
    }

    public func html(content: String, status!: Int64 = 200): HttpResponse {
        HttpResponse().html(content, status: status)
    }

    public func render(templateName: String, pageData: JsonValue): String {
        let data = baseData()
        mergeObject(data, pageData)
        try {
            return services.templates.render(templateName, data)
        } catch (e: Exception) {
            throw AppError("template", "公共模板 ${templateName}: ${e.message}")
        }
    }

    public func renderAdmin(templateName: String, pageData: JsonValue): String {
        let data = baseData()
        mergeObject(data, pageData)
        try {
            return services.adminTemplates.render(templateName, data)
        } catch (e: Exception) {
            throw AppError("template", "后台模板 ${templateName}: ${e.message}")
        }
    }

    public func baseData(): JsonValue {
        let data = JsonObject()
        let site = JsonObject()
        site.set("title", JStr(services.settings.str("site_title", def: services.config.siteTitle)))
        site.set("subtitle", JStr(services.settings.str("site_subtitle", def: "")))
        site.set("description", JStr(services.settings.str("site_description", def: "")))
        site.set("keywords", JStr(services.settings.str("site_keywords", def: "")))
        site.set("url", JStr(services.settings.str("site_url", def: services.config.siteUrl)))
        site.set("footer_text", JStr(services.settings.str("footer_text", def: "")))
        site.set("accent", JStr(services.settings.str("theme_accent", def: "#2f6f4e")))
        site.set("mode", JStr(services.settings.str("theme_mode", def: "auto")))
        site.set("locale", JStr(services.config.locale))
        site.set("year", JStr(formatTime(nowSeconds(), "yyyy")))
        site.set("nav", jsonArrayFrom(services.settings.navItems()))
        site.set("social", services.settings.json("social_links"))
        data.set("site", JObj(site))
        data.set("user", match (user) {
            case Some(value) => userSummary(value)
            case None => JNull
        })
        data.set("is_admin", JBool(isAdmin()))
        data.set("csrf", JStr(csrf()))
        data.set("flash", flashMessages())
        data.set("current_path", JStr(req.path))
        data.set("search_query", JStr(req.queryValue("q")))
        data.set("year", JStr(formatTime(nowSeconds(), "yyyy")))
        data.set("pending_comments", JInt(services.comments.pendingCount()))
        data.set("version", JStr(APP_VERSION))
        data.set("show_toc", JBool(services.settings.bool("show_toc", def: true)))
        data.set("show_reading_time", JBool(services.settings.bool("show_reading_time", def: true)))
        JObj(data)
    }

    public func renderPage(templateName: String, pageData: JsonValue, status!: Int64 = 200): HttpResponse {
        HttpResponse().html(render(templateName, pageData), status: status)
    }

    public func renderAdminPage(templateName: String, pageData: JsonValue, status!: Int64 = 200): HttpResponse {
        let response = HttpResponse().html(renderAdmin(templateName, pageData), status: status)
        response.headers.set("cache-control", "no-store")
        response.headers.set("x-robots-tag", "noindex, nofollow")
        response
    }

    public func siteUrl(path: String): String {
        let base = services.settings.str("site_url", def: services.config.siteUrl)
        if (path.startsWith("/")) {
            base + path
        } else {
            base + "/" + path
        }
    }
}

public func mergeObject(base: JsonValue, extra: JsonValue): Unit {
    if (let JObj(baseObj) <- base) {
        if (let JObj(extraObj) <- extra) {
            for ((key, value) in extraObj.fields) {
                baseObj.set(key, value)
            }
        }
    }
}

public func jsonArrayFrom(items: Array<JsonValue>): JsonValue {
    let arr = JsonArray()
    for (item in items) {
        arr.add(item)
    }
    JArr(arr)
}

// ---------------------------------------------------------------------------
// Web router
// ---------------------------------------------------------------------------

public type WebHandler = (Ctx) -> HttpResponse

class WebRoute {
    let method: String
    let segments: Array<String>
    let handler: WebHandler

    init(method: String, segments: Array<String>, handler: WebHandler) {
        this.method = method
        this.segments = segments
        this.handler = handler
    }
}

public class WebRouter {
    private let routes: ArrayList<WebRoute> = ArrayList<WebRoute>()

    public init() {}

    public func get(pattern: String, handler: WebHandler): WebRouter {
        add("GET", pattern, handler)
    }

    public func post(pattern: String, handler: WebHandler): WebRouter {
        add("POST", pattern, handler)
    }

    public func put(pattern: String, handler: WebHandler): WebRouter {
        add("PUT", pattern, handler)
    }

    public func delete(pattern: String, handler: WebHandler): WebRouter {
        add("DELETE", pattern, handler)
    }

    public func add(method: String, pattern: String, handler: WebHandler): WebRouter {
        routes.add(WebRoute(method.toAsciiUpper(), splitSegments(normalizePattern(pattern)), handler))
        this
    }

    public func dispatch(method: String, path: String, params: HashMap<String, String>): ?WebHandler {
        let upper = method.toAsciiUpper()
        let segments = splitSegments(normalizePattern(path))
        match (find(upper, segments, params)) {
            case Some(handler) => return Some(handler)
            case None => ()
        }
        if (upper == "HEAD") {
            return find("GET", segments, params)
        }
        None
    }

    private func find(method: String, segments: Array<String>, params: HashMap<String, String>): ?WebHandler {
        for (route in routes) {
            if (route.method != method) {
                continue
            }
            if (matches(route.segments, segments, params)) {
                return Some(route.handler)
            }
        }
        None
    }

    private func matches(pattern: Array<String>, actual: Array<String>, params: HashMap<String, String>): Bool {
        var pi = 0
        var ai = 0
        while (pi < pattern.size) {
            let segment = pattern[pi]
            if (segment.startsWith("*")) {
                let name = segment[1..segment.size]
                let rest = ArrayList<String>()
                while (ai < actual.size) {
                    rest.add(actual[ai])
                    ai += 1
                }
                if (name.size > 0) {
                    params[name] = String.join(rest.toArray(), delimiter: "/")
                }
                return true
            }
            if (ai >= actual.size) {
                return false
            }
            if (segment.startsWith(":")) {
                params[segment[1..segment.size]] = actual[ai]
            } else if (segment != actual[ai]) {
                return false
            }
            pi += 1
            ai += 1
        }
        ai == actual.size
    }
}

public func normalizePattern(path: String): String {
    var value = path.trimAscii()
    if (value.size == 0) {
        return "/"
    }
    if (!value.startsWith("/")) {
        value = "/" + value
    }
    while (value.size > 1 && value.endsWith("/")) {
        value = value[0..value.size - 1]
    }
    value
}

func splitSegments(path: String): Array<String> {
    let normalized = normalizePattern(path)
    if (normalized == "/") {
        return Array<String>(0, repeat: "")
    }
    let parts = normalized[1..normalized.size].split("/")
    let out = ArrayList<String>()
    for (part in parts) {
        if (part.size > 0) {
            out.add(part)
        }
    }
    out.toArray()
}

// ---------------------------------------------------------------------------
// View helpers
// ---------------------------------------------------------------------------

public func postUrl(post: JsonValue): String {
    if (docStr(post, "type") == "page") {
        return "/pages/" + docStr(post, "slug")
    }
    return "/posts/" + docStr(post, "slug")
}

public func categoryUrl(category: JsonValue): String {
    "/categories/" + docStr(category, "slug")
}

public func tagUrl(tag: JsonValue): String {
    "/tags/" + docStr(tag, "slug")
}

public func postCard(services: Services, post: JsonValue): JsonValue {
    let card = JsonObject()
    card.set("id", JStr(docStr(post, "id")))
    card.set("title", JStr(docStr(post, "title")))
    card.set("slug", JStr(docStr(post, "slug")))
    card.set("url", JStr(postUrl(post)))
    card.set("summary", JStr(docStr(post, "summary")))
    card.set("cover", JStr(docStr(post, "cover")))
    card.set("status", JStr(docStr(post, "status")))
    card.set("type", JStr(docStr(post, "type")))
    card.set("pinned", JBool(docBool(post, "pinned")))
    card.set("featured", JBool(docBool(post, "featured")))
    card.set("views", JInt(docInt(post, "views")))
    card.set("reading_minutes", JInt(docInt(post, "reading_minutes")))
    let publishedAt = docInt(post, "published_at")
    card.set("published_at", JInt(publishedAt))
    card.set("date", JStr(formatDate(publishedAt)))
    card.set("date_iso", JStr(formatUtcIso(publishedAt)))
    card.set("date_rfc", JStr(formatUtcRfc1123(publishedAt)))
    card.set("updated_at", JInt(docInt(post, "updated_at")))
    // Author
    let author = JsonObject()
    match (services.auth.userById(docStr(post, "author_id"))) {
        case Some(user) =>
            author.set("name", JStr(docStr(user, "display_name")))
            author.set("username", JStr(docStr(user, "username")))
            author.set("avatar", JStr(docStr(user, "avatar")))
            author.set("initial", JStr(initialOf(docStr(user, "display_name"))))
        case None =>
            author.set("name", JStr("已注销"))
            author.set("username", JStr(""))
            author.set("avatar", JStr(""))
            author.set("initial", JStr("?"))
    }
    card.set("author", JObj(author))
    // Category
    let category = JsonObject()
    let categoryId = docStr(post, "category_id")
    match (services.store.get(COL_CATEGORIES, categoryId)) {
        case Some(value) =>
            category.set("name", JStr(docStr(value, "name")))
            category.set("url", JStr(categoryUrl(value)))
        case None =>
            category.set("name", JStr(""))
            category.set("url", JStr(""))
    }
    card.set("category", JObj(category))
    // Tags
    let tags = JsonArray()
    for (tag in services.taxonomy.tagsForPost(post)) {
        let item = JsonObject()
        item.set("name", JStr(docStr(tag, "name")))
        item.set("url", JStr(tagUrl(tag)))
        tags.add(JObj(item))
    }
    card.set("tags", JArr(tags))
    JObj(card)
}

public func adminPostRow(services: Services, post: JsonValue): JsonValue {
    let row = JsonObject()
    row.set("id", JStr(docStr(post, "id")))
    row.set("title", JStr(docStr(post, "title")))
    row.set("slug", JStr(docStr(post, "slug")))
    row.set("type", JStr(docStr(post, "type")))
    let postStatus = docStr(post, "status")
    row.set("status", JStr(postStatus))
    row.set("status_text", JStr(if (postStatus == "published") { "已发布" } else if (postStatus == "draft") { "草稿" } else if (postStatus == "scheduled") { "定时" } else if (postStatus == "trash") { "回收站" } else { postStatus }))
    row.set("pinned", JBool(docBool(post, "pinned")))
    row.set("views", JInt(docInt(post, "views")))
    row.set("date", JStr(formatDate(docInt(post, "published_at"))))
    row.set("updated", JStr(formatDateTime(docInt(post, "updated_at"))))
    row.set("edit_url", JStr("/admin/posts/" + docStr(post, "id") + "/edit"))
    let author = JsonObject()
    match (services.auth.userById(docStr(post, "author_id"))) {
        case Some(user) => author.set("name", JStr(docStr(user, "display_name")))
        case None => author.set("name", JStr("已注销"))
    }
    row.set("author", JObj(author))
    JObj(row)
}

public func commentView(comment: JsonValue, post: ?JsonValue, depth: Int64): JsonValue {
    let view = JsonObject()
    view.set("id", JStr(docStr(comment, "id")))
    view.set("author_name", JStr(docStr(comment, "author_name")))
    view.set("author_url", JStr(docStr(comment, "author_url")))
    view.set("content", JStr(docStr(comment, "content")))
    let status = docStr(comment, "status")
    view.set("status", JStr(status))
    view.set("status_text", JStr(if (status == "approved") { "已通过" } else if (status == "spam") { "垃圾" } else if (status == "trash") { "回收站" } else if (status == "pending") { "待审核" } else { status }))
    view.set("depth", JInt(depth))
    view.set("created_at", JInt(docInt(comment, "created_at")))
    view.set("date", JStr(formatDateTime(docInt(comment, "created_at"))))
    view.set("relative", JStr(relativeTime(docInt(comment, "created_at"))))
    view.set("initial", JStr(initialOf(docStr(comment, "author_name"))))
    match (post) {
        case Some(value) =>
            view.set("post_title", JStr(docStr(value, "title")))
            view.set("post_url", JStr(postUrl(value)))
        case None =>
            view.set("post_title", JStr(""))
            view.set("post_url", JStr(""))
    }
    JObj(view)
}

public func buildPagination(page: Int64, pages: Int64, total: Int64, baseUrl: String, pageSize: Int64): JsonValue {
    let pagination = JsonObject()
    pagination.set("page", JInt(page))
    pagination.set("pages", JInt(pages))
    pagination.set("total", JInt(total))
    pagination.set("page_size", JInt(pageSize))
    pagination.set("prev_url", JStr(if (page > 1) { withPage(baseUrl, page - 1) } else { "" }))
    pagination.set("next_url", JStr(if (page < pages) { withPage(baseUrl, page + 1) } else { "" }))
    let numbers = JsonArray()
    var start = page - 2
    if (start < 1) { start = 1 }
    var end = start + 4
    if (end > pages) { end = pages }
    if (end - start < 4 && pages >= 5) {
        start = end - 4
        if (start < 1) { start = 1 }
    }
    var i = start
    while (i <= end) {
        let item = JsonObject()
        item.set("number", JInt(i))
        item.set("url", JStr(withPage(baseUrl, i)))
        item.set("current", JBool(i == page))
        numbers.add(JObj(item))
        i += 1
    }
    pagination.set("numbers", JArr(numbers))
    JObj(pagination)
}

func withPage(baseUrl: String, page: Int64): String {
    if (page <= 1) {
        return baseUrl
    }
    if (findSub(baseUrl, "?") >= 0) {
        return baseUrl + "&page=" + page.toString()
    }
    return baseUrl + "?page=" + page.toString()
}

public func initialOf(text: String): String {
    if (text.size == 0) {
        return "?"
    }
    truncateRunes(text, 1, suffix: "")
}
