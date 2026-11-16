/**
 * Cangmo - a small, safe, original template engine.
 *
 * Syntax:
 *   {{ value }}            HTML-escaped output
 *   {{{ value }}}          raw output (trusted HTML)
 *   {{ value|raw }}        raw output
 *   {% if expr %}...{% elif expr %}...{% else %}...{% endif %}
 *   {% for item in items %}...{% endfor %}
 *   {% include "partials/head.html" %}
 *   {# comment #}
 *
 * Expressions support dotted access, indexing, comparisons, boolean logic,
 * string/number literals and a small set of filters.
 */
package cangmo.template

import cangmo.core.*
import cangmo.json.*
import std.collection.*
import std.fs.*
import std.sync.*
import std.sort.*
import std.convert.*

// ---------------------------------------------------------------------------
// Expressions
// ---------------------------------------------------------------------------

interface Expr {
    func eval(ctx: RenderContext): JsonValue
}

class LiteralExpr <: Expr {
    let value: JsonValue
    init(value: JsonValue) {
        this.value = value
    }
    public func eval(ctx: RenderContext): JsonValue {
        value
    }
}

class VarExpr <: Expr {
    let name: String
    init(name: String) {
        this.name = name
    }
    public func eval(ctx: RenderContext): JsonValue {
        ctx.lookup(name)
    }
}

class FieldExpr <: Expr {
    let base: Expr
    let field: String
    init(base: Expr, field: String) {
        this.base = base
        this.field = field
    }
    public func eval(ctx: RenderContext): JsonValue {
        let value = base.eval(ctx)
        match (value) {
            case JArr(a) =>
                if (field == "length" || field == "size") {
                    return JInt(a.size())
                }
                return JNull
            case JObj(o) =>
                match (o.get(field)) {
                    case Some(v) => v
                    case None => JNull
                }
            case _ => JNull
        }
    }
}

class IndexExpr <: Expr {
    let base: Expr
    let index: Expr
    init(base: Expr, index: Expr) {
        this.base = base
        this.index = index
    }
    public func eval(ctx: RenderContext): JsonValue {
        let value = base.eval(ctx)
        let idx = index.eval(ctx)
        match (idx) {
            case JInt(i) =>
                match (value.at(i)) {
                    case Some(v) => v
                    case None => JNull
                }
            case JStr(key) =>
                match (value.get(key)) {
                    case Some(v) => v
                    case None => JNull
                }
            case _ => JNull
        }
    }
}

class UnaryExpr <: Expr {
    let op: String
    let operand: Expr
    init(op: String, operand: Expr) {
        this.op = op
        this.operand = operand
    }
    public func eval(ctx: RenderContext): JsonValue {
        let value = operand.eval(ctx)
        if (op == "not") {
            return JBool(!jsonTruthy(value))
        }
        if (op == "-") {
            match (value) {
                case JInt(i) => JInt(-i)
                case JFloat(f) => JFloat(-f)
                case _ => JInt(0)
            }
        } else {
            JNull
        }
    }
}

class BinaryExpr <: Expr {
    let op: String
    let left: Expr
    let right: Expr
    init(op: String, left: Expr, right: Expr) {
        this.op = op
        this.left = left
        this.right = right
    }
    public func eval(ctx: RenderContext): JsonValue {
        let l = left.eval(ctx)
        if (op == "and") {
            if (jsonTruthy(l)) {
                return right.eval(ctx)
            }
            return l
        }
        if (op == "or") {
            if (jsonTruthy(l)) {
                return l
            }
            return right.eval(ctx)
        }
        let r = right.eval(ctx)
        if (op == "==") {
            return JBool(jsonEquals(l, r))
        }
        if (op == "!=") {
            return JBool(!jsonEquals(l, r))
        }
        if (op == ">") {
            return JBool(jsonCompare(l, r) > 0)
        }
        if (op == "<") {
            return JBool(jsonCompare(l, r) < 0)
        }
        if (op == ">=") {
            return JBool(jsonCompare(l, r) >= 0)
        }
        if (op == "<=") {
            return JBool(jsonCompare(l, r) <= 0)
        }
        if (op == "+") {
            match (l) {
                case JInt(li) =>
                    match (r) {
                        case JInt(ri) => return JInt(li + ri)
                        case JFloat(rf) => return JFloat(Float64(li) + rf)
                        case _ => ()
                    }
                case JFloat(lf) =>
                    match (r) {
                        case JFloat(rf) => return JFloat(lf + rf)
                        case JInt(ri) => return JFloat(lf + Float64(ri))
                        case _ => ()
                    }
                case _ => ()
            }
            return JStr(jsonText(l) + jsonText(r))
        }
        JNull
    }
}

class FilterExpr <: Expr {
    let base: Expr
    let name: String
    let args: ArrayList<Expr>
    init(base: Expr, name: String, args: ArrayList<Expr>) {
        this.base = base
        this.name = name
        this.args = args
    }
    public func eval(ctx: RenderContext): JsonValue {
        let value = base.eval(ctx)
        applyFilter(name, value, args, ctx)
    }
}

// ---------------------------------------------------------------------------
// Rendering context
// ---------------------------------------------------------------------------

public class RenderContext {
    private let engine: TemplateEngine
    private let scopes: ArrayList<HashMap<String, JsonValue>>
    var includeDepth: Int64

    init(engine: TemplateEngine, data: JsonValue) {
        this.engine = engine
        this.scopes = ArrayList<HashMap<String, JsonValue>>()
        this.includeDepth = 0
        let root = HashMap<String, JsonValue>()
        if (let JObj(o) <- data) {
            for ((k, v) in o.fields) {
                root[k] = v
            }
        }
        scopes.add(root)
    }

    func lookup(name: String): JsonValue {
        var i = scopes.size - 1
        while (i >= 0) {
            match (scopes[i].get(name)) {
                case Some(v) => return v
                case None => ()
            }
            i -= 1
        }
        JNull
    }

    func push(values: HashMap<String, JsonValue>): Unit {
        scopes.add(values)
    }

    func pop(): Unit {
        if (scopes.size > 1) {
            scopes.remove(at: scopes.size - 1)
        }
    }

    func engineRef(): TemplateEngine {
        engine
    }
}

// ---------------------------------------------------------------------------
// Nodes
// ---------------------------------------------------------------------------

interface Node {
    func render(ctx: RenderContext, out: StringBuilder): Unit
}

class TextNode <: Node {
    let text: String
    init(text: String) {
        this.text = text
    }
    public func render(ctx: RenderContext, out: StringBuilder): Unit {
        out.append(text)
    }
}

class OutputNode <: Node {
    let expr: Expr
    let raw: Bool
    init(expr: Expr, raw: Bool) {
        this.expr = expr
        this.raw = raw
    }
    public func render(ctx: RenderContext, out: StringBuilder): Unit {
        let value = expr.eval(ctx)
        let text = jsonText(value)
        if (raw) {
            out.append(text)
        } else {
            out.append(escapeHtml(text))
        }
    }
}

class IfBranch {
    let condition: Expr
    let body: ArrayList<Node>
    init(condition: Expr, body: ArrayList<Node>) {
        this.condition = condition
        this.body = body
    }
}

class IfNode <: Node {
    let branches: ArrayList<IfBranch>
    let elseBody: ArrayList<Node>
    init(branches: ArrayList<IfBranch>, elseBody: ArrayList<Node>) {
        this.branches = branches
        this.elseBody = elseBody
    }
    public func render(ctx: RenderContext, out: StringBuilder): Unit {
        for (branch in branches) {
            if (jsonTruthy(branch.condition.eval(ctx))) {
                renderNodes(branch.body, ctx, out)
                return
            }
        }
        renderNodes(elseBody, ctx, out)
    }
}

class ForNode <: Node {
    let varName: String
    let listExpr: Expr
    let body: ArrayList<Node>
    let elseBody: ArrayList<Node>
    init(varName: String, listExpr: Expr, body: ArrayList<Node>, elseBody: ArrayList<Node>) {
        this.varName = varName
        this.listExpr = listExpr
        this.body = body
        this.elseBody = elseBody
    }
    public func render(ctx: RenderContext, out: StringBuilder): Unit {
        let value = listExpr.eval(ctx)
        match (value) {
            case JArr(arr) =>
                if (arr.size() == 0) {
                    renderNodes(elseBody, ctx, out)
                    return
                }
                for (i in 0..arr.items.size) {
                    let scope = HashMap<String, JsonValue>()
                    scope[varName] = arr.items[i]
                    scope["loop"] = loopInfo(i, arr.items.size)
                    ctx.push(scope)
                    renderNodes(body, ctx, out)
                    ctx.pop()
                }
            case JObj(obj) =>
                let keys = obj.keys()
                sortStrings(keys)
                if (keys.size == 0) {
                    renderNodes(elseBody, ctx, out)
                    return
                }
                for (i in 0..keys.size) {
                    let scope = HashMap<String, JsonValue>()
                    scope[varName] = obj.fields[keys[i]]
                    let info = loopInfo(i, keys.size)
                    setField(info, "key", JStr(keys[i]))
                    scope["loop"] = info
                    ctx.push(scope)
                    renderNodes(body, ctx, out)
                    ctx.pop()
                }
            case _ =>
                renderNodes(elseBody, ctx, out)
        }
    }
}

class IncludeNode <: Node {
    let name: String
    init(name: String) {
        this.name = name
    }
    public func render(ctx: RenderContext, out: StringBuilder): Unit {
        if (ctx.includeDepth >= 24) {
            throw AppError("template", "include depth exceeded at ${name}")
        }
        ctx.includeDepth += 1
        ctx.engineRef().renderInto(name, ctx, out)
        ctx.includeDepth -= 1
    }
}

func loopInfo(index: Int64, length: Int64): JsonValue {
    let o = JsonObject()
    o.set("index", JInt(index + 1))
    o.set("index0", JInt(index))
    o.set("first", JBool(index == 0))
    o.set("last", JBool(index == length - 1))
    o.set("length", JInt(length))
    JObj(o)
}

func renderNodes(nodes: ArrayList<Node>, ctx: RenderContext, out: StringBuilder): Unit {
    for (node in nodes) {
        node.render(ctx, out)
    }
}

// ---------------------------------------------------------------------------
// Expression parsing
// ---------------------------------------------------------------------------

class ExprParser {
    private let text: String
    private let data: Array<UInt8>
    private var pos: Int64
    private let label: String

    init(text: String, label: String) {
        this.text = text
        this.data = text.toArray()
        this.pos = 0
        this.label = label
    }

    func parse(): Expr {
        skipSpace()
        if (pos >= data.size) {
            fail("empty expression")
        }
        let expr = parseOr()
        skipSpace()
        if (pos != data.size) {
            fail("unexpected token '${text[pos..data.size]}'")
        }
        return expr
    }

    private func fail(message: String): Nothing {
        throw AppError("template", "${label}: ${message} in expression '${text}'")
    }

    private func skipSpace(): Unit {
        while (pos < data.size) {
            let b = data[pos]
            if (b == 0x20 || b == 0x09 || b == 0x0A || b == 0x0D) {
                pos += 1
            } else {
                break
            }
        }
    }

    private func peek(): Int64 {
        if (pos >= data.size) {
            return -1
        }
        return Int64(data[pos])
    }

    private func consume(word: String): Bool {
        skipSpace()
        let bytes = word.toArray()
        if (pos + bytes.size > data.size) {
            return false
        }
        for (i in 0..bytes.size) {
            if (data[pos + i] != bytes[i]) {
                return false
            }
        }
        pos += bytes.size
        return true
    }

    private func keyword(word: String): Bool {
        skipSpace()
        let bytes = word.toArray()
        if (pos + bytes.size > data.size) {
            return false
        }
        for (i in 0..bytes.size) {
            if (data[pos + i] != bytes[i]) {
                return false
            }
        }
        let after = pos + bytes.size
        if (after < data.size) {
            let b = data[after]
            let ident = (b >= 0x61 && b <= 0x7A) || (b >= 0x41 && b <= 0x5A) || (b >= 0x30 && b <= 0x39) || b == 0x5F
            if (ident) {
                return false
            }
        }
        pos = after
        return true
    }

    private func parseOr(): Expr {
        var left = parseAnd()
        while (true) {
            if (keyword("or")) {
                let right = parseAnd()
                left = BinaryExpr("or", left, right)
            } else {
                break
            }
        }
        return left
    }

    private func parseAnd(): Expr {
        var left = parseEquality()
        while (true) {
            if (keyword("and")) {
                let right = parseEquality()
                left = BinaryExpr("and", left, right)
            } else {
                break
            }
        }
        return left
    }

    private func parseEquality(): Expr {
        var left = parseComparison()
        while (true) {
            if (consume("==")) {
                left = BinaryExpr("==", left, parseComparison())
            } else if (consume("!=")) {
                left = BinaryExpr("!=", left, parseComparison())
            } else {
                break
            }
        }
        return left
    }

    private func parseComparison(): Expr {
        var left = parseAdditive()
        while (true) {
            if (consume(">=")) {
                left = BinaryExpr(">=", left, parseAdditive())
            } else if (consume("<=")) {
                left = BinaryExpr("<=", left, parseAdditive())
            } else if (consume(">")) {
                left = BinaryExpr(">", left, parseAdditive())
            } else if (consume("<")) {
                left = BinaryExpr("<", left, parseAdditive())
            } else {
                break
            }
        }
        return left
    }

    private func parseAdditive(): Expr {
        var left = parseUnary()
        while (true) {
            if (consume("+")) {
                left = BinaryExpr("+", left, parseUnary())
            } else {
                break
            }
        }
        return left
    }

    private func parseUnary(): Expr {
        if (keyword("not")) {
            return UnaryExpr("not", parseUnary())
        }
        if (consume("!")) {
            return UnaryExpr("not", parseUnary())
        }
        if (consume("-")) {
            return UnaryExpr("-", parseUnary())
        }
        return parsePostfix()
    }

    private func parsePostfix(): Expr {
        var expr = parsePrimary()
        while (true) {
            skipSpace()
            if (consume(".")) {
                let name = parseIdentifier()
                expr = FieldExpr(expr, name)
            } else if (consume("[")) {
                let index = parseOr()
                if (!consume("]")) {
                    fail("expected ']'")
                }
                expr = IndexExpr(expr, index)
            } else if (consume("|")) {
                let name = parseIdentifier()
                let args = ArrayList<Expr>()
                if (consume("(")) {
                    skipSpace()
                    if (!consume(")")) {
                        while (true) {
                            args.add(parseOr())
                            if (consume(",")) {
                                continue
                            }
                            if (consume(")")) {
                                break
                            }
                            fail("expected ',' or ')' in filter arguments")
                        }
                    }
                }
                expr = FilterExpr(expr, name, args)
            } else {
                break
            }
        }
        return expr
    }

    private func parseIdentifier(): String {
        skipSpace()
        let start = pos
        while (pos < data.size) {
            let b = data[pos]
            let ok = (b >= 0x61 && b <= 0x7A) || (b >= 0x41 && b <= 0x5A) ||
                     (b >= 0x30 && b <= 0x39) || b == 0x5F
            if (ok) {
                pos += 1
            } else {
                break
            }
        }
        if (pos == start) {
            fail("expected identifier")
        }
        return text[start..pos]
    }

    private func parsePrimary(): Expr {
        skipSpace()
        if (pos >= data.size) {
            fail("unexpected end of expression")
        }
        let b = data[pos]
        if (b == 0x22 || b == 0x27) {
            return LiteralExpr(JStr(parseString(b)))
        }
        if (b == 0x28) {
            pos += 1
            let inner = parseOr()
            if (!consume(")")) {
                fail("expected ')'")
            }
            return inner
        }
        if (b == 0x2D || (b >= 0x30 && b <= 0x39)) {
            return parseNumber()
        }
        if (keyword("true")) {
            return LiteralExpr(JBool(true))
        }
        if (keyword("false")) {
            return LiteralExpr(JBool(false))
        }
        if (keyword("null")) {
            return LiteralExpr(JNull)
        }
        let name = parseIdentifier()
        return VarExpr(name)
    }

    private func parseString(quoteByte: UInt8): String {
        pos += 1
        let sb = StringBuilder()
        while (pos < data.size) {
            let b = data[pos]
            if (b == quoteByte) {
                pos += 1
                return sb.toString()
            }
            if (b == 0x5C) {
                pos += 1
                if (pos >= data.size) {
                    fail("unterminated string")
                }
                let e = data[pos]
                pos += 1
                if (e == 0x6E) {
                    sb.append("\n")
                } else if (e == 0x74) {
                    sb.append("\t")
                } else if (e == 0x72) {
                    sb.append("\r")
                } else if (e == 0x22) {
                    sb.append("\"")
                } else if (e == 0x27) {
                    sb.append("'")
                } else if (e == 0x5C) {
                    sb.append("\\")
                } else {
                    sb.append(Rune(Int64(e)))
                }
            } else {
                let start = pos
                while (pos < data.size && data[pos] != quoteByte && data[pos] != 0x5C) {
                    pos += 1
                }
                sb.append(String.fromUtf8(data[start..pos]))
            }
        }
        fail("unterminated string")
    }

    private func parseNumber(): Expr {
        let start = pos
        if (data[pos] == 0x2D) {
            pos += 1
        }
        while (pos < data.size && data[pos] >= 0x30 && data[pos] <= 0x39) {
            pos += 1
        }
        var isFloat = false
        if (pos < data.size && data[pos] == 0x2E) {
            isFloat = true
            pos += 1
            while (pos < data.size && data[pos] >= 0x30 && data[pos] <= 0x39) {
                pos += 1
            }
        }
        let literal = text[start..pos]
        if (isFloat) {
            return LiteralExpr(JFloat(Float64.parse(literal)))
        }
        return LiteralExpr(JInt(Int64.parse(literal)))
    }
}

// ---------------------------------------------------------------------------
// Template parser
// ---------------------------------------------------------------------------

let K_TEXT: Int64 = 0
let K_OUTPUT: Int64 = 1
let K_TAG: Int64 = 2

class TplToken {
    let kind: Int64
    let text: String
    let raw: Bool
    let line: Int64
    init(kind: Int64, text: String, raw: Bool, line: Int64) {
        this.kind = kind
        this.text = text
        this.raw = raw
        this.line = line
    }
}

class TemplateParser {
    private let tokens: ArrayList<TplToken>
    private var pos: Int64
    private let name: String

    init(name: String, tokens: ArrayList<TplToken>) {
        this.name = name
        this.tokens = tokens
        this.pos = 0
    }

    func parse(): ArrayList<Node> {
        let (nodes, stop) = parseNodes(Array<String>(0, repeat: ""))
        if (stop.size > 0) {
            fail("unexpected tag '${stop}'", lineOfLast())
        }
        nodes
    }

    private func lineOfLast(): Int64 {
        if (tokens.size == 0) {
            return 1
        }
        tokens[tokens.size - 1].line
    }

    private func fail(message: String, line: Int64): Nothing {
        throw AppError("template", "${name}:${line}: ${message}")
    }

    private func parseNodes(stopTags: Array<String>): (ArrayList<Node>, String) {
        let nodes = ArrayList<Node>()
        while (pos < tokens.size) {
            let token = tokens[pos]
            pos += 1
            if (token.kind == K_TEXT) {
                nodes.add(TextNode(token.text))
                continue
            }
            if (token.kind == K_OUTPUT) {
                let parsed = parseOutput(token.text, token.raw, token.line)
                nodes.add(parsed)
                continue
            }
            let tag = token.text.trimAscii()
            if (tag.size == 0) {
                fail("empty tag", token.line)
            }
            let (tagName, tagRest) = splitTag(tag)
            if (contains(stopTags, tagName)) {
                return (nodes, tag)
            }
            if (tagName == "if") {
                nodes.add(parseIf(tagRest, token.line))
            } else if (tagName == "for") {
                nodes.add(parseFor(tagRest, token.line))
            } else if (tagName == "include") {
                nodes.add(parseInclude(tagRest, token.line))
            } else {
                fail("unknown tag '${tagName}'", token.line)
            }
        }
        return (nodes, "")
    }

    private func parseIf(conditionText: String, line: Int64): Node {
        let branches = ArrayList<IfBranch>()
        var currentCondition = parseExpression(conditionText, line)
        while (true) {
            let (body, stop) = parseNodes(["elif", "else", "endif"])
            branches.add(IfBranch(currentCondition, body))
            if (stop.size == 0) {
                fail("missing 'endif'", line)
            }
            let (stopName, stopRest) = splitTag(stop)
            if (stopName == "endif") {
                return IfNode(branches, ArrayList<Node>())
            }
            if (stopName == "elif") {
                currentCondition = parseExpression(stopRest, line)
                continue
            }
            if (stopName == "else") {
                let (elseNodes, elseStop) = parseNodes(["endif"])
                if (elseStop.size == 0) {
                    fail("missing 'endif'", line)
                }
                return IfNode(branches, elseNodes)
            }
            fail("unexpected tag '${stopName}'", line)
        }
        return IfNode(branches, ArrayList<Node>())
    }

    private func parseFor(spec: String, line: Int64): Node {
        let idx = findSub(spec, " in ")
        if (idx <= 0) {
            fail("for tag must be 'for name in expression'", line)
        }
        let varName = spec[0..idx].trimAscii()
        let listText = spec[idx + 4..spec.size].trimAscii()
        if (!isIdentifierText(varName) || listText.size == 0) {
            fail("invalid for tag", line)
        }
        let listExpr = parseExpression(listText, line)
        let (body, stop) = parseNodes(["endfor", "else"])
        var elseBody = ArrayList<Node>()
        if (stop.size > 0) {
            let (stopName, _) = splitTag(stop)
            if (stopName == "else") {
                let (elseNodes, elseStop) = parseNodes(["endfor"])
                if (elseStop.size == 0) {
                    fail("missing 'endfor'", line)
                }
                elseBody = elseNodes
            }
        }
        return ForNode(varName, listExpr, body, elseBody)
    }

    private func parseInclude(spec: String, line: Int64): Node {
        let trimmed = spec.trimAscii()
        var includeName = ""
        if (trimmed.size >= 2 && ((trimmed[0] == 0x22 && trimmed[trimmed.size - 1] == 0x22) ||
                                  (trimmed[0] == 0x27 && trimmed[trimmed.size - 1] == 0x27))) {
            includeName = trimmed[1..trimmed.size - 1]
        } else {
            fail("include requires a quoted template name", line)
        }
        if (!isSafeTemplateName(includeName)) {
            fail("unsafe template name '${includeName}'", line)
        }
        IncludeNode(includeName)
    }

    private func parseOutput(content: String, tripleRaw: Bool, line: Int64): Node {
        var text = content.trimAscii()
        var raw = tripleRaw
        let bytes = text.toArray()
        // Only inspect bytes when the expression really ends with the ASCII
        // marker "|raw"; slicing the last four bytes blindly can cut a
        // multi-byte UTF-8 character and crash String.fromUtf8.
        if (bytes.size >= 4 && bytes[bytes.size - 4] == 0x7C && bytes[bytes.size - 3] == 0x72 &&
            bytes[bytes.size - 2] == 0x61 && bytes[bytes.size - 1] == 0x77) {
            raw = true
            text = text[0..text.size - 4].trimAscii()
        }
        if (text.size == 0) {
            fail("empty output expression", line)
        }
        let expr = parseExpression(text, line)
        OutputNode(expr, raw)
    }

    private func parseExpression(text: String, line: Int64): Expr {
        try {
            return ExprParser(text, "${name}:${line}").parse()
        } catch (e: AppError) {
            throw e
        } catch (e: Exception) {
            throw AppError("template", "${name}:${line}: ${e.message}")
        }
    }

    private func splitTag(tag: String): (String, String) {
        var i = 0
        while (i < tag.size) {
            let b = tag.toArray()[i]
            if (b == 0x20 || b == 0x09 || b == 0x0A || b == 0x0D) {
                break
            }
            i += 1
        }
        let name = tag[0..i].trimAscii()
        let rest = if (i < tag.size) { tag[i..tag.size].trimAscii() } else { "" }
        (name, rest)
    }
}

func contains(items: Array<String>, value: String): Bool {
    for (item in items) {
        if (item == value) {
            return true
        }
    }
    false
}

func isIdentifierText(text: String): Bool {
    if (text.size == 0) {
        return false
    }
    let bytes = text.toArray()
    let first = bytes[0]
    if (!((first >= 0x61 && first <= 0x7A) || (first >= 0x41 && first <= 0x5A) || first == 0x5F)) {
        return false
    }
    for (b in bytes) {
        let ok = (b >= 0x61 && b <= 0x7A) || (b >= 0x41 && b <= 0x5A) ||
                 (b >= 0x30 && b <= 0x39) || b == 0x5F
        if (!ok) {
            return false
        }
    }
    true
}

func isSafeTemplateName(name: String): Bool {
    if (name.size == 0 || name.size > 160) {
        return false
    }
    if (name[0] == 0x2F || name.contains("..") || name.contains("\\")) {
        return false
    }
    for (b in name.toArray()) {
        let ok = (b >= 0x61 && b <= 0x7A) || (b >= 0x41 && b <= 0x5A) ||
                 (b >= 0x30 && b <= 0x39) || b == 0x2F || b == 0x2D ||
                 b == 0x5F || b == 0x2E
        if (!ok) {
            return false
        }
    }
    true
}

// ---------------------------------------------------------------------------
// Template lexer
// ---------------------------------------------------------------------------

func lexTemplate(source: String): ArrayList<TplToken> {
    let data = source.toArray()
    let tokens = ArrayList<TplToken>()
    var i: Int64 = 0
    var line: Int64 = 1
    var textStart: Int64 = 0
    while (i < data.size) {
        if (data[i] == 0x7B && i + 1 < data.size) {
            let next = data[i + 1]
            var kind = -1
            var openLen: Int64 = 2
            var close = ""
            var raw = false
            if (next == 0x7B) {
                if (i + 2 < data.size && data[i + 2] == 0x7B) {
                    kind = 1
                    openLen = 3
                    close = "}}}"
                    raw = true
                } else {
                    kind = 1
                    close = "}}"
                }
            } else if (next == 0x25) {
                kind = 2
                close = "%}"
            } else if (next == 0x23) {
                kind = 3
                close = "#}"
            }
            if (kind >= 0) {
                if (i > textStart) {
                    tokens.add(TplToken(K_TEXT, String.fromUtf8(data[textStart..i]), false, line))
                    line += countNewlines(data, textStart, i)
                }
                let contentStart = i + openLen
                let closeIdx = findPattern(data, contentStart, close)
                if (closeIdx < 0) {
                    throw AppError("template", "unterminated template tag at line ${line}")
                }
                let content = String.fromUtf8(data[contentStart..closeIdx])
                if (kind == 1) {
                    tokens.add(TplToken(K_OUTPUT, content, raw, line))
                } else if (kind == 2) {
                    tokens.add(TplToken(K_TAG, content, false, line))
                }
                line += countNewlines(data, i, closeIdx + close.size)
                i = closeIdx + close.size
                textStart = i
                continue
            }
        }
        i += 1
    }
    if (data.size > textStart) {
        tokens.add(TplToken(K_TEXT, String.fromUtf8(data[textStart..data.size]), false, line))
    }
    tokens
}

func countNewlines(data: Array<UInt8>, start: Int64, end: Int64): Int64 {
    var count: Int64 = 0
    var i = start
    while (i < end) {
        if (data[i] == 0x0A) {
            count += 1
        }
        i += 1
    }
    count
}

func findPattern(data: Array<UInt8>, from: Int64, pattern: String): Int64 {
    let pat = pattern.toArray()
    if (pat.size == 0 || from >= data.size) {
        return -1
    }
    var i = from
    while (i + pat.size <= data.size) {
        var matched = true
        for (j in 0..pat.size) {
            if (data[i + j] != pat[j]) {
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

// ---------------------------------------------------------------------------
// Value helpers
// ---------------------------------------------------------------------------

func jsonTruthy(v: JsonValue): Bool {
    match (v) {
        case JNull => false
        case JBool(b) => b
        case JInt(i) => i != 0
        case JFloat(f) => f != 0.0
        case JStr(s) => s.size > 0
        case JArr(a) => a.size() > 0
        case JObj(o) => o.size() > 0
    }
}

func jsonText(v: JsonValue): String {
    match (v) {
        case JNull => ""
        case JBool(b) =>
            if (b) { "true" } else { "false" }
        case JInt(i) => i.toString()
        case JFloat(f) => f.toString()
        case JStr(s) => s
        case JArr(_) => toJsonCompact(v)
        case JObj(_) => toJsonCompact(v)
    }
}

func jsonEquals(a: JsonValue, b: JsonValue): Bool {
    match (a) {
        case JNull => b.isNullValue()
        case JBool(ab) =>
            match (b) {
                case JBool(bb) => ab == bb
                case _ => false
            }
        case JInt(ai) =>
            match (b) {
                case JInt(bi) => ai == bi
                case JFloat(bf) => Float64(ai) == bf
                case _ => false
            }
        case JFloat(af) =>
            match (b) {
                case JFloat(bf) => af == bf
                case JInt(bi) => af == Float64(bi)
                case _ => false
            }
        case JStr(sa) =>
            match (b) {
                case JStr(bs) => sa == bs
                case _ => false
            }
        case JArr(aa) =>
            match (b) {
                case JArr(ba) =>
                    if (aa.size() != ba.size()) {
                        return false
                    }
                    for (i in 0..aa.items.size) {
                        if (!jsonEquals(aa.items[i], ba.items[i])) {
                            return false
                        }
                    }
                    true
                case _ => false
            }
        case JObj(ao) =>
            match (b) {
                case JObj(bo) =>
                    if (ao.size() != bo.size()) {
                        return false
                    }
                    for ((k, v) in ao.fields) {
                        match (bo.get(k)) {
                            case Some(other) =>
                                if (!jsonEquals(v, other)) {
                                    return false
                                }
                            case None => return false
                        }
                    }
                    true
                case _ => false
            }
    }
}

func jsonCompare(a: JsonValue, b: JsonValue): Int64 {
    match (a) {
        case JInt(ai) =>
            match (b) {
                case JInt(bi) =>
                    if (ai > bi) { 1 } else if (ai < bi) { -1 } else { 0 }
                case JFloat(bf) =>
                    let af = Float64(ai)
                    if (af > bf) { 1 } else if (af < bf) { -1 } else { 0 }
                case _ => 0
            }
        case JFloat(af) =>
            match (b) {
                case JFloat(bf) =>
                    if (af > bf) { 1 } else if (af < bf) { -1 } else { 0 }
                case JInt(bi) =>
                    let bf = Float64(bi)
                    if (af > bf) { 1 } else if (af < bf) { -1 } else { 0 }
                case _ => 0
            }
        case JStr(sa) =>
            match (b) {
                case JStr(bs) =>
                    if (sa > bs) { 1 } else if (sa < bs) { -1 } else { 0 }
                case _ => 0
            }
        case _ => 0
    }
}

func filterArg(args: ArrayList<Expr>, index: Int64, ctx: RenderContext, fallback: JsonValue): JsonValue {
    if (index < args.size) {
        args[index].eval(ctx)
    } else {
        fallback
    }
}

func applyFilter(name: String, value: JsonValue, args: ArrayList<Expr>, ctx: RenderContext): JsonValue {
    if (name == "raw") {
        return value
    }
    if (name == "default") {
        if (!jsonTruthy(value)) {
            return filterArg(args, 0, ctx, JStr(""))
        }
        return value
    }
    if (name == "upper") {
        return JStr(jsonText(value).toAsciiUpper())
    }
    if (name == "lower") {
        return JStr(jsonText(value).toAsciiLower())
    }
    if (name == "trim") {
        return JStr(jsonText(value).trimAscii())
    }
    if (name == "length") {
        match (value) {
            case JStr(s) => return JInt(runeCount(s))
            case JArr(a) => return JInt(a.size())
            case JObj(o) => return JInt(o.size())
            case _ => return JInt(0)
        }
    }
    if (name == "truncate") {
        let n = filterArg(args, 0, ctx, JInt(120))
        let limit = match (n) {
            case JInt(i) => i
            case _ => 120
        }
        return JStr(truncateRunes(htmlText(value), limit))
    }
    if (name == "strip") {
        return JStr(stripHtml(jsonText(value)))
    }
    if (name == "date") {
        let pattern = jsonText(filterArg(args, 0, ctx, JStr("yyyy-MM-dd")))
        match (value) {
            case JInt(i) => return JStr(formatTime(i, pattern))
            case _ => return JStr(jsonText(value))
        }
    }
    if (name == "relative") {
        match (value) {
            case JInt(i) => return JStr(relativeTime(i))
            case _ => return JStr(jsonText(value))
        }
    }
    if (name == "json") {
        return JStr(toJsonCompact(value))
    }
    if (name == "urlencode") {
        return JStr(urlEncode(jsonText(value)))
    }
    if (name == "join") {
        let sep = jsonText(filterArg(args, 0, ctx, JStr(", ")))
        match (value) {
            case JArr(a) =>
                let parts = ArrayList<String>()
                for (item in a.items) {
                    parts.add(jsonText(item))
                }
                return JStr(String.join(parts.toArray(), delimiter: sep))
            case _ => return JStr(jsonText(value))
        }
    }
    if (name == "first") {
        match (value) {
            case JArr(a) =>
                if (a.size() > 0) { return a.items[0] }
                return JNull
            case _ => return value
        }
    }
    if (name == "last") {
        match (value) {
            case JArr(a) =>
                if (a.size() > 0) { return a.items[a.size() - 1] }
                return JNull
            case _ => return value
        }
    }
    return value
}

func htmlText(value: JsonValue): String {
    match (value) {
        case JStr(s) => stripHtml(s)
        case _ => jsonText(value)
    }
}

func sortStrings(items: Array<String>): Unit {
    sort<String>(items)
}

// ---------------------------------------------------------------------------
// Engine
// ---------------------------------------------------------------------------

public class TemplateEngine {
    private let root: String
    private let devMode: Bool
    private let mutex: Mutex = Mutex()
    private let cache: HashMap<String, ArrayList<Node>> = HashMap<String, ArrayList<Node>>()

    public init(root: String, devMode!: Bool = false) {
        this.root = root
        this.devMode = devMode
    }

    public func render(name: String, data: JsonValue): String {
        let ctx = RenderContext(this, data)
        let out = StringBuilder()
        renderInto(name, ctx, out)
        out.toString()
    }

    func renderInto(name: String, ctx: RenderContext, out: StringBuilder): Unit {
        let nodes = load(name)
        renderNodes(nodes, ctx, out)
    }

    private func load(name: String): ArrayList<Node> {
        if (!isSafeTemplateName(name)) {
            throw AppError("template", "unsafe template name: ${name}")
        }
        if (!devMode) {
            synchronized(mutex) {
                match (cache.get(name)) {
                    case Some(nodes) => return nodes
                    case None => ()
                }
            }
        }
        let path = root + "/" + name
        if (!exists(path)) {
            throw AppError("template", "template not found: ${name}")
        }
        let source = try {
            readTextFile(path)
        } catch (e: Exception) {
            throw AppError("template", "cannot read template ${name}: ${e.message}")
        }
        let tokens = lexTemplate(source)
        let nodes = TemplateParser(name, tokens).parse()
        if (!devMode) {
            synchronized(mutex) {
                cache[name] = nodes
            }
        }
        return nodes
    }

    public func hasTemplate(name: String): Bool {
        if (!isSafeTemplateName(name)) {
            return false
        }
        exists(root + "/" + name)
    }
}
