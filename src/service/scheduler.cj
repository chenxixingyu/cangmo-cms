/**
 * Cangmo - background scheduler (scheduled posts, counters, cleanup).
 */
package cangmo.service

import cangmo.core.*
import cangmo.json.*
import cangmo.store.*
import std.collection.*
import std.env.*
import std.time.*

public class Scheduler {
    private let posts: PostService
    private let stats: StatsService
    private let auth: AuthService
    private let limiter: RateLimiter
    private let store: Store
    private let logger: Logger
    private let backup: BackupService
    private let settings: SettingsService
    private let webhooks: WebhookService
    private let plugins: PluginService
    private var running: Bool = false

    public init(posts: PostService, stats: StatsService, auth: AuthService, limiter: RateLimiter,
                store: Store, logger: Logger, backup: BackupService, settings: SettingsService,
                webhooks: WebhookService, plugins: PluginService) {
        this.posts = posts
        this.stats = stats
        this.auth = auth
        this.limiter = limiter
        this.store = store
        this.logger = logger
        this.backup = backup
        this.settings = settings
        this.webhooks = webhooks
        this.plugins = plugins
    }

    public func start(): Unit {
        running = true
        spawn {
            loop()
        }
    }

    public func stop(): Unit {
        running = false
    }

    private func loop(): Unit {
        var tick: Int64 = 0
        while (running) {
            try {
                let published = posts.publishDue()
                if (published > 0) {
                    logger.info("scheduler", "published ${published} scheduled posts")
                }
                if (tick % 2 == 0) {
                    stats.flush()
                }
                if (tick % 3 == 0) {
                    auth.pruneSessions()
                    limiter.prune()
                }
                if (store.pendingWalEntries() > 1500) {
                    store.compact()
                }
                maybeAutoBackup()
                webhooks.processRetries()
                plugins.processRetries()
            } catch (e: Exception) {
                logger.error("scheduler", "background task failed: ${e.message}")
            }
            sleep(Duration.second * 20)
            tick += 1
        }
    }

    private func maybeAutoBackup(): Unit {
        if (!settings.bool("backup_auto", def: false)) {
            return
        }
        let interval = settings.int("backup_interval_hours", def: 24)
        if (interval <= 0) {
            return
        }
        if (settings.bool("backup_encrypt", def: false)) {
            let passphrase = match (getVariable("CANGMO_BACKUP_PASSPHRASE")) {
                case Some(value) => value
                case None => ""
            }
            if (passphrase.size < 12) {
                logger.error("scheduler", "automatic backup disabled: CANGMO_BACKUP_PASSPHRASE is missing or too short")
                settings.setBool("backup_auto", false)
                return
            }
        }
        let now = nowSeconds()
        let last = settings.int("backup_last_at", def: 0)
        if (last > 0 && now - last < interval * 3600) {
            return
        }
        let label = "auto-" + formatTime(now, "yyyyMMdd-HHmmss")
        backup.createBackup(label, encrypt: settings.bool("backup_encrypt", def: false))
        settings.setInt("backup_last_at", now)
        let keep = settings.int("backup_keep", def: 7)
        if (keep < 1) {
            return
        }
        let autos = ArrayList<JsonValue>()
        for (item in backup.list()) {
            if (docStr(item, "name").startsWith("auto-")) {
                autos.add(item)
            }
        }
        sortDocsDesc(autos, "created_at")
        var index: Int64 = 0
        for (item in autos) {
            if (index >= keep) {
                backup.deleteBackup(docStr(item, "name"))
            }
            index += 1
        }
        logger.info("scheduler", "automatic backup created: ${label}")
    }
}
