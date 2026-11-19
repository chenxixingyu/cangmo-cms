/**
 * Cangmo - HTTP/1.1 data types, headers, cookies, multipart parsing and MIME.
 */
package cangmo.http

import cangmo.core.*
import cangmo.json.*
import std.collection.*
import std.time.*

// ---------------------------------------------------------------------------
// Headers
// ---------------------------------------------------------------------------

public class HttpHeaders {
    private let data: HashMap<String, ArrayList<String>>

    public init() {
        data = HashMap<String, ArrayList<String>>()
    }

    public func add(name: String, value: String): Unit {
        let key = normalizeHeaderName(name)
        if (key.size == 0) {
            return
        }
        let safe = sanitizeHeaderValue(value)
        if (!data.contains(key)) {
            data[key] = ArrayList<String>()
        }
        data[key].add(safe)
    }

    public func set(name: String, value: String): Unit {
        let key = normalizeHeaderName(name)
        if (key.size == 0) {
            return
        }
        let list = ArrayList<String>()
        list.add(sanitizeHeaderValue(value))
        data[key] = list
    }

    public func get(name: String): String {
        let key = normalizeHeaderName(name)
        match (data.get(key)) {
            case Some(list) =>
                if (list.size > 0) {
                    return list[0]
                }
                ""
            case None => ""
        }
    }

    public func getAll(name: String): Array<String> {
        let key = normalizeHeaderName(name)
        match (data.get(key)) {
            case Some(list) => list.toArray()
            case None => Array<String>(0, repeat: "")
        }
    }

    public func has(name: String): Bool {
        data.contains(normalizeHeaderName(name))
    }

    public func remove(name: String): Unit {
        data.remove(normalizeHeaderName(name))
    }

    public func names(): Array<String> {
        data.keys().toArray()
    }

    public func entries(): ArrayList<(String, String)> {
        let out = ArrayList<(String, String)>()
        for ((name, list) in data) {
            for (value in list) {
                out.add((name, value))
            }
        }
        out
    }

    public func copyFrom(other: HttpHeaders): Unit {
        for ((name, list) in other.data) {
            for (value in list) {
                add(name, value)
            }
        }
    }
}

func normalizeHeaderName(name: String): String {
    let trimmed = name.trimAscii().toAsciiLower()
    if (trimmed.size == 0 || trimmed.size > 100) {
        return ""
    }
    for (b in trimmed.toArray()) {
        let ok = (b >= 0x61 && b <= 0x7A) || (b >= 0x30 && b <= 0x39) ||
                 b == 0x2D || b == 0x5F
        if (!ok) {
            return ""
        }
    }
    trimmed
}

func sanitizeHeaderValue(value: String): String {
    var out = value.replace("\r", "").replace("\n", "").replace("\u{0}", "")
    truncateUtf8(out, 8192)
}

// ---------------------------------------------------------------------------
// Cookies
// ---------------------------------------------------------------------------

public class HttpCookie {
    public var name: String
    public var value: String
    public var path: String = "/"
    public var maxAge: Int64 = -1
    public var httpOnly: Bool = true
    public var secure: Bool = false
    public var sameSite: String = "Lax"
    public var domain: String = ""

    public init(name: String, value: String) {
        this.name = name
        this.value = value
    }
}

public func parseCookieHeader(header: String): HashMap<String, String> {
    let out = HashMap<String, String>()
    if (header.size == 0) {
        return out
    }
    for (part in header.split(";")) {
        let item = part.trimAscii()
        if (item.size == 0) {
            continue
        }
        let eq = findSub(item, "=")
        if (eq <= 0) {
            continue
        }
        let name = item[0..eq].trimAscii()
        var value = item[eq + 1..item.size].trimAscii()
        if (value.size >= 2 && value[0] == 0x22 && value[value.size - 1] == 0x22) {
            value = value[1..value.size - 1]
        }
        if (name.size > 0 && name.size <= 100) {
            value = tryUrlDecode(value, plusAsSpace: false) ?? value
            out[name] = value
        }
    }
    return out
}

public func serializeCookie(cookie: HttpCookie, nowTs: Int64): String {
    let sb = StringBuilder()
    sb.append(cookie.name)
    sb.append("=")
    sb.append(urlEncode(cookie.value))
    if (cookie.maxAge >= 0) {
        sb.append("; Max-Age=")
        sb.append(cookie.maxAge.toString())
        sb.append("; Expires=")
        sb.append(formatUtcRfc1123(nowTs + cookie.maxAge))
    }
    sb.append("; Path=")
    sb.append(if (cookie.path.size > 0) { cookie.path } else { "/" })
    if (cookie.domain.size > 0) {
        sb.append("; Domain=")
        sb.append(cookie.domain)
    }
    if (cookie.secure) {
        sb.append("; Secure")
    }
    if (cookie.httpOnly) {
        sb.append("; HttpOnly")
    }
    if (cookie.sameSite.size > 0) {
        sb.append("; SameSite=")
        sb.append(cookie.sameSite)
    }
    sb.toString()
}

// ---------------------------------------------------------------------------
// Request / response
// ---------------------------------------------------------------------------

public class UploadedFile {
    public let fieldName: String
    public let filename: String
    public let contentType: String
    public let data: Array<UInt8>

    public init(fieldName: String, filename: String, contentType: String, data: Array<UInt8>) {
        this.fieldName = fieldName
        this.filename = filename
        this.contentType = contentType
        this.data = data
    }

    public func size(): Int64 {
        data.size
    }
}

public class HttpRequest {
    public var method: String
    public var path: String
    public var rawQuery: String
    public var version: String
    public var headers: HttpHeaders = HttpHeaders()
    public var body: Array<UInt8> = Array<UInt8>(0, repeat: 0)
    public var remoteIp: String = ""
    public var remotePort: Int64 = 0
    public var scheme: String = "http"
    public var host: String = ""
    public let query: HashMap<String, ArrayList<String>>
    public let cookies: HashMap<String, String> = HashMap<String, String>()
    public let form: HashMap<String, ArrayList<String>> = HashMap<String, ArrayList<String>>()
    public let files: ArrayList<UploadedFile> = ArrayList<UploadedFile>()
    public let params: HashMap<String, String> = HashMap<String, String>()
    private var formParsed: Bool = false

    public init(method: String, path: String, rawQuery: String, version: String) {
        this.method = method
        this.path = path
        this.rawQuery = rawQuery
        this.version = version
        this.query = parseQueryMulti(rawQuery)
    }

    public func header(name: String): String {
        headers.get(name)
    }

    public func contentType(): String {
        headers.get("content-type")
    }

    public func isSecure(): Bool {
        scheme == "https"
    }

    public func queryValue(name: String, def!: String = ""): String {
        firstValue(query, name, def)
    }

    public func queryInt(name: String, def!: Int64 = 0): Int64 {
        parseIntOr(queryValue(name), def)
    }

    public func formValue(name: String, def!: String = ""): String {
        parseForm()
        firstValue(form, name, def)
    }

    public func formValues(name: String): Array<String> {
        parseForm()
        match (form.get(name)) {
            case Some(list) => list.toArray()
            case None => Array<String>(0, repeat: "")
        }
    }

    public func cookieValue(name: String, def!: String = ""): String {
        match (cookies.get(name)) {
            case Some(value) => value
            case None => def
        }
    }

    public func paramValue(name: String, def!: String = ""): String {
        match (params.get(name)) {
            case Some(value) => value
            case None => def
        }
    }

    public func parseCookies(): Unit {
        if (cookies.size > 0) {
            return
        }
        let header = headers.get("cookie")
        if (header.size == 0) {
            return
        }
        let parsed = parseCookieHeader(header)
        for ((k, v) in parsed) {
            cookies[k] = v
        }
    }

    public func parseForm(): Unit {
        if (formParsed) {
            return
        }
        formParsed = true
        let ct = contentType().toAsciiLower()
        if (ct.startsWith("application/x-www-form-urlencoded")) {
            if (body.size > 2 * 1024 * 1024) {
                throw AppError("validation", "表单数据过大")
            }
            let text = try {
                String.fromUtf8(body)
            } catch (e: Exception) {
                throw AppError("validation", "表单编码无效")
            }
            let parsed = try {
                parseQueryMulti(text)
            } catch (e: Exception) {
                throw AppError("validation", "表单编码无效")
            }
            var count = 0
            for ((k, values) in parsed) {
                if (k.size > 200) {
                    continue
                }
                count += 1
                if (count > 500) {
                    throw AppError("validation", "表单字段过多")
                }
                form[k] = values
            }
        } else if (ct.startsWith("multipart/form-data")) {
            // Use the original header value: browser boundaries are case-sensitive
            // (e.g. ----WebKitFormBoundaryAbC...). Lowercasing it breaks parsing.
            let boundary = multipartBoundary(contentType())
            if (boundary.size == 0) {
                throw AppError("validation", "缺少 multipart boundary")
            }
            parseMultipart(this, boundary)
        }
    }

    public func firstFormValue(name: String, def!: String = ""): String {
        formValue(name, def: def)
    }

    public func clientIp(): String {
        remoteIp
    }
}

func firstValue(map: HashMap<String, ArrayList<String>>, name: String, def: String): String {
    match (map.get(name)) {
        case Some(list) =>
            if (list.size > 0) {
                return list[0]
            }
            def
        case None => def
    }
}

public class HttpResponse {
    public var status: Int64 = 200
    public var headers: HttpHeaders = HttpHeaders()
    public var body: Array<UInt8> = Array<UInt8>(0, repeat: 0)
    public let cookies: ArrayList<HttpCookie> = ArrayList<HttpCookie>()
    public var closeConnection: Bool = false

    public init() {}

    public static func make(status: Int64): HttpResponse {
        let response = HttpResponse()
        response.status = status
        response
    }

    public func setHeader(name: String, value: String): HttpResponse {
        headers.set(name, value)
        this
    }

    public func addHeader(name: String, value: String): HttpResponse {
        headers.add(name, value)
        this
    }

    public func setCookie(cookie: HttpCookie): HttpResponse {
        cookies.add(cookie)
        this
    }

    public func cookie(name: String, value: String, maxAge!: Int64 = -1, path!: String = "/",
                       httpOnly!: Bool = true, secure!: Bool = false, sameSite!: String = "Lax"): HttpResponse {
        let c = HttpCookie(name, value)
        c.maxAge = maxAge
        c.path = path
        c.httpOnly = httpOnly
        c.secure = secure
        c.sameSite = sameSite
        cookies.add(c)
        this
    }

    public func deleteCookie(name: String, path!: String = "/"): HttpResponse {
        let c = HttpCookie(name, "")
        c.maxAge = 0
        c.path = path
        c.httpOnly = true
        cookies.add(c)
        this
    }

    public func text(content: String, status!: Int64 = 200): HttpResponse {
        this.status = status
        headers.set("content-type", "text/plain; charset=utf-8")
        body = content.toArray()
        this
    }

    public func html(content: String, status!: Int64 = 200): HttpResponse {
        this.status = status
        headers.set("content-type", "text/html; charset=utf-8")
        body = content.toArray()
        this
    }

    public func json(value: JsonValue, status!: Int64 = 200): HttpResponse {
        this.status = status
        headers.set("content-type", "application/json; charset=utf-8")
        body = toJsonCompact(value).toArray()
        this
    }

    public func bytes(content: Array<UInt8>, contentType: String, status!: Int64 = 200): HttpResponse {
        this.status = status
        headers.set("content-type", contentType)
        body = content
        this
    }

    public func redirect(location: String, status!: Int64 = 302): HttpResponse {
        this.status = status
        headers.set("location", sanitizeRedirect(location))
        body = Array<UInt8>(0, repeat: 0)
        this
    }

    public func empty(status: Int64): HttpResponse {
        this.status = status
        body = Array<UInt8>(0, repeat: 0)
        this
    }

    public func withSecurityHeaders(isSecure: Bool): HttpResponse {
        headers.set("x-content-type-options", "nosniff")
        headers.set("x-frame-options", "DENY")
        headers.set("referrer-policy", "strict-origin-when-cross-origin")
        headers.set("permissions-policy", "camera=(), microphone=(), geolocation=(), interest-cohort=()")
        headers.set("cross-origin-opener-policy", "same-origin")
        headers.set("cross-origin-resource-policy", "same-origin")
        headers.set("content-security-policy", "default-src 'self'; img-src 'self' data:; style-src 'self' 'unsafe-inline'; script-src 'self'; font-src 'self'; connect-src 'self'; frame-ancestors 'none'; base-uri 'self'; form-action 'self'")
        if (isSecure) {
            headers.set("strict-transport-security", "max-age=31536000; includeSubDomains")
        }
        this
    }
}

func sanitizeRedirect(location: String): String {
    var value = sanitizeHeaderValue(location).trimAscii()
    if (value.startsWith("//")) {
        value = "/" + value[2..value.size]
    }
    let lower = value.toAsciiLower()
    if (lower.startsWith("javascript:") || lower.startsWith("data:") || lower.startsWith("vbscript:")) {
        return "/"
    }
    value
}

public func statusText(status: Int64): String {
    match (status) {
        case 200 => "OK"
        case 201 => "Created"
        case 202 => "Accepted"
        case 204 => "No Content"
        case 206 => "Partial Content"
        case 301 => "Moved Permanently"
        case 302 => "Found"
        case 303 => "See Other"
        case 304 => "Not Modified"
        case 307 => "Temporary Redirect"
        case 308 => "Permanent Redirect"
        case 400 => "Bad Request"
        case 401 => "Unauthorized"
        case 403 => "Forbidden"
        case 404 => "Not Found"
        case 405 => "Method Not Allowed"
        case 408 => "Request Timeout"
        case 409 => "Conflict"
        case 410 => "Gone"
        case 413 => "Payload Too Large"
        case 414 => "URI Too Long"
        case 415 => "Unsupported Media Type"
        case 422 => "Unprocessable Entity"
        case 429 => "Too Many Requests"
        case 431 => "Request Header Fields Too Large"
        case 500 => "Internal Server Error"
        case 501 => "Not Implemented"
        case 502 => "Bad Gateway"
        case 503 => "Service Unavailable"
        case 504 => "Gateway Timeout"
        case _ => "Unknown"
    }
}

public func mimeTypeFor(path: String): String {
    let ext = extensionOf(path)
    match (ext) {
        case "html" => "text/html; charset=utf-8"
        case "htm" => "text/html; charset=utf-8"
        case "css" => "text/css; charset=utf-8"
        case "js" => "application/javascript; charset=utf-8"
        case "mjs" => "application/javascript; charset=utf-8"
        case "json" => "application/json; charset=utf-8"
        case "xml" => "application/xml; charset=utf-8"
        case "txt" => "text/plain; charset=utf-8"
        case "md" => "text/markdown; charset=utf-8"
        case "png" => "image/png"
        case "jpg" => "image/jpeg"
        case "jpeg" => "image/jpeg"
        case "gif" => "image/gif"
        case "webp" => "image/webp"
        case "avif" => "image/avif"
        case "ico" => "image/x-icon"
        case "svg" => "image/svg+xml"
        case "woff" => "font/woff"
        case "woff2" => "font/woff2"
        case "ttf" => "font/ttf"
        case "otf" => "font/otf"
        case "mp4" => "video/mp4"
        case "webm" => "video/webm"
        case "mp3" => "audio/mpeg"
        case "pdf" => "application/pdf"
        case "zip" => "application/zip"
        case "webmanifest" => "application/manifest+json"
        case _ => "application/octet-stream"
    }
}

// ---------------------------------------------------------------------------
// Multipart
// ---------------------------------------------------------------------------

func multipartBoundary(contentType: String): String {
    let lower = contentType.toAsciiLower()
    let idx = findSub(lower, "boundary=")
    if (idx < 0) {
        return ""
    }
    var rest = contentType[idx + 9..contentType.size].trimAscii()
    let semi = findSub(rest, ";")
    if (semi >= 0) {
        rest = rest[0..semi].trimAscii()
    }
    if (rest.size >= 2 && rest[0] == 0x22 && rest[rest.size - 1] == 0x22) {
        rest = rest[1..rest.size - 1]
    }
    if (rest.size == 0 || rest.size > 200) {
        return ""
    }
    rest
}

func parseMultipart(request: HttpRequest, boundary: String): Unit {
    let delimiter = ("--" + boundary).toArray()
    let parts = splitBytes(request.body, delimiter)
    if (parts.size <= 1) {
        throw AppError("validation", "multipart 数据损坏")
    }
    var partCount = 0
    var index = 1
    while (index < parts.size) {
        var segment = parts[index]
        index += 1
        // The final boundary is "--\r\n".
        if (startsWithBytes(segment, "--".toArray())) {
            break
        }
        segment = stripLeadingCrlf(segment)
        if (segment.size == 0) {
            continue
        }
        partCount += 1
        if (partCount > 200) {
            throw AppError("validation", "multipart 分片过多")
        }
        let headerEnd = indexOfBytes(segment, "\r\n\r\n".toArray(), 0)
        if (headerEnd < 0) {
            continue
        }
        let headerText = String.fromUtf8(segment[0..headerEnd])
        var content = segment[headerEnd + 4..segment.size]
        if (endsWithBytes(content, "\r\n".toArray())) {
            content = content[0..content.size - 2]
        }
        let partHeaders = parsePartHeaders(headerText)
        let disposition = headerValue(partHeaders, "content-disposition", "")
        let props = parseDisposition(disposition)
        let fieldName = headerValue(props, "name", "")
        if (fieldName.size == 0) {
            continue
        }
        let filenameRaw = headerValue(props, "filename", "")
        if (filenameRaw.size > 0) {
            let safeName = sanitizeFilename(filenameRaw)
            let contentType = headerValue(partHeaders, "content-type", "application/octet-stream")
            request.files.add(UploadedFile(fieldName, safeName, contentType, content))
        } else {
            if (content.size > 1024 * 1024) {
                throw AppError("validation", "表单字段过大")
            }
            let value = try {
                String.fromUtf8(content)
            } catch (e: Exception) {
                ""
            }
            if (!request.form.contains(fieldName)) {
                request.form[fieldName] = ArrayList<String>()
            }
            request.form[fieldName].add(value)
        }
    }
}

func headerValue(map: HashMap<String, String>, key: String, def: String): String {
    match (map.get(key)) {
        case Some(value) => value
        case None => def
    }
}

func parsePartHeaders(text: String): HashMap<String, String> {    let out = HashMap<String, String>()
    for (line in text.split("\r\n")) {
        let colon = findSub(line, ":")
        if (colon <= 0) {
            continue
        }
        let name = line[0..colon].trimAscii().toAsciiLower()
        let value = line[colon + 1..line.size].trimAscii()
        if (name.size > 0) {
            out[name] = value
        }
    }
    out
}

func parseDisposition(text: String): HashMap<String, String> {
    let out = HashMap<String, String>()
    for (part in text.split(";")) {
        let item = part.trimAscii()
        let eq = findSub(item, "=")
        if (eq <= 0) {
            continue
        }
        let key = item[0..eq].trimAscii().toAsciiLower()
        var value = item[eq + 1..item.size].trimAscii()
        if (value.size >= 2 && value[0] == 0x22 && value[value.size - 1] == 0x22) {
            value = value[1..value.size - 1]
        }
        out[key] = value
    }
    out
}

func splitBytes(data: Array<UInt8>, delimiter: Array<UInt8>): ArrayList<Array<UInt8>> {
    let result = ArrayList<Array<UInt8>>()
    var start: Int64 = 0
    var index = indexOfBytes(data, delimiter, 0)
    while (index >= 0) {
        result.add(data[start..index])
        start = index + delimiter.size
        index = indexOfBytes(data, delimiter, start)
    }
    result.add(data[start..data.size])
    result
}

func indexOfBytes(data: Array<UInt8>, pattern: Array<UInt8>, from: Int64): Int64 {
    if (pattern.size == 0 || data.size < pattern.size) {
        return -1
    }
    var i = from
    while (i + pattern.size <= data.size) {
        var matched = true
        for (j in 0..pattern.size) {
            if (data[i + j] != pattern[j]) {
                matched = false
                break
            }
        }
        if (matched) {
            return i
        }
        i += 1
    }
    -1
}

func startsWithBytes(data: Array<UInt8>, prefix: Array<UInt8>): Bool {
    if (data.size < prefix.size) {
        return false
    }
    for (i in 0..prefix.size) {
        if (data[i] != prefix[i]) {
            return false
        }
    }
    true
}

func endsWithBytes(data: Array<UInt8>, suffix: Array<UInt8>): Bool {
    if (data.size < suffix.size) {
        return false
    }
    let offset = data.size - suffix.size
    for (i in 0..suffix.size) {
        if (data[offset + i] != suffix[i]) {
            return false
        }
    }
    true
}

func stripLeadingCrlf(data: Array<UInt8>): Array<UInt8> {
    var i = 0
    while (i + 1 < data.size && data[i] == 0x0D && data[i + 1] == 0x0A) {
        i += 2
    }
    data[i..data.size]
}
