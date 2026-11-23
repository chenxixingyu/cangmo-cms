/**
 * Cangmo - out-of-process sidecar plugin protocol.
 * A plugin is an HTTP endpoint that subscribes to domain events.
 */
package cangmo.service

import cangmo.core.*
import cangmo.json.*
import cangmo.store.*
import std.collection.*

public class PluginService {
    private let store: Store
    private let audit: AuditService
    private let http: HttpClient

    public init(store: Store, audit: AuditService, http: HttpClient) {
        this.store = store
        this.audit = audit
        this.http = http
    }

    public func list(): Array<JsonValue> {
        let items = ArrayList<JsonValue>()
        for (item in store.list(COL_PLUGINS)) {
            items.add(item)
        }
        sortDocsDesc(items, "created_at")
        items.toArray()
    }

    public func create(name: String, endpoint: String, events: Array<String>, capabilities: Array<String>,
                       secret: String, actor: JsonValue, ip: String): String {
        let pluginName = name.trimAscii()
        let url = endpoint.trimAscii()
        if (pluginName.size == 0 || pluginName.size > 80) {
            throw AppError("validation", "插件名称长度无效")
        }
        if (url.size < 8 || url.size > 500 || (!url.startsWith("http://") && !url.startsWith("https://")) ||
            url.contains(" ") || url.contains("\n") || url.contains("\r")) {
            throw AppError("validation", "插件端点需为 http(s) URL")
        }
        let cleanEvents = ArrayList<String>()
        for (event in events) {
            let value = event.trimAscii()
            if (value == "post.published" || value == "comment.created" || value == "test") {
                if (!cleanEvents.contains(value)) {
                    cleanEvents.add(value)
                }
            }
        }
        if (cleanEvents.size == 0) {
            throw AppError("validation", "至少订阅一个事件")
        }
        let cleanCaps = ArrayList<String>()
        for (capability in capabilities) {
            let value = capability.trimAscii()
            if (value == "posts.read" || value == "comments.read" || value == "media.read" ||
                value == "http.outbound") {
                if (!cleanCaps.contains(value)) {
                    cleanCaps.add(value)
                }
            }
        }
        if (cleanCaps.size == 0) {
            cleanCaps.add("posts.read")
        }
        let id = newId("plugin")
        let doc = JsonObject()
        doc.set("id", JStr(id))
        doc.set("name", JStr(pluginName))
        doc.set("endpoint", JStr(url))
        doc.set("events", jsonStringList(cleanEvents.toArray()))
        doc.set("capabilities", jsonStringList(cleanCaps.toArray()))
        doc.set("secret", JStr(truncateUtf8(secret.trimAscii(), 200)))
        doc.set("active", JBool(true))
        doc.set("created_at", JInt(nowSeconds()))
        doc.set("last_at", JInt(0))
        doc.set("last_status", JInt(0))
        store.put(COL_PLUGINS, id, JObj(doc))
        audit.log(docStr(actor, "id"), docStr(actor, "username"), "plugin_created", "plugin", id, ip, pluginName)
        id
    }

    public func delete(id: String, actor: JsonValue, ip: String): Unit {
        if (store.get(COL_PLUGINS, id).isNone()) {
            throw AppError("not_found", "插件不存在")
        }
        store.delete(COL_PLUGINS, id)
        audit.log(docStr(actor, "id"), docStr(actor, "username"), "plugin_deleted", "plugin", id, ip, "")
    }

    public func setActive(id: String, active: Bool): Unit {
        let plugin = match (store.get(COL_PLUGINS, id)) {
            case Some(value) => value
            case None => throw AppError("not_found", "插件不存在")
        }
        let updated = cloneDoc(plugin)
        setField(updated, "active", JBool(active))
        store.put(COL_PLUGINS, id, updated)
    }

    public func dispatch(event: String, payload: JsonValue, siteId: String): Int64 {
        var delivered: Int64 = 0
        for (plugin in store.list(COL_PLUGINS)) {
            if (!docBool(plugin, "active", def: true) || !docStrings(plugin, "events").contains(event)) {
                continue
            }
            let envelope = JsonObject()
            envelope.set("event", JStr(event))
            envelope.set("site_id", JStr(siteId))
            envelope.set("plugin_id", JStr(docStr(plugin, "id")))
            envelope.set("payload", payload)
            envelope.set("sent_at", JInt(nowSeconds()))
            let body = toJson(JObj(envelope), pretty: false)
            let headers = HashMap<String, String>()
            headers["x-cangmo-event"] = event
            let secret = docStr(plugin, "secret")
            if (secret.size > 0) {
                headers["x-cangmo-signature"] = hmacSha256Hex(secret, body)
            }
            let code = http.postJson(docStr(plugin, "endpoint"), body, headers)
            let updated = cloneDoc(plugin)
            setField(updated, "last_at", JInt(nowSeconds()))
            setField(updated, "last_status", JInt(code))
            store.put(COL_PLUGINS, docStr(plugin, "id"), updated)
            if (code == 0) {
                delivered += 1
            }
        }
        delivered
    }
}
