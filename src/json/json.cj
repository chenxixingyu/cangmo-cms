/**
 * Cangmo - JSON (RFC 8259) parser and serializer.
 *
 * Implemented from the RFC. No third-party JSON library is used.
 */
package cangmo.json

import std.collection.*
import std.convert.*
import std.sort.*

public enum JsonValue {
    | JNull
    | JBool(Bool)
    | JInt(Int64)
    | JFloat(Float64)
    | JStr(String)
    | JArr(JsonArray)
    | JObj(JsonObject)
}

public class JsonArray {
    public let items: ArrayList<JsonValue>

    public init() {
        items = ArrayList<JsonValue>()
    }

    public init(items: ArrayList<JsonValue>) {
        this.items = items
    }

    public func add(value: JsonValue): JsonArray {
        items.add(value)
        return this
    }

    public func size(): Int64 {
        items.size
    }

    public func get(index: Int64): ?JsonValue {
        if (index < 0 || index >= items.size) {
            return None
        }
        return Some(items[index])
    }
}

public class JsonObject {
    public let fields: HashMap<String, JsonValue>

    public init() {
        fields = HashMap<String, JsonValue>()
    }

    public init(fields: HashMap<String, JsonValue>) {
        this.fields = fields
    }

    public func set(key: String, value: JsonValue): JsonObject {
        fields[key] = value
        return this
    }

    public func get(key: String): ?JsonValue {
        fields.get(key)
    }

    public func has(key: String): Bool {
        fields.contains(key)
    }

    public func remove(key: String): Unit {
        fields.remove(key)
    }

    public func size(): Int64 {
        fields.size
    }

    public func keys(): Array<String> {
        fields.keys().toArray()
    }
}

public func jnull(): JsonValue {
    JNull
}

public func jbool(v: Bool): JsonValue {
    JBool(v)
}

public func jint(v: Int64): JsonValue {
    JInt(v)
}

public func jfloat(v: Float64): JsonValue {
    JFloat(v)
}

public func jstr(v: String): JsonValue {
    JStr(v)
}

public func jarr(): JsonValue {
    JArr(JsonArray())
}

public func jobj(): JsonValue {
    JObj(JsonObject())
}

public func jsonArrayOf(items: Array<JsonValue>): JsonValue {
    let a = JsonArray()
    for (item in items) {
        a.add(item)
    }
    JArr(a)
}

public func jsonObjectOf(pairs: Array<(String, JsonValue)>): JsonValue {
    let o = JsonObject()
    for ((k, v) in pairs) {
        o.set(k, v)
    }
    JObj(o)
}

public func jsonStringList(items: Array<String>): JsonValue {
    let a = JsonArray()
    for (item in items) {
        a.add(JStr(item))
    }
    JArr(a)
}

public func jsonNumberList(items: Array<Int64>): JsonValue {
    let a = JsonArray()
    for (item in items) {
        a.add(JInt(item))
    }
    JArr(a)
}

// ---------------------------------------------------------------------------
// Access helpers
// ---------------------------------------------------------------------------

extend JsonValue {
    public func get(key: String): ?JsonValue {
        match (this) {
            case JObj(o) => o.fields.get(key)
            case _ => None
        }
    }

    public func at(index: Int64): ?JsonValue {
        match (this) {
            case JArr(a) => a.get(index)
            case _ => None
        }
    }

    public func asString(): ?String {
        match (this) {
            case JStr(s) => Some(s)
            case _ => None
        }
    }

    public func asInt(): ?Int64 {
        match (this) {
            case JInt(i) => Some(i)
            case JFloat(f) => Some(Int64(f))
            case _ => None
        }
    }

    public func asFloat(): ?Float64 {
        match (this) {
            case JFloat(f) => Some(f)
            case JInt(i) => Some(Float64(i))
            case _ => None
        }
    }

    public func asBool(): ?Bool {
        match (this) {
            case JBool(b) => Some(b)
            case _ => None
        }
    }

    public func asArray(): ?JsonArray {
        match (this) {
            case JArr(a) => Some(a)
            case _ => None
        }
    }

    public func asObject(): ?JsonObject {
        match (this) {
            case JObj(o) => Some(o)
            case _ => None
        }
    }

    public func isNullValue(): Bool {
        match (this) {
            case JNull => true
            case _ => false
        }
    }

    public func arraySize(): Int64 {
        match (this) {
            case JArr(a) => a.size()
            case _ => 0
        }
    }
}

public func getString(v: JsonValue, key: String, def!: String = ""): String {
    match (v.get(key)) {
        case Some(JStr(s)) => s
        case _ => def
    }
}

public func getInt(v: JsonValue, key: String, def!: Int64 = 0): Int64 {
    match (v.get(key)) {
        case Some(JInt(i)) => i
        case Some(JFloat(f)) => Int64(f)
        case _ => def
    }
}

public func getBool(v: JsonValue, key: String, def!: Bool = false): Bool {
    match (v.get(key)) {
        case Some(JBool(b)) => b
        case _ => def
    }
}

public func getObject(v: JsonValue, key: String): ?JsonObject {
    match (v.get(key)) {
        case Some(JObj(o)) => Some(o)
        case _ => None
    }
}

public func getArray(v: JsonValue, key: String): ?JsonArray {
    match (v.get(key)) {
        case Some(JArr(a)) => Some(a)
        case _ => None
    }
}

public func getStrings(v: JsonValue, key: String): Array<String> {
    let out = ArrayList<String>()
    if (let Some(JArr(a)) <- v.get(key)) {
        for (item in a.items) {
            if (let JStr(s) <- item) {
                out.add(s)
            }
        }
    }
    return out.toArray()
}

public func setField(v: JsonValue, key: String, value: JsonValue): Unit {
    if (let JObj(o) <- v) {
        o.set(key, value)
    }
}

public func removeField(v: JsonValue, key: String): Unit {
    if (let JObj(o) <- v) {
        o.remove(key)
    }
}

public func cloneJson(v: JsonValue): JsonValue {
    match (v) {
        case JArr(a) =>
            let out = JsonArray()
            for (item in a.items) {
                out.add(cloneJson(item))
            }
            JArr(out)
        case JObj(o) =>
            let out = JsonObject()
            for ((k, item) in o.fields) {
                out.set(k, cloneJson(item))
            }
            JObj(out)
        case JStr(s) => JStr(s)
        case JInt(i) => JInt(i)
        case JFloat(f) => JFloat(f)
        case JBool(b) => JBool(b)
        case JNull => JNull
    }
}

// ---------------------------------------------------------------------------
// Serializer
// ---------------------------------------------------------------------------

let JSON_HEX: Array<String> = ["0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "a", "b", "c", "d", "e", "f"]

func writeJsonString(s: String, sb: StringBuilder): Unit {
    sb.append("\"")
    let bytes = s.toArray()
    var i = 0
    var runStart = 0
    while (i < bytes.size) {
        let b = bytes[i]
        var esc = ""
        if (b == 0x22) {
            esc = "\\\""
        } else if (b == 0x5C) {
            esc = "\\\\"
        } else if (b == 0x0A) {
            esc = "\\n"
        } else if (b == 0x0D) {
            esc = "\\r"
        } else if (b == 0x09) {
            esc = "\\t"
        } else if (b == 0x08) {
            esc = "\\b"
        } else if (b == 0x0C) {
            esc = "\\f"
        } else if (b == 0x3C) {
            esc = "\\u003c"
        } else if (b == 0x3E) {
            esc = "\\u003e"
        } else if (b == 0x26) {
            esc = "\\u0026"
        } else if (b < 0x20) {
            esc = "\\u00" + JSON_HEX[Int64(b) >> 4] + JSON_HEX[Int64(b) & 0x0F]
        }
        if (esc.size > 0) {
            if (i > runStart) {
                sb.append(String.fromUtf8(bytes[runStart..i]))
            }
            sb.append(esc)
            i += 1
            runStart = i
        } else {
            i += 1
        }
    }
    if (bytes.size > runStart) {
        sb.append(String.fromUtf8(bytes[runStart..bytes.size]))
    }
    sb.append("\"")
}

func writeIndent(sb: StringBuilder, level: Int64): Unit {
    for (i in 0..level) {
        sb.append("  ")
    }
}

func jsonFloatText(f: Float64): String {
    let s = f.toString()
    let lower = s.toAsciiLower()
    if (lower.contains("nan") || lower.contains("inf")) {
        return "null"
    }
    if (f >= -9223372036854775808.0 && f <= 9223372036854775807.0) {
        let i = Int64(f)
        if (Float64(i) == f) {
            return i.toString()
        }
    }
    return s
}

func writeJsonValue(v: JsonValue, sb: StringBuilder, pretty: Bool, level: Int64): Unit {
    match (v) {
        case JNull => sb.append("null")
        case JBool(b) =>
            let text = if (b) { "true" } else { "false" }
            sb.append(text)
        case JInt(i) => sb.append(i.toString())
        case JFloat(f) => sb.append(jsonFloatText(f))
        case JStr(s) => writeJsonString(s, sb)
        case JArr(a) =>
            if (a.size() == 0) {
                sb.append("[]")
            } else {
                sb.append("[")
                for (i in 0..a.items.size) {
                    if (i > 0) {
                        sb.append(",")
                    }
                    if (pretty) {
                        sb.append("\n")
                        writeIndent(sb, level + 1)
                    }
                    writeJsonValue(a.items[i], sb, pretty, level + 1)
                }
                if (pretty) {
                    sb.append("\n")
                    writeIndent(sb, level)
                }
                sb.append("]")
            }
        case JObj(o) =>
            if (o.size() == 0) {
                sb.append("{}")
            } else {
                sb.append("{")
                let keys = o.keys()
                sort<String>(keys)
                var first = true
                for (key in keys) {
                    if (!first) {
                        sb.append(",")
                    }
                    first = false
                    if (pretty) {
                        sb.append("\n")
                        writeIndent(sb, level + 1)
                    }
                    writeJsonString(key, sb)
                    if (pretty) {
                        sb.append(": ")
                    } else {
                        sb.append(":")
                    }
                    writeJsonValue(o.fields[key], sb, pretty, level + 1)
                }
                if (pretty) {
                    sb.append("\n")
                    writeIndent(sb, level)
                }
                sb.append("}")
            }
    }
}

public func toJson(value: JsonValue, pretty!: Bool = false): String {
    let sb = StringBuilder()
    writeJsonValue(value, sb, pretty, 0)
    return sb.toString()
}

public func toJsonCompact(value: JsonValue): String {
    toJson(value, pretty: false)
}

// ---------------------------------------------------------------------------
// Parser
// ---------------------------------------------------------------------------

public class JsonParseError <: Exception {
    public init(message: String) {
        super(message)
    }
}

class JsonParser {
    private let data: Array<UInt8>
    private var pos: Int64
    private let maxDepth: Int64

    init(text: String) {
        data = text.toArray()
        pos = 0
        maxDepth = 128
    }

    func parse(): JsonValue {
        skipWhitespace()
        let value = parseValue(0)
        skipWhitespace()
        if (pos != data.size) {
            fail("unexpected trailing content")
        }
        return value
    }

    private func fail(message: String): Nothing {
        throw JsonParseError("${message} at byte ${pos}")
    }

    private func skipWhitespace(): Unit {
        while (pos < data.size) {
            let b = data[pos]
            if (b == 0x20 || b == 0x09 || b == 0x0A || b == 0x0D) {
                pos += 1
            } else {
                break
            }
        }
    }

    private func parseValue(depth: Int64): JsonValue {
        if (depth > maxDepth) {
            fail("maximum nesting depth exceeded")
        }
        if (pos >= data.size) {
            fail("unexpected end of input")
        }
        let b = data[pos]
        if (b == 0x7B) {
            return parseObject(depth)
        }
        if (b == 0x5B) {
            return parseArray(depth)
        }
        if (b == 0x22) {
            return JStr(parseString())
        }
        if (b == 0x74) {
            expectKeyword("true")
            return JBool(true)
        }
        if (b == 0x66) {
            expectKeyword("false")
            return JBool(false)
        }
        if (b == 0x6E) {
            expectKeyword("null")
            return JNull
        }
        if (b == 0x2D || (b >= 0x30 && b <= 0x39)) {
            return parseNumber()
        }
        fail("unexpected character")
    }

    private func parseObject(depth: Int64): JsonValue {
        pos += 1
        let obj = JsonObject()
        skipWhitespace()
        if (pos < data.size && data[pos] == 0x7D) {
            pos += 1
            return JObj(obj)
        }
        while (true) {
            skipWhitespace()
            if (pos >= data.size || data[pos] != 0x22) {
                fail("object key must be a string")
            }
            let key = parseString()
            skipWhitespace()
            if (pos >= data.size || data[pos] != 0x3A) {
                fail("expected ':' after object key")
            }
            pos += 1
            skipWhitespace()
            let value = parseValue(depth + 1)
            obj.set(key, value)
            skipWhitespace()
            if (pos >= data.size) {
                fail("unterminated object")
            }
            let sep = data[pos]
            if (sep == 0x2C) {
                pos += 1
                continue
            }
            if (sep == 0x7D) {
                pos += 1
                return JObj(obj)
            }
            fail("expected ',' or '}' in object")
        }
        return JObj(obj)
    }

    private func parseArray(depth: Int64): JsonValue {
        pos += 1
        let arr = JsonArray()
        skipWhitespace()
        if (pos < data.size && data[pos] == 0x5D) {
            pos += 1
            return JArr(arr)
        }
        while (true) {
            skipWhitespace()
            arr.add(parseValue(depth + 1))
            skipWhitespace()
            if (pos >= data.size) {
                fail("unterminated array")
            }
            let sep = data[pos]
            if (sep == 0x2C) {
                pos += 1
                continue
            }
            if (sep == 0x5D) {
                pos += 1
                return JArr(arr)
            }
            fail("expected ',' or ']' in array")
        }
        return JArr(arr)
    }

    private func parseString(): String {
        pos += 1
        let sb = StringBuilder()
        var runStart = pos
        while (true) {
            if (pos >= data.size) {
                fail("unterminated string")
            }
            let b = data[pos]
            if (b == 0x22) {
                if (pos > runStart) {
                    appendUtf8(sb, runStart, pos)
                }
                pos += 1
                return sb.toString()
            }
            if (b == 0x5C) {
                if (pos > runStart) {
                    appendUtf8(sb, runStart, pos)
                }
                pos += 1
                if (pos >= data.size) {
                    fail("unterminated escape")
                }
                let e = data[pos]
                pos += 1
                if (e == 0x22) {
                    sb.append("\"")
                } else if (e == 0x5C) {
                    sb.append("\\")
                } else if (e == 0x2F) {
                    sb.append("/")
                } else if (e == 0x62) {
                    sb.append("\b")
                } else if (e == 0x66) {
                    sb.append("\f")
                } else if (e == 0x6E) {
                    sb.append("\n")
                } else if (e == 0x72) {
                    sb.append("\r")
                } else if (e == 0x74) {
                    sb.append("\t")
                } else if (e == 0x75) {
                    var cp = parseHex4()
                    if (cp >= 0xD800 && cp <= 0xDBFF) {
                        if (pos + 6 <= data.size && data[pos] == 0x5C && data[pos + 1] == 0x75) {
                            let save = pos
                            pos += 2
                            let low = parseHex4()
                            if (low >= 0xDC00 && low <= 0xDFFF) {
                                cp = 0x10000 + ((cp - 0xD800) << 10) + (low - 0xDC00)
                            } else {
                                pos = save
                            }
                        }
                    }
                    if (cp >= 0xD800 && cp <= 0xDFFF) {
                        cp = 0xFFFD
                    }
                    sb.append(Rune(cp))
                } else {
                    fail("invalid escape sequence")
                }
                runStart = pos
            } else if (b < 0x20) {
                fail("unescaped control character in string")
            } else {
                pos += 1
            }
        }
        return ""
    }

    private func appendUtf8(sb: StringBuilder, start: Int64, end: Int64): Unit {
        try {
            sb.append(String.fromUtf8(data[start..end]))
        } catch (e: Exception) {
            fail("invalid UTF-8 in string")
        }
    }

    private func parseHex4(): Int64 {
        if (pos + 4 > data.size) {
            fail("truncated \\u escape")
        }
        var value: Int64 = 0
        for (i in 0..4) {
            let v = hexValue(data[pos + i])
            if (v < 0) {
                fail("invalid hex digit in \\u escape")
            }
            value = value * 16 + v
        }
        pos += 4
        return value
    }

    private func hexValue(b: UInt8): Int64 {
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

    private func parseNumber(): JsonValue {
        let start = pos
        if (data[pos] == 0x2D) {
            pos += 1
        }
        if (pos >= data.size || data[pos] < 0x30 || data[pos] > 0x39) {
            fail("invalid number")
        }
        while (pos < data.size && data[pos] >= 0x30 && data[pos] <= 0x39) {
            pos += 1
        }
        var isFloat = false
        if (pos < data.size && data[pos] == 0x2E) {
            isFloat = true
            pos += 1
            if (pos >= data.size || data[pos] < 0x30 || data[pos] > 0x39) {
                fail("invalid fraction")
            }
            while (pos < data.size && data[pos] >= 0x30 && data[pos] <= 0x39) {
                pos += 1
            }
        }
        if (pos < data.size && (data[pos] == 0x65 || data[pos] == 0x45)) {
            isFloat = true
            pos += 1
            if (pos < data.size && (data[pos] == 0x2B || data[pos] == 0x2D)) {
                pos += 1
            }
            if (pos >= data.size || data[pos] < 0x30 || data[pos] > 0x39) {
                fail("invalid exponent")
            }
            while (pos < data.size && data[pos] >= 0x30 && data[pos] <= 0x39) {
                pos += 1
            }
        }
        let text = String.fromUtf8(data[start..pos])
        if (!isFloat) {
            try {
                return JInt(Int64.parse(text))
            } catch (e: Exception) {
                try {
                    return JFloat(Float64.parse(text))
                } catch (e2: Exception) {
                    fail("number out of range")
                }
            }
        }
        try {
            return JFloat(Float64.parse(text))
        } catch (e: Exception) {
            fail("invalid number")
        }
    }

    private func expectKeyword(word: String): Unit {
        let bytes = word.toArray()
        if (pos + bytes.size > data.size) {
            fail("unexpected end of input")
        }
        for (i in 0..bytes.size) {
            if (data[pos + i] != bytes[i]) {
                fail("invalid literal")
            }
        }
        pos += bytes.size
    }
}

public func parseJson(text: String): JsonValue {
    JsonParser(text).parse()
}

public func tryParseJson(text: String): ?JsonValue {
    try {
        return Some(parseJson(text))
    } catch (e: Exception) {
        return None
    }
}

public func parseJsonObject(text: String): JsonObject {
    match (parseJson(text)) {
        case JObj(o) => o
        case _ => throw JsonParseError("expected a JSON object")
    }
}
