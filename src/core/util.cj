/**
 * Cangmo - core utilities.
 *
 * Original implementation, written from scratch for the Cangmo project.
 * No third-party source code is copied. See LICENSE / THIRD_PARTY_NOTICES.md.
 */
package cangmo.core

import std.collection.*
import std.time.*
import std.fs.*
import std.env.*
import std.convert.*
import std.random.*

public let APP_NAME: String = "Cangmo"
public let APP_NAME_CN: String = "仓墨"
public let APP_VERSION: String = "2.0.3"
public let APP_CODENAME: String = "Qingyu"

// ---------------------------------------------------------------------------
// Errors
// ---------------------------------------------------------------------------

/**
 * Application level error carrying a machine readable kind ("not_found",
 * "forbidden", "validation", "conflict", "rate_limited", ...).
 */
public class AppError <: Exception {
    public let kind: String
    public init(kind: String, message: String) {
        super(message)
        this.kind = kind
    }
}

public func appError(kind: String, message: String): AppError {
    AppError(kind, message)
}

// ---------------------------------------------------------------------------
// Time
// ---------------------------------------------------------------------------

public func nowSeconds(): Int64 {
    DateTime.now().toUnixTimeStamp().toSeconds()
}

public func nowMillis(): Int64 {
    DateTime.now().toUnixTimeStamp().toMilliseconds()
}

public func formatTime(seconds: Int64, pattern: String): String {
    if (seconds <= 0) {
        return ""
    }
    try {
        return DateTime.fromUnixTimeStamp(Duration.second * seconds).inLocal().format(pattern)
    } catch (e: Exception) {
        return ""
    }
}

public func formatDate(seconds: Int64): String {
    formatTime(seconds, "yyyy-MM-dd")
}

public func formatDateTime(seconds: Int64): String {
    formatTime(seconds, "yyyy-MM-dd HH:mm")
}

public func formatDateTimeSeconds(seconds: Int64): String {
    formatTime(seconds, "yyyy-MM-dd HH:mm:ss")
}

public func formatMonthDay(seconds: Int64): String {
    formatTime(seconds, "MM-dd")
}

public func formatYear(seconds: Int64): String {
    formatTime(seconds, "yyyy")
}

public func formatUtcRfc1123(seconds: Int64): String {
    try {
        let dt = DateTime.fromUnixTimeStamp(Duration.second * seconds).inUTC()
        let weekdays = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        let months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
        let days = seconds / 86400
        let weekday = weekdays[((days + 4) % 7 + 7) % 7]
        let month = months[parseIntOr(dt.format("MM"), 1) - 1]
        return "${weekday}, ${dt.format("dd")} ${month} ${dt.format("yyyy")} ${dt.format("HH:mm:ss")} GMT"
    } catch (e: Exception) {
        return "Thu, 01 Jan 1970 00:00:00 GMT"
    }
}

public func formatUtcIso(seconds: Int64): String {
    try {
        return DateTime.fromUnixTimeStamp(Duration.second * seconds).inUTC().format("yyyy-MM-dd'T'HH:mm:ss") + "Z"
    } catch (e: Exception) {
        return "1970-01-01T00:00:00Z"
    }
}

public func dateKey(seconds: Int64): String {
    formatTime(seconds, "yyyy-MM-dd")
}

public func relativeTime(seconds: Int64): String {
    if (seconds <= 0) {
        return ""
    }
    let diff = nowSeconds() - seconds
    if (diff < 60) {
        return "刚刚"
    }
    if (diff < 3600) {
        return "${diff / 60} 分钟前"
    }
    if (diff < 86400) {
        return "${diff / 3600} 小时前"
    }
    if (diff < 86400 * 30) {
        return "${diff / 86400} 天前"
    }
    return formatDate(seconds)
}

public func daysAgo(days: Int64): Int64 {
    nowSeconds() - days * 86400
}

// ---------------------------------------------------------------------------
// Text
// ---------------------------------------------------------------------------

/**
 * String.indexOf / lastIndexOf return Option<Int64> in Cangjie. These
 * helpers preserve the familiar "not found == -1" convention.
 */
public func findSub(s: String, sub: String): Int64 {
    match (s.indexOf(sub)) {
        case Some(i) => i
        case None => -1
    }
}

public func findLastSub(s: String, sub: String): Int64 {
    match (s.lastIndexOf(sub)) {
        case Some(i) => i
        case None => -1
    }
}

public func isBlank(s: String): Bool {
    for (b in s.toArray()) {
        if (b != 0x20 && b != 0x09 && b != 0x0A && b != 0x0D) {
            return false
        }
    }
    return true
}

public func isNotBlank(s: String): Bool {
    !isBlank(s)
}

public func trimText(s: String): String {
    s.trimAscii()
}

public func byteLength(s: String): Int64 {
    s.toArray().size
}

public func runeCount(s: String): Int64 {
    var n = 0
    for (b in s.toArray()) {
        if ((b & 0xC0) != 0x80) {
            n += 1
        }
    }
    return n
}

/**
 * Cut a UTF-8 string at a byte budget without breaking a code point.
 */
public func truncateUtf8(s: String, maxBytes: Int64): String {
    let bytes = s.toArray()
    if (maxBytes <= 0) {
        return ""
    }
    if (bytes.size <= maxBytes) {
        return s
    }
    var end = maxBytes
    while (end > 0 && (bytes[end] & 0xC0) == 0x80) {
        end -= 1
    }
    return s[0..end]
}

/**
 * Cut by Unicode scalar count, appending a suffix when anything was removed.
 */
public func truncateRunes(s: String, maxRunes: Int64, suffix!: String = "…"): String {
    if (maxRunes <= 0) {
        return ""
    }
    let bytes = s.toArray()
    var seen = 0
    var i = 0
    while (i < bytes.size) {
        if ((bytes[i] & 0xC0) != 0x80) {
            if (seen >= maxRunes) {
                return s[0..i] + suffix
            }
            seen += 1
        }
        i += 1
    }
    return s
}

public func escapeHtml(s: String): String {
    let bytes = s.toArray()
    let sb = StringBuilder()
    var i = 0
    var runStart = 0
    while (i < bytes.size) {
        let b = bytes[i]
        var entity = ""
        if (b == 0x26) {
            entity = "&amp;"
        } else if (b == 0x3C) {
            entity = "&lt;"
        } else if (b == 0x3E) {
            entity = "&gt;"
        } else if (b == 0x22) {
            entity = "&quot;"
        } else if (b == 0x27) {
            entity = "&#39;"
        }
        if (entity.size > 0) {
            if (i > runStart) {
                sb.append(String.fromUtf8(bytes[runStart..i]))
            }
            sb.append(entity)
            i += 1
            runStart = i
        } else {
            i += 1
        }
    }
    if (bytes.size > runStart) {
        sb.append(String.fromUtf8(bytes[runStart..bytes.size]))
    }
    return sb.toString()
}

/**
 * Strip HTML tags and decode the handful of entities produced by our own
 * renderer. Used for excerpts, RSS descriptions and meta descriptions.
 */
public func stripHtml(s: String): String {
    let bytes = s.toArray()
    let sb = StringBuilder()
    var i = 0
    var inTag = false
    var runStart = 0
    while (i < bytes.size) {
        let b = bytes[i]
        if (b == 0x3C) {
            if (i > runStart && !inTag) {
                sb.append(String.fromUtf8(bytes[runStart..i]))
            }
            inTag = true
            i += 1
        } else if (b == 0x3E && inTag) {
            inTag = false
            i += 1
            runStart = i
        } else {
            i += 1
        }
    }
    if (!inTag && bytes.size > runStart) {
        sb.append(String.fromUtf8(bytes[runStart..bytes.size]))
    }
    var out = sb.toString()
    out = out.replace("&lt;", "<")
    out = out.replace("&gt;", ">")
    out = out.replace("&quot;", "\"")
    out = out.replace("&#39;", "'")
    out = out.replace("&nbsp;", " ")
    out = out.replace("&amp;", "&")
    return out
}

public func normalizeWhitespace(s: String): String {
    let bytes = s.toArray()
    let out = ArrayList<UInt8>()
    var started = false
    var pendingSpace = false
    for (b in bytes) {
        if (b == 0x20 || b == 0x09 || b == 0x0A || b == 0x0D) {
            if (started) {
                pendingSpace = true
            }
        } else {
            if (pendingSpace) {
                out.add(0x20)
                pendingSpace = false
            }
            out.add(b)
            started = true
        }
    }
    return String.fromUtf8(out.toArray())
}

public func makeExcerpt(markdownOrHtml: String, maxRunes!: Int64 = 120): String {
    let text = normalizeWhitespace(stripHtml(markdownOrHtml))
    return truncateRunes(text, maxRunes)
}

public func readingMinutes(markdown: String): Int64 {
    // Count CJK characters and Latin words; ~350 CJK chars or 200 words/min.
    let bytes = markdown.toArray()
    var cjk = 0
    var latinWords = 0
    var inWord = false
    for (b in bytes) {
        if (b >= 0xE4 && b <= 0xE9) {
            cjk += 1
        } else if ((b >= 0x41 && b <= 0x5A) || (b >= 0x61 && b <= 0x7A) || (b >= 0x30 && b <= 0x39)) {
            if (!inWord) {
                latinWords += 1
                inWord = true
            }
        } else {
            inWord = false
        }
    }
    var minutes = (cjk + 349) / 350 + (latinWords + 199) / 200
    if (minutes < 1) {
        minutes = 1
    }
    return minutes
}

public func slugify(s: String): String {
    let lower = s.toAsciiLower()
    let sb = StringBuilder()
    var lastDash = false
    var length = 0
    for (b in lower.toArray()) {
        if ((b >= 0x61 && b <= 0x7A) || (b >= 0x30 && b <= 0x39)) {
            sb.append(Rune(Int64(b)))
            lastDash = false
            length += 1
        } else if (b == 0x2D || b == 0x5F || b == 0x20 || b == 0x2E || b == 0x2C || b == 0x2F) {
            if (!lastDash && length > 0) {
                sb.append("-")
                lastDash = true
            }
        }
    }
    var out = sb.toString()
    while (out.size > 0 && out[out.size - 1] == 0x2D) {
        out = out[0..out.size - 1]
    }
    return out
}

public func isValidSlug(s: String): Bool {
    if (s.size < 1 || s.size > 96) {
        return false
    }
    for (b in s.toArray()) {
        let ok = (b >= 0x61 && b <= 0x7A) || (b >= 0x30 && b <= 0x39) || b == 0x2D
        if (!ok) {
            return false
        }
    }
    return true
}

public func isValidUsername(s: String): Bool {
    let bytes = s.toArray()
    if (bytes.size < 3 || bytes.size > 32) {
        return false
    }
    let first = bytes[0]
    if (!((first >= 0x41 && first <= 0x5A) || (first >= 0x61 && first <= 0x7A))) {
        return false
    }
    for (b in bytes) {
        let ok = (b >= 0x41 && b <= 0x5A) || (b >= 0x61 && b <= 0x7A) ||
                 (b >= 0x30 && b <= 0x39) || b == 0x5F || b == 0x2D
        if (!ok) {
            return false
        }
    }
    return true
}

public func isValidEmail(s: String): Bool {
    let bytes = s.toArray()
    if (bytes.size < 5 || bytes.size > 254) {
        return false
    }
    var at = -1
    var dots = 0
    for (i in 0..bytes.size) {
        let b = bytes[i]
        if (b == 0x40) {
            if (at >= 0) {
                return false
            }
            at = i
        } else if (b == 0x2E) {
            dots += 1
        } else if (b <= 0x20 || b == 0x3C || b == 0x3E || b == 0x22 || b == 0x27) {
            return false
        }
    }
    if (at <= 0 || at >= bytes.size - 3 || dots == 0) {
        return false
    }
    let domain = s[at + 1..bytes.size]
    if (findSub(domain, ".") < 0 || domain[0] == 0x2E || domain[domain.size - 1] == 0x2E) {
        return false
    }
    return true
}

public func maskEmail(s: String): String {
    let at = findSub(s, "@")
    if (at <= 0) {
        return "***"
    }
    let name = s[0..at]
    if (name.size <= 2) {
        return "***" + s[at..s.size]
    }
    return name[0..1] + "***" + s[at..s.size]
}

// ---------------------------------------------------------------------------
// URL / query
// ---------------------------------------------------------------------------

let HEX_UPPER: Array<String> = ["0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "A", "B", "C", "D", "E", "F"]

public func hexEncode(data: Array<UInt8>): String {
    let sb = StringBuilder()
    for (b in data) {
        let v = Int64(b)
        sb.append(HEX_UPPER[v >> 4])
        sb.append(HEX_UPPER[v & 0x0F])
    }
    return sb.toString()
}

func hexValue(b: UInt8): Int64 {
    if (b >= 0x30 && b <= 0x39) {
        return Int64(b - 0x30)
    }
    if (b >= 0x61 && b <= 0x66) {
        return Int64(b - 0x61 + 10)
    }
    if (b >= 0x41 && b <= 0x46) {
        return Int64(b - 0x41 + 10)
    }
    return -1
}

public func hexDecode(s: String): Array<UInt8> {
    let out = ArrayList<UInt8>()
    let bytes = s.toArray()
    var i = 0
    while (i + 1 < bytes.size) {
        let hi = hexValue(bytes[i])
        let lo = hexValue(bytes[i + 1])
        if (hi < 0 || lo < 0) {
            throw AppError("validation", "invalid hex string")
        }
        out.add(UInt8(hi * 16 + lo))
        i += 2
    }
    return out.toArray()
}

public func urlEncode(s: String): String {
    let sb = StringBuilder()
    for (b in s.toArray()) {
        let unreserved = (b >= 0x41 && b <= 0x5A) || (b >= 0x61 && b <= 0x7A) ||
                         (b >= 0x30 && b <= 0x39) || b == 0x2D || b == 0x2E || b == 0x5F || b == 0x7E
        if (unreserved) {
            sb.append(Rune(Int64(b)))
        } else {
            let v = Int64(b)
            sb.append("%")
            sb.append(HEX_UPPER[v >> 4])
            sb.append(HEX_UPPER[v & 0x0F])
        }
    }
    return sb.toString()
}

public func urlEncodeForm(s: String): String {
    let sb = StringBuilder()
    for (b in s.toArray()) {
        if (b == 0x20) {
            sb.append("+")
            continue
        }
        let unreserved = (b >= 0x41 && b <= 0x5A) || (b >= 0x61 && b <= 0x7A) ||
                         (b >= 0x30 && b <= 0x39) || b == 0x2D || b == 0x2E || b == 0x5F || b == 0x7E
        if (unreserved) {
            sb.append(Rune(Int64(b)))
        } else {
            let v = Int64(b)
            sb.append("%")
            sb.append(HEX_UPPER[v >> 4])
            sb.append(HEX_UPPER[v & 0x0F])
        }
    }
    return sb.toString()
}

public func urlDecode(s: String, plusAsSpace!: Bool = true): String {
    let bytes = s.toArray()
    let out = ArrayList<UInt8>()
    var i = 0
    while (i < bytes.size) {
        let b = bytes[i]
        if (b == 0x25 && i + 2 < bytes.size) {
            let hi = hexValue(bytes[i + 1])
            let lo = hexValue(bytes[i + 2])
            if (hi >= 0 && lo >= 0) {
                out.add(UInt8(hi * 16 + lo))
                i += 3
                continue
            }
            out.add(b)
            i += 1
        } else if (b == 0x2B && plusAsSpace) {
            out.add(0x20)
            i += 1
        } else {
            out.add(b)
            i += 1
        }
    }
    return String.fromUtf8(out.toArray())
}

public func tryUrlDecode(s: String, plusAsSpace!: Bool = true): ?String {
    try {
        return Some(urlDecode(s, plusAsSpace: plusAsSpace))
    } catch (e: Exception) {
        return None
    }
}

public func parseQuery(raw: String): HashMap<String, String> {
    let out = HashMap<String, String>()
    if (raw.size == 0) {
        return out
    }
    for (pair in raw.split("&")) {
        if (pair.size == 0) {
            continue
        }
        let eq = findSub(pair, "=")
        let key = if (eq < 0) { pair } else { pair[0..eq] }
        let val = if (eq < 0) { "" } else { pair[eq + 1..pair.size] }
        let k = urlDecode(key)
        if (k.size > 0 && !out.contains(k)) {
            out[k] = urlDecode(val)
        }
    }
    return out
}

public func parseQueryMulti(raw: String): HashMap<String, ArrayList<String>> {
    let out = HashMap<String, ArrayList<String>>()
    if (raw.size == 0) {
        return out
    }
    for (pair in raw.split("&")) {
        if (pair.size == 0) {
            continue
        }
        let eq = findSub(pair, "=")
        let key = if (eq < 0) { pair } else { pair[0..eq] }
        let val = if (eq < 0) { "" } else { pair[eq + 1..pair.size] }
        let k = urlDecode(key)
        let v = urlDecode(val)
        if (k.size == 0) {
            continue
        }
        if (!out.contains(k)) {
            out[k] = ArrayList<String>()
        }
        out[k].add(v)
    }
    return out
}

public func buildQuery(params: HashMap<String, String>): String {
    let parts = ArrayList<String>()
    for ((k, v) in params) {
        if (v.size == 0) {
            continue
        }
        parts.add(urlEncode(k) + "=" + urlEncode(v))
    }
    return String.join(parts.toArray(), delimiter: "&")
}

// ---------------------------------------------------------------------------
// Base64
// ---------------------------------------------------------------------------

let B64_STD: String = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
let B64_URL: String = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"

func b64Char(table: String, idx: Int64): Rune {
    Rune(Int64(table.toArray()[idx]))
}

public func base64Encode(data: Array<UInt8>): String {
    base64WithTable(data, B64_STD)
}

public func base64UrlEncode(data: Array<UInt8>): String {
    let raw = base64WithTable(data, B64_URL)
    var end = raw.size
    while (end > 0 && raw[end - 1] == 0x3D) {
        end -= 1
    }
    return raw[0..end]
}

func base64WithTable(data: Array<UInt8>, table: String): String {
    let sb = StringBuilder()
    var i = 0
    while (i + 2 < data.size) {
        let n = (Int64(data[i]) << 16) | (Int64(data[i + 1]) << 8) | Int64(data[i + 2])
        sb.append(b64Char(table, (n >> 18) & 63))
        sb.append(b64Char(table, (n >> 12) & 63))
        sb.append(b64Char(table, (n >> 6) & 63))
        sb.append(b64Char(table, n & 63))
        i += 3
    }
    let rest = data.size - i
    if (rest == 1) {
        let n = Int64(data[i]) << 16
        sb.append(b64Char(table, (n >> 18) & 63))
        sb.append(b64Char(table, (n >> 12) & 63))
        sb.append("=")
        sb.append("=")
    } else if (rest == 2) {
        let n = (Int64(data[i]) << 16) | (Int64(data[i + 1]) << 8)
        sb.append(b64Char(table, (n >> 18) & 63))
        sb.append(b64Char(table, (n >> 12) & 63))
        sb.append(b64Char(table, (n >> 6) & 63))
        sb.append("=")
    }
    return sb.toString()
}

func b64Value(b: UInt8): Int64 {
    if (b >= 0x41 && b <= 0x5A) {
        return Int64(b - 0x41)
    }
    if (b >= 0x61 && b <= 0x7A) {
        return Int64(b - 0x61 + 26)
    }
    if (b >= 0x30 && b <= 0x39) {
        return Int64(b - 0x30 + 52)
    }
    if (b == 0x2B || b == 0x2D) {
        return 62
    }
    if (b == 0x2F || b == 0x5F) {
        return 63
    }
    return -1
}

public func base64Decode(s: String): Array<UInt8> {
    let out = ArrayList<UInt8>()
    var buffer: Int64 = 0
    var bits = 0
    for (b in s.toArray()) {
        if (b == 0x3D) {
            break
        }
        if (b == 0x20 || b == 0x0A || b == 0x0D || b == 0x09) {
            continue
        }
        let v = b64Value(b)
        if (v < 0) {
            throw AppError("validation", "invalid base64 data")
        }
        buffer = (buffer << 6) | v
        bits += 6
        if (bits >= 8) {
            bits -= 8
            out.add(UInt8((buffer >> bits) & 0xFF))
        }
    }
    return out.toArray()
}

// ---------------------------------------------------------------------------
// Identifiers / randomness
// ---------------------------------------------------------------------------

public func base36Encode(n: Int64): String {
    if (n == 0) {
        return "0"
    }
    var x = n
    if (x < 0) {
        x = -x
    }
    let tmp = ArrayList<UInt8>()
    while (x > 0) {
        let d = x % 36
        let c = if (d < 10) { 0x30 + d } else { 0x61 + d - 10 }
        tmp.add(UInt8(c))
        x = x / 36
    }
    let out = Array<UInt8>(tmp.size, repeat: 0)
    for (i in 0..tmp.size) {
        out[i] = tmp[tmp.size - 1 - i]
    }
    return String.fromUtf8(out)
}

public func newId(prefix: String): String {
    let t = base36Encode(nowMillis())
    let r = hexEncode(secureRandomBytes(8))
    return "${prefix}_${t}${r}"
}

public func newUuid(): String {
    let b = secureRandomBytes(16)
    b[6] = (b[6] & 0x0F) | 0x40
    b[8] = (b[8] & 0x3F) | 0x80
    let h = hexEncode(b).toAsciiLower()
    return h[0..8] + "-" + h[8..12] + "-" + h[12..16] + "-" + h[16..20] + "-" + h[20..32]
}

public func randomToken(bytes!: Int64 = 32): String {
    base64UrlEncode(secureRandomBytes(bytes))
}

public func randomHex(bytes!: Int64 = 16): String {
    hexEncode(secureRandomBytes(bytes)).toAsciiLower()
}

public func secureEqualsText(a: String, b: String): Bool {
    secureEqualsBytes(a.toArray(), b.toArray())
}

public func hashIp(ip: String, secret: String): String {
    hexEncode(sha256((ip + "|" + secret).toArray()))[0..32].toAsciiLower()
}

// ---------------------------------------------------------------------------
// Parsing helpers
// ---------------------------------------------------------------------------

public func parseIntOr(s: String, fallback: Int64): Int64 {
    try {
        return Int64.parse(s.trimAscii())
    } catch (e: Exception) {
        return fallback
    }
}

public func parseIntStrict(s: String): ?Int64 {
    try {
        return Some(Int64.parse(s.trimAscii()))
    } catch (e: Exception) {
        return None
    }
}

public func parseBoolOr(s: String, fallback: Bool): Bool {
    let v = s.trimAscii().toAsciiLower()
    if (v == "1" || v == "true" || v == "yes" || v == "on") {
        return true
    }
    if (v == "0" || v == "false" || v == "no" || v == "off") {
        return false
    }
    return fallback
}

public func formatFileSize(bytes: Int64): String {
    if (bytes < 1024) {
        return "${bytes} B"
    }
    if (bytes < 1024 * 1024) {
        return "${bytes / 1024} KB"
    }
    if (bytes < 1024 * 1024 * 1024) {
        return "${bytes / (1024 * 1024)} MB"
    }
    return "${bytes / (1024 * 1024 * 1024)} GB"
}

public func extensionOf(filename: String): String {
    let base = baseName(filename).toAsciiLower()
    let parts = base.split(".")
    if (parts.size < 2) {
        return ""
    }
    let ext = parts[parts.size - 1]
    if (ext.size == 0 || ext.size > 12) {
        return ""
    }
    return ext
}

public func baseName(path: String): String {
    let normalized = path.replace("\\", "/")
    let idx = findLastSub(normalized, "/")
    if (idx < 0) {
        return normalized
    }
    return normalized[idx + 1..normalized.size]
}

public func sanitizeFilename(name: String): String {
    let base = baseName(name)
    let sb = StringBuilder()
    var count = 0
    for (b in base.toArray()) {
        if (count >= 120) {
            break
        }
        let ok = (b >= 0x41 && b <= 0x5A) || (b >= 0x61 && b <= 0x7A) ||
                 (b >= 0x30 && b <= 0x39) || b == 0x2D || b == 0x5F || b == 0x2E
        if (ok) {
            sb.append(Rune(Int64(b)))
            count += 1
        } else if (b >= 0x80) {
            sb.append("-")
            count += 1
        }
    }
    var out = sb.toString()
    while (out.size > 0 && out[0] == 0x2D) {
        out = out[1..out.size]
    }
    if (out.size == 0) {
        out = "file"
    }
    return out
}

/**
 * Sanitize a human-facing display name while keeping UTF-8 text (e.g. Chinese).
 * Path separators and control characters are stripped, unsafe ASCII punctuation
 * becomes '-', and multi-byte sequences are copied whole so the result stays valid.
 * The on-disk name is always generated separately (media id + extension).
 */
public func sanitizeDisplayName(name: String): String {
    let src = baseName(name).toArray()
    let out = ArrayList<UInt8>()
    var i = 0
    var budget = 180
    while (i < src.size && budget > 0) {
        let b = src[i]
        if (b < 0x80) {
            if (b < 0x20 || b == 0x7F) {
                i += 1
                continue
            }
            let safe = (b >= 0x41 && b <= 0x5A) || (b >= 0x61 && b <= 0x7A) ||
                       (b >= 0x30 && b <= 0x39) || b == 0x2D || b == 0x5F ||
                       b == 0x2E || b == 0x20
            out.add(if (safe) { b } else { 0x2D })
            budget -= 1
            i += 1
            continue
        }
        let width = if (b >= 0xF0) { 4 } else if (b >= 0xE0) { 3 } else if (b >= 0xC0) { 2 } else { 1 }
        if (i + width > src.size || budget < width) {
            break
        }
        for (j in 0..width) {
            out.add(src[i + j])
        }
        budget -= width
        i += width
    }
    let cleaned = try {
        String.fromUtf8(out.toArray()).trimAscii()
    } catch (e: Exception) {
        ""
    }
    if (cleaned.size == 0) {
        return "file"
    }
    cleaned
}

// ---------------------------------------------------------------------------
// Files
// ---------------------------------------------------------------------------

public func ensureDir(path: String): Unit {
    if (!exists(path)) {
        Directory.create(path, recursive: true)
    }
}

public func readTextFile(path: String): String {
    String.fromUtf8(File.readFrom(path))
}

public func writeTextFile(path: String, text: String): Unit {
    File.writeTo(path, text.toArray())
}

public func writeTextAtomic(path: String, text: String): Unit {
    let tmp = path + ".tmp"
    File.writeTo(tmp, text.toArray())
    if (exists(path)) {
        remove(path, recursive: false)
    }
    rename(tmp, to: path, overwrite: true)
}

public func appendTextFile(path: String, text: String): Unit {
    File.appendTo(path, text.toArray())
}

public func fileExists(path: String): Bool {
    exists(path)
}

public func isDirectory(path: String): Bool {
    if (!exists(path)) {
        return false
    }
    try {
        return FileInfo(path).isDirectory()
    } catch (e: Exception) {
        return false
    }
}

public func fileSize(path: String): Int64 {
    try {
        return FileInfo(path).size
    } catch (e: Exception) {
        return 0
    }
}

public func listDir(path: String): Array<String> {
    let result = ArrayList<String>()
    try {
        for (info in Directory.readFrom(path)) {
            result.add(info.name)
        }
    } catch (e: Exception) {
        return []
    }
    return result.toArray()
}
