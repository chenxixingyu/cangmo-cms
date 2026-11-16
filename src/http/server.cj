/**
 * Cangmo - HTTP/1.1 server.
 *
 * A small, defensive HTTP/1.1 implementation over std.net:
 *   - bounded header/body sizes, read and keep-alive timeouts
 *   - only HTTP/1.0 and HTTP/1.1, strict request-line/header validation
 *   - Content-Length and chunked request bodies
 *   - keep-alive, HEAD support, graceful 4xx/5xx responses
 *   - one OS thread per connection, capped by maxConnections
 */
package cangmo.http

import cangmo.core.*
import std.net.*
import std.collection.*
import std.sync.*
import std.time.*
import std.convert.*

class Counter {
    private let mutex: Mutex = Mutex()
    private var value: Int64 = 0

    func inc(): Int64 {
        synchronized(mutex) {
            value += 1
            value
        }
    }

    func dec(): Unit {
        synchronized(mutex) {
            if (value > 0) {
                value -= 1
            }
        }
    }

    func get(): Int64 {
        synchronized(mutex) {
            value
        }
    }
}

class ByteQueue {
    private var buf: Array<UInt8>
    private var start: Int64
    private var end: Int64

    init() {
        buf = Array<UInt8>(8192, repeat: 0)
        start = 0
        end = 0
    }

    func available(): Int64 {
        end - start
    }

    private func compact(): Unit {
        if (start == 0) {
            return
        }
        let count = end - start
        for (i in 0..count) {
            buf[i] = buf[start + i]
        }
        start = 0
        end = count
    }

    private func ensure(extra: Int64): Unit {
        let need = available() + extra
        if (need <= buf.size) {
            if (end + extra > buf.size) {
                compact()
            }
            return
        }
        var size = buf.size
        while (size < need) {
            size = size * 2
        }
        let next = Array<UInt8>(size, repeat: 0)
        let count = available()
        for (i in 0..count) {
            next[i] = buf[start + i]
        }
        buf = next
        start = 0
        end = count
    }

    func append(data: Array<UInt8>): Unit {
        if (data.size == 0) {
            return
        }
        ensure(data.size)
        for (i in 0..data.size) {
            buf[end + i] = data[i]
        }
        end += data.size
    }

    func indexOf(pattern: Array<UInt8>, from: Int64): Int64 {
        if (pattern.size == 0 || available() < pattern.size) {
            return -1
        }
        var i = start + from
        while (i + pattern.size <= end) {
            var matched = true
            for (j in 0..pattern.size) {
                if (buf[i + j] != pattern[j]) {
                    matched = false
                    break
                }
            }
            if (matched) {
                return i - start
            }
            i += 1
        }
        -1
    }

    func consume(count: Int64): Array<UInt8> {
        if (count <= 0) {
            return Array<UInt8>(0, repeat: 0)
        }
        let out = Array<UInt8>(count, repeat: 0)
        for (i in 0..count) {
            out[i] = buf[start + i]
        }
        start += count
        if (start >= end) {
            start = 0
            end = 0
        }
        return out
    }

    func peek(index: Int64): UInt8 {
        buf[start + index]
    }
}

class SocketReader {
    private let sock: TcpSocket
    private let queue: ByteQueue = ByteQueue()
    private let chunk: Array<UInt8> = Array<UInt8>(16384, repeat: 0)
    private var eof: Bool = false

    init(sock: TcpSocket) {
        this.sock = sock
    }

    private func readMore(): Bool {
        if (eof) {
            return false
        }
        let n = sock.read(chunk)
        if (n <= 0) {
            eof = true
            return false
        }
        queue.append(chunk[0..n])
        return true
    }

    func readHeaderBlock(maxBytes: Int64): ?Array<UInt8> {
        let pattern = "\r\n\r\n".toArray()
        while (true) {
            let index = queue.indexOf(pattern, 0)
            if (index >= 0) {
                if (index + 4 > maxBytes) {
                    throw AppError("request", "请求头过大")
                }
                let head = queue.consume(index + 4)
                return Some(head[0..index])
            }
            if (queue.available() > maxBytes) {
                throw AppError("request", "请求头过大")
            }
            if (!readMore()) {
                return None
            }
        }
        return None
    }

    func readExact(count: Int64): ?Array<UInt8> {
        if (count == 0) {
            return Some(Array<UInt8>(0, repeat: 0))
        }
        while (queue.available() < count) {
            if (!readMore()) {
                return None
            }
        }
        Some(queue.consume(count))
    }

    func readLine(maxBytes: Int64): ?String {
        while (true) {
            let index = queue.indexOf("\n".toArray(), 0)
            if (index >= 0) {
                let raw = queue.consume(index + 1)
                var line = raw[0..raw.size - 1]
                if (line.size > 0 && line[line.size - 1] == 0x0D) {
                    line = line[0..line.size - 1]
                }
                return Some(String.fromUtf8(line))
            }
            if (queue.available() > maxBytes) {
                throw AppError("request", "行长度超限")
            }
            if (!readMore()) {
                return None
            }
        }
        return None
    }
}

class ParsedHead {
    let method: String
    let path: String
    let rawQuery: String
    let version: String
    let headers: HttpHeaders
    let keepAlive: Bool

    init(method: String, path: String, rawQuery: String, version: String, headers: HttpHeaders, keepAlive: Bool) {
        this.method = method
        this.path = path
        this.rawQuery = rawQuery
        this.version = version
        this.headers = headers
        this.keepAlive = keepAlive
    }
}

public class HttpServer {
    private let config: Config
    private let handler: HttpHandler
    private let logger: Logger
    private var server: ?TcpServerSocket = None
    private var running: Bool = false
    private let active: Counter = Counter()

    public init(config: Config, handler: HttpHandler, logger: Logger) {
        this.config = config
        this.handler = handler
        this.logger = logger
    }

    public func start(): Unit {
        let address = IPSocketAddress(config.host, UInt16(config.port))
        let socket = TcpServerSocket(bindAt: address)
        socket.bind()
        server = Some(socket)
        running = true
        logger.info("server", "Cangmo ${APP_VERSION} listening on http://${config.host}:${config.port}")
        while (running) {
            let client = try {
                socket.accept()
            } catch (e: Exception) {
                if (running) {
                    logger.warn("server", "accept failed: ${e.message}")
                    continue
                }
                break
            }
            if (active.get() >= config.maxConnections) {
                try {
                    client.close()
                } catch (e: Exception) {}
                continue
            }
            active.inc()
            spawn {
                handleConnection(client)
            }
        }
        try {
            socket.close()
        } catch (e: Exception) {}
    }

    public func stop(): Unit {
        running = false
        match (server) {
            case Some(socket) =>
                try {
                    socket.close()
                } catch (e: Exception) {}
            case None => ()
        }
    }

    public func connectionCount(): Int64 {
        active.get()
    }

    private func handleConnection(client: TcpSocket): Unit {
        var remoteIp = ""
        var remotePort: Int64 = 0
        match (client.remoteAddress) {
            case address: IPSocketAddress =>
                remoteIp = address.address.toString()
                remotePort = Int64(address.port)
            case _ => ()
        }
        try {
            client.readTimeout = Duration.millisecond * config.readTimeoutMs
            client.writeTimeout = Duration.millisecond * config.readTimeoutMs
            try {
                client.noDelay = true
            } catch (e: Exception) {}
            let reader = SocketReader(client)
            var requests: Int64 = 0
            while (requests < 100) {
                let headBytes = try {
                    reader.readHeaderBlock(config.maxHeaderBytes)
                } catch (e: AppError) {
                    sendPlain(client, requestErrorStatus(e.kind), e.message)
                    break
                } catch (e: Exception) {
                    break
                }
                if (headBytes.isNone()) {
                    break
                }
                var headData = Array<UInt8>(0, repeat: 0)
                match (headBytes) {
                    case Some(bytes) => headData = bytes
                    case None => break
                }
                let head = try {
                    parseHead(headData)
                } catch (e: AppError) {
                    sendPlain(client, requestErrorStatus(e.kind), e.message)
                    break
                }
                if (!hostAllowed(head.headers.get("host"))) {
                    sendPlain(client, 400, "无效的 Host 请求头")
                    break
                }
                let expect = head.headers.get("expect").toAsciiLower()
                if (expect.contains("100-continue")) {
                    writeAll(client, "HTTP/1.1 100 Continue\r\n\r\n".toArray())
                }
                let body = try {
                    readBody(reader, head)
                } catch (e: AppError) {
                    sendPlain(client, requestErrorStatus(e.kind), e.message)
                    break
                }
                let request = HttpRequest(head.method, head.path, head.rawQuery, head.version)
                request.headers = head.headers
                request.body = body
                request.remoteIp = effectiveIp(head.headers, remoteIp)
                request.remotePort = remotePort
                request.scheme = effectiveScheme(head.headers)
                request.host = head.headers.get("host")
                request.parseCookies()
                let started = MonoTime.now()
                var response = HttpResponse()
                try {
                    response = handler(request)
                } catch (e: AppError) {
                    response = describeError(e.kind, e.message)
                } catch (e: Exception) {
                    logger.error("http", "unhandled error on ${head.method} ${head.path}: ${e.message}")
                    response = HttpResponse().text("服务器内部错误", status: 500)
                }
                let elapsed = (MonoTime.now() - started).toMilliseconds()
                if (response.status >= 500) {
                    logger.error("http", "${head.method} ${head.path} -> ${response.status} (${elapsed}ms)")
                }
                logger.requestLog(head.method, head.path, response.status, elapsed, request.remoteIp)
                var keepAlive = head.keepAlive
                if (response.closeConnection) {
                    keepAlive = false
                }
                let written = try {
                    sendResponse(client, head, response, keepAlive)
                } catch (e: Exception) {
                    false
                }
                requests += 1
                if (!written || !keepAlive) {
                    break
                }
            }
        } catch (e: Exception) {
            logger.debug("http", "connection from ${remoteIp} closed: ${e.message}")
        }
        try {
            client.close()
        } catch (e: Exception) {}
        active.dec()
    }

    private func effectiveIp(headers: HttpHeaders, remoteIp: String): String {
        if (!config.trustProxy) {
            return remoteIp
        }
        let forwarded = headers.get("x-forwarded-for")
        if (forwarded.size == 0) {
            return remoteIp
        }
        let first = forwarded.split(",")[0].trimAscii()
        if (isReasonableIp(first)) {
            return first
        }
        remoteIp
    }

    private func effectiveScheme(headers: HttpHeaders): String {
        if (config.trustProxy) {
            let proto = headers.get("x-forwarded-proto").toAsciiLower().trimAscii()
            if (proto == "https") {
                return "https"
            }
        }
        if (config.cookieSecure) {
            return "https"
        }
        "http"
    }

    private func hostAllowed(host: String): Bool {
        if (config.allowedHosts.size == 0) {
            return true
        }
        let hostOnly = host.split(":")[0].toAsciiLower().trimAscii()
        for (allowed in config.allowedHosts) {
            if (allowed.toAsciiLower() == hostOnly) {
                return true
            }
        }
        false
    }

    private func readBody(reader: SocketReader, head: ParsedHead): Array<UInt8> {
        if (head.headers.getAll("content-length").size > 1 || head.headers.getAll("transfer-encoding").size > 1) {
            throw AppError("request", "重复的 Content-Length 或 Transfer-Encoding")
        }
        let transferEncoding = head.headers.get("transfer-encoding").toAsciiLower()
        let contentLengthText = head.headers.get("content-length")
        if (transferEncoding.size > 0 && contentLengthText.size > 0) {
            throw AppError("request", "同时存在 Content-Length 与 Transfer-Encoding")
        }
        if (transferEncoding.size > 0) {
            if (!transferEncoding.contains("chunked")) {
                throw AppError("request", "不支持的 Transfer-Encoding")
            }
            return readChunked(reader, config.maxBodyBytes)
        }
        if (contentLengthText.size == 0) {
            return Array<UInt8>(0, repeat: 0)
        }
        let length = try {
            Int64.parse(contentLengthText.trimAscii())
        } catch (e: Exception) {
            throw AppError("request", "无效的 Content-Length")
        }
        if (length < 0 || length > config.maxBodyBytes) {
            throw AppError("payload", "请求体过大")
        }
        if (length == 0) {
            return Array<UInt8>(0, repeat: 0)
        }
        match (reader.readExact(length)) {
            case Some(bytes) => bytes
            case None => throw AppError("request", "请求体不完整")
        }
    }

    private func readChunked(reader: SocketReader, maxBytes: Int64): Array<UInt8> {
        let out = ArrayList<UInt8>()
        while (true) {
            let line = match (reader.readLine(1024)) {
                case Some(value) => value
                case None => throw AppError("request", "分块编码不完整")
            }
            let semi = findSub(line, ";")
            let sizeText = (if (semi >= 0) { line[0..semi] } else { line }).trimAscii()
            let size = parseHex(sizeText)
            if (size < 0) {
                throw AppError("request", "无效的分块长度")
            }
            if (size == 0) {
                while (true) {
                    let trailer = match (reader.readLine(2048)) {
                        case Some(value) => value
                        case None => ""
                    }
                    if (trailer.size == 0) {
                        break
                    }
                }
                break
            }
            if (out.size + size > maxBytes) {
                throw AppError("payload", "请求体过大")
            }
            let chunk = match (reader.readExact(size)) {
                case Some(value) => value
                case None => throw AppError("request", "分块编码不完整")
            }
            for (b in chunk) {
                out.add(b)
            }
            let terminator = match (reader.readExact(2)) {
                case Some(value) => value
                case None => throw AppError("request", "分块编码不完整")
            }
            if (terminator.size != 2 || terminator[0] != 0x0D || terminator[1] != 0x0A) {
                throw AppError("request", "分块编码格式错误")
            }
        }
        out.toArray()
    }

    private func sendResponse(client: TcpSocket, head: ParsedHead, response: HttpResponse, keepAlive: Bool): Bool {
        let sb = StringBuilder()
        sb.append("HTTP/1.1 ")
        sb.append(response.status.toString())
        sb.append(" ")
        sb.append(statusText(response.status))
        sb.append("\r\n")
        sb.append("Date: ")
        sb.append(formatUtcRfc1123(nowSeconds()))
        sb.append("\r\n")
        sb.append("Server: Cangmo/")
        sb.append(APP_VERSION)
        sb.append("\r\n")
        for ((name, value) in response.headers.entries()) {
            if (name == "connection" || name == "transfer-encoding" || name == "content-length" ||
                name == "date" || name == "server") {
                continue
            }
            sb.append(name)
            sb.append(": ")
            sb.append(value)
            sb.append("\r\n")
        }
        let noBodyStatus = response.status == 204 || response.status == 304
        if (!noBodyStatus) {
            sb.append("Content-Length: ")
            sb.append(response.body.size.toString())
            sb.append("\r\n")
        }
        for (cookie in response.cookies) {
            sb.append("Set-Cookie: ")
            sb.append(serializeCookie(cookie, nowSeconds()))
            sb.append("\r\n")
        }
        sb.append("Connection: ")
        sb.append(if (keepAlive) { "keep-alive" } else { "close" })
        sb.append("\r\n\r\n")
        writeAll(client, sb.toString().toArray())
        if (head.method != "HEAD" && !noBodyStatus && response.body.size > 0) {
            writeAll(client, response.body)
        }
        return true
    }
}

func parseHead(raw: Array<UInt8>): ParsedHead {
    let text = try {
        String.fromUtf8(raw)
    } catch (e: Exception) {
        throw AppError("request", "请求头编码无效")
    }
    let lines = text.split("\r\n")
    if (lines.size == 0) {
        throw AppError("request", "空请求")
    }
    let requestLine = lines[0]
    let parts = requestLine.split(" ")
    if (parts.size != 3) {
        throw AppError("request", "无效的请求行")
    }
    let method = parts[0].toAsciiUpper()
    let allowed = ["GET", "HEAD", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"]
    var methodOk = false
    for (item in allowed) {
        if (item == method) {
            methodOk = true
        }
    }
    if (!methodOk) {
        throw AppError("request", "不支持的请求方法")
    }
    let target = parts[1]
    if (!target.startsWith("/") || target.size > 8192) {
        throw AppError("request", "无效的请求目标")
    }
    let version = parts[2].toAsciiUpper()
    if (version != "HTTP/1.1" && version != "HTTP/1.0") {
        throw AppError("request", "不支持的 HTTP 版本")
    }
    let question = findSub(target, "?")
    let rawPath = if (question >= 0) { target[0..question] } else { target }
    let rawQuery = if (question >= 0) { target[question + 1..target.size] } else { "" }
    let path = normalizePath(rawPath)
    let headers = HttpHeaders()
    var headerCount = 0
    for (i in 1..lines.size) {
        let line = lines[i]
        if (line.size == 0) {
            continue
        }
        if (line[0] == 0x20 || line[0] == 0x09) {
            throw AppError("request", "不支持折行的请求头")
        }
        let colon = findSub(line, ":")
        if (colon <= 0) {
            throw AppError("request", "无效的请求头")
        }
        headerCount += 1
        if (headerCount > 100) {
            throw AppError("request", "请求头过多")
        }
        let name = line[0..colon].trimAscii()
        let value = line[colon + 1..line.size].trimAscii()
        headers.add(name, value)
    }
    if (version == "HTTP/1.1" && headers.get("host").size == 0) {
        throw AppError("request", "HTTP/1.1 请求缺少 Host")
    }
    let connection = headers.get("connection").toAsciiLower()
    var keepAlive = version == "HTTP/1.1"
    if (connection.contains("close")) {
        keepAlive = false
    }
    if (version == "HTTP/1.0" && !connection.contains("keep-alive")) {
        keepAlive = false
    }
    ParsedHead(method, path, rawQuery, version, headers, keepAlive)
}

/**
 * Decode each path segment, reject encoded slashes/backslashes, dot segments
 * and control characters. This is the single place where path traversal is
 * neutralised before routing.
 */
func normalizePath(rawPath: String): String {
    let segments = rawPath.split("/")
    let out = ArrayList<String>()
    for (segment in segments) {
        if (segment.size == 0) {
            continue
        }
        let decoded = match (tryUrlDecode(segment, plusAsSpace: false)) {
            case Some(value) => value
            case None => throw AppError("request", "路径编码无效")
        }
        if (decoded == ".") {
            continue
        }
        if (decoded == "..") {
            throw AppError("request", "非法路径")
        }
        if (decoded.contains("/") || decoded.contains("\\") || decoded.contains("\u{0}")) {
            throw AppError("request", "非法路径")
        }
        if (decoded.size > 512) {
            throw AppError("request", "路径过长")
        }
        out.add(decoded)
    }
    if (out.size == 0) {
        return "/"
    }
    return "/" + String.join(out.toArray(), delimiter: "/")
}

func parseHex(text: String): Int64 {
    if (text.size == 0 || text.size > 16) {
        return -1
    }
    var value: Int64 = 0
    for (b in text.toArray()) {
        var digit: Int64 = -1
        if (b >= 0x30 && b <= 0x39) {
            digit = Int64(b - 0x30)
        } else if (b >= 0x61 && b <= 0x66) {
            digit = Int64(b - 0x61 + 10)
        } else if (b >= 0x41 && b <= 0x46) {
            digit = Int64(b - 0x41 + 10)
        }
        if (digit < 0) {
            return -1
        }
        value = value * 16 + digit
        if (value < 0) {
            return -1
        }
    }
    value
}

func isReasonableIp(value: String): Bool {
    if (value.size == 0 || value.size > 64) {
        return false
    }
    for (b in value.toArray()) {
        let ok = (b >= 0x30 && b <= 0x39) || b == 0x2E || b == 0x3A || b == 0x5B || b == 0x5D ||
                 (b >= 0x61 && b <= 0x66) || (b >= 0x41 && b <= 0x46)
        if (!ok) {
            return false
        }
    }
    true
}

func writeAll(client: TcpSocket, data: Array<UInt8>): Unit {
    client.write(data)
}

func sendPlain(client: TcpSocket, status: Int64, message: String): Unit {
    let text = "<!doctype html><html><head><meta charset=\"utf-8\"><title>${status}</title></head>" +
               "<body style=\"font-family:system-ui;padding:3rem;max-width:40rem;margin:auto\">" +
               "<h1>${status} ${statusText(status)}</h1><p>${escapeHtml(message)}</p></body></html>"
    let body = text.toArray()
    let header = "HTTP/1.1 ${status} ${statusText(status)}\r\n" +
                 "Content-Type: text/html; charset=utf-8\r\n" +
                 "Content-Length: ${body.size}\r\n" +
                 "Connection: close\r\n" +
                 "X-Content-Type-Options: nosniff\r\n\r\n"
    try {
        writeAll(client, header.toArray())
        writeAll(client, body)
    } catch (e: Exception) {}
}

func describeError(kind: String, message: String): HttpResponse {
    let status = match (kind) {
        case "validation" => 400
        case "request" => 400
        case "unauthorized" => 401
        case "forbidden" => 403
        case "not_found" => 404
        case "method" => 405
        case "conflict" => 409
        case "payload" => 413
        case "rate_limited" => 429
        case _ => 500
    }
    HttpResponse().text(message, status: status)
}

func requestErrorStatus(kind: String): Int64 {
    match (kind) {
        case "payload" => 413
        case "rate_limited" => 429
        case "method" => 405
        case _ => 400
    }
}
