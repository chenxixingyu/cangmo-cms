/**
 * Cangmo - internal 301 redirects for moved slugs and manual aliases.
 */
package cangmo.service

import cangmo.core.*
import cangmo.json.*
import cangmo.store.*
import std.collection.*

public class RedirectService {
    private let store: Store
    private let audit: AuditService

    public init(store: Store, audit: AuditService) {
        this.store = store
        this.audit = audit
    }

    public func list(): Array<JsonValue> {
        let items = ArrayList<JsonValue>()
        for (item in store.list(COL_REDIRECTS)) {
            items.add(item)
        }
        sortDocsDesc(items, "created_at")
        items.toArray()
    }

    public func find(path: String): ?String {
        for (item in store.list(COL_REDIRECTS)) {
            if (docStr(item, "from") == path) {
                return Some(docStr(item, "to"))
            }
        }
        None
    }

    public func create(from: String, to: String, actor: JsonValue, ip: String): String {
        let source = normalizePath(from, isSource: true)
        let target = normalizePath(to, isSource: false)
        if (source == target) {
            throw AppError("validation", "源路径与目标路径不能相同")
        }
        for (item in store.list(COL_REDIRECTS)) {
            if (docStr(item, "from") == source) {
                store.delete(COL_REDIRECTS, docStr(item, "id"))
            }
        }
        let id = newId("redir")
        let doc = JsonObject()
        doc.set("id", JStr(id))
        doc.set("from", JStr(source))
        doc.set("to", JStr(target))
        doc.set("created_at", JInt(nowSeconds()))
        doc.set("created_by", JStr(docStr(actor, "id")))
        store.put(COL_REDIRECTS, id, JObj(doc))
        audit.log(docStr(actor, "id"), docStr(actor, "username"), "redirect_created", "redirect", id, ip,
                  "${source} -> ${target}")
        id
    }

    public func delete(id: String, actor: JsonValue, ip: String): Unit {
        match (store.get(COL_REDIRECTS, id)) {
            case Some(item) =>
                store.delete(COL_REDIRECTS, id)
                audit.log(docStr(actor, "id"), docStr(actor, "username"), "redirect_deleted", "redirect", id, ip,
                          docStr(item, "from"))
            case None => throw AppError("not_found", "重定向不存在")
        }
    }

    private func normalizePath(value: String, isSource!: Bool): String {
        var path = value.trimAscii()
        if (path.size == 0) {
            throw AppError("validation", "路径不能为空")
        }
        if (!path.startsWith("/")) {
            path = "/" + path
        }
        if (path.size > 300 || path.contains("..") || path.contains("?") || path.contains("#") ||
            path.contains("\\") || path.contains(":") || path.startsWith("//")) {
            throw AppError("validation", "路径格式无效")
        }
        if (path == "/" || path.startsWith("/admin") || path.startsWith("/api") ||
            path.startsWith("/static") || path.startsWith("/media")) {
            throw AppError("validation", "该路径不能用于重定向")
        }
        if (isSource && path.endsWith("/")) {
            path = path[0..path.size - 1]
        }
        path
    }
}
