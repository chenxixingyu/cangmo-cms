/**
 * Cangmo - outbound webhooks with a small persistent retry queue.
 */
package cangmo.service

import cangmo.core.*
import cangmo.json.*
import cangmo.store.*
import std.collection.*

public class WebhookService {
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
            let code = deliver(docStr(item, "url"), event, body, secret)
            let updated = cloneDoc(item)
            setField(updated, "last_at", JInt(nowSeconds()))
            setField(updated, "last_status", JInt(code))
            store.put(COL_WEBHOOKS, docStr(item, "id"), updated)
            if (code == 0) {
                delivered += 1
            } else {
                enqueue(docStr(item, "url"), event, body, secret)
            }
        }
        delivered
    }

    public func processRetries(): Int64 {
        var processed: Int64 = 0
        let due = ArrayList<JsonValue>()
        for (job in store.list(COL_JOBS)) {
            if (docStr(job, "status") == "pending" && docInt(job, "next_at") <= nowSeconds()) {
                due.add(job)
            }
        }
        for (job in due) {
            let attempts = docInt(job, "attempts") + 1
            let code = deliver(docStr(job, "url"), docStr(job, "event"), docStr(job, "body"), docStr(job, "secret"))
            let updated = cloneDoc(job)
            setField(updated, "attempts", JInt(attempts))
            setField(updated, "last_status", JInt(code))
            setField(updated, "last_at", JInt(nowSeconds()))
            if (code == 0) {
                setField(updated, "status", JStr("done"))
            } else if (attempts >= 3) {
                setField(updated, "status", JStr("failed"))
            } else {
                setField(updated, "next_at", JInt(nowSeconds() + 60 * attempts))
            }
            store.put(COL_JOBS, docStr(job, "id"), updated)
            processed += 1
        }
        processed
    }

    public func jobs(): Array<JsonValue> {
        let items = ArrayList<JsonValue>()
        for (job in store.list(COL_JOBS)) {
            items.add(job)
        }
        sortDocsDesc(items, "created_at")
        items.toArray()
    }

    public func retryJob(id: String): Bool {
        match (store.get(COL_JOBS, id)) {
            case Some(job) =>
                let updated = cloneDoc(job)
                setField(updated, "status", JStr("pending"))
                setField(updated, "next_at", JInt(nowSeconds()))
                store.put(COL_JOBS, id, updated)
                true
            case None => false
        }
    }

    public func cancelJob(id: String): Bool {
        if (store.get(COL_JOBS, id).isNone()) {
            return false
        }
        store.delete(COL_JOBS, id)
        true
    }

    private func enqueue(url: String, event: String, body: String, secret: String): Unit {
        let id = newId("job")
        let job = JsonObject()
        job.set("id", JStr(id))
        job.set("kind", JStr("webhook"))
        job.set("url", JStr(url))
        job.set("event", JStr(event))
        job.set("body", JStr(truncateUtf8(body, 8000)))
        job.set("secret", JStr(secret))
        job.set("status", JStr("pending"))
        job.set("attempts", JInt(0))
        job.set("created_at", JInt(nowSeconds()))
        job.set("next_at", JInt(nowSeconds() + 60))
        job.set("last_status", JInt(0))
        store.put(COL_JOBS, id, JObj(job))
    }

    private func deliver(url: String, event: String, body: String, secret: String): Int64 {
        let headers = HashMap<String, String>()
        headers["x-cangmo-event"] = event
        if (secret.size > 0) {
            headers["x-cangmo-signature"] = hmacSha256Hex(secret, body)
        }
        http.postJson(url, body, headers)
    }
}
