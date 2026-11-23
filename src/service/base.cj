/**
 * Cangmo - shared service helpers, settings, rate limiting and audit log.
 */
package cangmo.service

import cangmo.core.*
import cangmo.json.*
import cangmo.store.*
import std.collection.*
import std.sync.*
import std.sort.*
import std.time.*

public let COL_USERS: String = "users"
public let COL_POSTS: String = "posts"
public let COL_CATEGORIES: String = "categories"
public let COL_TAGS: String = "tags"
public let COL_COMMENTS: String = "comments"
public let COL_MEDIA: String = "media"
public let COL_SESSIONS: String = "sessions"
public let COL_SETTINGS: String = "settings"
public let COL_AUDIT: String = "audit"
public let COL_REVISIONS: String = "revisions"
public let COL_REDIRECTS: String = "redirects"
public let COL_PREVIEW_TOKENS: String = "preview_tokens"
public let COL_PASSWORD_RESETS: String = "password_resets"
public let COL_SEARCH_STATS: String = "search_stats"
public let COL_WEBHOOKS: String = "webhooks"
public let COL_JOBS: String = "jobs"
public let COL_SITES: String = "sites"
public let COL_PLUGINS: String = "plugins"
public let COL_API_TOKENS: String = "api_tokens"
public let COL_SUBSCRIBERS: String = "subscribers"
public let COL_STATS: String = "stats"

public let STATUS_DRAFT: String = "draft"
public let STATUS_PUBLISHED: String = "published"
public let STATUS_REVIEW: String = "review"
public let STATUS_SCHEDULED: String = "scheduled"
public let STATUS_TRASH: String = "trash"

public let ROLE_ADMIN: String = "admin"
public let ROLE_EDITOR: String = "editor"
public let ROLE_AUTHOR: String = "author"
public let ROLE_CONTRIBUTOR: String = "contributor"
public let ROLE_SUBSCRIBER: String = "subscriber"

public class PageResult {
    public let items: Array<JsonValue>
    public let total: Int64
    public let page: Int64
    public let pageSize: Int64
    public let pages: Int64

    public init(items: Array<JsonValue>, total: Int64, page: Int64, pageSize: Int64) {
        this.items = items
        this.total = total
        this.page = page
        this.pageSize = pageSize
        this.pages = if (pageSize <= 0) { 1 } else { (total + pageSize - 1) / pageSize }
    }
}

public func pageResult(items: ArrayList<JsonValue>, total: Int64, page: Int64, pageSize: Int64): PageResult {
    PageResult(items.toArray(), total, page, pageSize)
}

// ---------------------------------------------------------------------------
// Document helpers
// ---------------------------------------------------------------------------

public func docStr(doc: JsonValue, key: String, def!: String = ""): String {
    getString(doc, key, def: def)
}

public func docInt(doc: JsonValue, key: String, def!: Int64 = 0): Int64 {
    getInt(doc, key, def: def)
}

public func docBool(doc: JsonValue, key: String, def!: Bool = false): Bool {
    getBool(doc, key, def: def)
}

public func docStrings(doc: JsonValue, key: String): Array<String> {
    getStrings(doc, key)
}

public func docObj(doc: JsonValue, key: String): JsonValue {
    match (doc.get(key)) {
        case Some(JObj(o)) => JObj(o)
        case _ => jobj()
    }
}

public func cloneDoc(doc: JsonValue): JsonValue {
    cloneJson(doc)
}

public func setKv(doc: JsonValue, key: String, value: JsonValue): Unit {
    setField(doc, key, value)
}

public func userSummary(user: JsonValue): JsonValue {
    let o = JsonObject()
    let displayName = docStr(user, "display_name")
    o.set("id", JStr(docStr(user, "id")))
    o.set("username", JStr(docStr(user, "username")))
    o.set("display_name", JStr(displayName))
    o.set("initial", JStr(if (displayName.size > 0) { truncateRunes(displayName, 1, suffix: "") } else { "?" }))
    o.set("role", JStr(docStr(user, "role")))
    o.set("avatar", JStr(docStr(user, "avatar")))
    o.set("bio", JStr(docStr(user, "bio")))
    JObj(o)
}

public func sortDocsDesc(items: ArrayList<JsonValue>, key: String): Unit {
    sort<JsonValue>(items, by: { a: JsonValue, b: JsonValue =>
        let av = docInt(a, key)
        let bv = docInt(b, key)
        if (av > bv) { Ordering.GT } else if (av < bv) { Ordering.LT } else { Ordering.EQ }
    })
}

public func sortDocsAsc(items: ArrayList<JsonValue>, key: String): Unit {
    sort<JsonValue>(items, by: { a: JsonValue, b: JsonValue =>
        let av = docInt(a, key)
        let bv = docInt(b, key)
        if (av < bv) { Ordering.GT } else if (av > bv) { Ordering.LT } else { Ordering.EQ }
    })
}

// ---------------------------------------------------------------------------
// Settings
// ---------------------------------------------------------------------------

public class SettingsService {
    private let store: Store
    private let mutex: Mutex = Mutex()

    public init(store: Store) {
        this.store = store
    }

    public func ensureDefaults(config: Config): Unit {
        setDefault("site_title", JStr(config.siteTitle))
        setDefault("site_subtitle", JStr(config.siteSubtitle))
        setDefault("site_description", JStr(config.siteDescription))
        setDefault("site_keywords", JStr("仓颉,博客,技术,随笔"))
        setDefault("site_url", JStr(config.siteUrl))
        setDefault("footer_text", JStr("由仓墨驱动 · 用仓颉写下的文字"))
        setDefault("posts_per_page", JInt(config.postsPerPage))
        setDefault("theme", JStr(config.theme))
        setDefault("theme_accent", JStr("#2f6f4e"))
        setDefault("theme_mode", JStr("auto"))
        setDefault("show_reading_time", JBool(true))
        setDefault("show_toc", JBool(true))
        setDefault("show_related_posts", JBool(true))
        setDefault("comment_enabled", JBool(true))
        setDefault("comment_moderation", JBool(true))
        setDefault("comment_max_links", JInt(3))
        setDefault("comment_rate_per_hour", JInt(config.commentRateLimitPerHour))
        setDefault("nav", JStr("[{\"label\":\"首页\",\"url\":\"/\"},{\"label\":\"归档\",\"url\":\"/archive\"},{\"label\":\"关于\",\"url\":\"/pages/about\"}]"))
        setDefault("social_links", JStr("[]"))
        setDefault("maintenance", JBool(false))
        setDefault("setup_completed", JBool(false))
        setDefault("default_category", JStr(""))
        setDefault("api_enabled", JBool(config.enableApi))
        setDefault("backup_auto", JBool(false))
        setDefault("backup_interval_hours", JInt(24))
        setDefault("backup_keep", JInt(7))
        setDefault("backup_last_at", JInt(0))
        setDefault("backup_encrypt", JBool(false))
        setDefault("site_logo", JStr(""))
        setDefault("site_favicon", JStr(""))
        setDefault("footer_copyright", JStr(""))
        setDefault("footer_icp", JStr(""))
        setDefault("home_hero_title", JStr(""))
        setDefault("home_hero_subtitle", JStr(""))
        setDefault("home_hero_image", JStr(""))
        setDefault("home_show_featured", JBool(true))
        setDefault("show_author", JBool(true))
        setDefault("show_date", JBool(true))
        setDefault("show_category", JBool(true))
        setDefault("show_tags", JBool(true))
        setDefault("excerpt_length", JInt(120))
        setDefault("related_count", JInt(3))
        setDefault("seo_image", JStr(""))
        setDefault("seo_twitter", JStr(""))
        setDefault("theme_font_size", JInt(17))
        setDefault("theme_width", JInt(1120))
        setDefault("theme_radius", JInt(12))
        setDefault("theme_market_url", JStr(""))
        setDefault("custom_css", JStr(""))
        setDefault("maintenance", JBool(false))
        setDefault("maintenance_message", JStr("站点维护中，请稍后再来。"))
    }

    private func setDefault(key: String, value: JsonValue): Unit {
        if (!store.exists(COL_SETTINGS, key)) {
            set(key, value)
        }
    }

    public func get(key: String): ?JsonValue {
        match (store.get(COL_SETTINGS, key)) {
            case Some(doc) => doc.get("value")
            case None => None
        }
    }

    public func str(key: String, def!: String = ""): String {
        match (get(key)) {
            case Some(JStr(value)) => value
            case _ => def
        }
    }

    public func int(key: String, def!: Int64 = 0): Int64 {
        match (get(key)) {
            case Some(JInt(value)) => value
            case _ => def
        }
    }

    public func bool(key: String, def!: Bool = false): Bool {
        match (get(key)) {
            case Some(JBool(value)) => value
            case _ => def
        }
    }

    public func json(key: String): JsonValue {
        match (get(key)) {
            case Some(JStr(text)) =>
                match (tryParseJson(text)) {
                    case Some(value) => value
                    case None => JNull
                }
            case Some(value) => value
            case None => JNull
        }
    }

    public func set(key: String, value: JsonValue): Unit {
        if (!isSafeName(key)) {
            throw AppError("validation", "无效的配置键")
        }
        synchronized(mutex) {
            let doc = JsonObject()
            doc.set("key", JStr(key))
            doc.set("value", value)
            doc.set("updated_at", JInt(nowSeconds()))
            store.put(COL_SETTINGS, key, JObj(doc))
        }
    }

    public func setString(key: String, value: String): Unit {
        set(key, JStr(value))
    }

    public func setInt(key: String, value: Int64): Unit {
        set(key, JInt(value))
    }

    public func setBool(key: String, value: Bool): Unit {
        set(key, JBool(value))
    }

    public func all(): JsonValue {
        let out = JsonObject()
        for (doc in store.list(COL_SETTINGS)) {
            let key = docStr(doc, "key")
            match (doc.get("value")) {
                case Some(value) => out.set(key, value)
                case None => ()
            }
        }
        JObj(out)
    }

    public func navItems(): Array<JsonValue> {
        let result = ArrayList<JsonValue>()
        match (json("nav")) {
            case JArr(arr) =>
                for (item in arr.items) {
                    if (docStr(item, "label").size > 0 && docStr(item, "url").size > 0) {
                        result.add(item)
                    }
                }
            case _ => ()
        }
        result.toArray()
    }
}

// ---------------------------------------------------------------------------
// Rate limiting (in-memory sliding window)
// ---------------------------------------------------------------------------

public class RateLimiter {
    private let mutex: Mutex = Mutex()
    private let buckets: HashMap<String, ArrayList<Int64>> = HashMap<String, ArrayList<Int64>>()

    public init() {}

    public func allow(key: String, limit: Int64, windowSeconds: Int64): Bool {
        if (limit <= 0) {
            return true
        }
        synchronized(mutex) {
            let now = nowSeconds()
            let cutoff = now - windowSeconds
            if (!buckets.contains(key)) {
                buckets[key] = ArrayList<Int64>()
            }
            let previous = buckets[key]
            let kept = ArrayList<Int64>()
            for (stamp in previous) {
                if (stamp > cutoff) {
                    kept.add(stamp)
                }
            }
            if (kept.size >= limit) {
                buckets[key] = kept
                return false
            }
            kept.add(now)
            buckets[key] = kept
            if (buckets.size > 20000) {
                pruneLocked(now)
            }
            return true
        }
    }

    public func reset(key: String): Unit {
        synchronized(mutex) {
            buckets.remove(key)
        }
    }

    public func prune(): Unit {
        synchronized(mutex) {
            pruneLocked(nowSeconds())
        }
    }

    private func pruneLocked(now: Int64): Unit {
        let empty = ArrayList<String>()
        for ((key, list) in buckets) {
            if (list.size == 0 || list[list.size - 1] < now - 86400) {
                empty.add(key)
            }
        }
        for (key in empty) {
            buckets.remove(key)
        }
    }
}

// ---------------------------------------------------------------------------
// Audit log
// ---------------------------------------------------------------------------

public class AuditService {
    private let store: Store
    private let mutex: Mutex = Mutex()

    public init(store: Store) {
        this.store = store
    }

    public func log(actorId: String, actorName: String, action: String, targetType: String,
                    targetId: String, ip: String, detail: String): Unit {
        synchronized(mutex) {
            let id = newId("audit")
            let doc = JsonObject()
            doc.set("id", JStr(id))
            doc.set("actor_id", JStr(actorId))
            doc.set("actor_name", JStr(actorName))
            doc.set("action", JStr(action))
            doc.set("target_type", JStr(targetType))
            doc.set("target_id", JStr(targetId))
            doc.set("ip", JStr(ip))
            doc.set("detail", JStr(truncateUtf8(detail, 1000)))
            doc.set("created_at", JInt(nowSeconds()))
            store.put(COL_AUDIT, id, JObj(doc))
            if (store.count(COL_AUDIT) > 8000) {
                prune()
            }
        }
    }

    private func prune(): Unit {
        let all = store.list(COL_AUDIT)
        let items = ArrayList<JsonValue>()
        for (doc in all) {
            items.add(doc)
        }
        sortDocsAsc(items, "created_at")
        let removeCount = items.size - 5000
        var removed: Int64 = 0
        for (doc in items) {
            if (removed >= removeCount) {
                break
            }
            store.delete(COL_AUDIT, docStr(doc, "id"))
            removed += 1
        }
    }

    public func list(page: Int64, pageSize: Int64): PageResult {
        search(page, pageSize, actor: "", action: "", fromDate: "", toDate: "", text: "")
    }

    public func search(page: Int64, pageSize: Int64, actor!: String, action!: String,
                       fromDate!: String, toDate!: String, text!: String): PageResult {
        let actorNeedle = actor.trimAscii().toAsciiLower()
        let actionNeedle = action.trimAscii().toAsciiLower()
        let textNeedle = text.trimAscii().toAsciiLower()
        let from = fromDate.trimAscii()
        let to = toDate.trimAscii()
        let items = ArrayList<JsonValue>()
        for (doc in store.list(COL_AUDIT)) {
            let date = formatDate(docInt(doc, "created_at"))
            if (from.size > 0 && date < from) {
                continue
            }
            if (to.size > 0 && date > to) {
                continue
            }
            if (actorNeedle.size > 0) {
                let haystack = (docStr(doc, "actor_name") + " " + docStr(doc, "actor_id")).toAsciiLower()
                if (!haystack.contains(actorNeedle)) {
                    continue
                }
            }
            if (actionNeedle.size > 0 && !docStr(doc, "action").toAsciiLower().contains(actionNeedle)) {
                continue
            }
            if (textNeedle.size > 0) {
                let haystack = (docStr(doc, "detail") + " " + docStr(doc, "target_type") + " " +
                                docStr(doc, "target_id") + " " + docStr(doc, "ip")).toAsciiLower()
                if (!haystack.contains(textNeedle)) {
                    continue
                }
            }
            items.add(doc)
        }
        sortDocsDesc(items, "created_at")
        let total = items.size
        let start = (page - 1) * pageSize
        let out = ArrayList<JsonValue>()
        if (start < total) {
            var i = start
            while (i < total && i < start + pageSize) {
                out.add(items[i])
                i += 1
            }
        }
        pageResult(out, total, page, pageSize)
    }
}
