/**
 * Cangmo - outbound webhooks delivered through curl (HTTP and HTTPS).
 */
package cangmo.service

import cangmo.core.*
import cangmo.json.*
import cangmo.store.*
import std.collection.*
import std.process.*

public class WebhookService {
    private let store: Store
    private let audit: AuditService

    public init(store: Store, audit: AuditService) {
        this.store = store
        this.audit = audit
    }

    public func list(): Array<JsonValue> {
        let items = ArrayList<JsonValue>()
        for (item in store.list(COL_WEBHOOKS)) {
            items.add(item)
        }
        sortDocsDesc(items, "created_at")
        items.toArray()
    }

    public func create(url: String, events: Array<String>, secret: String, actor: JsonValue, ip: String): String {
        let target = url.trimAscii()
        if (target.size < 8 || target.size > 500 ||
            (!target.startsWith("http://") && !target.startsWith("https://")) ||
            target.contains("\n") || target.contains("\r") || target.contains(" ")) {
            throw AppError("validation", "Webhook 地址需为 http(s) URL")
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
            throw AppError("validation", "至少选择一个事件")
        }
        let id = newId("hook")
        let doc = JsonObject()
        doc.set("id", JStr(id))
        doc.set("url", JStr(target))
        doc.set("events", jsonStringList(cleanEvents.toArray()))
        doc.set("secret", JStr(truncateUtf8(secret.trimAscii(), 200)))
        doc.set("active", JBool(true))
        doc.set("created_at", JInt(nowSeconds()))
        doc.set("last_at", JInt(0))
        doc.set("last_status", JInt(0))
        store.put(COL_WEBHOOKS, id, JObj(doc))
        audit.log(docStr(actor, "id"), docStr(actor, "username"), "webhook_created", "webhook", id, ip, target)
        id
    }

    public func delete(id: String, actor: JsonValue, ip: String): Unit {
        match (store.get(COL_WEBHOOKS, id)) {
            case Some(item) =>
                store.delete(COL_WEBHOOKS, id)
                audit.log(docStr(actor, "id"), docStr(actor, "username"), "webhook_deleted", "webhook", id, ip, "")
            case None => throw AppError("not_found", "Webhook 不存在")
        }
    }

    public func dispatch(event: String, payload: JsonValue): Int64 {
        var delivered: Int64 = 0
        let body = toJson(payload, pretty: false)
        for (item in store.list(COL_WEBHOOKS)) {
            if (!docBool(item, "active", def: true) || !docStrings(item, "events").contains(event)) {
                continue
            }
            let secret = docStr(item, "secret")
            let args = ArrayList<String>()
            args.add("-sS")
            args.add("--max-time")
            args.add("8")
            args.add("-X")
            args.add("POST")
            args.add("-H")
            args.add("content-type: application/json")
            args.add("-H")
            args.add("x-cangmo-event: " + event)
            if (secret.size > 0) {
                args.add("-H")
                args.add("x-cangmo-signature: " + hmacSha256Hex(secret, body))
            }
            args.add("--data-binary")
            args.add(body)
            args.add(docStr(item, "url"))
            let code = try {
                execute("curl", args.toArray())
            } catch (e: Exception) {
                -1
            }
            let updated = cloneDoc(item)
            setField(updated, "last_at", JInt(nowSeconds()))
            setField(updated, "last_status", JInt(code))
            store.put(COL_WEBHOOKS, docStr(item, "id"), updated)
            if (code == 0) {
                delivered += 1
            }
        }
        delivered
    }
}
