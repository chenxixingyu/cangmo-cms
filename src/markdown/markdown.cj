/**
 * Cangmo - Markdown renderer.
 *
 * An original, dependency-free CommonMark-inspired renderer with a security
 * first design: raw HTML is escaped unless explicitly enabled for trusted
 * editors, link schemes are allow-listed, and all text is HTML escaped.
 *
 * Supported blocks: ATX headings, fenced code, block quotes, ordered and
 * unordered lists (including nesting), tables, thematic breaks, paragraphs.
 * Supported inline: emphasis, strong, strikethrough, code spans, links,
 * images, autolinks, hard breaks, backslash escapes.
 */
package cangmo.markdown

import cangmo.core.*
import std.collection.*

public class Heading {
    public let level: Int64
    public let text: String
    public let id: String

    public init(level: Int64, text: String, id: String) {
        this.level = level
        this.text = text
        this.id = id
    }
}

public class MarkdownResult {
    public let html: String
    public let headings: Array<Heading>

    public init(html: String, headings: Array<Heading>) {
        this.html = html
        this.headings = headings
    }
}

public class MarkdownRenderer {
    private let allowRawHtml: Bool

    public init(allowRawHtml!: Bool = false) {
        this.allowRawHtml = allowRawHtml
    }

    public func render(source: String): MarkdownResult {
        let normalized = source.replace("\r\n", "\n").replace("\r", "\n")
        let lines = normalized.split("\n")
        let headings = ArrayList<Heading>()
        let ids = HashMap<String, Int64>()
        let html = renderBlocks(lines, 0, lines.size, headings, ids, 0)
        MarkdownResult(html, headings.toArray())
    }

    public func renderHtml(source: String): String {
        render(source).html
    }

    // -----------------------------------------------------------------------
    // Block level
    // -----------------------------------------------------------------------

    private func renderBlocks(lines: Array<String>, start: Int64, end: Int64,
                              headings: ArrayList<Heading>, ids: HashMap<String, Int64>,
                              depth: Int64): String {
        if (depth > 16) {
            return "<p>嵌套内容过深</p>"
        }
        let sb = StringBuilder()
        var i = start
        while (i < end) {
            let line = lines[i]
            if (isBlankLine(line)) {
                i += 1
                continue
            }
            if (isFence(line)) {
                let (fenceMarker, fenceLang) = fenceInfo(line)
                i += 1
                let codeLines = ArrayList<String>()
                while (i < end && !isClosingFence(lines[i], fenceMarker)) {
                    codeLines.add(lines[i])
                    i += 1
                }
                if (i < end) {
                    i += 1
                }
                sb.append("<pre><code")
                if (fenceLang.size > 0) {
                    sb.append(" class=\"language-")
                    sb.append(escapeHtml(fenceLang))
                    sb.append("\"")
                }
                sb.append(">")
                sb.append(escapeHtml(String.join(codeLines.toArray(), delimiter: "\n")))
                sb.append("</code></pre>\n")
                continue
            }
            let headingLevel = headingLevelOf(line)
            if (headingLevel > 0) {
                let raw = headingText(line, headingLevel)
                let inlineHtml = inline(raw, allowRawHtml)
                let plain = normalizeWhitespace(stripHtml(inlineHtml))
                let baseId = slugify(plain)
                var id = if (baseId.size == 0) { "h-" + sha256Hex(plain)[0..8] } else { baseId }
                if (ids.contains(id)) {
                    let next = ids[id] + 1
                    ids[id] = next
                    id = "${id}-${next}"
                } else {
                    ids[id] = 1
                }
                headings.add(Heading(headingLevel, plain, id))
                sb.append("<h${headingLevel} id=\"${id}\">")
                sb.append(inlineHtml)
                sb.append("</h${headingLevel}>\n")
                i += 1
                continue
            }
            if (isThematicBreak(line)) {
                sb.append("<hr>\n")
                i += 1
                continue
            }
            if (isBlockQuote(line)) {
                let quoteLines = ArrayList<String>()
                while (i < end && isBlockQuote(lines[i])) {
                    quoteLines.add(stripQuoteMarker(lines[i]))
                    i += 1
                }
                sb.append("<blockquote>\n")
                sb.append(renderBlocks(quoteLines.toArray(), 0, quoteLines.size, headings, ids, depth + 1))
                sb.append("</blockquote>\n")
                continue
            }
            if (isListLine(line)) {
                let (html, next) = renderList(lines, i, end, headings, ids, depth)
                sb.append(html)
                i = next
                continue
            }
            if (isTableStart(lines, i, end)) {
                let (html, next) = renderTable(lines, i, end)
                sb.append(html)
                i = next
                continue
            }
            if (allowRawHtml && startsWithHtmlBlock(line)) {
                let raw = ArrayList<String>()
                while (i < end && !isBlankLine(lines[i])) {
                    raw.add(lines[i])
                    i += 1
                }
                sb.append(String.join(raw.toArray(), delimiter: "\n"))
                sb.append("\n")
                continue
            }
            let paraLines = ArrayList<String>()
            while (i < end && !isBlankLine(lines[i]) && !isBlockStarter(lines[i]) &&
                   !isTableStart(lines, i, end)) {
                paraLines.add(lines[i])
                i += 1
            }
            if (paraLines.size == 0) {
                // Safety valve: always make progress.
                paraLines.add(lines[i])
                i += 1
            }
            sb.append("<p>")
            sb.append(inline(String.join(paraLines.toArray(), delimiter: "\n"), allowRawHtml))
            sb.append("</p>\n")
        }
        return sb.toString()
    }

    private func isBlockStarter(line: String): Bool {
        isFence(line) || headingLevelOf(line) > 0 || isThematicBreak(line) ||
        isBlockQuote(line) || isListLine(line)
    }

    private func renderList(lines: Array<String>, start: Int64, end: Int64,
                            headings: ArrayList<Heading>, ids: HashMap<String, Int64>,
                            depth: Int64): (String, Int64) {
        let first = lines[start]
        let ordered = isOrderedListLine(first)
        let baseIndent = leadingSpaces(first)
        let items = ArrayList<ArrayList<String>>()
        var i = start
        while (i < end) {
            let line = lines[i]
            if (isBlankLine(line)) {
                // A blank line only continues the list when the next line is
                // indented content of the current item.
                if (i + 1 < end && leadingSpaces(lines[i + 1]) > baseIndent) {
                    if (items.size > 0) {
                        items[items.size - 1].add("")
                    }
                    i += 1
                    continue
                }
                break
            }
            let indent = leadingSpaces(line)
            if (indent == baseIndent && isListLine(line) && isOrderedListLine(line) == ordered) {
                items.add(ArrayList<String>())
                items[items.size - 1].add(listItemText(line))
                i += 1
                continue
            }
            if (indent > baseIndent && items.size > 0) {
                items[items.size - 1].add(dedent(line, baseIndent + 2))
                i += 1
                continue
            }
            break
        }
        let sb = StringBuilder()
        sb.append(if (ordered) { "<ol>\n" } else { "<ul>\n" })
        for (item in items) {
            sb.append("<li>")
            let itemHtml = renderBlocks(item.toArray(), 0, item.size, headings, ids, depth + 1).trimAscii()
            var content = itemHtml
            if (content.startsWith("<p>") && content.endsWith("</p>") &&
                findSub(content, "</p>") == content.size - 4) {
                content = content[3..content.size - 4]
            }
            sb.append(content)
            sb.append("</li>\n")
        }
        sb.append(if (ordered) { "</ol>\n" } else { "</ul>\n" })
        return (sb.toString(), i)
    }

    private func renderTable(lines: Array<String>, start: Int64, end: Int64): (String, Int64) {
        let header = splitTableRow(lines[start])
        let aligns = parseTableAlignments(lines[start + 1], header.size)
        let sb = StringBuilder()
        sb.append("<div class=\"table-wrap\"><table>\n<thead><tr>")
        for (i in 0..header.size) {
            sb.append("<th")
            if (aligns[i].size > 0) {
                sb.append(" style=\"text-align: ${aligns[i]}\"")
            }
            sb.append(">")
            sb.append(inline(header[i], allowRawHtml))
            sb.append("</th>")
        }
        sb.append("</tr></thead>\n<tbody>\n")
        var i = start + 2
        while (i < end && !isBlankLine(lines[i]) && findSub(lines[i], "|") >= 0) {
            let cells = splitTableRow(lines[i])
            sb.append("<tr>")
            for (c in 0..header.size) {
                let text = if (c < cells.size) { cells[c] } else { "" }
                sb.append("<td")
                if (aligns[c].size > 0) {
                    sb.append(" style=\"text-align: ${aligns[c]}\"")
                }
                sb.append(">")
                sb.append(inline(text, allowRawHtml))
                sb.append("</td>")
            }
            sb.append("</tr>\n")
            i += 1
        }
        sb.append("</tbody></table></div>\n")
        return (sb.toString(), i)
    }

    private func isTableStart(lines: Array<String>, i: Int64, end: Int64): Bool {
        if (i + 1 >= end) {
            return false
        }
        let head = lines[i]
        if (findSub(head, "|") < 0 && findSub(head, "\\|") < 0) {
            return false
        }
        let sep = lines[i + 1].trimAscii()
        if (sep.size < 3) {
            return false
        }
        for (b in sep.toArray()) {
            let ok = b == 0x7C || b == 0x2D || b == 0x3A || b == 0x20 || b == 0x09
            if (!ok) {
                return false
            }
        }
        return findSub(sep, "-") >= 0
    }

    private func splitTableRow(line: String): Array<String> {
        var text = line.trimAscii()
        if (text.size > 0 && text[0] == 0x7C) {
            text = text[1..text.size]
        }
        if (text.size > 0 && text[text.size - 1] == 0x7C) {
            text = text[0..text.size - 1]
        }
        let cells = ArrayList<String>()
        for (cell in text.split("|")) {
            cells.add(cell.trimAscii())
        }
        cells.toArray()
    }

    private func parseTableAlignments(line: String, columns: Int64): Array<String> {
        let raw = splitTableRow(line)
        let out = Array<String>(columns, repeat: "")
        for (i in 0..columns) {
            if (i < raw.size) {
                let cell = raw[i].trimAscii()
                let left = cell.startsWith(":")
                let right = cell.endsWith(":")
                if (left && right) {
                    out[i] = "center"
                } else if (right) {
                    out[i] = "right"
                } else if (left) {
                    out[i] = "left"
                }
            }
        }
        return out
    }

    private func leadingSpaces(line: String): Int64 {
        var i = 0
        while (i < line.size) {
            let b = line.toArray()[i]
            if (b == 0x20) {
                i += 1
            } else if (b == 0x09) {
                i += 4
            } else {
                break
            }
        }
        return i
    }

    private func dedent(line: String, spaces: Int64): String {
        var i = 0
        while (i < line.size && i < spaces) {
            let b = line.toArray()[i]
            if (b == 0x20 || b == 0x09) {
                i += 1
            } else {
                break
            }
        }
        line[i..line.size]
    }

    private func isBlankLine(line: String): Bool {
        isBlank(line)
    }

    private func isFence(line: String): Bool {
        let t = line.trimAscii()
        t.startsWith("```") || t.startsWith("~~~")
    }

    private func fenceInfo(line: String): (String, String) {
        let t = line.trimAscii()
        let marker = if (t.startsWith("```")) { "```" } else { "~~~" }
        let info = t[marker.size..t.size].trimAscii()
        var lang = StringBuilder()
        let space = findSub(info, " ")
        let raw = if (space < 0) { info } else { info[0..space] }
        for (b in raw.toArray()) {
            let ok = (b >= 0x61 && b <= 0x7A) || (b >= 0x41 && b <= 0x5A) ||
                     (b >= 0x30 && b <= 0x39) || b == 0x2D || b == 0x5F || b == 0x2B || b == 0x23
            if (ok) {
                lang.append(Rune(Int64(b)))
            }
        }
        (marker, lang.toString())
    }

    private func isClosingFence(line: String, marker: String): Bool {
        let t = line.trimAscii()
        t.startsWith(marker) && t.size >= marker.size
    }

    private func headingLevelOf(line: String): Int64 {
        let t = line.trimAscii()
        var i = 0
        while (i < t.size && t.toArray()[i] == 0x23) {
            i += 1
        }
        if (i < 1 || i > 6) {
            return 0
        }
        if (i < t.size && t.toArray()[i] != 0x20) {
            return 0
        }
        i
    }

    private func headingText(line: String, level: Int64): String {
        let t = line.trimAscii()
        var text = t[level..t.size].trimAscii()
        // Remove optional closing hashes.
        var end = text.size
        while (end > 0 && text.toArray()[end - 1] == 0x23) {
            end -= 1
        }
        text = text[0..end].trimAscii()
        text
    }

    private func isThematicBreak(line: String): Bool {
        let t = line.trimAscii()
        if (t.size < 3) {
            return false
        }
        let b0 = t.toArray()[0]
        if (b0 != 0x2D && b0 != 0x2A && b0 != 0x5F) {
            return false
        }
        for (b in t.toArray()) {
            if (b != b0 && b != 0x20 && b != 0x09) {
                return false
            }
        }
        true
    }

    private func isBlockQuote(line: String): Bool {
        line.trimAscii().startsWith(">")
    }

    private func stripQuoteMarker(line: String): String {
        let t = line.trimAscii()
        var rest = t[1..t.size]
        if (rest.size > 0 && rest[0] == 0x20) {
            rest = rest[1..rest.size]
        }
        rest
    }

    private func isListLine(line: String): Bool {
        let t = line.trimAscii()
        if (t.size < 2) {
            return false
        }
        let bytes = t.toArray()
        if ((bytes[0] == 0x2D || bytes[0] == 0x2A || bytes[0] == 0x2B) && bytes[1] == 0x20) {
            return true
        }
        return isOrderedListLine(t)
    }

    private func isOrderedListLine(line: String): Bool {
        let t = line.trimAscii()
        var i = 0
        let bytes = t.toArray()
        while (i < bytes.size && bytes[i] >= 0x30 && bytes[i] <= 0x39) {
            i += 1
        }
        if (i == 0 || i >= bytes.size) {
            return false
        }
        if ((bytes[i] == 0x2E || bytes[i] == 0x29) && i + 1 < bytes.size && bytes[i + 1] == 0x20) {
            return true
        }
        false
    }

    private func listItemText(line: String): String {
        let t = line.trimAscii()
        let bytes = t.toArray()
        if (bytes[0] == 0x2D || bytes[0] == 0x2A || bytes[0] == 0x2B) {
            return t[2..t.size]
        }
        var i = 0
        while (i < bytes.size && bytes[i] >= 0x30 && bytes[i] <= 0x39) {
            i += 1
        }
        return t[i + 2..t.size]
    }

    private func startsWithHtmlBlock(line: String): Bool {
        let t = line.trimAscii().toAsciiLower()
        let tags = ["<div", "<p", "<section", "<article", "<table", "<ul", "<ol", "<blockquote",
                    "<pre", "<h1", "<h2", "<h3", "<h4", "<h5", "<h6", "<hr", "<figure", "<iframe"]
        for (tag in tags) {
            if (t.startsWith(tag)) {
                return true
            }
        }
        false
    }

    // -----------------------------------------------------------------------
    // Inline level
    // -----------------------------------------------------------------------

    public func inline(text: String, allowRaw: Bool): String {
        let bytes = text.toArray()
        let sb = StringBuilder()
        var i: Int64 = 0
        var plainStart: Int64 = 0
        while (i < bytes.size) {
            let b = bytes[i]
            if (b == 0x5C && i + 1 < bytes.size) {
                // Backslash escape.
                flushPlain(bytes, plainStart, i, sb)
                sb.append(escapeHtml(String.fromUtf8(bytes[i + 1..i + 2])))
                i += 2
                plainStart = i
                continue
            }
            if (b == 0x60) {
                var ticks = 0
                while (i + ticks < bytes.size && bytes[i + ticks] == 0x60) {
                    ticks += 1
                }
                let closing = findBackticks(bytes, i + ticks, ticks)
                if (closing >= 0) {
                    flushPlain(bytes, plainStart, i, sb)
                    var code = String.fromUtf8(bytes[i + ticks..closing])
                    if (code.size >= 2 && code[0] == 0x20 && code[code.size - 1] == 0x20) {
                        code = code[1..code.size - 1]
                    }
                    sb.append("<code>")
                    sb.append(escapeHtml(code.replace("\n", " ")))
                    sb.append("</code>")
                    i = closing + ticks
                    plainStart = i
                    continue
                }
            }
            if (b == 0x21 && i + 1 < bytes.size && bytes[i + 1] == 0x5B) {
                let parsed = parseLink(text, i + 1)
                if (let Some(link) <- parsed) {
                    flushPlain(bytes, plainStart, i, sb)
                    sb.append("<img src=\"")
                    sb.append(escapeHtml(safeUrl(link.url)))
                    sb.append("\" alt=\"")
                    sb.append(escapeHtml(stripHtml(inline(link.label, allowRaw))))
                    sb.append("\" loading=\"lazy\" decoding=\"async\"")
                    if (link.title.size > 0) {
                        sb.append(" title=\"")
                        sb.append(escapeHtml(link.title))
                        sb.append("\"")
                    }
                    sb.append(">")
                    i = link.end
                    plainStart = i
                    continue
                }
            }
            if (b == 0x5B) {
                if (let Some(link) <- parseLink(text, i)) {
                    flushPlain(bytes, plainStart, i, sb)
                    sb.append("<a href=\"")
                    sb.append(escapeHtml(safeUrl(link.url)))
                    sb.append("\"")
                    if (link.title.size > 0) {
                        sb.append(" title=\"")
                        sb.append(escapeHtml(link.title))
                        sb.append("\"")
                    }
                    sb.append(" rel=\"noopener nofollow\"")
                    sb.append(">")
                    sb.append(inline(link.label, allowRaw))
                    sb.append("</a>")
                    i = link.end
                    plainStart = i
                    continue
                }
            }
            if (b == 0x3C) {
                let close = findByte(bytes, i + 1, 0x3E)
                if (close > i) {
                    let inner = String.fromUtf8(bytes[i + 1..close])
                    let lower = inner.toAsciiLower()
                    if (lower.startsWith("http://") || lower.startsWith("https://") || lower.startsWith("mailto:")) {
                        flushPlain(bytes, plainStart, i, sb)
                        sb.append("<a href=\"")
                        sb.append(escapeHtml(safeUrl(inner)))
                        sb.append("\" rel=\"noopener nofollow\">")
                        sb.append(escapeHtml(inner))
                        sb.append("</a>")
                        i = close + 1
                        plainStart = i
                        continue
                    }
                    if (allowRaw) {
                        flushPlain(bytes, plainStart, i, sb)
                        sb.append(String.fromUtf8(bytes[i..close + 1]))
                        i = close + 1
                        plainStart = i
                        continue
                    }
                }
            }
            if (b == 0x2A || b == 0x5F) {
                let double = i + 1 < bytes.size && bytes[i + 1] == b
                if (double) {
                    let close = findDouble(bytes, i + 2, b)
                    if (close > i + 2) {
                        flushPlain(bytes, plainStart, i, sb)
                        sb.append("<strong>")
                        sb.append(inline(String.fromUtf8(bytes[i + 2..close]), allowRaw))
                        sb.append("</strong>")
                        i = close + 2
                        plainStart = i
                        continue
                    }
                } else {
                    let close = findByte(bytes, i + 1, b)
                    if (close > i + 1) {
                        flushPlain(bytes, plainStart, i, sb)
                        sb.append("<em>")
                        sb.append(inline(String.fromUtf8(bytes[i + 1..close]), allowRaw))
                        sb.append("</em>")
                        i = close + 1
                        plainStart = i
                        continue
                    }
                }
            }
            if (b == 0x7E && i + 1 < bytes.size && bytes[i + 1] == 0x7E) {
                let close = findDouble(bytes, i + 2, 0x7E)
                if (close > i + 2) {
                    flushPlain(bytes, plainStart, i, sb)
                    sb.append("<del>")
                    sb.append(inline(String.fromUtf8(bytes[i + 2..close]), allowRaw))
                    sb.append("</del>")
                    i = close + 2
                    plainStart = i
                    continue
                }
            }
            if (b == 0x0A) {
                // Hard break when preceded by two spaces.
                var spaceCount = 0
                var k = i
                while (k > 0 && bytes[k - 1] == 0x20) {
                    spaceCount += 1
                    k -= 1
                }
                if (spaceCount >= 2) {
                    flushPlain(bytes, plainStart, k, sb)
                    sb.append("<br>\n")
                    i += 1
                    plainStart = i
                    continue
                }
            }
            i += 1
        }
        flushPlain(bytes, plainStart, bytes.size, sb)
        sb.toString()
    }

    private func flushPlain(bytes: Array<UInt8>, start: Int64, end: Int64, sb: StringBuilder): Unit {
        if (end > start) {
            sb.append(escapeHtml(String.fromUtf8(bytes[start..end])))
        }
    }

    private func findByte(bytes: Array<UInt8>, from: Int64, target: UInt8): Int64 {
        var i = from
        while (i < bytes.size) {
            if (bytes[i] == target) {
                return i
            }
            i += 1
        }
        -1
    }

    private func findDouble(bytes: Array<UInt8>, from: Int64, target: UInt8): Int64 {
        var i = from
        while (i + 1 < bytes.size) {
            if (bytes[i] == target && bytes[i + 1] == target) {
                return i
            }
            i += 1
        }
        -1
    }

    private func findBackticks(bytes: Array<UInt8>, from: Int64, count: Int64): Int64 {
        var i = from
        while (i + count <= bytes.size) {
            var ok = true
            for (j in 0..count) {
                if (bytes[i + j] != 0x60) {
                    ok = false
                    break
                }
            }
            if (ok) {
                return i
            }
            i += 1
        }
        -1
    }
}

public class MarkdownLink {
    public let label: String
    public let url: String
    public let title: String
    public let end: Int64

    public init(label: String, url: String, title: String, end: Int64) {
        this.label = label
        this.url = url
        this.title = title
        this.end = end
    }
}

func parseLink(text: String, start: Int64): ?MarkdownLink {
    let bytes = text.toArray()
    if (start >= bytes.size || bytes[start] != 0x5B) {
        return None
    }
    let closeBracket = findMatching(bytes, start + 1, 0x5D)
    if (closeBracket < 0) {
        return None
    }
    if (closeBracket + 1 >= bytes.size || bytes[closeBracket + 1] != 0x28) {
        return None
    }
    let closeParen = findMatching(bytes, closeBracket + 2, 0x29)
    if (closeParen < 0) {
        return None
    }
    let label = String.fromUtf8(bytes[start + 1..closeBracket])
    var inner = String.fromUtf8(bytes[closeBracket + 2..closeParen]).trimAscii()
    var url = inner
    var title = ""
    let space = findSub(inner, " ")
    if (space > 0) {
        let rest = inner[space + 1..inner.size].trimAscii()
        if (rest.size >= 2 && ((rest[0] == 0x22 && rest[rest.size - 1] == 0x22) ||
                               (rest[0] == 0x27 && rest[rest.size - 1] == 0x27))) {
            title = rest[1..rest.size - 1]
            url = inner[0..space].trimAscii()
        }
    }
    if (url.size >= 2 && ((url[0] == 0x3C && url[url.size - 1] == 0x3E))) {
        url = url[1..url.size - 1]
    }
    MarkdownLink(label, url, title, closeParen + 1)
}

func findMatching(bytes: Array<UInt8>, from: Int64, target: UInt8): Int64 {
    var i = from
    var depth: Int64 = 0
    while (i < bytes.size) {
        if (bytes[i] == 0x5C && i + 1 < bytes.size) {
            i += 2
            continue
        }
        if (bytes[i] == target) {
            if (depth == 0) {
                return i
            }
            depth -= 1
        } else if ((target == 0x5D && bytes[i] == 0x5B) || (target == 0x29 && bytes[i] == 0x28)) {
            depth += 1
        }
        i += 1
    }
    -1
}

public func safeUrl(url: String): String {
    var trimmed = url.trimAscii()
    let out = ArrayList<UInt8>()
    for (b in trimmed.toArray()) {
        if (b > 0x20 && b != 0x7F) {
            out.add(b)
        }
    }
    trimmed = String.fromUtf8(out.toArray())
    let lower = trimmed.toAsciiLower()
    if (lower.startsWith("javascript:") || lower.startsWith("data:") || lower.startsWith("vbscript:") ||
        lower.startsWith("file:") || lower.startsWith("jar:")) {
        return "#"
    }
    trimmed
}
