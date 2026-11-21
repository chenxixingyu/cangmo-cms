/**
 * Cangmo - posts, pages, categories and tags.
 */
package cangmo.service

import cangmo.core.*
import cangmo.json.*
import cangmo.markdown.*
import cangmo.store.*
import std.collection.*
import std.sort.*
import std.time.*

public class PostInput {
    public var title: String = ""
    public var slug: String = ""
    public var summary: String = ""
    public var content: String = ""
    public var postType: String = "post"
    public var status: String = STATUS_DRAFT
    public var categoryId: String = ""
    public var tagNames: Array<String> = Array<String>(0, repeat: "")
    public var cover: String = ""
    public var allowComments: Bool = true
    public var pinned: Bool = false
    public var featured: Bool = false
    public var seoTitle: String = ""
    public var seoDescription: String = ""
    public var scheduledAt: Int64 = 0
}

public class PostQuery {
    public var postType: String = "post"
    public var status: String = STATUS_PUBLISHED
    public var categoryId: String = ""
    public var tagId: String = ""
    public var authorId: String = ""
    public var search: String = ""
    public var includeTrash: Bool = false
    public var sort: String = "newest"
}

public class PostService {
    private let store: Store
    private let config: Config
    private let settings: SettingsService
    private let markdown: MarkdownRenderer
    private let audit: AuditService

    public init(store: Store, config: Config, settings: SettingsService, audit: AuditService) {
        this.store = store
        this.config = config
        this.settings = settings
        this.markdown = MarkdownRenderer(allowRawHtml: config.allowRawHtml)
        this.audit = audit
    }

    public func markdownRenderer(): MarkdownRenderer {
        markdown
    }

    public func get(id: String): ?JsonValue {
        store.get(COL_POSTS, id)
    }

    public func getPublishedBySlug(slug: String, postType!: String = "post"): ?JsonValue {
        for (post in store.list(COL_POSTS)) {
            if (docStr(post, "slug") == slug && docStr(post, "type") == postType &&
                docStr(post, "status") == STATUS_PUBLISHED) {
                return Some(post)
            }
        }
        None
    }

    public func save(input: PostInput, actor: JsonValue, id: String, ip: String): String {
        let actorId = docStr(actor, "id")
        let role = docStr(actor, "role")
        let isPage = input.postType == "page"
        if (isPage && role != ROLE_ADMIN && role != ROLE_EDITOR) {
            throw AppError("forbidden", "无权管理页面")
        }
        if (!isPage && input.postType != "post") {
            throw AppError("validation", "无效的内容类型")
        }
        let title = input.title.trimAscii()
        if (title.size == 0 || title.size > 200) {
            throw AppError("validation", "标题长度需在 1-200 字之间")
        }
        if (input.content.size > 1024 * 1024) {
            throw AppError("validation", "正文超过 1MB 限制")
        }
        let allowedStatus = [STATUS_DRAFT, STATUS_PUBLISHED, STATUS_SCHEDULED]
        if (!allowedStatus.contains(input.status)) {
            throw AppError("validation", "无效的发布状态")
        }
        let existing: ?JsonValue = if (id.size > 0) { get(id) } else { None }
        if (id.size > 0) {
            match (existing) {
                case Some(post) =>
                    if (!canEdit(actor, post)) {
                        throw AppError("forbidden", "无权编辑此内容")
                    }
                case None => throw AppError("not_found", "内容不存在")
            }
        } else {
            if (!canCreate(actor, input.postType)) {
                throw AppError("forbidden", "无权创建内容")
            }
        }
        if ((input.status == STATUS_PUBLISHED || input.status == STATUS_SCHEDULED) && !canPublish(actor)) {
            throw AppError("forbidden", "你的角色不能发布或定时发布内容，请先保存为草稿")
        }
        var status = input.status
        var scheduledAt = input.scheduledAt
        if (status == STATUS_SCHEDULED) {
            if (scheduledAt <= nowSeconds()) {
                status = STATUS_PUBLISHED
                scheduledAt = 0
            }
        }
        let now = nowSeconds()
        let content = input.content
        let rendered = markdown.render(content)
        var summary = input.summary.trimAscii()
        if (summary.size == 0) {
            summary = makeExcerpt(rendered.html, maxRunes: 160)
        }
        summary = truncateUtf8(summary, 500)
        var categoryId = input.categoryId.trimAscii()
        if (!isPage && categoryId.size == 0) {
            categoryId = ensureDefaultCategory()
        }
        if (!isPage && categoryId.size > 0 && store.get(COL_CATEGORIES, categoryId).isNone()) {
            throw AppError("validation", "分类不存在")
        }
        let tagIds = if (isPage) { Array<String>(0, repeat: "") } else { resolveTags(input.tagNames) }
        let cover = input.cover.trimAscii()
        if (cover.size > 0 && !cover.startsWith("/media/") && !isValidWebUrl(cover)) {
            throw AppError("validation", "封面地址需为附件库链接或 http(s) 地址")
        }
        let postId = if (id.size > 0) { id } else { newId("post") }
        let slug = uniqueSlug(input.slug, title, postId)
        let postDoc = match (existing) {
            case Some(value) => cloneDoc(value)
            case None => jobj()
        }
        // Keep a revision before overwriting an existing post.
        if (id.size > 0) {
            match (existing) {
                case Some(value) => saveRevision(value, actorId)
                case None => ()
            }
        }
        let previousPublishedAt = docInt(postDoc, "published_at")
        let publishedAt = if (status == STATUS_PUBLISHED) {
            if (previousPublishedAt > 0) { previousPublishedAt } else { now }
        } else {
            previousPublishedAt
        }
        setField(postDoc, "id", JStr(postId))
        setField(postDoc, "type", JStr(input.postType))
        setField(postDoc, "title", JStr(title))
        setField(postDoc, "slug", JStr(slug))
        setField(postDoc, "summary", JStr(summary))
        setField(postDoc, "content", JStr(content))
        setField(postDoc, "content_html", JStr(rendered.html))
        setField(postDoc, "headings", headingsJson(rendered.headings))
        setField(postDoc, "status", JStr(status))
        setField(postDoc, "author_id", JStr(if (id.size > 0) { docStr(postDoc, "author_id") } else { actorId }))
        setField(postDoc, "category_id", JStr(categoryId))
        setField(postDoc, "tag_ids", jsonStringList(tagIds))
        setField(postDoc, "cover", JStr(cover))
        setField(postDoc, "allow_comments", JBool(input.allowComments))
        setField(postDoc, "pinned", JBool(input.pinned))
        setField(postDoc, "featured", JBool(input.featured))
        setField(postDoc, "seo_title", JStr(truncateUtf8(input.seoTitle.trimAscii(), 200)))
        setField(postDoc, "seo_description", JStr(truncateUtf8(input.seoDescription.trimAscii(), 300)))
        setField(postDoc, "scheduled_at", JInt(scheduledAt))
        setField(postDoc, "reading_minutes", JInt(readingMinutes(content)))
        setField(postDoc, "created_at", JInt(if (id.size > 0) { docInt(postDoc, "created_at") } else { now }))
        setField(postDoc, "updated_at", JInt(now))
        setField(postDoc, "published_at", JInt(publishedAt))
        setField(postDoc, "views", JInt(docInt(postDoc, "views")))
        store.put(COL_POSTS, postId, postDoc)
        audit.log(actorId, docStr(actor, "username"), if (id.size > 0) { "post_updated" } else { "post_created" },
                  input.postType, postId, ip, "status=${status} slug=${slug}")
        postId
    }

    /** Copy a post/page into a fresh draft owned by the actor. */
    public func duplicate(id: String, actor: JsonValue, ip: String): String {
        let post = match (get(id)) {
            case Some(value) => value
            case None => throw AppError("not_found", "内容不存在")
        }
        if (!canEdit(actor, post)) {
            throw AppError("forbidden", "无权复制此内容")
        }
        let postType = docStr(post, "type", def: "post")
        if (!canCreate(actor, postType)) {
            throw AppError("forbidden", "无权创建内容")
        }
        var categoryId = docStr(post, "category_id")
        if (categoryId.size > 0 && store.get(COL_CATEGORIES, categoryId).isNone()) {
            categoryId = ""
        }
        let tagNames = ArrayList<String>()
        for (tagId in docStrings(post, "tag_ids")) {
            match (store.get(COL_TAGS, tagId)) {
                case Some(tag) => tagNames.add(docStr(tag, "name"))
                case None => ()
            }
        }
        let input = PostInput()
        input.postType = postType
        input.title = truncateUtf8(docStr(post, "title", def: "未命名") + "（副本）", 200)
        input.slug = ""
        input.summary = docStr(post, "summary")
        input.content = docStr(post, "content")
        input.status = STATUS_DRAFT
        input.categoryId = categoryId
        input.tagNames = tagNames.toArray()
        input.cover = docStr(post, "cover")
        input.allowComments = docBool(post, "allow_comments", def: true)
        input.seoTitle = docStr(post, "seo_title")
        input.seoDescription = docStr(post, "seo_description")
        save(input, actor, "", ip)
    }

    private func canCreate(actor: JsonValue, postType: String): Bool {
        let role = docStr(actor, "role")
        if (postType == "page") {
            return role == ROLE_ADMIN || role == ROLE_EDITOR
        }
        return role == ROLE_ADMIN || role == ROLE_EDITOR || role == ROLE_AUTHOR || role == ROLE_CONTRIBUTOR
    }

    private func canPublish(actor: JsonValue): Bool {
        let role = docStr(actor, "role")
        role == ROLE_ADMIN || role == ROLE_EDITOR || role == ROLE_AUTHOR
    }

    public func canEdit(actor: JsonValue, post: JsonValue): Bool {
        let role = docStr(actor, "role")
        if (role == ROLE_ADMIN || role == ROLE_EDITOR) {
            return true
        }
        let authorId = docStr(post, "author_id")
        if (authorId != docStr(actor, "id")) {
            return false
        }
        if (role == ROLE_AUTHOR) {
            return true
        }
        if (role == ROLE_CONTRIBUTOR) {
            return docStr(post, "status") == STATUS_DRAFT
        }
        false
    }

    public func saveRevision(post: JsonValue, actorId: String): Unit {
        let revision = JsonObject()
        revision.set("id", JStr(newId("rev")))
        revision.set("post_id", JStr(docStr(post, "id")))
        revision.set("title", JStr(docStr(post, "title")))
        revision.set("content", JStr(docStr(post, "content")))
        revision.set("summary", JStr(docStr(post, "summary")))
        revision.set("status", JStr(docStr(post, "status")))
        revision.set("slug", JStr(docStr(post, "slug")))
        revision.set("category_id", JStr(docStr(post, "category_id")))
        revision.set("tag_ids", match (post.get("tag_ids")) { case Some(value) => value; case None => jarr() })
        revision.set("cover", JStr(docStr(post, "cover")))
        revision.set("allow_comments", JBool(docBool(post, "allow_comments", def: true)))
        revision.set("pinned", JBool(docBool(post, "pinned")))
        revision.set("featured", JBool(docBool(post, "featured")))
        revision.set("seo_title", JStr(docStr(post, "seo_title")))
        revision.set("seo_description", JStr(docStr(post, "seo_description")))
        revision.set("scheduled_at", JInt(docInt(post, "scheduled_at")))
        revision.set("created_at", JInt(nowSeconds()))
        revision.set("author_id", JStr(actorId))
        store.put(COL_REVISIONS, docStr(JObj(revision), "id"), JObj(revision))
        trimRevisions(docStr(post, "id"))
    }

    private func trimRevisions(postId: String): Unit {
        let items = ArrayList<JsonValue>()
        for (revision in store.list(COL_REVISIONS)) {
            if (docStr(revision, "post_id") == postId) {
                items.add(revision)
            }
        }
        if (items.size <= 20) {
            return
        }
        sortDocsAsc(items, "created_at")
        let removeCount = items.size - 20
        var removed: Int64 = 0
        for (revision in items) {
            if (removed >= removeCount) {
                break
            }
            store.delete(COL_REVISIONS, docStr(revision, "id"))
            removed += 1
        }
    }

    public func revisions(postId: String): Array<JsonValue> {
        let items = ArrayList<JsonValue>()
        for (revision in store.list(COL_REVISIONS)) {
            if (docStr(revision, "post_id") == postId) {
                items.add(revision)
            }
        }
        sortDocsDesc(items, "created_at")
        items.toArray()
    }

    public func revision(postId: String, revisionId: String): ?JsonValue {
        match (store.get(COL_REVISIONS, revisionId)) {
            case Some(value) =>
                if (docStr(value, "post_id") == postId) {
                    return Some(value)
                }
            case None => ()
        }
        None
    }

    /**
     * Restore a snapshot as a draft. Current slug is preserved so links stay stable;
     * the current content is saved as a new revision first, making the restore undoable.
     */
    public func restoreRevision(postId: String, revisionId: String, actor: JsonValue, ip: String): String {
        let post = match (get(postId)) {
            case Some(value) => value
            case None => throw AppError("not_found", "内容不存在")
        }
        if (!canEdit(actor, post)) {
            throw AppError("forbidden", "无权恢复此内容")
        }
        let snapshot = match (revision(postId, revisionId)) {
            case Some(value) => value
            case None => throw AppError("not_found", "版本不存在")
        }
        let currentCategory = docStr(post, "category_id")
        let categoryId = match (snapshot.get("category_id")) {
            case Some(JStr(value)) => value
            case _ => currentCategory
        }
        let validCategory = if (categoryId.size > 0 && store.get(COL_CATEGORIES, categoryId).isSome()) {
            categoryId
        } else {
            ""
        }
        let tagIds = ArrayList<String>()
        match (snapshot.get("tag_ids")) {
            case Some(JArr(items)) =>
                for (item in items.items) {
                    match (item) {
                        case JStr(value) => tagIds.add(value)
                        case _ => ()
                    }
                }
            case _ =>
                for (tagId in docStrings(post, "tag_ids")) {
                    tagIds.add(tagId)
                }
        }
        let tagNames = ArrayList<String>()
        for (tagId in tagIds) {
            if (tagId.size == 0) {
                continue
            }
            match (store.get(COL_TAGS, tagId)) {
                case Some(tag) => tagNames.add(docStr(tag, "name"))
                case None => ()
            }
        }
        let input = PostInput()
        input.postType = docStr(post, "type", def: "post")
        input.title = docStr(snapshot, "title", def: docStr(post, "title"))
        input.content = docStr(snapshot, "content", def: docStr(post, "content"))
        input.summary = docStr(snapshot, "summary", def: docStr(post, "summary"))
        input.slug = docStr(post, "slug")
        input.categoryId = validCategory
        input.tagNames = tagNames.toArray()
        input.cover = docStr(snapshot, "cover", def: docStr(post, "cover"))
        input.allowComments = docBool(snapshot, "allow_comments", def: docBool(post, "allow_comments", def: true))
        input.pinned = docBool(snapshot, "pinned", def: docBool(post, "pinned"))
        input.featured = docBool(snapshot, "featured", def: docBool(post, "featured"))
        input.seoTitle = docStr(snapshot, "seo_title", def: docStr(post, "seo_title"))
        input.seoDescription = docStr(snapshot, "seo_description", def: docStr(post, "seo_description"))
        input.status = STATUS_DRAFT
        input.scheduledAt = 0
        let savedId = save(input, actor, postId, ip)
        audit.log(docStr(actor, "id"), docStr(actor, "username"), "post_revision_restored",
                  input.postType, postId, ip, "revision=${revisionId}")
        savedId
    }

    private func headingsJson(headings: Array<Heading>): JsonValue {
        let arr = JsonArray()
        for (heading in headings) {
            let item = JsonObject()
            item.set("level", JInt(heading.level))
            item.set("text", JStr(heading.text))
            item.set("id", JStr(heading.id))
            arr.add(JObj(item))
        }
        JArr(arr)
    }

    private func resolveTags(names: Array<String>): Array<String> {
        let ids = ArrayList<String>()
        for (name in names) {
            let trimmed = name.trimAscii()
            if (trimmed.size == 0 || trimmed.size > 40) {
                continue
            }
            let id = ensureTag(trimmed)
            if (!ids.contains(id)) {
                ids.add(id)
            }
        }
        ids.toArray()
    }

    public func ensureTag(name: String): String {
        let needle = name.trimAscii()
        for (tag in store.list(COL_TAGS)) {
            if (docStr(tag, "name").toAsciiLower() == needle.toAsciiLower()) {
                return docStr(tag, "id")
            }
        }
        let id = newId("tag")
        let doc = JsonObject()
        doc.set("id", JStr(id))
        doc.set("name", JStr(needle))
        doc.set("slug", JStr(uniqueTaxonomySlug(needle, COL_TAGS, "")))
        doc.set("created_at", JInt(nowSeconds()))
        store.put(COL_TAGS, id, JObj(doc))
        id
    }

    public func ensureDefaultCategory(): String {
        // A settings key keeps the default stable across restarts.
        let defaultId = settings.str("default_category")
        if (defaultId.size > 0 && store.exists(COL_CATEGORIES, defaultId)) {
            return defaultId
        }
        for (category in store.list(COL_CATEGORIES)) {
            let id = docStr(category, "id")
            if (id.size > 0) {
                settings.setString("default_category", id)
                return id
            }
        }
        let id = newId("cat")
        let doc = JsonObject()
        doc.set("id", JStr(id))
        doc.set("name", JStr("未分类"))
        doc.set("slug", JStr("uncategorized"))
        doc.set("description", JStr(""))
        doc.set("sort", JInt(0))
        doc.set("created_at", JInt(nowSeconds()))
        store.put(COL_CATEGORIES, id, JObj(doc))
        settings.setString("default_category", id)
        id
    }

    private func uniqueTaxonomySlug(name: String, collection: String, excludeId: String): String {
        var base = slugify(name)
        if (base.size == 0) {
            let prefix = if (collection == COL_TAGS) { "tag-" } else { "category-" }
            base = prefix + sha256Hex(name)[0..8]
        }
        var candidate = base
        var counter = 2
        while (true) {
            var taken = false
            for (doc in store.list(collection)) {
                if (docStr(doc, "slug") == candidate && docStr(doc, "id") != excludeId) {
                    taken = true
                    break
                }
            }
            if (!taken) {
                return candidate
            }
            candidate = "${base}-${counter}"
            counter += 1
        }
        base
    }

    public func uniqueSlug(requested: String, title: String, postId: String): String {
        var base = requested.trimAscii().toAsciiLower()
        if (!isValidSlug(base)) {
            base = slugify(title)
        }
        if (base.size == 0) {
            base = "p-" + sha256Hex(title)[0..8]
        }
        if (base.size > 80) {
            base = truncateUtf8(base, 80)
        }
        var candidate = base
        var counter = 2
        while (true) {
            var taken = false
            for (post in store.list(COL_POSTS)) {
                if (docStr(post, "slug") == candidate && docStr(post, "id") != postId) {
                    taken = true
                    break
                }
            }
            if (!taken) {
                return candidate
            }
            candidate = "${base}-${counter}"
            counter += 1
        }
        base
    }

    public func list(query: PostQuery, page: Int64, pageSize: Int64): PageResult {
        let items = ArrayList<JsonValue>()
        let needle = query.search.trimAscii().toAsciiLower()
        for (post in store.list(COL_POSTS)) {
            if (query.postType != "any" && docStr(post, "type") != query.postType) {
                continue
            }
            if (query.status != "any" && docStr(post, "status") != query.status) {
                continue
            }
            if (!query.includeTrash && docStr(post, "status") == STATUS_TRASH) {
                continue
            }
            if (query.categoryId.size > 0 && docStr(post, "category_id") != query.categoryId) {
                continue
            }
            if (query.authorId.size > 0 && docStr(post, "author_id") != query.authorId) {
                continue
            }
            if (query.tagId.size > 0 && !docStrings(post, "tag_ids").contains(query.tagId)) {
                continue
            }
            if (needle.size > 0) {
                let haystack = (docStr(post, "title") + " " + docStr(post, "summary") + " " +
                                docStr(post, "content")).toAsciiLower()
                if (!haystack.contains(needle)) {
                    continue
                }
            }
            items.add(post)
        }
        if (query.sort == "oldest") {
            sortDocsAsc(items, "published_at")
        } else if (query.sort == "views") {
            sortDocsDesc(items, "views")
        } else {
            sortDocsDesc(items, "published_at")
        }
        let total = items.size
        let safePage = if (page < 1) { 1 } else { page }
        let start = (safePage - 1) * pageSize
        let out = ArrayList<JsonValue>()
        if (start < total) {
            var i = start
            while (i < total && i < start + pageSize) {
                out.add(items[i])
                i += 1
            }
        }
        pageResult(out, total, safePage, pageSize)
    }

    public func publishedPosts(): Array<JsonValue> {
        let items = ArrayList<JsonValue>()
        for (post in store.list(COL_POSTS)) {
            if (docStr(post, "type") == "post" && docStr(post, "status") == STATUS_PUBLISHED) {
                items.add(post)
            }
        }
        sortDocsDesc(items, "published_at")
        items.toArray()
    }

    public func publishedPages(): Array<JsonValue> {
        let items = ArrayList<JsonValue>()
        for (post in store.list(COL_POSTS)) {
            if (docStr(post, "type") == "page" && docStr(post, "status") == STATUS_PUBLISHED) {
                items.add(post)
            }
        }
        sortDocsDesc(items, "published_at")
        items.toArray()
    }

    public func publish(id: String, actor: JsonValue, ip: String): Unit {
        let post = match (get(id)) {
            case Some(value) => value
            case None => throw AppError("not_found", "内容不存在")
        }
        if (!canEdit(actor, post)) {
            throw AppError("forbidden", "无权操作此内容")
        }
        if (!canPublish(actor)) {
            throw AppError("forbidden", "你的角色不能发布内容")
        }
        let updated = cloneDoc(post)
        setField(updated, "status", JStr(STATUS_PUBLISHED))
        if (docInt(updated, "published_at") == 0) {
            setField(updated, "published_at", JInt(nowSeconds()))
        }
        setField(updated, "updated_at", JInt(nowSeconds()))
        store.put(COL_POSTS, id, updated)
        audit.log(docStr(actor, "id"), docStr(actor, "username"), "post_published", "post", id, ip, "")
    }

    public func moveToTrash(id: String, actor: JsonValue, ip: String): Unit {
        let post = match (get(id)) {
            case Some(value) => value
            case None => throw AppError("not_found", "内容不存在")
        }
        if (!canEdit(actor, post)) {
            throw AppError("forbidden", "无权操作此内容")
        }
        let updated = cloneDoc(post)
        setField(updated, "status", JStr(STATUS_TRASH))
        setField(updated, "updated_at", JInt(nowSeconds()))
        store.put(COL_POSTS, id, updated)
        audit.log(docStr(actor, "id"), docStr(actor, "username"), "post_trashed", "post", id, ip, "")
    }

    public func restore(id: String, actor: JsonValue, ip: String): Unit {
        let post = match (get(id)) {
            case Some(value) => value
            case None => throw AppError("not_found", "内容不存在")
        }
        if (!canEdit(actor, post)) {
            throw AppError("forbidden", "无权操作此内容")
        }
        let updated = cloneDoc(post)
        setField(updated, "status", JStr(STATUS_DRAFT))
        setField(updated, "updated_at", JInt(nowSeconds()))
        store.put(COL_POSTS, id, updated)
        audit.log(docStr(actor, "id"), docStr(actor, "username"), "post_restored", "post", id, ip, "")
    }

    public func deletePermanently(id: String, actor: JsonValue, ip: String): Unit {
        let post = match (get(id)) {
            case Some(value) => value
            case None => throw AppError("not_found", "内容不存在")
        }
        if (!isAdminOrEditor(actor)) {
            throw AppError("forbidden", "只有管理员或编辑可以永久删除")
        }
        store.delete(COL_POSTS, id)
        for (comment in store.list(COL_COMMENTS)) {
            if (docStr(comment, "post_id") == id) {
                store.delete(COL_COMMENTS, docStr(comment, "id"))
            }
        }
        for (revision in store.list(COL_REVISIONS)) {
            if (docStr(revision, "post_id") == id) {
                store.delete(COL_REVISIONS, docStr(revision, "id"))
            }
        }
        audit.log(docStr(actor, "id"), docStr(actor, "username"), "post_deleted", "post", id, ip, "")
    }

    private func isAdminOrEditor(actor: JsonValue): Bool {
        let role = docStr(actor, "role")
        role == ROLE_ADMIN || role == ROLE_EDITOR
    }

    public func publishDue(): Int64 {
        let now = nowSeconds()
        var count: Int64 = 0
        for (post in store.list(COL_POSTS)) {
            if (docStr(post, "status") == STATUS_SCHEDULED && docInt(post, "scheduled_at") <= now &&
                docInt(post, "scheduled_at") > 0) {
                let updated = cloneDoc(post)
                setField(updated, "status", JStr(STATUS_PUBLISHED))
                setField(updated, "published_at", JInt(now))
                setField(updated, "updated_at", JInt(now))
                store.put(COL_POSTS, docStr(post, "id"), updated)
                count += 1
            }
        }
        count
    }

    public func related(post: JsonValue, limit: Int64): Array<JsonValue> {
        let postId = docStr(post, "id")
        let categoryId = docStr(post, "category_id")
        let tagIds = docStrings(post, "tag_ids")
        let candidates = ArrayList<JsonValue>()
        let scores = HashMap<String, Int64>()
        for (other in store.list(COL_POSTS)) {
            if (docStr(other, "id") == postId || docStr(other, "type") != "post" ||
                docStr(other, "status") != STATUS_PUBLISHED) {
                continue
            }
            var score: Int64 = 0
            if (categoryId.size > 0 && docStr(other, "category_id") == categoryId) {
                score += 2
            }
            for (tagId in tagIds) {
                if (docStrings(other, "tag_ids").contains(tagId)) {
                    score += 3
                }
            }
            if (score > 0) {
                candidates.add(other)
                scores[docStr(other, "id")] = score
            }
        }
        sort<JsonValue>(candidates, by: { a: JsonValue, b: JsonValue =>
            let av = scores.get(docStr(a, "id")) ?? 0
            let bv = scores.get(docStr(b, "id")) ?? 0
            if (av > bv) { Ordering.GT } else if (av < bv) { Ordering.LT } else { Ordering.EQ }
        })
        let out = ArrayList<JsonValue>()
        for (item in candidates) {
            if (out.size >= limit) {
                break
            }
            out.add(item)
        }
        out.toArray()
    }

    public func archiveCounts(): Array<(String, Int64)> {
        let counts = HashMap<String, Int64>()
        for (post in store.list(COL_POSTS)) {
            if (docStr(post, "type") != "post" || docStr(post, "status") != STATUS_PUBLISHED) {
                continue
            }
            let key = formatTime(docInt(post, "published_at"), "yyyy-MM")
            if (key.size == 0) {
                continue
            }
            counts[key] = (counts.get(key) ?? 0) + 1
        }
        let keys = counts.keys().toArray()
        sort<String>(keys, descending: true)
        let out = ArrayList<(String, Int64)>()
        for (key in keys) {
            out.add((key, counts[key]))
        }
        out.toArray()
    }
}

public class TaxonomyService {
    private let store: Store
    private let audit: AuditService

    public init(store: Store, audit: AuditService) {
        this.store = store
        this.audit = audit
    }

    public func listCategories(): Array<JsonValue> {
        let items = ArrayList<JsonValue>()
        for (category in store.list(COL_CATEGORIES)) {
            items.add(category)
        }
        sort<JsonValue>(items, by: { a: JsonValue, b: JsonValue =>
            let av = docInt(a, "sort")
            let bv = docInt(b, "sort")
            if (av > bv) { Ordering.GT } else if (av < bv) { Ordering.LT } else { Ordering.EQ }
        })
        items.toArray()
    }

    public func getCategory(id: String): ?JsonValue {
        store.get(COL_CATEGORIES, id)
    }

    public func categoryBySlug(slug: String): ?JsonValue {
        for (category in store.list(COL_CATEGORIES)) {
            if (docStr(category, "slug") == slug) {
                return Some(category)
            }
        }
        None
    }

    public func createCategory(name: String, slug: String, description: String, ip: String): String {
        let trimmed = name.trimAscii()
        if (trimmed.size == 0 || trimmed.size > 60) {
            throw AppError("validation", "分类名称需在 1-60 字之间")
        }
        let finalSlug = uniqueSlug(slug, trimmed, COL_CATEGORIES, "")
        let id = newId("cat")
        let doc = JsonObject()
        doc.set("id", JStr(id))
        doc.set("name", JStr(trimmed))
        doc.set("slug", JStr(finalSlug))
        doc.set("description", JStr(truncateUtf8(description.trimAscii(), 300)))
        doc.set("sort", JInt(0))
        doc.set("created_at", JInt(nowSeconds()))
        store.put(COL_CATEGORIES, id, JObj(doc))
        audit.log("", "", "category_created", "category", id, ip, trimmed)
        id
    }

    public func updateCategory(id: String, name: String, slug: String, description: String, ip: String): Unit {
        let category = match (store.get(COL_CATEGORIES, id)) {
            case Some(value) => value
            case None => throw AppError("not_found", "分类不存在")
        }
        let trimmed = name.trimAscii()
        if (trimmed.size == 0) {
            throw AppError("validation", "分类名称不能为空")
        }
        let updated = cloneDoc(category)
        setField(updated, "name", JStr(trimmed))
        setField(updated, "slug", JStr(uniqueSlug(slug, trimmed, COL_CATEGORIES, id)))
        setField(updated, "description", JStr(truncateUtf8(description.trimAscii(), 300)))
        store.put(COL_CATEGORIES, id, updated)
        audit.log("", "", "category_updated", "category", id, ip, trimmed)
    }

    public func deleteCategory(id: String, ip: String): Unit {
        if (store.count(COL_CATEGORIES) <= 1) {
            throw AppError("validation", "至少需要保留一个分类")
        }
        // Move posts to another category first.
        let remaining = store.list(COL_CATEGORIES)
        var fallbackId = ""
        for (category in remaining) {
            if (docStr(category, "id") != id) {
                fallbackId = docStr(category, "id")
                break
            }
        }
        for (post in store.list(COL_POSTS)) {
            if (docStr(post, "category_id") == id) {
                let updated = cloneDoc(post)
                setField(updated, "category_id", JStr(fallbackId))
                store.put(COL_POSTS, docStr(post, "id"), updated)
            }
        }
        store.delete(COL_CATEGORIES, id)
        audit.log("", "", "category_deleted", "category", id, ip, "")
    }

    public func listTags(): Array<JsonValue> {
        let items = ArrayList<JsonValue>()
        for (tag in store.list(COL_TAGS)) {
            let doc = cloneDoc(tag)
            var count: Int64 = 0
            for (post in store.list(COL_POSTS)) {
                if (docStr(post, "type") == "post" && docStr(post, "status") == STATUS_PUBLISHED &&
                    docStrings(post, "tag_ids").contains(docStr(tag, "id"))) {
                    count += 1
                }
            }
            setField(doc, "post_count", JInt(count))
            items.add(doc)
        }
        sort<JsonValue>(items, by: { a: JsonValue, b: JsonValue =>
            let ac = docInt(a, "post_count")
            let bc = docInt(b, "post_count")
            if (ac > bc) { Ordering.GT } else if (ac < bc) { Ordering.LT } else { Ordering.EQ }
        })
        items.toArray()
    }

    public func tagBySlug(slug: String): ?JsonValue {
        for (tag in store.list(COL_TAGS)) {
            if (docStr(tag, "slug") == slug) {
                return Some(tag)
            }
        }
        None
    }

    public func tagsForPost(post: JsonValue): Array<JsonValue> {
        let result = ArrayList<JsonValue>()
        for (id in docStrings(post, "tag_ids")) {
            match (store.get(COL_TAGS, id)) {
                case Some(tag) => result.add(tag)
                case None => ()
            }
        }
        result.toArray()
    }

    public func deleteTag(id: String, ip: String): Unit {
        store.delete(COL_TAGS, id)
        for (post in store.list(COL_POSTS)) {
            let ids = docStrings(post, "tag_ids")
            if (ids.contains(id)) {
                let kept = ArrayList<String>()
                for (tagId in ids) {
                    if (tagId != id) {
                        kept.add(tagId)
                    }
                }
                let updated = cloneDoc(post)
                setField(updated, "tag_ids", jsonStringList(kept.toArray()))
                store.put(COL_POSTS, docStr(post, "id"), updated)
            }
        }
        audit.log("", "", "tag_deleted", "tag", id, ip, "")
    }

    private func uniqueSlug(requested: String, name: String, collection: String, excludeId: String): String {
        var base = requested.trimAscii().toAsciiLower()
        if (!isValidSlug(base)) {
            base = slugify(name)
        }
        if (base.size == 0) {
            let prefix = if (collection == COL_TAGS) { "tag-" } else { "category-" }
            base = prefix + sha256Hex(name)[0..8]
        }
        var candidate = base
        var counter = 2
        while (true) {
            var taken = false
            for (doc in store.list(collection)) {
                if (docStr(doc, "slug") == candidate && docStr(doc, "id") != excludeId) {
                    taken = true
                    break
                }
            }
            if (!taken) {
                return candidate
            }
            candidate = "${base}-${counter}"
            counter += 1
        }
        base
    }

    public func ensureDefaultCategory(settings: SettingsService): String {
        let configured = settings.str("default_category")
        if (configured.size > 0 && store.exists(COL_CATEGORIES, configured)) {
            return configured
        }
        for (category in store.list(COL_CATEGORIES)) {
            let id = docStr(category, "id")
            if (id.size > 0) {
                settings.setString("default_category", id)
                return id
            }
        }
        let id = newId("cat")
        let doc = JsonObject()
        doc.set("id", JStr(id))
        doc.set("name", JStr("未分类"))
        doc.set("slug", JStr("uncategorized"))
        doc.set("description", JStr(""))
        doc.set("sort", JInt(0))
        doc.set("created_at", JInt(nowSeconds()))
        store.put(COL_CATEGORIES, id, JObj(doc))
        settings.setString("default_category", id)
        id
    }
}
