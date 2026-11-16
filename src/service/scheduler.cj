/**
 * Cangmo - background scheduler (scheduled posts, counters, cleanup).
 */
package cangmo.service

import cangmo.core.*
import cangmo.store.*
import std.time.*

public class Scheduler {
    private let posts: PostService
    private let stats: StatsService
    private let auth: AuthService
    private let limiter: RateLimiter
    private let store: Store
    private let logger: Logger
    private var running: Bool = false

    public init(posts: PostService, stats: StatsService, auth: AuthService, limiter: RateLimiter,
                store: Store, logger: Logger) {
        this.posts = posts
        this.stats = stats
        this.auth = auth
        this.limiter = limiter
        this.store = store
        this.logger = logger
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
            } catch (e: Exception) {
                logger.error("scheduler", "background task failed: ${e.message}")
            }
            sleep(Duration.second * 20)
            tick += 1
        }
    }
}
