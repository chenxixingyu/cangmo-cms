/**
 * Cangmo - mail outbox. Messages are queued as .eml files.
 * A deployment can forward them with sendmail or an external worker.
 */
package cangmo.service

import cangmo.core.*
import cangmo.json.*
import std.collection.*
import std.fs.*
import std.time.*

public class MailService {
    private let config: Config
    private let auth: AuthService
    private let settings: SettingsService

    public init(config: Config, auth: AuthService, settings: SettingsService) {
        this.config = config
        this.auth = auth
        this.settings = settings
    }

    public func outboxDir(): String {
        config.dataDir + "/mail-outbox"
    }

    public func send(to: String, subject: String, body: String): String {
        let dir = outboxDir()
        ensureDir(dir)
        let name = "mail-${formatTime(nowSeconds(), "yyyyMMdd-HHmmss")}-${randomHex(bytes: 3)}.eml"
        let text = "To: ${to}\nSubject: ${subject}\nDate: ${formatUtcRfc1123(nowSeconds())}\n" +
                   "X-Cangmo-Status: queued\n\n${body}\n"
        writeTextAtomic(dir + "/" + name, text)
        name
    }

    public func list(): Array<JsonValue> {
        let dir = outboxDir()
        ensureDir(dir)
        let items = ArrayList<JsonValue>()
        for (name in listDir(dir)) {
            if (!name.endsWith(".eml")) {
                continue
            }
            let path = dir + "/" + name
            let text = try { readTextFile(path) } catch (e: Exception) { "" }
            let item = JsonObject()
            item.set("name", JStr(name))
            item.set("to", JStr(headerValue(text, "To:")))
            item.set("subject", JStr(headerValue(text, "Subject:")))
            item.set("size", JInt(fileSize(path)))
            var modified: Int64 = 0
            try {
                modified = FileInfo(path).lastModificationTime.toUnixTimeStamp().toSeconds()
            } catch (e: Exception) {}
            item.set("created_at", JInt(modified))
            items.add(JObj(item))
        }
        sortDocsDesc(items, "created_at")
        items.toArray()
    }

    public func read(name: String): ?String {
        if (name.size == 0 || name.size > 200 || name.contains("..") ||
            name.contains("/") || name.contains("\\") || !name.endsWith(".eml")) {
            return None
        }
        let path = outboxDir() + "/" + name
        if (!exists(path)) {
            return None
        }
        try {
            Some(readTextFile(path))
        } catch (e: Exception) {
            None
        }
    }

    public func notifyPasswordReset(to: String, link: String): Unit {
        if (to.trimAscii().size == 0) {
            return
        }
        send(to, "仓墨密码重置", "请在 30 分钟内打开以下链接重置密码：\n\n${link}\n\n如果不是你发起的，请忽略此邮件。")
    }

    public func notifyComment(post: JsonValue, commentId: String, author: String, content: String,
                              moderated: Bool): Unit {
        let path = if (docStr(post, "type") == "page") { "/pages/" + docStr(post, "slug") } else { "/posts/" + docStr(post, "slug") }
        let link = settings.str("site_url", def: config.siteUrl) + path
        let state = if (moderated) { "待审核" } else { "已发布" }
        let excerpt = makeExcerpt(content, maxRunes: 160)
        for (to in auth.adminEmails()) {
            send(to, "仓墨新评论（${state}）", "文章：${docStr(post, "title")}\n评论者：${author}\n\n${excerpt}\n\n${link}#comments")
        }
    }

    private func headerValue(text: String, prefix: String): String {
        for (line in text.split("\n")) {
            if (line.startsWith(prefix)) {
                return line[prefix.size..line.size].trimAscii()
            }
        }
        ""
    }
}
