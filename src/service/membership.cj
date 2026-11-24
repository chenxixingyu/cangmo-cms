/**
 * Cangmo - membership plans and paid-content access. Payments are external.
 */
package cangmo.service

import cangmo.core.*
import cangmo.json.*
import cangmo.store.*
import std.collection.*

public class MembershipService {
    private let store: Store
    private let audit: AuditService
    private let http: HttpClient
    private let config: Config
    private let settings: SettingsService

    public init(store: Store, audit: AuditService, http: HttpClient, config: Config, settings: SettingsService) {
        this.store = store
        this.audit = audit
        this.http = http
        this.config = config
        this.settings = settings
    }

    public func createCheckout(planId: String, user: JsonValue, siteId: String, baseUrl: String): String {
        let secret = settings.str("stripe_secret_key", def: "")
        if (secret.size == 0) {
            throw AppError("validation", "Stripe 未配置")
        }
        let plan = match (store.get(COL_MEMBERSHIP_PLANS, planId)) {
            case Some(value) => value
            case None => throw AppError("validation", "会员计划不存在")
        }
        if (docStr(plan, "site_id", def: DEFAULT_SITE_ID) != siteId) {
            throw AppError("validation", "计划不属于当前站点")
        }
        let email = docStr(user, "email")
        if (email.size == 0) {
            throw AppError("validation", "当前账户没有邮箱")
        }
        let form = HashMap<String, String>()
        form["mode"] = "subscription"
        form["success_url"] = baseUrl + "/membership?paid=1"
        form["cancel_url"] = baseUrl + "/membership?canceled=1"
        form["customer_email"] = email
        form["client_reference_id"] = docStr(user, "id")
        form["line_items[0][quantity]"] = "1"
        form["line_items[0][price_data][currency]"] = settings.str("stripe_currency", def: "cny")
        form["line_items[0][price_data][unit_amount]"] = docInt(plan, "price_cents").toString()
        form["line_items[0][price_data][product_data][name]"] = docStr(plan, "name")
        form["metadata[plan_id]"] = planId
        form["metadata[site_id]"] = siteId
        form["metadata[email]"] = email
        form["metadata[days]"] = "30"
        let headers = HashMap<String, String>()
        headers["authorization"] = "Bearer " + secret
        let endpoint = settings.str("stripe_api_base", def: "https://api.stripe.com") + "/v1/checkout/sessions"
        let response = match (http.postFormText(endpoint, form, headers)) {
            case Some(value) => value
            case None => throw AppError("validation", "Stripe 创建会话失败")
        }
        let parsed = try { parseJson(response) } catch (e: Exception) {
            throw AppError("validation", "Stripe 返回无效 JSON")
        }
        let url = docStr(parsed, "url")
        if (!url.startsWith("http")) {
            throw AppError("validation", "Stripe 未返回 checkout URL")
        }
        url
    }

    public func stripeWebhook(rawBody: String, signature: String): Bool {
        let secret = settings.str("stripe_webhook_secret", def: "")
        if (secret.size == 0) {
            return false
        }
        var timestamp = ""
        var signatures = ArrayList<String>()
        for (part in signature.split(",")) {
            let trimmed = part.trimAscii()
            if (trimmed.startsWith("t=")) {
                timestamp = trimmed[2..trimmed.size]
            } else if (trimmed.startsWith("v1=")) {
                signatures.add(trimmed[3..trimmed.size])
            }
        }
        if (timestamp.size == 0 || signatures.size == 0) {
            return false
        }
        let stamp = parseIntOr(timestamp, 0)
        if (stamp <= 0 || nowSeconds() - stamp > 300 || stamp - nowSeconds() > 300) {
            return false
        }
        let expected = hmacSha256Hex(secret, timestamp + "." + rawBody)
        var valid = false
        for (candidate in signatures) {
            if (secureEqualsText(candidate, expected)) {
                valid = true
            }
        }
        if (!valid) {
            return false
        }
        let event = try { parseJson(rawBody) } catch (e: Exception) {
            return false
        }
        let session = match (getObject(event, "data")) {
            case Some(value) => match (getObject(JObj(value), "object")) {
                case Some(object) => object
                case None => return false
            }
            case None => return false
        }
        let eventType = docStr(event, "type")
        if (eventType == "checkout.session.completed") {
            let metadata = match (getObject(JObj(session), "metadata")) {
                case Some(value) => value
                case None => return false
            }
            let email = getString(JObj(metadata), "email")
            let planId = getString(JObj(metadata), "plan_id")
            let siteId = getString(JObj(metadata), "site_id")
            if (email.size == 0 || planId.size == 0 || siteId.size == 0) {
                return false
            }
            let days = parseIntOr(getString(JObj(metadata), "days"), 30)
            let subscriptionId = docStr(JObj(session), "subscription")
            let customerId = docStr(JObj(session), "customer")
            try {
                let actor = JsonObject()
                actor.set("id", JStr("stripe"))
                actor.set("username", JStr("stripe"))
                grant(email, planId, days, siteId, JObj(actor), "stripe",
                      subscriptionId: subscriptionId, customerId: customerId)
                true
            } catch (e: Exception) {
                false
            }
        } else if (eventType == "invoice.paid") {
            let subscriptionId = docStr(JObj(session), "subscription")
            if (subscriptionId.size == 0) {
                return true
            }
            renewBySubscription(subscriptionId, 30)
            true
        } else if (eventType == "customer.subscription.deleted") {
            let subscriptionId = docStr(JObj(session), "id")
            if (subscriptionId.size == 0) {
                return true
            }
            revokeBySubscription(subscriptionId)
            true
        } else {
            true
        }
    }

    private func renewBySubscription(subscriptionId: String, days: Int64): Unit {
        for (item in store.list(COL_MEMBERSHIPS)) {
            if (docStr(item, "stripe_subscription_id") == subscriptionId) {
                let updated = cloneDoc(item)
                var span = days
                match (store.get(COL_MEMBERSHIP_PLANS, docStr(item, "plan_id"))) {
                    case Some(plan) =>
                        if (docStr(plan, "interval") == "year") { span = 365 }
                    case None => ()
                }
                let base = if (docInt(item, "expires_at") > nowSeconds()) { docInt(item, "expires_at") } else { nowSeconds() }
                setField(updated, "expires_at", JInt(base + span * 86400))
                setField(updated, "status", JStr("active"))
                store.put(COL_MEMBERSHIPS, docStr(item, "id"), updated)
            }
        }
    }

    private func revokeBySubscription(subscriptionId: String): Unit {
        for (item in store.list(COL_MEMBERSHIPS)) {
            if (docStr(item, "stripe_subscription_id") == subscriptionId) {
                let updated = cloneDoc(item)
                setField(updated, "status", JStr("revoked"))
                store.put(COL_MEMBERSHIPS, docStr(item, "id"), updated)
            }
        }
    }
    public func canManage(userId: String, siteId: String): Bool {
        for (item in store.list(COL_MEMBERSHIPS)) {
            if (docStr(item, "user_id") == userId &&
                docStr(item, "site_id", def: DEFAULT_SITE_ID) == siteId &&
                docStr(item, "status") == "active" &&
                docStr(item, "stripe_customer_id").size > 0) {
                return true
            }
        }
        false
    }

    public func createPortal(userId: String, siteId: String, baseUrl: String): String {
        let secret = settings.str("stripe_secret_key", def: "")
        if (secret.size == 0) {
            throw AppError("validation", "Stripe 未配置")
        }
        var customerId = ""
        for (item in store.list(COL_MEMBERSHIPS)) {
            if (docStr(item, "user_id") == userId &&
                docStr(item, "site_id", def: DEFAULT_SITE_ID) == siteId &&
                docStr(item, "status") == "active") {
                customerId = docStr(item, "stripe_customer_id")
            }
        }
        if (customerId.size == 0) {
            throw AppError("validation", "当前账户没有可管理的 Stripe 订阅")
        }
        let form = HashMap<String, String>()
        form["customer"] = customerId
        form["return_url"] = baseUrl + "/membership"
        let headers = HashMap<String, String>()
        headers["authorization"] = "Bearer " + secret
        let endpoint = settings.str("stripe_api_base", def: "https://api.stripe.com") + "/v1/billing_portal/sessions"
        let response = match (http.postFormText(endpoint, form, headers)) {
            case Some(value) => value
            case None => throw AppError("validation", "Stripe 创建 Portal 会话失败")
        }
        let parsed = try { parseJson(response) } catch (e: Exception) {
            throw AppError("validation", "Stripe 返回无效 JSON")
        }
        let url = docStr(parsed, "url")
        if (!url.startsWith("http")) {
            throw AppError("validation", "Stripe 未返回 Portal URL")
        }
        url
    }

    public func plans(siteId: String): Array<JsonValue> {
        let items = ArrayList<JsonValue>()
        for (plan in store.list(COL_MEMBERSHIP_PLANS)) {
            if (docStr(plan, "site_id", def: DEFAULT_SITE_ID) == siteId) {
                items.add(plan)
            }
        }
        sortDocsDesc(items, "created_at")
        items.toArray()
    }

    public func createPlan(name: String, priceCents: Int64, interval: String, siteId: String,
                           actor: JsonValue, ip: String): String {
        let label = name.trimAscii()
        if (label.size == 0 || label.size > 80) {
            throw AppError("validation", "会员计划名称长度无效")
        }
        if (priceCents < 0) {
            throw AppError("validation", "价格不能为负")
        }
        let period = if (interval == "year") { "year" } else { "month" }
        let id = newId("plan")
        let doc = JsonObject()
        doc.set("id", JStr(id))
        doc.set("site_id", JStr(siteId))
        doc.set("name", JStr(label))
        doc.set("price_cents", JInt(priceCents))
        doc.set("interval", JStr(period))
        doc.set("active", JBool(true))
        doc.set("created_at", JInt(nowSeconds()))
        store.put(COL_MEMBERSHIP_PLANS, id, JObj(doc))
        audit.log(docStr(actor, "id"), docStr(actor, "username"), "plan_created", "plan", id, ip, label)
        id
    }

    public func grant(email: String, planId: String, days: Int64, siteId: String,
                      actor: JsonValue, ip: String, subscriptionId!: String = "", customerId!: String = ""): String {
        let address = email.trimAscii().toAsciiLower()
        let user = match (findUserByEmail(address)) {
            case Some(value) => value
            case None => throw AppError("validation", "用户不存在")
        }
        let plan = match (store.get(COL_MEMBERSHIP_PLANS, planId)) {
            case Some(value) => value
            case None => throw AppError("validation", "会员计划不存在")
        }
        if (docStr(plan, "site_id", def: DEFAULT_SITE_ID) != siteId) {
            throw AppError("validation", "计划不属于当前站点")
        }
        let span = if (days > 0) { days } else { 30 }
        let id = newId("member")
        let doc = JsonObject()
        doc.set("id", JStr(id))
        doc.set("site_id", JStr(siteId))
        doc.set("user_id", JStr(docStr(user, "id")))
        doc.set("email", JStr(address))
        doc.set("plan_id", JStr(planId))
        doc.set("status", JStr("active"))
        doc.set("stripe_subscription_id", JStr(subscriptionId))
        doc.set("stripe_customer_id", JStr(customerId))
        doc.set("created_at", JInt(nowSeconds()))
        doc.set("expires_at", JInt(nowSeconds() + span * 86400))
        store.put(COL_MEMBERSHIPS, id, JObj(doc))
        audit.log(docStr(actor, "id"), docStr(actor, "username"), "membership_granted", "member", id, ip, address)
        id
    }

    public func revoke(id: String, actor: JsonValue, ip: String): Unit {
        let member = match (store.get(COL_MEMBERSHIPS, id)) {
            case Some(value) => value
            case None => throw AppError("not_found", "会员不存在")
        }
        let updated = cloneDoc(member)
        setField(updated, "status", JStr("revoked"))
        store.put(COL_MEMBERSHIPS, id, updated)
        audit.log(docStr(actor, "id"), docStr(actor, "username"), "membership_revoked", "member", id, ip, "")
    }

    public func members(siteId: String): Array<JsonValue> {
        let items = ArrayList<JsonValue>()
        for (item in store.list(COL_MEMBERSHIPS)) {
            if (docStr(item, "site_id", def: DEFAULT_SITE_ID) == siteId) {
                items.add(item)
            }
        }
        sortDocsDesc(items, "created_at")
        items.toArray()
    }

    public func isActive(userId: String, siteId: String): Bool {
        if (userId.size == 0) {
            return false
        }
        for (item in store.list(COL_MEMBERSHIPS)) {
            if (docStr(item, "user_id") == userId &&
                docStr(item, "site_id", def: DEFAULT_SITE_ID) == siteId &&
                docStr(item, "status") == "active" &&
                docInt(item, "expires_at") > nowSeconds()) {
                return true
            }
        }
        false
    }

    private func findUserByEmail(email: String): ?JsonValue {
        for (user in store.list(COL_USERS)) {
            if (docStr(user, "email").toAsciiLower() == email) {
                return Some(user)
            }
        }
        None
    }
}
