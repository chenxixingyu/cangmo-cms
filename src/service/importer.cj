/**
 * Cangmo - lightweight Markdown importer with a small front-matter subset.
 */
package cangmo.service

import cangmo.core.*
import cangmo.json.*
import std.collection.*

public class ImportDoc {
    public var title: String = ""
    public var slug: String = ""
    public var summary: String = ""
    public var content: String = ""
    public var tags: Array<String> = Array<String>(0, repeat: "")
    public var category: String = ""
    public var cover: String = ""
    public var pinned: Bool = false
    public var featured: Bool = false
    public var seoTitle: String = ""
    public var seoDescription: String = ""
}

public class ImportResult {
    public let id: String
    public let title: String
    public let error: String

    public init(id: String, title: String, error: String) {
        this.id = id
        this.title = title
        this.error = error
    }
}

public func parseMarkdownDocument(raw: String, filename: String): ImportDoc {
    var text = raw.replace("\r\n", "\n").replace("\r", "\n")
    if (text.size >= 3) {
        let bytes = text.toArray()
        if (bytes[0] == 0xEF && bytes[1] == 0xBB && bytes[2] == 0xBF) {
            text = text[3..text.size]
        }
    }
    let doc = ImportDoc()
    let lines = text.split("\n")
    var bodyStart: Int64 = 0
    if (lines.size > 0 && lines[0].trimAscii() == "---") {
        var closing: Int64 = -1
        var i: Int64 = 1
        while (i < lines.size) {
            if (lines[i].trimAscii() == "---") {
                closing = i
                break
            }
            i += 1
        }
        if (closing > 0) {
            for (j in 1..closing) {
                applyImportHeader(doc, lines[j])
            }
            bodyStart = closing + 1
        }
    }
    let bodyLines = ArrayList<String>()
    var k = bodyStart
    while (k < lines.size) {
        bodyLines.add(lines[k])
        k += 1
    }
    doc.content = String.join(bodyLines.toArray(), delimiter: "\n").trimAscii()
    if (doc.title.size == 0) {
        let base = baseName(filename)
        let dot = findLastSub(base, ".")
        doc.title = if (dot > 0) { base[0..dot] } else { base }
    }
    if (doc.title.size == 0) {
        doc.title = "未命名"
    }
    doc
}

private func applyImportHeader(doc: ImportDoc, line: String): Unit {
    let trimmed = line.trimAscii()
    if (trimmed.size == 0 || trimmed.startsWith("#")) {
        return
    }
    let idx = findSub(trimmed, ":")
    if (idx <= 0) {
        return
    }
    let key = trimmed[0..idx].trimAscii().toAsciiLower()
    var value = trimmed[idx + 1..trimmed.size].trimAscii()
    if (value.size >= 2 && value[0] == 0x22 && value[value.size - 1] == 0x22) {
        value = value[1..value.size - 1]
    }
    if (key == "title") {
        doc.title = value
    } else if (key == "slug") {
        doc.slug = value
    } else if (key == "summary") {
        doc.summary = value
    } else if (key == "category") {
        doc.category = value
    } else if (key == "cover") {
        doc.cover = value
    } else if (key == "tags") {
        doc.tags = splitImportTags(value)
    } else if (key == "pinned") {
        doc.pinned = importTruthy(value)
    } else if (key == "featured") {
        doc.featured = importTruthy(value)
    } else if (key == "seo_title") {
        doc.seoTitle = value
    } else if (key == "seo_description") {
        doc.seoDescription = value
    }
}

private func importTruthy(value: String): Bool {
    let lower = value.trimAscii().toAsciiLower()
    lower == "true" || lower == "yes" || lower == "on" || lower == "1"
}

private func splitImportTags(value: String): Array<String> {
    let items = ArrayList<String>()
    for (part in value.replace("，", ",").split(",")) {
        let tag = part.trimAscii()
        if (tag.size > 0) {
            items.add(tag)
        }
    }
    items.toArray()
}

public class MarkdownImporter {
    private let posts: PostService
    private let taxonomy: TaxonomyService

    public init(posts: PostService, taxonomy: TaxonomyService) {
        this.posts = posts
        this.taxonomy = taxonomy
    }

    public func parse(raw: String, filename: String): ImportDoc {
        parseMarkdownDocument(raw, filename)
    }

    private func resolveCategory(name: String): String {
        let key = name.trimAscii()
        if (key.size == 0) {
            return ""
        }
        for (category in taxonomy.listCategories()) {
            if (docStr(category, "slug") == key || docStr(category, "name") == key) {
                return docStr(category, "id")
            }
        }
        ""
    }

    public func importOne(doc: ImportDoc, actor: JsonValue, publish: Bool, ip: String): ImportResult {
        let input = PostInput()
        input.postType = "post"
        input.title = doc.title
        input.slug = doc.slug
        input.summary = doc.summary
        input.content = doc.content
        input.status = if (publish) { STATUS_PUBLISHED } else { STATUS_DRAFT }
        input.categoryId = resolveCategory(doc.category)
        input.tagNames = doc.tags
        input.cover = doc.cover
        input.pinned = doc.pinned
        input.featured = doc.featured
        input.seoTitle = doc.seoTitle
        input.seoDescription = doc.seoDescription
        let id = posts.save(input, actor, "", ip)
        ImportResult(id, input.title, "")
    }
}
