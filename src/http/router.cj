/**
 * Cangmo - HTTP router.
 *
 * Patterns: /posts/:slug, /media/:path, /admin/posts/:id/edit
 */
package cangmo.http

import std.collection.*

public type HttpHandler = (HttpRequest) -> HttpResponse

class Route {
    let method: String
    let pattern: String
    let segments: Array<String>
    let handler: HttpHandler

    init(method: String, pattern: String, segments: Array<String>, handler: HttpHandler) {
        this.method = method
        this.pattern = pattern
        this.segments = segments
        this.handler = handler
    }
}

public class RouteMatch {
    public let handler: HttpHandler
    public let params: HashMap<String, String>
    public let method: String

    public init(handler: HttpHandler, params: HashMap<String, String>, method: String) {
        this.handler = handler
        this.params = params
        this.method = method
    }
}

public class Router {
    private let routes: ArrayList<Route> = ArrayList<Route>()

    public init() {}

    public func get(pattern: String, handler: HttpHandler): Router {
        add("GET", pattern, handler)
    }

    public func post(pattern: String, handler: HttpHandler): Router {
        add("POST", pattern, handler)
    }

    public func put(pattern: String, handler: HttpHandler): Router {
        add("PUT", pattern, handler)
    }

    public func patch(pattern: String, handler: HttpHandler): Router {
        add("PATCH", pattern, handler)
    }

    public func delete(pattern: String, handler: HttpHandler): Router {
        add("DELETE", pattern, handler)
    }

    public func add(method: String, pattern: String, handler: HttpHandler): Router {
        let normalized = normalizeRoutePath(pattern)
        let segments = splitSegments(normalized)
        routes.add(Route(method.toAsciiUpper(), normalized, segments, handler))
        this
    }

    public func dispatch(method: String, path: String): ?RouteMatch {
        let normalized = normalizeRoutePath(path)
        let requestSegments = splitSegments(normalized)
        let upperMethod = method.toAsciiUpper()
        // HEAD falls back to GET.
        let first = tryMatch(upperMethod, requestSegments)
        match (first) {
            case Some(m) => return Some(m)
            case None => ()
        }
        if (upperMethod == "HEAD") {
            return tryMatch("GET", requestSegments)
        }
        None
    }

    private func tryMatch(method: String, segments: Array<String>): ?RouteMatch {
        for (route in routes) {
            if (route.method != method && route.method != "*") {
                continue
            }
            let params = HashMap<String, String>()
            if (matches(route.segments, segments, params)) {
                return Some(RouteMatch(route.handler, params, route.method))
            }
        }
        None
    }

    private func matches(pattern: Array<String>, actual: Array<String>, params: HashMap<String, String>): Bool {
        var pi = 0
        var ai = 0
        while (pi < pattern.size) {
            let seg = pattern[pi]
            if (seg.startsWith("*")) {
                let name = seg[1..seg.size]
                let rest = ArrayList<String>()
                while (ai < actual.size) {
                    rest.add(actual[ai])
                    ai += 1
                }
                if (name.size > 0) {
                    params[name] = String.join(rest.toArray(), delimiter: "/")
                }
                return true
            }
            if (ai >= actual.size) {
                return false
            }
            if (seg.startsWith(":")) {
                params[seg[1..seg.size]] = actual[ai]
            } else if (seg != actual[ai]) {
                return false
            }
            pi += 1
            ai += 1
        }
        ai == actual.size
    }

    public func allowedMethods(path: String): Array<String> {
        let normalized = normalizeRoutePath(path)
        let requestSegments = splitSegments(normalized)
        let methods = ArrayList<String>()
        for (route in routes) {
            let params = HashMap<String, String>()
            if (matches(route.segments, requestSegments, params)) {
                if (!methods.contains(route.method)) {
                    methods.add(route.method)
                }
            }
        }
        methods.toArray()
    }
}

public func normalizeRoutePath(path: String): String {
    var value = path.trimAscii()
    if (value.size == 0) {
        return "/"
    }
    if (!value.startsWith("/")) {
        value = "/" + value
    }
    while (value.size > 1 && value.endsWith("/")) {
        value = value[0..value.size - 1]
    }
    value
}

func splitSegments(path: String): Array<String> {
    let normalized = normalizeRoutePath(path)
    if (normalized == "/") {
        return Array<String>(0, repeat: "")
    }
    let raw = normalized[1..normalized.size].split("/")
    let out = ArrayList<String>()
    for (segment in raw) {
        if (segment.size > 0) {
            out.add(segment)
        }
    }
    out.toArray()
}
