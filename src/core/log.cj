/**
 * Cangmo - structured, thread-safe logger with daily file rotation.
 */
package cangmo.core

import std.sync.*
import std.fs.*
import std.collection.*

public class Logger {
    private let mutex: Mutex = Mutex()
    private let logDir: String
    private let threshold: Int64
    private let alsoConsole: Bool
    private var currentDay: String = ""

    public init(logDir: String, threshold!: Int64 = 1, alsoConsole!: Bool = true) {
        this.logDir = logDir
        this.threshold = threshold
        this.alsoConsole = alsoConsole
        ensureDir(logDir)
    }

    public func debug(category: String, message: String): Unit {
        write(0, "DEBUG", category, message, true)
    }

    public func info(category: String, message: String): Unit {
        write(1, "INFO", category, message, false)
    }

    public func warn(category: String, message: String): Unit {
        write(2, "WARN", category, message, false)
    }

    public func error(category: String, message: String): Unit {
        write(3, "ERROR", category, message, false)
    }

    public func requestLog(method: String, path: String, status: Int64, durationMs: Int64, ip: String): Unit {
        let line = "${method} ${path} ${status} ${durationMs}ms ${ip}"
        write(1, "ACCESS", "http", line, false)
    }

    private func write(level: Int64, levelText: String, category: String, message: String, debugOnly: Bool): Unit {
        if (level < threshold) {
            return
        }
        let safeMessage = sanitizeLog(message)
        let safeCategory = sanitizeLog(category)
        let line = "[${formatDateTimeSeconds(nowSeconds())}] [${levelText}] [${safeCategory}] ${safeMessage}"
        synchronized(mutex) {
            if (alsoConsole) {
                println(line)
            }
            try {
                let day = dateKey(nowSeconds())
                if (day != currentDay) {
                    currentDay = day
                }
                appendTextFile(logDir + "/app-" + day + ".log", line + "\n")
            } catch (e: Exception) {
                // Logging must never take the application down.
            }
        }
    }
}

func sanitizeLog(text: String): String {
    var out = text.replace("\r", " ").replace("\n", " ")
    if (out.size > 4000) {
        out = truncateUtf8(out, 4000)
    }
    out
}
