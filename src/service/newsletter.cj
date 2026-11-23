/**
 * Cangmo - newsletter subscribers, double opt-in and campaigns.
 */
package cangmo.service

import cangmo.core.*
import cangmo.json.*
import cangmo.store.*
import std.collection.*

public class NewsletterService {
    private let store: Store
    private let config: Config
    private let settings: SettingsService
    private let mail: MailService
    private let audit: AuditService

    public init(store: Store, config: Config, settings: SettingsService, mail: MailService, audit: AuditService) {
        this.store = store
        this.config = config
        this.settings = settings
        this.mail = mail
        this.audit = audit
    }

    public func subscribe(email: String, name: String, siteId: String): String {
        let address = email.trimAscii().toAsciiLower()
        if (!isValidEmail(address)) {
            throw AppError("validation", "邮箱格式无效")
        }
        for (item in store.list(COL_NEWSLETTER_SUBSCRIBERS)) {
            if (docStr(item, "site_id", def: DEFAULT_SITE_ID) == siteId &&
                docStr(item, "email").toAsciiLower() == address) {
                if (docStr(item, "status") == "confirmed") {
                    return docStr(item, "id")
                }
                sendConfirmation(item)
                return docStr(item, "id")
            }
        }
        let id = newId("sub")
        let token = randomToken(bytes: 18)
        let doc = JsonObject()
        doc.set("id", JStr(id))
        doc.set("site_id", JStr(siteId))
        doc.set("email", JStr(address))
        doc.set("name", JStr(truncateUtf8(name.trimAscii(), 80)))
        doc.set("status", JStr("pending"))
        doc.set("token", JStr(token))
        doc.set("created_at", JInt(nowSeconds()))
        doc.set("confirmed_at", JInt(0))
        store.put(COL_NEWSLETTER_SUBSCRIBERS, id, JObj(doc))
        sendConfirmation(JObj(doc))
        id
    }

    public func confirm(token: String): Bool {
        for (item in store.list(COL_NEWSLETTER_SUBSCRIBERS)) {
            if (secureEqualsText(docStr(item, "token"), token)) {
                let updated = cloneDoc(item)
                setField(updated, "status", JStr("confirmed"))
                setField(updated, "confirmed_at", JInt(nowSeconds()))
                store.put(COL_NEWSLETTER_SUBSCRIBERS, docStr(item, "id"), updated)
                return true
            }
        }
        false
    }

    public func unsubscribe(token: String): Bool {
        for (item in store.list(COL_NEWSLETTER_SUBSCRIBERS)) {
            if (secureEqualsText(docStr(item, "token"), token)) {
                let updated = cloneDoc(item)
                setField(updated, "status", JStr("unsubscribed"))
                store.put(COL_NEWSLETTER_SUBSCRIBERS, docStr(item, "id"), updated)
                return true
            }
        }
        false
    }

    public func subscribers(siteId: String): Array<JsonValue> {
        let items = ArrayList<JsonValue>()
        for (item in store.list(COL_NEWSLETTER_SUBSCRIBERS)) {
            if (docStr(item, "site_id", def: DEFAULT_SITE_ID) == siteId) {
                items.add(item)
            }
        }
        sortDocsDesc(items, "created_at")
        items.toArray()
    }

    public func campaigns(siteId: String): Array<JsonValue> {
        let items = ArrayList<JsonValue>()
        for (item in store.list(COL_NEWSLETTER_CAMPAIGNS)) {
            if (docStr(item, "site_id", def: DEFAULT_SITE_ID) == siteId) {
                items.add(item)
            }
        }
        sortDocsDesc(items, "created_at")
        items.toArray()
    }

    public func createCampaign(subject: String, body: String, siteId: String, actor: JsonValue, ip: String): String {
        let title = subject.trimAscii()
        if (title.size == 0 || title.size > 200) {
            throw AppError("validation", "邮件主题需在 1-200 字之间")
        }
        if (body.trimAscii().size == 0) {
            throw AppError("validation", "邮件正文不能为空")
        }
        let id = newId("news")
        let doc = JsonObject()
        doc.set("id", JStr(id))
        doc.set("site_id", JStr(siteId))
        doc.set("subject", JStr(title))
        doc.set("body", JStr(truncateUtf8(body.trimAscii(), 20000)))
        doc.set("status", JStr("draft"))
        doc.set("created_at", JInt(nowSeconds()))
        doc.set("sent_at", JInt(0))
        doc.set("recipients", JInt(0))
        store.put(COL_NEWSLETTER_CAMPAIGNS, id, JObj(doc))
        audit.log(docStr(actor, "id"), docStr(actor, "username"), "newsletter_created", "newsletter", id, ip, title)
        id
    }

    public func sendCampaign(id: String, actor: JsonValue, ip: String): Int64 {
        let campaign = match (store.get(COL_NEWSLETTER_CAMPAIGNS, id)) {
            case Some(value) => value
            case None => throw AppError("not_found", "Newsletter 不存在")
        }
        if (docStr(campaign, "status") == "sent") {
            throw AppError("validation", "Newsletter 已发送")
        }
        let siteId = docStr(campaign, "site_id", def: DEFAULT_SITE_ID)
        var sent: Int64 = 0
        for (subscriber in store.list(COL_NEWSLETTER_SUBSCRIBERS)) {
            if (docStr(subscriber, "site_id", def: DEFAULT_SITE_ID) != siteId ||
                docStr(subscriber, "status") != "confirmed") {
                continue
            }
            let base = settings.str("site_url", def: config.siteUrl)
            let link = base + "/newsletter/unsubscribe?token=" + urlEncode(docStr(subscriber, "token"))
            mail.send(docStr(subscriber, "email"), docStr(campaign, "subject"),
                      docStr(campaign, "body") + "\n\n退订：${link}\n")
            sent += 1
        }
        let updated = cloneDoc(campaign)
        setField(updated, "status", JStr("sent"))
        setField(updated, "sent_at", JInt(nowSeconds()))
        setField(updated, "recipients", JInt(sent))
        store.put(COL_NEWSLETTER_CAMPAIGNS, id, updated)
        audit.log(docStr(actor, "id"), docStr(actor, "username"), "newsletter_sent", "newsletter", id, ip,
                  docStr(campaign, "subject"))
        sent
    }

    private func sendConfirmation(item: JsonValue): Unit {
        let base = settings.str("site_url", def: config.siteUrl)
        let link = base + "/newsletter/confirm?token=" + urlEncode(docStr(item, "token"))
        let subject = "确认订阅仓墨 Newsletter"
        let body = "请打开以下链接确认订阅：\n\n${link}\n\n如果不是你订阅的，请忽略此邮件。"
        mail.send(docStr(item, "email"), subject, body)
    }
}
