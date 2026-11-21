/**
 * Cangmo - comments, media, statistics, search and backups.
 */
package cangmo.service

import cangmo.core.*
import cangmo.json.*
import cangmo.http.*
import cangmo.store.*
import std.collection.*
import std.fs.*
import std.sort.*
import std.sync.*
import std.time.*

// ---------------------------------------------------------------------------
// Comments
// ---------------------------------------------------------------------------

public class CommentService {
    private let store: Store
    private let config: Config
    private let settings: SettingsService
    private let audit: AuditService
    private let limiter: RateLimiter

    public init(store: Store, config: Config, settings: SettingsService, audit: AuditService, limiter: RateLimiter) {
        this.store = store
        this.config = config
        this.settings = settings
        this.audit = audit
        this.limiter = limiter
    }

    public func create(post: JsonValue, parentId: String, name: String, email: String, url: String,
                       content: String, ip: String, userAgent: String): String {
        if (!settings.bool("comment_enabled", def: true)) {
            throw AppError("forbidden", "评论功能已关闭")
        }
        if (!docBool(post, "allow_comments", def: true)) {
            throw AppError("forbidden", "本文已关闭评论")
        }
        let author = name.trimAscii()
        let mail = email.trimAscii().toAsciiLower()
        let site = url.trimAscii()
        let body = content.trimAscii()
        if (author.size < 1 || author.size > 50) {
            throw AppError("validation", "昵称长度需在 1-50 字之间")
        }
        if (!isValidEmail(mail)) {
            throw AppError("validation", "邮箱格式无效")
        }
        if (body.size < 2 || body.size > 5000) {
            throw AppError("validation", "评论内容需在 2-5000 字之间")
        }
        if (site.size > 0 && !isValidWebUrl(site)) {
            throw AppError("validation", "网址格式无效")
        }
        let maxLinks = settings.int("comment_max_links", def: 3)
        if (countOccurrences(body.toAsciiLower(), "http") > maxLinks) {
            throw AppError("validation", "评论中的链接过多")
        }
        let rate = settings.int("comment_rate_per_hour", def: config.commentRateLimitPerHour)
        if (!limiter.allow("comment:" + hashIp(ip, config.secret), rate, 3600)) {
            throw AppError("rate_limited", "评论过于频繁，请稍后再试")
        }
        var parent = parentId.trimAscii()
        if (parent.size > 0) {
            match (store.get(COL_COMMENTS, parent)) {
                case Some(value) =>
                    if (docStr(value, "post_id") != docStr(post, "id")) {
                        parent = ""
                    }
                case None => parent = ""
            }
        }
        let moderation = settings.bool("comment_moderation", def: true)
        let id = newId("comment")
        let now = nowSeconds()
        let doc = JsonObject()
        doc.set("id", JStr(id))
        doc.set("post_id", JStr(docStr(post, "id")))
        doc.set("parent_id", JStr(parent))
        doc.set("author_name", JStr(author))
        doc.set("author_email", JStr(mail))
        doc.set("author_url", JStr(site))
        doc.set("content", JStr(body))
        doc.set("status", JStr(if (moderation) { "pending" } else { "approved" }))
        doc.set("ip_hash", JStr(hashIp(ip, config.secret)))
        doc.set("user_agent", JStr(truncateUtf8(userAgent, 300)))
        doc.set("created_at", JInt(now))
        doc.set("updated_at", JInt(now))
        store.put(COL_COMMENTS, id, JObj(doc))
        id
    }

    public func listForPost(postId: String): Array<JsonValue> {
        let items = ArrayList<JsonValue>()
        for (comment in store.list(COL_COMMENTS)) {
            if (docStr(comment, "post_id") == postId && docStr(comment, "status") == "approved") {
                items.add(comment)
            }
        }
        sortDocsAsc(items, "created_at")
        items.toArray()
    }

    public func adminList(status: String, page: Int64, pageSize: Int64,
                          query!: String = "", postId!: String = ""): PageResult {
        let needle = query.trimAscii().toAsciiLower()
        let items = ArrayList<JsonValue>()
        for (comment in store.list(COL_COMMENTS)) {
            if (status != "all" && docStr(comment, "status") != status) {
                continue
            }
            if (postId.size > 0 && docStr(comment, "post_id") != postId) {
                continue
            }
            if (needle.size > 0) {
                let haystack = (docStr(comment, "author_name") + " " + docStr(comment, "author_email") + " " +
                                docStr(comment, "content") + " " + docStr(comment, "post_id")).toAsciiLower()
                if (!haystack.contains(needle)) {
                    continue
                }
            }
            items.add(comment)
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

    public func statusCounts(): JsonValue {
        let data = JsonObject()
        var pending: Int64 = 0
        var approved: Int64 = 0
        var spam: Int64 = 0
        var trash: Int64 = 0
        var all: Int64 = 0
        for (comment in store.list(COL_COMMENTS)) {
            all += 1
            let status = docStr(comment, "status")
            if (status == "pending") {
                pending += 1
            } else if (status == "approved") {
                approved += 1
            } else if (status == "spam") {
                spam += 1
            } else if (status == "trash") {
                trash += 1
            }
        }
        data.set("all", JInt(all))
        data.set("pending", JInt(pending))
        data.set("approved", JInt(approved))
        data.set("spam", JInt(spam))
        data.set("trash", JInt(trash))
        JObj(data)
    }

    public func get(id: String): ?JsonValue {
        store.get(COL_COMMENTS, id)
    }

    public func moderate(id: String, status: String, actor: JsonValue, ip: String): Unit {
        if (status != "approved" && status != "pending" && status != "spam" && status != "trash") {
            throw AppError("validation", "无效的评论状态")
        }
        let comment = match (get(id)) {
            case Some(value) => value
            case None => throw AppError("not_found", "评论不存在")
        }
        let updated = cloneDoc(comment)
        setField(updated, "status", JStr(status))
        setField(updated, "updated_at", JInt(nowSeconds()))
        store.put(COL_COMMENTS, id, updated)
        audit.log(docStr(actor, "id"), docStr(actor, "username"), "comment_${status}", "comment", id, ip, "")
    }

    public func delete(id: String, actor: JsonValue, ip: String): Unit {
        if (get(id).isNone()) {
            throw AppError("not_found", "评论不存在")
        }
        // Remove replies as well so no orphan comments remain visible.
        let toDelete = ArrayList<String>()
        toDelete.add(id)
        var changed = true
        while (changed) {
            changed = false
            for (comment in store.list(COL_COMMENTS)) {
                let commentId = docStr(comment, "id")
                if (!toDelete.contains(commentId) && toDelete.contains(docStr(comment, "parent_id"))) {
                    toDelete.add(commentId)
                    changed = true
                }
            }
        }
        for (commentId in toDelete) {
            store.delete(COL_COMMENTS, commentId)
        }
        audit.log(docStr(actor, "id"), docStr(actor, "username"), "comment_deleted", "comment", id, ip, "")
    }

    public func pendingCount(): Int64 {
        var count: Int64 = 0
        for (comment in store.list(COL_COMMENTS)) {
            if (docStr(comment, "status") == "pending") {
                count += 1
            }
        }
        count
    }

    public func count(): Int64 {
        store.count(COL_COMMENTS)
    }

    public func recent(limit: Int64): Array<JsonValue> {
        let items = ArrayList<JsonValue>()
        for (comment in store.list(COL_COMMENTS)) {
            items.add(comment)
        }
        sortDocsDesc(items, "created_at")
        let out = ArrayList<JsonValue>()
        for (item in items) {
            if (out.size >= limit) {
                break
            }
            out.add(item)
        }
        out.toArray()
    }
}

public func isValidWebUrl(url: String): Bool {
    if (url.size > 300 || url.contains(" ") || url.contains("\n") || url.contains("\r")) {
        return false
    }
    let lower = url.toAsciiLower()
    (lower.startsWith("http://") && url.size > 8) || (lower.startsWith("https://") && url.size > 9)
}

func countOccurrences(text: String, needle: String): Int64 {
    if (needle.size == 0) {
        return 0
    }
    var count: Int64 = 0
    var from = 0
    while (true) {
        let index = findSub(text[from..text.size], needle)
        if (index < 0) {
            break
        }
        count += 1
        from += index + needle.size
        if (from >= text.size) {
            break
        }
    }
    count
}

// ---------------------------------------------------------------------------
// Media
// ---------------------------------------------------------------------------

public class ImageSize {
    public let width: Int64
    public let height: Int64

    public init(width: Int64, height: Int64) {
        this.width = width
        this.height = height
    }
}

public class MediaService {
    private let store: Store
    private let config: Config
    private let audit: AuditService

    public init(store: Store, config: Config, audit: AuditService) {
        this.store = store
        this.config = config
        this.audit = audit
    }

    public func upload(file: UploadedFile, userId: String, ip: String): JsonValue {
        if (file.data.size == 0 || file.data.size > config.maxBodyBytes) {
            throw AppError("validation", "文件为空或超过大小限制")
        }
        let original = sanitizeDisplayName(file.filename)
        let ext = extensionOf(original)
        let allowed = ["jpg", "jpeg", "png", "gif", "webp", "avif", "pdf", "mp4", "webm", "mp3"]
        if (!allowed.contains(ext)) {
            throw AppError("validation", "不允许上传该类型的文件")
        }
        if (!magicMatches(file.data, ext)) {
            throw AppError("validation", "文件内容与扩展名不符")
        }
        let id = newId("media")
        let now = nowSeconds()
        let year = formatTime(now, "yyyy")
        let month = formatTime(now, "MM")
        let relativeDir = year + "/" + month
        let dir = config.uploadsDir() + "/" + relativeDir
        ensureDir(dir)
        let storedName = id + "." + ext
        let path = dir + "/" + storedName
        try {
            File.writeTo(path, file.data)
        } catch (e: Exception) {
            throw AppError("storage", "文件保存失败：${e.message}")
        }
        let size = imageSize(file.data, ext)
        let kind = if (ext == "pdf") { "document" } else if (ext == "mp4" || ext == "webm") { "video" } else if (ext == "mp3") { "audio" } else { "image" }
        let doc = JsonObject()
        doc.set("id", JStr(id))
        doc.set("kind", JStr(kind))
        doc.set("path", JStr(relativeDir + "/" + storedName))
        doc.set("url", JStr("/media/" + relativeDir + "/" + storedName))
        doc.set("filename", JStr(storedName))
        doc.set("original_name", JStr(original))
        doc.set("mime", JStr(mimeTypeFor(storedName)))
        doc.set("size", JInt(file.data.size))
        doc.set("width", JInt(size.width))
        doc.set("height", JInt(size.height))
        doc.set("created_at", JInt(now))
        doc.set("uploaded_by", JStr(userId))
        doc.set("sha256", JStr(hexEncode(sha256(file.data)).toAsciiLower()))
        store.put(COL_MEDIA, id, JObj(doc))
        audit.log(userId, "", "media_uploaded", "media", id, ip, original)
        JObj(doc)
    }

    public func list(page: Int64, pageSize: Int64, kind!: String = "all", query!: String = ""): PageResult {
        let needle = query.trimAscii().toAsciiLower()
        let items = ArrayList<JsonValue>()
        for (item in store.list(COL_MEDIA)) {
            if (kind != "all" && mediaKindOf(item) != kind) {
                continue
            }
            if (needle.size > 0) {
                let haystack = (docStr(item, "original_name") + " " + docStr(item, "filename") + " " +
                                docStr(item, "mime")).toAsciiLower()
                if (!haystack.contains(needle)) {
                    continue
                }
            }
            items.add(item)
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

    public func counts(): JsonValue {
        let data = JsonObject()
        var all: Int64 = 0
        var images: Int64 = 0
        var videos: Int64 = 0
        var audio: Int64 = 0
        var documents: Int64 = 0
        var bytes: Int64 = 0
        for (item in store.list(COL_MEDIA)) {
            all += 1
            bytes += docInt(item, "size")
            let kind = mediaKindOf(item)
            if (kind == "image") {
                images += 1
            } else if (kind == "video") {
                videos += 1
            } else if (kind == "audio") {
                audio += 1
            } else if (kind == "document") {
                documents += 1
            }
        }
        data.set("all", JInt(all))
        data.set("image", JInt(images))
        data.set("video", JInt(videos))
        data.set("audio", JInt(audio))
        data.set("document", JInt(documents))
        data.set("bytes", JInt(bytes))
        JObj(data)
    }

    public func get(id: String): ?JsonValue {
        store.get(COL_MEDIA, id)
    }

    /** Rename only the display name; the public URL and stored file stay unchanged. */
    public func rename(id: String, name: String, actor: JsonValue, ip: String): Unit {
        let media = match (get(id)) {
            case Some(value) => value
            case None => throw AppError("not_found", "附件不存在")
        }
        let current = docStr(media, "original_name", def: docStr(media, "filename"))
        let ext = extensionOf(current)
        let trimmed = name.trimAscii()
        if (trimmed.size == 0) {
            throw AppError("validation", "名称不能为空")
        }
        if (trimmed.size > 160) {
            throw AppError("validation", "名称过长")
        }
        let inputExt = extensionOf(trimmed)
        if (inputExt.size > 0 && inputExt != ext) {
            throw AppError("validation", "不能修改附件扩展名")
        }
        var base = trimmed
        if (inputExt.size > 0 && ext.size > 0 && trimmed.size > ext.size + 1) {
            base = trimmed[0..trimmed.size - ext.size - 1]
        }
        let safe = sanitizeDisplayName(base)
        if (safe.size == 0 || safe == "file") {
            throw AppError("validation", "名称无效")
        }
        let finalName = if (ext.size > 0) { safe + "." + ext } else { safe }
        if (finalName.size > 180) {
            throw AppError("validation", "名称过长")
        }
        let updated = cloneDoc(media)
        setField(updated, "original_name", JStr(finalName))
        store.put(COL_MEDIA, id, updated)
        audit.log(docStr(actor, "id"), docStr(actor, "username"), "media_renamed", "media", id, ip, finalName)
    }

    private func usageRows(url: String): JsonArray {
        let rows = JsonArray()
        for (post in store.list(COL_POSTS)) {
            let reasons = ArrayList<String>()
            if (docStr(post, "cover") == url) {
                reasons.add("封面")
            }
            if (docStr(post, "content").contains(url)) {
                reasons.add("正文")
            }
            if (reasons.size == 0) {
                continue
            }
            let row = JsonObject()
            row.set("id", JStr(docStr(post, "id")))
            row.set("title", JStr(docStr(post, "title")))
            row.set("type", JStr(docStr(post, "type")))
            row.set("status", JStr(docStr(post, "status")))
            row.set("reason", JStr(String.join(reasons.toArray(), delimiter: "、")))
            rows.add(JObj(row))
        }
        rows
    }

    public func usage(id: String): JsonValue {
        let media = match (get(id)) {
            case Some(value) => value
            case None => throw AppError("not_found", "附件不存在")
        }
        let rows = usageRows(docStr(media, "url"))
        let data = JsonObject()
        data.set("count", JInt(rows.size()))
        data.set("items", JArr(rows))
        JObj(data)
    }

    public func delete(id: String, actor: JsonValue, ip: String, force!: Bool = false): Unit {
        let media = match (get(id)) {
            case Some(value) => value
            case None => throw AppError("not_found", "附件不存在")
        }
        if (!force) {
            let rows = usageRows(docStr(media, "url"))
            if (rows.size() > 0) {
                throw AppError("validation", "附件被 ${rows.size()} 篇内容引用，请确认后再删除")
            }
        }
        let path = config.uploadsDir() + "/" + docStr(media, "path")
        if (exists(path)) {
            try {
                remove(path, recursive: false)
            } catch (e: Exception) {}
        }
        store.delete(COL_MEDIA, id)
        audit.log(docStr(actor, "id"), docStr(actor, "username"), "media_deleted", "media", id, ip, "")
    }

    public func pathForUrl(url: String): ?String {
        if (!url.startsWith("/media/")) {
            return None
        }
        let relative = url[7..url.size]
        if (relative.size == 0 || relative.contains("..") || relative.contains("\\")) {
            return None
        }
        for (b in relative.toArray()) {
            let ok = (b >= 0x61 && b <= 0x7A) || (b >= 0x41 && b <= 0x5A) ||
                     (b >= 0x30 && b <= 0x39) || b == 0x2F || b == 0x2D ||
                     b == 0x5F || b == 0x2E
            if (!ok) {
                return None
            }
        }
        let full = config.uploadsDir() + "/" + relative
        if (!exists(full)) {
            return None
        }
        Some(full)
    }
}

func mediaKindOf(item: JsonValue): String {
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

func magicMatches(data: Array<UInt8>, ext: String): Bool {
    if (data.size < 4) {
        return false
    }
    if (ext == "jpg" || ext == "jpeg") {
        return data[0] == 0xFF && data[1] == 0xD8 && data[2] == 0xFF
    }
    if (ext == "png") {
        return data[0] == 0x89 && data[1] == 0x50 && data[2] == 0x4E && data[3] == 0x47
    }
    if (ext == "gif") {
        return data[0] == 0x47 && data[1] == 0x49 && data[2] == 0x46 && data[3] == 0x38
    }
    if (ext == "webp") {
        return data.size > 12 && data[0] == 0x52 && data[1] == 0x49 && data[2] == 0x46 && data[3] == 0x46 &&
               data[8] == 0x57 && data[9] == 0x45 && data[10] == 0x42 && data[11] == 0x50
    }
    if (ext == "pdf") {
        return data[0] == 0x25 && data[1] == 0x50 && data[2] == 0x44 && data[3] == 0x46
    }
    if (ext == "mp4") {
        return data.size > 8 && data[4] == 0x66 && data[5] == 0x74 && data[6] == 0x79 && data[7] == 0x70
    }
    if (ext == "webm") {
        return data[0] == 0x1A && data[1] == 0x45 && data[2] == 0xDF && data[3] == 0xA3
    }
    if (ext == "mp3") {
        return (data[0] == 0x49 && data[1] == 0x44 && data[2] == 0x33) ||
               (data[0] == 0xFF && (data[1] == 0xFB || data[1] == 0xF3 || data[1] == 0xF2))
    }
    if (ext == "avif") {
        return data.size > 12 && data[4] == 0x66 && data[5] == 0x74 && data[6] == 0x79 && data[7] == 0x70
    }
    false
}

func imageSize(data: Array<UInt8>, ext: String): ImageSize {
    if (ext == "png" && data.size > 24) {
        let width = (Int64(data[16]) << 24) | (Int64(data[17]) << 16) | (Int64(data[18]) << 8) | Int64(data[19])
        let height = (Int64(data[20]) << 24) | (Int64(data[21]) << 16) | (Int64(data[22]) << 8) | Int64(data[23])
        return ImageSize(width, height)
    }
    if (ext == "gif" && data.size > 10) {
        let width = Int64(data[6]) | (Int64(data[7]) << 8)
        let height = Int64(data[8]) | (Int64(data[9]) << 8)
        return ImageSize(width, height)
    }
    if (ext == "jpeg" || ext == "jpg") {
        var i: Int64 = 2
        while (i + 9 < data.size) {
            if (data[i] != 0xFF) {
                i += 1
                continue
            }
            let marker = data[i + 1]
            if (marker == 0xC0 || marker == 0xC1 || marker == 0xC2) {
                let height = (Int64(data[i + 5]) << 8) | Int64(data[i + 6])
                let width = (Int64(data[i + 7]) << 8) | Int64(data[i + 8])
                return ImageSize(width, height)
            }
            let length = (Int64(data[i + 2]) << 8) | Int64(data[i + 3])
            if (length < 2) {
                break
            }
            i += 2 + length
        }
    }
    ImageSize(0, 0)
}

// ---------------------------------------------------------------------------
// Statistics
// ---------------------------------------------------------------------------

public class StatsService {
    private let store: Store
    private let mutex: Mutex = Mutex()
    private let pendingViews: HashMap<String, Int64> = HashMap<String, Int64>()

    public init(store: Store) {
        this.store = store
    }

    public func recordView(postId: String): Unit {
        synchronized(mutex) {
            pendingViews[postId] = (pendingViews.get(postId) ?? 0) + 1
        }
    }

    public func flush(): Int64 {
        let snapshot = HashMap<String, Int64>()
        synchronized(mutex) {
            for ((id, count) in pendingViews) {
                snapshot[id] = count
            }
            pendingViews.clear()
        }
        var updated: Int64 = 0
        for ((id, count) in snapshot) {
            match (store.get(COL_POSTS, id)) {
                case Some(post) =>
                    let doc = cloneDoc(post)
                    setField(doc, "views", JInt(docInt(doc, "views") + count))
                    store.put(COL_POSTS, id, doc)
                    updated += 1
                case None => ()
            }
        }
        updated
    }

    public func totalViews(): Int64 {
        var total: Int64 = 0
        for (post in store.list(COL_POSTS)) {
            total += docInt(post, "views")
        }
        synchronized(mutex) {
            for ((_, count) in pendingViews) {
                total += count
            }
        }
        total
    }

    public func counts(): JsonValue {
        let data = JsonObject()
        var posts: Int64 = 0
        var pages: Int64 = 0
        var drafts: Int64 = 0
        var scheduled: Int64 = 0
        var comments: Int64 = 0
        var publishedComments: Int64 = 0
        var pendingComments: Int64 = 0
        for (post in store.list(COL_POSTS)) {
            if (docStr(post, "type") == "page") {
                pages += 1
            } else {
                posts += 1
            }
            let status = docStr(post, "status")
            if (status == STATUS_DRAFT) {
                drafts += 1
            } else if (status == STATUS_SCHEDULED) {
                scheduled += 1
            }
        }
        for (comment in store.list(COL_COMMENTS)) {
            comments += 1
            let status = docStr(comment, "status")
            if (status == "approved") {
                publishedComments += 1
            } else if (status == "pending") {
                pendingComments += 1
            }
        }
        data.set("posts", JInt(posts))
        data.set("pages", JInt(pages))
        data.set("drafts", JInt(drafts))
        data.set("scheduled", JInt(scheduled))
        data.set("comments", JInt(comments))
        data.set("comments_approved", JInt(publishedComments))
        data.set("comments_pending", JInt(pendingComments))
        data.set("users", JInt(store.count(COL_USERS)))
        data.set("media", JInt(store.count(COL_MEDIA)))
        data.set("views", JInt(totalViews()))
        JObj(data)
    }
}

// ---------------------------------------------------------------------------
// Search
// ---------------------------------------------------------------------------

public class SearchService {
    private let store: Store
    private let config: Config

    public init(store: Store, config: Config) {
        this.store = store
        this.config = config
    }

    public func search(query: String, limit: Int64): Array<JsonValue> {
        let needle = query.trimAscii().toAsciiLower()
        if (needle.size == 0 || needle.size > 100) {
            return Array<JsonValue>(0, repeat: JNull)
        }
        let terms = needle.split(" ")
        let items = ArrayList<JsonValue>()
        let scores = HashMap<String, Int64>()
        for (post in store.list(COL_POSTS)) {
            if (docStr(post, "status") != STATUS_PUBLISHED) {
                continue
            }
            let title = docStr(post, "title").toAsciiLower()
            let summary = docStr(post, "summary").toAsciiLower()
            let content = docStr(post, "content").toAsciiLower()
            let tags = String.join(docStrings(post, "tag_ids"), delimiter: " ").toAsciiLower()
            var score: Int64 = 0
            var matchedAll = true
            for (term in terms) {
                if (term.size == 0) {
                    continue
                }
                var termScore: Int64 = 0
                if (title.contains(term)) { termScore += 20 }
                if (summary.contains(term)) { termScore += 8 }
                if (tags.contains(term)) { termScore += 10 }
                if (content.contains(term)) { termScore += 3 }
                if (termScore == 0) {
                    matchedAll = false
                    break
                }
                score += termScore
            }
            if (!matchedAll) {
                continue
            }
            if (score > 0) {
                items.add(post)
                scores[docStr(post, "id")] = score
            }
        }
        sort<JsonValue>(items, by: { a: JsonValue, b: JsonValue =>
            let av = scores.get(docStr(a, "id")) ?? 0
            let bv = scores.get(docStr(b, "id")) ?? 0
            if (av > bv) { Ordering.GT } else if (av < bv) { Ordering.LT } else { Ordering.EQ }
        })
        let out = ArrayList<JsonValue>()
        for (item in items) {
            if (out.size >= limit) {
                break
            }
            out.add(item)
        }
        out.toArray()
    }
}

// ---------------------------------------------------------------------------
// Backups
// ---------------------------------------------------------------------------

public class BackupService {
    private let store: Store
    private let config: Config

    public init(store: Store, config: Config) {
        this.store = store
        this.config = config
    }

    public func exportJson(pretty!: Bool = true): String {
        toJson(store.exportAll(), pretty: pretty)
    }

    public func createBackup(label: String): JsonValue {
        ensureDir(config.backupDir())
        let stamp = formatTime(nowSeconds(), "yyyyMMdd-HHmmss")
        let safeLabel = sanitizeFilename(if (label.trimAscii().size > 0) { label } else { "backup" })
        let name = "${safeLabel}-${stamp}-${randomHex(bytes: 3)}.json"
        let path = config.backupDir() + "/" + name
        writeTextAtomic(path, exportJson(pretty: true))
        let result = JsonObject()
        result.set("name", JStr(name))
        result.set("size", JInt(fileSize(path)))
        result.set("created_at", JInt(nowSeconds()))
        JObj(result)
    }

    public func list(): Array<JsonValue> {
        let items = ArrayList<JsonValue>()
        ensureDir(config.backupDir())
        for (name in listDir(config.backupDir())) {
            if (!name.endsWith(".json")) {
                continue
            }
            let path = config.backupDir() + "/" + name
            let item = JsonObject()
            item.set("name", JStr(name))
            item.set("size", JInt(fileSize(path)))
            var modified: Int64 = 0
            try {
                modified = FileInfo(path).lastModificationTime.toUnixTimeStamp().toSeconds()
            } catch (e: Exception) {}
            item.set("created_at", JInt(modified))
            items.add(JObj(item))
        }
        sortDocsDesc(items, "created_at")
        items.toArray()
    }

    public func readBackup(name: String): ?String {
        if (!isSafeBackupName(name)) {
            return None
        }
        let path = config.backupDir() + "/" + name
        if (!exists(path)) {
            return None
        }
        try {
            Some(readTextFile(path))
        } catch (e: Exception) {
            None
        }
    }

    public func restore(text: String): Int64 {
        let parsed = try {
            parseJson(text)
        } catch (e: Exception) {
            throw AppError("validation", "备份文件不是有效 JSON")
        }
        let format = getInt(parsed, "format")
        if (format != 1) {
            throw AppError("validation", "不支持的备份格式")
        }
        if (getObject(parsed, "collections").isNone()) {
            throw AppError("validation", "备份缺少 collections 字段")
        }
        let count = store.replaceAll(parsed)
        // Restored sessions must not resurrect old browser sessions.
        for (id in store.listIds(COL_SESSIONS)) {
            store.delete(COL_SESSIONS, id)
        }
        count
    }

    public func deleteBackup(name: String): Unit {
        if (!isSafeBackupName(name)) {
            throw AppError("validation", "备份名称无效")
        }
        let path = config.backupDir() + "/" + name
        if (exists(path)) {
            remove(path, recursive: false)
        }
    }
}

func isSafeBackupName(name: String): Bool {
    if (name.size == 0 || name.size > 200 || name.contains("..") || name.contains("/") || name.contains("\\")) {
        return false
    }
    name.endsWith(".json")
}
