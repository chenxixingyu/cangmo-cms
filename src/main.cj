/**
 * Cangmo - command line entry point.
 *
 * Commands:
 *   cangmo serve [--config FILE] [--host HOST] [--port PORT] [--data DIR]
 *   cangmo init
 *   cangmo doctor
 *   cangmo user create <username> <email> [password] [role]
 *   cangmo user reset <username> <new-password>
 *   cangmo user list
 *   cangmo backup [label]
 *   cangmo export [file]
 *   cangmo version
 */
package cangmo

import cangmo.core.*
import cangmo.http.*
import cangmo.json.*
import cangmo.service.*
import cangmo.store.*
import cangmo.web.*
import std.collection.*
import std.env.*
import std.fs.*

main(args: Array<String>): Int64 {
    let command = if (args.size > 0) { args[0] } else { "serve" }
    if (command == "version" || command == "--version" || command == "-v") {
        println("${APP_NAME} ${APP_VERSION} (${APP_CODENAME})")
        return 0
    }
    if (command == "help" || command == "--help" || command == "-h") {
        printUsage()
        return 0
    }
    if (command == "serve") {
        return serveCommand(args)
    }
    if (command == "init") {
        return initCommand(args)
    }
    if (command == "doctor") {
        return doctorCommand(args)
    }
    if (command == "user") {
        return userCommand(args)
    }
    if (command == "backup") {
        return backupCommand(args)
    }
    if (command == "export") {
        return exportCommand(args)
    }
    println("未知命令：${command}")
    printUsage()
    return 1
}

func printUsage(): Unit {
    println("仓墨 Cangmo ${APP_VERSION} — 用仓颉语言构建的博客系统")
    println("")
    println("用法：")
    println("  cangmo serve [--config FILE] [--host HOST] [--port PORT] [--data DIR]")
    println("  cangmo init")
    println("  cangmo doctor")
    println("  cangmo user create <username> <email> [password] [role]")
    println("  cangmo user reset <username> <new-password>")
    println("  cangmo user list")
    println("  cangmo backup [label]")
    println("  cangmo export [file]")
    println("  cangmo version")
    println("")
    println("环境变量：CANGMO_HOST, CANGMO_PORT, CANGMO_DATA_DIR, CANGMO_SECRET,")
    println("          CANGMO_DEV, CANGMO_SETUP_TOKEN, CANGMO_PASSWORD")
}

func optionValue(args: Array<String>, name: String): ?String {
    var i = 0
    while (i < args.size) {
        if (args[i] == name && i + 1 < args.size) {
            return Some(args[i + 1])
        }
        i += 1
    }
    None
}

func configPath(args: Array<String>): String {
    match (optionValue(args, "--config")) {
        case Some(value) => value
        case None => getVariable("CANGMO_CONFIG") ?? "config.json"
    }
}

func serveCommand(args: Array<String>): Int64 {
    let config = Config.load(path: configPath(args))
    match (optionValue(args, "--host")) {
        case Some(value) => config.host = value
        case None => ()
    }
    match (optionValue(args, "--port")) {
        case Some(value) => config.port = parseIntOr(value, config.port)
        case None => ()
    }
    match (optionValue(args, "--data")) {
        case Some(value) => config.dataDir = value
        case None => ()
    }
    if (config.port < 1 || config.port > 65535) {
        println("端口无效：${config.port}")
        return 1
    }
    let app = WebApp(config)
    let services = app.serviceRegistry()
    if (!services.templates.hasTemplate("home.html")) {
        services.logger.error("startup", "默认主题模板缺失：${services.themeTemplatesDir()}/home.html")
        return 1
    }
    if (!services.adminTemplates.hasTemplate("login.html")) {
        services.logger.error("startup", "后台模板缺失：${services.config.adminTemplatesDir()}/login.html")
        return 1
    }
    let scheduler = Scheduler(services.posts, services.stats, services.auth, services.limiter,
                              services.store, services.logger, services.backup, services.settings,
                              services.webhooks)
    scheduler.start()
    let server = HttpServer(config, { req: HttpRequest => app.handle(req) }, services.logger)
    services.logger.info("startup", "数据目录：${config.dataDir}")
    services.logger.info("startup", "后台地址：http://${config.host}:${config.port}/admin")
    server.start()
    scheduler.stop()
    services.store.close()
    return 0
}

func initCommand(args: Array<String>): Int64 {
    let config = Config.load(path: configPath(args))
    ensureDir(config.dataDir)
    ensureDir(config.uploadsDir())
    ensureDir(config.logsDir())
    ensureDir(config.backupDir())
    let services = Services(config)
    services.store.close()
    println("初始化完成。")
    println("配置文件：${config.configPath}")
    println("数据目录：${config.dataDir}")
    println("运行 cangmo serve 启动站点。")
    return 0
}

func doctorCommand(args: Array<String>): Int64 {
    let config = Config.load(path: configPath(args))
    let services = Services(config)
    var ok = true
    println("== 仓墨自检 ==")
    println("版本：${APP_VERSION}")
    println("配置：${config.configPath}")
    println("数据目录：${config.dataDir} ${if (isDirectory(config.dataDir)) { "✓" } else { "✗" }}")
    println("上传目录：${config.uploadsDir()} ${if (isDirectory(config.uploadsDir())) { "✓" } else { "✗" }}")
    println("主题：${services.settings.str("theme", def: config.theme)} ${if (services.templates.hasTemplate("home.html")) { "✓" } else { "✗" }}")
    println("后台模板：${if (services.adminTemplates.hasTemplate("login.html")) { "✓" } else { "✗" }}")
    println("静态资源：${if (exists(services.themeAssetDir() + "/style.css")) { "✓" } else { "✗" }}")
    println("安全密钥长度：${config.secret.size} ${if (config.secret.size >= 32) { "✓" } else { "✗" }}")
    println("用户数：${services.store.count(COL_USERS)}")
    println("文章数：${services.store.count(COL_POSTS)}")
    println("评论数：${services.store.count(COL_COMMENTS)}")
    println("附件数：${services.store.count(COL_MEDIA)}")
    println("附件库：${if (services.adminTemplates.hasTemplate("attachments.html")) { "✓" } else { "✗" }}")
    println("备份中心：${if (services.adminTemplates.hasTemplate("backups.html")) { "✓" } else { "✗" }}")
    println("WAL 待压缩记录：${services.store.pendingWalEntries()}")
    println("PBKDF2 迭代：${config.pbkdf2Iterations}")
    let templateNames = ["login.html", "setup.html", "dashboard.html", "posts.html", "editor.html",
                         "categories.html", "tags.html", "comments.html", "attachments.html", "users.html",
                         "settings.html", "themes.html", "audit.html", "tools.html", "backups.html", "profile.html", "error.html"]
    var templateCount: Int64 = 0
    for (name in templateNames) {
        if (services.adminTemplates.hasTemplate(name)) {
            templateCount += 1
        }
    }
    println("后台模板完整度：${templateCount}/${templateNames.size}")
    if (templateCount < templateNames.size) {
        ok = false
    }
    if (!services.templates.hasTemplate("home.html") || !exists(services.themeAssetDir() + "/style.css")) {
        ok = false
    }
    if (config.secret.size < 32) {
        ok = false
    }
    services.store.close()
    if (ok) {
        println("自检通过。")
        return 0
    }
    println("自检发现问题，请检查上方标记。")
    return 1
}

func userCommand(args: Array<String>): Int64 {
    if (args.size < 2) {
        println("用法：cangmo user create|reset|list ...")
        return 1
    }
    let config = Config.load(path: configPath(args))
    let services = Services(config)
    let sub = args[1]
    if (sub == "list") {
        for (user in services.auth.listUsers()) {
            println("${docStr(user, "username")}\t${docStr(user, "role")}\t${docStr(user, "email")}")
        }
        services.store.close()
        return 0
    }
    if (sub == "create") {
        if (args.size < 4) {
            println("用法：cangmo user create <username> <email> [password] [role]")
            services.store.close()
            return 1
        }
        let username = args[2]
        let email = args[3]
        var password = ""
        if (args.size >= 5) {
            password = args[4]
        } else {
            password = getVariable("CANGMO_PASSWORD") ?? ""
        }
        if (password.size == 0) {
            println("请通过第 5 个参数或 CANGMO_PASSWORD 环境变量提供密码。")
            services.store.close()
            return 1
        }
        var role = ROLE_ADMIN
        if (args.size >= 6) {
            role = args[5]
        }
        let id = services.auth.createUser(username, email, password, username, role, "127.0.0.1")
        println("用户已创建：${id}")
        services.store.close()
        return 0
    }
    if (sub == "reset") {
        if (args.size < 4) {
            println("用法：cangmo user reset <username> <new-password>")
            services.store.close()
            return 1
        }
        let user = match (services.auth.userByUsername(args[2])) {
            case Some(value) => value
            case None =>
                println("用户不存在：${args[2]}")
                services.store.close()
                return 1
        }
        services.auth.resetPassword(docStr(user, "id"), args[3], "127.0.0.1")
        println("密码已重置：${args[2]}")
        services.store.close()
        return 0
    }
    println("未知 user 子命令：${sub}")
    services.store.close()
    return 1
}

func backupCommand(args: Array<String>): Int64 {
    let config = Config.load(path: configPath(args))
    let services = Services(config)
    let label = if (args.size >= 2) { args[1] } else { "cli" }
    let result = services.backup.createBackup(label)
    println("备份已创建：${config.backupDir()}/${docStr(result, "name")}")
    services.store.close()
    return 0
}

func exportCommand(args: Array<String>): Int64 {
    let config = Config.load(path: configPath(args))
    let services = Services(config)
    let text = services.backup.exportJson(pretty: true)
    let path = if (args.size >= 2) { args[1] } else { "cangmo-export.json" }
    writeTextAtomic(path, text)
    println("已导出到 ${path}（${text.size} 字节）")
    services.store.close()
    return 0
}
