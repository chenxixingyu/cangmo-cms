/**
 * Cangmo - configuration.
 *
 * Configuration is a small JSON document. Environment variables override the
 * file for container/CI deployments. Secrets are generated once and stored in
 * the same file (mode is documented in SECURITY.md).
 */
package cangmo.core

import cangmo.json.*
import std.collection.*
import std.env.*
import std.fs.*

public class Config {
    // server
    public var host: String = "127.0.0.1"
    public var port: Int64 = 8080
    public var workers: Int64 = 48
    public var maxConnections: Int64 = 256
    public var readTimeoutMs: Int64 = 15000
    public var keepAliveMs: Int64 = 10000
    public var maxHeaderBytes: Int64 = 65536
    public var maxBodyBytes: Int64 = 25 * 1024 * 1024
    public var maxUrlLength: Int64 = 2048
    // site
    public var siteUrl: String = ""
    public var siteTitle: String = "仓墨"
    public var siteSubtitle: String = "用仓颉写下的文字"
    public var siteDescription: String = "仓墨是一个使用仓颉语言原生构建的现代、安全的博客系统。"
    public var locale: String = "zh-CN"
    public var timezone: String = "Asia/Shanghai"
    public var postsPerPage: Int64 = 10
    public var theme: String = "default"
    // security
    public var secret: String = ""
    public var trustProxy: Bool = false
    public var cookieSecure: Bool = false
    public var allowedHosts: Array<String> = Array<String>(0, repeat: "")
    public var sessionTtlHours: Int64 = 168
    public var sessionIdleHours: Int64 = 48
    public var loginMaxAttempts: Int64 = 5
    public var loginWindowMinutes: Int64 = 15
    public var lockoutMinutes: Int64 = 15
    public var pbkdf2Iterations: Int64 = 120000
    public var commentRateLimitPerHour: Int64 = 10
    public var apiRateLimitPerMinute: Int64 = 120
    public var allowRawHtml: Bool = false
    public var enableApi: Bool = true
    // runtime
    public var dataDir: String = "./data"
    public var themesDir: String = "./themes"
    public var adminDir: String = "./resources/admin"
    public var devMode: Bool = false
    public var logLevel: Int64 = 1
    public var configPath: String = "./config.json"

    public init() {}

    public static func load(path!: String = "./config.json"): Config {
        let config = Config()
        config.configPath = path
        if (exists(path)) {
            match (tryParseJson(readTextFile(path))) {
                case Some(root) =>
                    if (let JObj(_) <- root) {
                        config.applyJson(root)
                    }
                case None =>
                    throw AppError("config", "config.json is not valid JSON")
            }
        }
        config.applyEnvironment()
        if (config.secret.size < 32) {
            config.secret = randomHex(bytes: 32)
        }
        if (config.siteUrl.size == 0) {
            let displayHost = if (config.host == "0.0.0.0") { "127.0.0.1" } else { config.host }
            config.siteUrl = "http://${displayHost}:${config.port}"
        }
        config.save()
        config
    }

    public func save(): Unit {
        let root = JsonObject()
        let server = JsonObject()
        server.set("host", JStr(host))
        server.set("port", JInt(port))
        server.set("workers", JInt(workers))
        server.set("maxConnections", JInt(maxConnections))
        server.set("readTimeoutMs", JInt(readTimeoutMs))
        server.set("keepAliveMs", JInt(keepAliveMs))
        server.set("maxHeaderBytes", JInt(maxHeaderBytes))
        server.set("maxBodyBytes", JInt(maxBodyBytes))
        server.set("maxUrlLength", JInt(maxUrlLength))
        root.set("server", JObj(server))

        let site = JsonObject()
        site.set("url", JStr(siteUrl))
        site.set("title", JStr(siteTitle))
        site.set("subtitle", JStr(siteSubtitle))
        site.set("description", JStr(siteDescription))
        site.set("locale", JStr(locale))
        site.set("timezone", JStr(timezone))
        site.set("postsPerPage", JInt(postsPerPage))
        site.set("theme", JStr(theme))
        root.set("site", JObj(site))

        let security = JsonObject()
        security.set("secret", JStr(secret))
        security.set("trustProxy", JBool(trustProxy))
        security.set("cookieSecure", JBool(cookieSecure))
        security.set("allowedHosts", jsonStringList(allowedHosts))
        security.set("sessionTtlHours", JInt(sessionTtlHours))
        security.set("sessionIdleHours", JInt(sessionIdleHours))
        security.set("loginMaxAttempts", JInt(loginMaxAttempts))
        security.set("loginWindowMinutes", JInt(loginWindowMinutes))
        security.set("lockoutMinutes", JInt(lockoutMinutes))
        security.set("pbkdf2Iterations", JInt(pbkdf2Iterations))
        security.set("commentRateLimitPerHour", JInt(commentRateLimitPerHour))
        security.set("apiRateLimitPerMinute", JInt(apiRateLimitPerMinute))
        security.set("allowRawHtml", JBool(allowRawHtml))
        security.set("enableApi", JBool(enableApi))
        root.set("security", JObj(security))

        let runtime = JsonObject()
        runtime.set("dataDir", JStr(dataDir))
        runtime.set("themesDir", JStr(themesDir))
        runtime.set("adminDir", JStr(adminDir))
        runtime.set("devMode", JBool(devMode))
        runtime.set("logLevel", JInt(logLevel))
        root.set("runtime", JObj(runtime))

        try {
            writeTextAtomic(configPath, toJson(JObj(root), pretty: true) + "\n")
        } catch (e: Exception) {
            throw AppError("config", "could not write config.json: ${e.message}")
        }
    }

    private func applyJson(root: JsonValue): Unit {
        if (let Some(JObj(server)) <- root.get("server")) {
            let sv = JObj(server)
            host = getString(sv, "host", def: host)
            port = getInt(sv, "port", def: port)
            workers = getInt(sv, "workers", def: workers)
            maxConnections = getInt(sv, "maxConnections", def: maxConnections)
            readTimeoutMs = getInt(sv, "readTimeoutMs", def: readTimeoutMs)
            keepAliveMs = getInt(sv, "keepAliveMs", def: keepAliveMs)
            maxHeaderBytes = getInt(sv, "maxHeaderBytes", def: maxHeaderBytes)
            maxBodyBytes = getInt(sv, "maxBodyBytes", def: maxBodyBytes)
            maxUrlLength = getInt(sv, "maxUrlLength", def: maxUrlLength)
        }
        if (let Some(JObj(site)) <- root.get("site")) {
            let sv = JObj(site)
            siteUrl = getString(sv, "url", def: siteUrl)
            siteTitle = getString(sv, "title", def: siteTitle)
            siteSubtitle = getString(sv, "subtitle", def: siteSubtitle)
            siteDescription = getString(sv, "description", def: siteDescription)
            locale = getString(sv, "locale", def: locale)
            timezone = getString(sv, "timezone", def: timezone)
            postsPerPage = getInt(sv, "postsPerPage", def: postsPerPage)
            theme = getString(sv, "theme", def: theme)
        }
        if (let Some(JObj(security)) <- root.get("security")) {
            let sv = JObj(security)
            secret = getString(sv, "secret", def: secret)
            trustProxy = getBool(sv, "trustProxy", def: trustProxy)
            cookieSecure = getBool(sv, "cookieSecure", def: cookieSecure)
            allowedHosts = getStrings(sv, "allowedHosts")
            sessionTtlHours = getInt(sv, "sessionTtlHours", def: sessionTtlHours)
            sessionIdleHours = getInt(sv, "sessionIdleHours", def: sessionIdleHours)
            loginMaxAttempts = getInt(sv, "loginMaxAttempts", def: loginMaxAttempts)
            loginWindowMinutes = getInt(sv, "loginWindowMinutes", def: loginWindowMinutes)
            lockoutMinutes = getInt(sv, "lockoutMinutes", def: lockoutMinutes)
            pbkdf2Iterations = getInt(sv, "pbkdf2Iterations", def: pbkdf2Iterations)
            commentRateLimitPerHour = getInt(sv, "commentRateLimitPerHour", def: commentRateLimitPerHour)
            apiRateLimitPerMinute = getInt(sv, "apiRateLimitPerMinute", def: apiRateLimitPerMinute)
            allowRawHtml = getBool(sv, "allowRawHtml", def: allowRawHtml)
            enableApi = getBool(sv, "enableApi", def: enableApi)
        }
        if (let Some(JObj(runtime)) <- root.get("runtime")) {
            let sv = JObj(runtime)
            dataDir = getString(sv, "dataDir", def: dataDir)
            themesDir = getString(sv, "themesDir", def: themesDir)
            adminDir = getString(sv, "adminDir", def: adminDir)
            devMode = getBool(sv, "devMode", def: devMode)
            logLevel = getInt(sv, "logLevel", def: logLevel)
        }
    }

    private func applyEnvironment(): Unit {
        if (let Some(v) <- getVariable("CANGMO_HOST")) {
            host = v
        }
        if (let Some(v) <- getVariable("CANGMO_PORT")) {
            port = parseIntOr(v, port)
        }
        if (let Some(v) <- getVariable("CANGMO_DATA_DIR")) {
            dataDir = v
        }
        if (let Some(v) <- getVariable("CANGMO_SITE_URL")) {
            siteUrl = v
        }
        if (let Some(v) <- getVariable("CANGMO_SECRET")) {
            secret = v
        }
        if (let Some(v) <- getVariable("CANGMO_DEV")) {
            devMode = parseBoolOr(v, devMode)
        }
        if (let Some(v) <- getVariable("CANGMO_TRUST_PROXY")) {
            trustProxy = parseBoolOr(v, trustProxy)
        }
        if (let Some(v) <- getVariable("CANGMO_COOKIE_SECURE")) {
            cookieSecure = parseBoolOr(v, cookieSecure)
        }
    }

    public func uploadsDir(): String {
        dataDir + "/uploads"
    }

    public func logsDir(): String {
        dataDir + "/logs"
    }

    public func backupDir(): String {
        dataDir + "/backups"
    }

    public func adminTemplatesDir(): String {
        adminDir + "/templates"
    }

    public func adminStaticDir(): String {
        adminDir + "/static"
    }
}
