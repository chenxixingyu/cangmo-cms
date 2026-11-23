/**
 * Cangmo - site registry and default-site migration for multi-site v2.0.
 */
package cangmo.service

import cangmo.core.*
import cangmo.json.*
import cangmo.store.*
import std.collection.*

public let DEFAULT_SITE_ID: String = "site_default"

public class SiteService {
    private let store: Store
    private let settings: SettingsService
    private let config: Config

    public init(store: Store, settings: SettingsService, config: Config) {
        this.store = store
        this.settings = settings
        this.config = config
    }

    public func ensureDefault(): Unit {
        if (store.get(COL_SITES, DEFAULT_SITE_ID).isNone()) {
            let doc = JsonObject()
            doc.set("id", JStr(DEFAULT_SITE_ID))
            doc.set("name", JStr(settings.str("site_title", def: config.siteTitle)))
            doc.set("domains", jsonStringList([hostOf(settings.str("site_url", def: config.siteUrl))]))
            doc.set("theme", JStr(settings.str("theme", def: config.theme)))
            doc.set("status", JStr("active"))
            doc.set("created_at", JInt(nowSeconds()))
            store.put(COL_SITES, DEFAULT_SITE_ID, JObj(doc))
        }
        migrateSiteIds()
    }

    public func list(): Array<JsonValue> {
        let items = ArrayList<JsonValue>()
        for (item in store.list(COL_SITES)) {
            items.add(item)
        }
        sortDocsDesc(items, "created_at")
        items.toArray()
    }

    public func get(id: String): ?JsonValue {
        store.get(COL_SITES, id)
    }

    public func theme(siteId: String): String {
        match (store.get(COL_SITES, siteId)) {
            case Some(site) =>
                let value = docStr(site, "theme")
                if (value.size > 0) { value } else { settings.str("theme", def: config.theme) }
            case None => settings.str("theme", def: config.theme)
        }
    }

    public func setTheme(siteId: String, theme: String): Unit {
        match (store.get(COL_SITES, siteId)) {
            case Some(site) =>
                let updated = cloneDoc(site)
                setField(updated, "theme", JStr(theme))
                store.put(COL_SITES, siteId, updated)
            case None => throw AppError("not_found", "站点不存在")
        }
    }

    public func defaultSite(): JsonValue {
        match (store.get(COL_SITES, DEFAULT_SITE_ID)) {
            case Some(value) => value
            case None => JNull
        }
    }

    public func create(name: String, domain: String): String {
        let title = name.trimAscii()
        let host = domain.trimAscii().toAsciiLower()
        if (title.size == 0 || title.size > 100) {
            throw AppError("validation", "站点名称长度无效")
        }
        if (host.size == 0 || host.size > 200 || host.contains("/") || host.contains(" ")) {
            throw AppError("validation", "域名格式无效")
        }
        for (site in store.list(COL_SITES)) {
            for (existing in docStrings(site, "domains")) {
                if (existing.toAsciiLower() == host) {
                    throw AppError("conflict", "域名已被其他站点使用")
                }
            }
        }
        let id = newId("site")
        let doc = JsonObject()
        doc.set("id", JStr(id))
        doc.set("name", JStr(title))
        doc.set("domains", jsonStringList([host]))
        doc.set("theme", JStr(settings.str("theme", def: config.theme)))
        doc.set("status", JStr("active"))
        doc.set("created_at", JInt(nowSeconds()))
        store.put(COL_SITES, id, JObj(doc))
        id
    }

    public func resolveHost(host: String): String {        var name = host.trimAscii().toAsciiLower()
        let colon = match (name.indexOf(":")) {
            case Some(index) => index
            case None => name.size
        }
        name = name[0..colon]
        for (site in store.list(COL_SITES)) {
            if (docStr(site, "status") != "active") {
                continue
            }
            for (domain in docStrings(site, "domains")) {
                if (domain.toAsciiLower() == name) {
                    return docStr(site, "id")
                }
            }
        }
        DEFAULT_SITE_ID
    }

    private func migrateSiteIds(): Unit {
        let collections = [
            "posts", "comments", "media", "categories", "tags", "audit", "jobs", "webhooks",
            "sessions", "api_tokens", "password_resets", "preview_tokens", "revisions", "redirects"
        ]
        for (collection in collections) {
            for (id in store.listIds(collection)) {
                match (store.get(collection, id)) {
                    case Some(doc) =>
                        if (doc.get("site_id").isNone()) {
                            let updated = cloneDoc(doc)
                            setField(updated, "site_id", JStr(DEFAULT_SITE_ID))
                            store.put(collection, id, updated)
                        }
                    case None => ()
                }
            }
        }
    }

    private func hostOf(url: String): String {
        var value = url.trimAscii()
        if (value.startsWith("http://")) {
            value = value[7..value.size]
        } else if (value.startsWith("https://")) {
            value = value[8..value.size]
        }
        let slash = match (value.indexOf("/")) {
            case Some(index) => index
            case None => value.size
        }
        value[0..slash]
    }
}
