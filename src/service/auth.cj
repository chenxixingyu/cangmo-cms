/**
 * Cangmo - authentication, sessions, roles, API tokens.
 */
package cangmo.service

import cangmo.core.*
import cangmo.json.*
import cangmo.store.*
import std.collection.*
import std.sync.*
import std.time.*

public class FlashMessage {
    public let kind: String
    public let text: String

    public init(kind: String, text: String) {
        this.kind = kind
        this.text = text
    }
}

public class SessionData {
    public var token: String = ""
    public var id: String = ""
    public var userId: String = ""
    public var csrf: String = ""
    public var createdAt: Int64 = 0
    public var expiresAt: Int64 = 0
    public var lastSeenAt: Int64 = 0
    public var lastPersistedAt: Int64 = 0
    public var ipHash: String = ""
    public var userAgent: String = ""
    public var flash: ArrayList<FlashMessage> = ArrayList<FlashMessage>()
}

public class LoginResult {
    public let ok: Bool
    public let message: String
    public let user: ?JsonValue
    public let session: ?SessionData

    public init(ok: Bool, message: String, user: ?JsonValue, session: ?SessionData) {
        this.ok = ok
        this.message = message
        this.user = user
        this.session = session
    }
}

public class AuthService {
    private let store: Store
    private let config: Config
    private let settings: SettingsService
    private let audit: AuditService
    private let limiter: RateLimiter
    private let dummyHash: String

    public init(store: Store, config: Config, settings: SettingsService, audit: AuditService, limiter: RateLimiter) {
        this.store = store
        this.config = config
        this.settings = settings
        this.audit = audit
        this.limiter = limiter
        this.dummyHash = hashPassword(randomToken(bytes: 18), iterations: config.pbkdf2Iterations)
    }

    // -----------------------------------------------------------------------
    // Sessions
    // -----------------------------------------------------------------------

    public func createSession(userId: String, ip: String, userAgent: String): SessionData {
        let session = SessionData()
        session.token = randomToken(bytes: 32)
        session.id = sha256Hex(session.token)
        session.userId = userId
        session.csrf = randomToken(bytes: 24)
        session.createdAt = nowSeconds()
        session.expiresAt = session.createdAt + config.sessionTtlHours * 3600
        session.lastSeenAt = session.createdAt
        session.lastPersistedAt = session.createdAt
        session.ipHash = hashIp(ip, config.secret)
        session.userAgent = truncateUtf8(userAgent, 300)
        persist(session)
        session
    }

    public func loadSession(token: String): ?SessionData {
        if (token.size < 20 || token.size > 200) {
            return None
        }
        let id = sha256Hex(token)
        let doc = match (store.get(COL_SESSIONS, id)) {
            case Some(value) => value
            case None => return None
        }
        let session = SessionData()
        session.token = token
        session.id = id
        session.userId = docStr(doc, "user_id")
        session.csrf = docStr(doc, "csrf")
        session.createdAt = docInt(doc, "created_at")
        session.expiresAt = docInt(doc, "expires_at")
        session.lastSeenAt = docInt(doc, "last_seen_at")
        session.lastPersistedAt = session.lastSeenAt
        session.ipHash = docStr(doc, "ip_hash")
        session.userAgent = docStr(doc, "user_agent")
        match (doc.get("flash")) {
            case Some(JArr(arr)) =>
                for (item in arr.items) {
                    session.flash.add(FlashMessage(docStr(item, "kind", def: "info"), docStr(item, "text")))
                }
            case _ => ()
        }
        let now = nowSeconds()
        if (session.expiresAt <= now || session.lastSeenAt + config.sessionIdleHours * 3600 <= now) {
            store.delete(COL_SESSIONS, id)
            return None
        }
        session.lastSeenAt = now
        if (now - session.lastPersistedAt > 300) {
            persist(session)
        }
        Some(session)
    }

    public func persist(session: SessionData): Unit {
        let doc = JsonObject()
        doc.set("user_id", JStr(session.userId))
        doc.set("csrf", JStr(session.csrf))
        doc.set("created_at", JInt(session.createdAt))
        doc.set("expires_at", JInt(session.expiresAt))
        doc.set("last_seen_at", JInt(session.lastSeenAt))
        doc.set("ip_hash", JStr(session.ipHash))
        doc.set("user_agent", JStr(session.userAgent))
        let flash = JsonArray()
        for (message in session.flash) {
            let item = JsonObject()
            item.set("kind", JStr(message.kind))
            item.set("text", JStr(message.text))
            flash.add(JObj(item))
        }
        doc.set("flash", JArr(flash))
        store.put(COL_SESSIONS, session.id, JObj(doc))
        session.lastPersistedAt = session.lastSeenAt
    }

    public func destroySession(session: SessionData): Unit {
        store.delete(COL_SESSIONS, session.id)
    }

    public func revokeUserSessions(userId: String, exceptSessionId: String): Unit {
        for (id in store.listIds(COL_SESSIONS)) {
            let doc = store.get(COL_SESSIONS, id)
            match (doc) {
                case Some(value) =>
                    if (docStr(value, "user_id") == userId && id != exceptSessionId) {
                        store.delete(COL_SESSIONS, id)
                    }
                case None => ()
            }
        }
    }

    public func pruneSessions(): Int64 {
        let now = nowSeconds()
        var removed: Int64 = 0
        for (id in store.listIds(COL_SESSIONS)) {
            let doc = store.get(COL_SESSIONS, id)
            match (doc) {
                case Some(value) =>
                    if (docInt(value, "expires_at") <= now ||
                        docInt(value, "last_seen_at") + config.sessionIdleHours * 3600 <= now) {
                        store.delete(COL_SESSIONS, id)
                        removed += 1
                    }
                case None => ()
            }
        }
        removed
    }

    public func setFlash(session: SessionData, kind: String, text: String): Unit {
        if (session.flash.size >= 5) {
            session.flash.remove(at: 0)
        }
        session.flash.add(FlashMessage(kind, truncateUtf8(text, 500)))
        persist(session)
    }

    public func consumeFlash(session: SessionData): ArrayList<FlashMessage> {
        let messages = ArrayList<FlashMessage>()
        for (message in session.flash) {
            messages.add(message)
        }
        session.flash.clear()
        persist(session)
        messages
    }

    // -----------------------------------------------------------------------
    // Login
    // -----------------------------------------------------------------------

    public func login(loginName: String, password: String, ip: String, userAgent: String): LoginResult {
        let key = "login:" + ip
        if (!limiter.allow(key, config.loginMaxAttempts * 4, config.loginWindowMinutes * 60)) {
            return LoginResult(false, "尝试次数过多，请稍后再试", None, None)
        }
        let userOpt = findUserByLogin(loginName)
        if (userOpt.isNone()) {
            // Constant-work dummy verification reduces user enumeration.
            verifyPassword(password, dummyHash)
            return LoginResult(false, "用户名或密码错误", None, None)
        }
        let user = match (userOpt) {
            case Some(value) => value
            case None => return LoginResult(false, "用户名或密码错误", None, None)
        }
        let now = nowSeconds()
        if (docStr(user, "status") != "active") {
            return LoginResult(false, "账户已被停用", None, None)
        }
        if (docInt(user, "locked_until") > now) {
            let minutes = (docInt(user, "locked_until") - now) / 60 + 1
            return LoginResult(false, "账户已锁定，请 ${minutes} 分钟后再试", None, None)
        }
        let hash = docStr(user, "password_hash")
        if (!verifyPassword(password, hash)) {
            recordFailedLogin(user, ip)
            return LoginResult(false, "用户名或密码错误", None, None)
        }
        let updated = cloneDoc(user)
        setField(updated, "failed_logins", JInt(0))
        setField(updated, "locked_until", JInt(0))
        setField(updated, "last_login_at", JInt(now))
        setField(updated, "updated_at", JInt(now))
        if (passwordNeedsRehash(hash, iterations: config.pbkdf2Iterations)) {
            setField(updated, "password_hash", JStr(hashPassword(password, iterations: config.pbkdf2Iterations)))
        }
        store.put(COL_USERS, docStr(updated, "id"), updated)
        let session = createSession(docStr(updated, "id"), ip, userAgent)
        audit.log(docStr(updated, "id"), docStr(updated, "username"), "login", "user",
                  docStr(updated, "id"), ip, "login success")
        LoginResult(true, "登录成功", Some(updated), Some(session))
    }

    private func recordFailedLogin(user: JsonValue, ip: String): Unit {
        let updated = cloneDoc(user)
        let failures = docInt(updated, "failed_logins") + 1
        setField(updated, "failed_logins", JInt(failures))
        if (failures >= config.loginMaxAttempts) {
            setField(updated, "locked_until", JInt(nowSeconds() + config.lockoutMinutes * 60))
        }
        setField(updated, "updated_at", JInt(nowSeconds()))
        store.put(COL_USERS, docStr(updated, "id"), updated)
        audit.log(docStr(updated, "id"), docStr(updated, "username"), "login_failed", "user",
                  docStr(updated, "id"), ip, "failed login")
    }

    public func findUserByLogin(loginName: String): ?JsonValue {
        let needle = loginName.trimAscii().toAsciiLower()
        if (needle.size == 0) {
            return None
        }
        for (user in store.list(COL_USERS)) {
            if (docStr(user, "username").toAsciiLower() == needle ||
                docStr(user, "email").toAsciiLower() == needle) {
                return Some(user)
            }
        }
        None
    }

    public func userById(id: String): ?JsonValue {
        store.get(COL_USERS, id)
    }

    public func userByUsername(username: String): ?JsonValue {
        for (user in store.list(COL_USERS)) {
            if (docStr(user, "username").toAsciiLower() == username.toAsciiLower()) {
                return Some(user)
            }
        }
        None
    }

    public func hasUsers(): Bool {
        store.count(COL_USERS) > 0
    }

    public func adminCount(): Int64 {
        var count: Int64 = 0
        for (user in store.list(COL_USERS)) {
            if (docStr(user, "role") == ROLE_ADMIN && docStr(user, "status") == "active") {
                count += 1
            }
        }
        count
    }

    // -----------------------------------------------------------------------
    // API tokens
    // -----------------------------------------------------------------------

    public func createApiToken(userId: String, name: String): String {
        let raw = "cmo_" + base64UrlEncode(secureRandomBytes(32))
        let id = sha256Hex(raw)
        let doc = JsonObject()
        doc.set("id", JStr(id))
        doc.set("user_id", JStr(userId))
        doc.set("name", JStr(truncateUtf8(name, 100)))
        doc.set("prefix", JStr(raw[0..12]))
        doc.set("created_at", JInt(nowSeconds()))
        doc.set("last_used_at", JInt(0))
        store.put(COL_API_TOKENS, id, JObj(doc))
        raw
    }

    public func userByApiToken(raw: String): ?JsonValue {
        if (!raw.startsWith("cmo_") || raw.size < 20 || raw.size > 200) {
            return None
        }
        let id = sha256Hex(raw)
        let doc = match (store.get(COL_API_TOKENS, id)) {
            case Some(value) => value
            case None => return None
        }
        let userId = docStr(doc, "user_id")
        let user = match (userById(userId)) {
            case Some(value) => value
            case None => return None
        }
        if (docStr(user, "status") != "active") {
            return None
        }
        let updated = cloneDoc(doc)
        setField(updated, "last_used_at", JInt(nowSeconds()))
        store.put(COL_API_TOKENS, id, updated)
        Some(user)
    }

    public func listApiTokens(userId: String): Array<JsonValue> {
        let items = ArrayList<JsonValue>()
        for (doc in store.list(COL_API_TOKENS)) {
            if (docStr(doc, "user_id") == userId) {
                items.add(doc)
            }
        }
        sortDocsDesc(items, "created_at")
        items.toArray()
    }

    public func revokeApiToken(id: String, userId: String): Bool {
        match (store.get(COL_API_TOKENS, id)) {
            case Some(doc) =>
                if (docStr(doc, "user_id") != userId) {
                    return false
                }
                store.delete(COL_API_TOKENS, id)
                true
            case None => false
        }
    }

    // -----------------------------------------------------------------------
    // Users
    // -----------------------------------------------------------------------

    public func createUser(username: String, email: String, password: String, displayName: String,
                           role: String, ip: String): String {
        let name = username.trimAscii()
        let mail = email.trimAscii().toAsciiLower()
        if (!isValidUsername(name)) {
            throw AppError("validation", "用户名需为 3-32 位字母、数字、下划线或连字符，并以字母开头")
        }
        if (!isValidEmail(mail)) {
            throw AppError("validation", "邮箱格式无效")
        }
        if (!validRole(role)) {
            throw AppError("validation", "无效的角色")
        }
        if (userByUsername(name).isSome()) {
            throw AppError("conflict", "用户名已存在")
        }
        for (user in store.list(COL_USERS)) {
            if (docStr(user, "email").toAsciiLower() == mail) {
                throw AppError("conflict", "邮箱已被使用")
            }
        }
        match (passwordProblem(password, username: name, email: mail)) {
            case Some(problem) => throw AppError("validation", problem)
            case None => ()
        }
        let id = newId("user")
        let now = nowSeconds()
        let doc = JsonObject()
        doc.set("id", JStr(id))
        doc.set("username", JStr(name))
        doc.set("email", JStr(mail))
        doc.set("password_hash", JStr(hashPassword(password, iterations: config.pbkdf2Iterations)))
        doc.set("display_name", JStr(if (displayName.trimAscii().size > 0) { displayName.trimAscii() } else { name }))
        doc.set("role", JStr(role))
        doc.set("status", JStr("active"))
        doc.set("avatar", JStr(""))
        doc.set("bio", JStr(""))
        doc.set("created_at", JInt(now))
        doc.set("updated_at", JInt(now))
        doc.set("last_login_at", JInt(0))
        doc.set("failed_logins", JInt(0))
        doc.set("locked_until", JInt(0))
        store.put(COL_USERS, id, JObj(doc))
        audit.log(id, name, "user_created", "user", id, ip, "role=${role}")
        id
    }

    public func updateProfile(userId: String, displayName: String, email: String, bio: String): Unit {
        let user = match (userById(userId)) {
            case Some(value) => value
            case None => throw AppError("not_found", "用户不存在")
        }
        let mail = email.trimAscii().toAsciiLower()
        if (mail.size > 0 && !isValidEmail(mail)) {
            throw AppError("validation", "邮箱格式无效")
        }
        for (other in store.list(COL_USERS)) {
            if (docStr(other, "id") != userId && docStr(other, "email").toAsciiLower() == mail && mail.size > 0) {
                throw AppError("conflict", "邮箱已被使用")
            }
        }
        let updated = cloneDoc(user)
        setField(updated, "display_name", JStr(truncateUtf8(displayName.trimAscii(), 60)))
        setField(updated, "email", JStr(mail))
        setField(updated, "bio", JStr(truncateUtf8(bio.trimAscii(), 500)))
        setField(updated, "updated_at", JInt(nowSeconds()))
        store.put(COL_USERS, userId, updated)
    }

    public func adminUpdateUser(userId: String, role: String, status: String, displayName: String, ip: String): Unit {
        let user = match (userById(userId)) {
            case Some(value) => value
            case None => throw AppError("not_found", "用户不存在")
        }
        if (!validRole(role)) {
            throw AppError("validation", "无效的角色")
        }
        if (status != "active" && status != "suspended") {
            throw AppError("validation", "无效的账户状态")
        }
        if (docStr(user, "role") == ROLE_ADMIN && role != ROLE_ADMIN && adminCount() <= 1) {
            throw AppError("validation", "不能降级唯一的系统管理员")
        }
        if (docStr(user, "role") == ROLE_ADMIN && status != "active" && adminCount() <= 1) {
            throw AppError("validation", "不能停用唯一的系统管理员")
        }
        let updated = cloneDoc(user)
        setField(updated, "role", JStr(role))
        setField(updated, "status", JStr(status))
        if (displayName.trimAscii().size > 0) {
            setField(updated, "display_name", JStr(truncateUtf8(displayName.trimAscii(), 60)))
        }
        setField(updated, "updated_at", JInt(nowSeconds()))
        store.put(COL_USERS, userId, updated)
        audit.log(userId, docStr(updated, "username"), "user_updated", "user", userId, ip,
                  "role=${role} status=${status}")
    }

    public func changePassword(userId: String, oldPassword: String, newPassword: String, currentSessionId: String): Unit {
        let user = match (userById(userId)) {
            case Some(value) => value
            case None => throw AppError("not_found", "用户不存在")
        }
        if (!verifyPassword(oldPassword, docStr(user, "password_hash"))) {
            throw AppError("validation", "当前密码不正确")
        }
        match (passwordProblem(newPassword, username: docStr(user, "username"), email: docStr(user, "email"))) {
            case Some(problem) => throw AppError("validation", problem)
            case None => ()
        }
        let updated = cloneDoc(user)
        setField(updated, "password_hash", JStr(hashPassword(newPassword, iterations: config.pbkdf2Iterations)))
        setField(updated, "updated_at", JInt(nowSeconds()))
        store.put(COL_USERS, userId, updated)
        revokeUserSessions(userId, currentSessionId)
    }

    public func resetPassword(userId: String, newPassword: String, ip: String): Unit {
        let user = match (userById(userId)) {
            case Some(value) => value
            case None => throw AppError("not_found", "用户不存在")
        }
        match (passwordProblem(newPassword, username: docStr(user, "username"), email: docStr(user, "email"))) {
            case Some(problem) => throw AppError("validation", problem)
            case None => ()
        }
        let updated = cloneDoc(user)
        setField(updated, "password_hash", JStr(hashPassword(newPassword, iterations: config.pbkdf2Iterations)))
        setField(updated, "failed_logins", JInt(0))
        setField(updated, "locked_until", JInt(0))
        setField(updated, "updated_at", JInt(nowSeconds()))
        store.put(COL_USERS, userId, updated)
        revokeUserSessions(userId, "")
        audit.log(userId, docStr(updated, "username"), "password_reset", "user", userId, ip, "admin reset")
    }

    public func listUsers(): Array<JsonValue> {
        let items = ArrayList<JsonValue>()
        for (user in store.list(COL_USERS)) {
            items.add(user)
        }
        sortDocsAsc(items, "created_at")
        items.toArray()
    }

    // -----------------------------------------------------------------------
    // Roles
    // -----------------------------------------------------------------------

    public func validRole(role: String): Bool {
        role == ROLE_ADMIN || role == ROLE_EDITOR || role == ROLE_AUTHOR ||
        role == ROLE_CONTRIBUTOR || role == ROLE_SUBSCRIBER
    }

    public func isAdmin(user: JsonValue): Bool {
        docStr(user, "role") == ROLE_ADMIN
    }

    public func can(user: JsonValue, capability: String): Bool {
        let role = docStr(user, "role")
        if (role == ROLE_ADMIN) {
            return true
        }
        if (capability == "post.read") {
            return true
        }
        if (capability == "post.create") {
            return role == ROLE_EDITOR || role == ROLE_AUTHOR || role == ROLE_CONTRIBUTOR
        }
        if (capability == "post.edit.any" || capability == "page.manage") {
            return role == ROLE_EDITOR
        }
        if (capability == "post.publish") {
            return role == ROLE_EDITOR || role == ROLE_AUTHOR
        }
        if (capability == "comment.moderate") {
            return role == ROLE_EDITOR
        }
        if (capability == "media.upload" || capability == "media.manage") {
            return role == ROLE_EDITOR || role == ROLE_AUTHOR
        }
        false
    }

    public func canEditPost(user: JsonValue, post: JsonValue): Bool {
        let role = docStr(user, "role")
        let userId = docStr(user, "id")
        if (role == ROLE_ADMIN || role == ROLE_EDITOR) {
            return true
        }
        if (docStr(post, "author_id") != userId) {
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

    public func generateSetupToken(): String {
        randomToken(bytes: 18)
    }
}
