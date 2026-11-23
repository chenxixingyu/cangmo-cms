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

    public init(store: Store, audit: AuditService) {
        this.store = store
        this.audit = audit
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
                      actor: JsonValue, ip: String): String {
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
