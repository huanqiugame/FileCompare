import Foundation
import Kanna

/// Converts HTML into the canonical Markdown subset used by the diff view.
///
/// Kanna is a thin Swift wrapper around the system libxml2 HTML parser. It
/// keeps the app small (no bundled HTML parser) while still handling malformed
/// markup and decoding entities. The Markdown mapping itself is intentionally
/// limited to the constructs the renderer and diff view understand: headings,
/// paragraphs, lists, tables, links, code, emphasis and hard breaks.
enum HTMLMarkdownRenderer {
    private typealias Node = Kanna.XMLElement

    private static let skippedTags: Set<String> = [
        "script", "style", "head", "title", "meta", "link", "noscript", "template",
        "iframe", "object", "embed", "video", "audio", "svg", "canvas", "img",
        "picture", "source", "track", "input", "textarea", "select", "option"
    ]

    private static let blockTags: Set<String> = [
        "address", "article", "aside", "blockquote", "details", "dialog", "dd",
        "div", "dl", "dt", "fieldset", "figcaption", "figure", "footer", "form",
        "h1", "h2", "h3", "h4", "h5", "h6", "header", "hgroup", "hr", "li",
        "main", "nav", "ol", "p", "pre", "section", "table", "ul"
    ]

    /// Converts a complete HTML document or fragment to Markdown source.
    static func markdown(fromHTML html: String) throws -> String {
        guard !html.isEmpty else { return "" }

        let document = try HTML(html: html, encoding: .utf8)
        guard let root = document.body else { return "" }
        return blockChildren(of: root, depth: 0).joined(separator: "\n")
    }

    // MARK: - Block rendering

    private static func blockChildren(of element: Node, depth: Int) -> [String] {
        var lines: [String] = []
        var buffer = ""
        var hasBlock = false

        func appendBlock(_ block: [String]) {
            guard !block.isEmpty else { return }
            // Blank lines keep Markdown blocks separate. Without them a table
            // directly after a list is parsed as a lazy continuation of the
            // last list item.
            if hasBlock {
                lines.append("")
            }
            lines.append(contentsOf: block)
            hasBlock = true
        }

        func flush() {
            let paragraph = paragraphLines(from: buffer)
            buffer = ""
            appendBlock(paragraph)
        }

        for child in directNodes(of: element) {
            guard let tag = child.tagName?.lowercased() else { continue }

            if tag == "text" {
                buffer += escapeText(child.text ?? "")
            } else if skippedTags.contains(tag) {
                continue
            } else if blockTags.contains(tag) {
                flush()
                appendBlock(blockLines(of: child, depth: depth))
            } else {
                buffer += inlineMarkdown(of: child)
            }
        }

        flush()
        return lines
    }

    private static func blockLines(of element: Node, depth: Int) -> [String] {
        guard let tag = element.tagName?.lowercased() else { return [] }
        if skippedTags.contains(tag) { return [] }

        switch tag {
        case "h1", "h2", "h3", "h4", "h5", "h6":
            let level = Int(tag.dropFirst()) ?? 1
            let content = normalizeInline(inlineChildren(of: element))
            guard !content.isEmpty else { return [] }
            return [String(repeating: "#", count: level) + " " + content]
        case "ul":
            return listLines(of: element, depth: depth, ordered: false)
        case "ol":
            return listLines(of: element, depth: depth, ordered: true)
        case "pre":
            return codeBlockLines(of: element)
        case "table":
            return tableLines(of: element)
        case "blockquote":
            return blockChildren(of: element, depth: depth).map {
                $0.isEmpty ? ">" : "> " + $0
            }
        case "hr":
            return ["---"]
        case "p", "li", "dt", "dd", "figcaption":
            return paragraphLines(from: inlineChildren(of: element))
        default:
            return blockChildren(of: element, depth: depth)
        }
    }

    private static func listLines(of element: Node, depth: Int, ordered: Bool) -> [String] {
        var lines: [String] = []
        let indent = String(repeating: "  ", count: depth)
        let items = element.children.filter { $0.tagName?.lowercased() == "li" }

        for (index, item) in items.enumerated() {
            var buffer = ""
            for child in directNodes(of: item) {
                guard let tag = child.tagName?.lowercased() else { continue }
                if tag == "ul" || tag == "ol" { continue }

                if tag == "text" {
                    buffer += escapeText(child.text ?? "")
                } else if skippedTags.contains(tag) {
                    continue
                } else if blockTags.contains(tag) {
                    buffer += "\n" + blockLines(of: child, depth: depth + 1).joined(separator: "\n")
                } else {
                    buffer += inlineMarkdown(of: child)
                }
            }

            let contentLines = paragraphLines(from: buffer)
            let marker = ordered ? "\(index + 1). " : "- "
            if contentLines.isEmpty {
                lines.append(indent + marker.trimmingCharacters(in: .whitespaces))
            } else {
                lines.append(indent + marker + contentLines[0])
                for line in contentLines.dropFirst() {
                    lines.append(indent + "  " + line)
                }
            }

            for nested in item.children {
                guard let nestedTag = nested.tagName?.lowercased(),
                      nestedTag == "ul" || nestedTag == "ol" else { continue }
                lines.append(contentsOf: listLines(
                    of: nested,
                    depth: depth + 1,
                    ordered: nestedTag == "ol"
                ))
            }
        }

        return lines
    }

    private static func tableLines(of element: Node) -> [String] {
        var rows: [Node] = []
        for child in element.children {
            guard let tag = child.tagName?.lowercased() else { continue }
            if tag == "tr" {
                rows.append(child)
            } else if tag == "tbody" || tag == "thead" || tag == "tfoot" {
                rows.append(contentsOf: child.children.filter {
                    $0.tagName?.lowercased() == "tr"
                })
            }
        }
        guard !rows.isEmpty else { return [] }

        var lines: [String] = []
        for (index, row) in rows.enumerated() {
            let cells = row.children.filter {
                let tag = $0.tagName?.lowercased()
                return tag == "td" || tag == "th"
            }
            let values = cells.map {
                normalizeInline(inlineChildren(of: $0, inTable: true))
            }
            lines.append("| " + values.joined(separator: " | ") + " |")

            // GFM tables require a delimiter row directly after the first row.
            if index == 0 {
                lines.append("| " + values.map { _ in "---" }.joined(separator: " | ") + " |")
            }
        }
        return lines
    }

    private static func codeBlockLines(of element: Node) -> [String] {
        let raw = (element.text ?? "")
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        guard !raw.isEmpty else { return [] }

        var lines = raw.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        while lines.last?.isEmpty == true { lines.removeLast() }
        guard !lines.isEmpty else { return [] }

        let fence = raw.contains("```") ? "~~~" : "```"
        return [fence] + lines + [fence]
    }

    // MARK: - Inline rendering

    private static func directNodes(of element: Node) -> [Node] {
        let object = element.xpath("node()")
        guard object.count > 0 else { return [] }
        return (0..<object.count).map { object[$0] }
    }

    private static func inlineChildren(of element: Node, inTable: Bool = false) -> String {
        directNodes(of: element)
            .map { inlineMarkdown(of: $0, inTable: inTable) }
            .joined()
    }

    private static func inlineMarkdown(of node: Node, inTable: Bool = false) -> String {
        guard let tag = node.tagName?.lowercased() else { return "" }
        if tag == "text" { return escapeText(node.text ?? "", inTable: inTable) }
        if skippedTags.contains(tag) { return "" }

        switch tag {
        case "br":
            // A vertical tab survives whitespace normalization and is turned
            // into a Markdown hard break by `paragraphLines`.
            return "\u{000B}"
        case "strong", "b":
            return wrap(inlineChildren(of: node, inTable: inTable), prefix: "**", suffix: "**")
        case "em", "i":
            return wrap(inlineChildren(of: node, inTable: inTable), prefix: "*", suffix: "*")
        case "del", "s", "strike":
            return wrap(inlineChildren(of: node, inTable: inTable), prefix: "~~", suffix: "~~")
        case "code":
            let raw = node.text ?? ""
            guard !raw.contains("\n") else { return escapeText(raw, inTable: inTable) }
            let fence = raw.contains("`") ? "``" : "`"
            return "\(fence)\(raw)\(fence)"
        case "a":
            let content = inlineChildren(of: node, inTable: inTable)
            guard let href = node["href"], !href.isEmpty else { return content }
            let core = content.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !core.isEmpty else { return content }
            return "[\(core)](\(escapeURL(href)))"
        default:
            return inlineChildren(of: node, inTable: inTable)
        }
    }

    private static func wrap(_ content: String, prefix: String, suffix: String) -> String {
        let core = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !core.isEmpty else { return content }

        let leading = String(content.prefix { $0.isWhitespace })
        let trailing = String(content.reversed().prefix { $0.isWhitespace }.reversed())
        return leading + prefix + core + suffix + trailing
    }

    // MARK: - Normalization and escaping

    private static func paragraphLines(from raw: String) -> [String] {
        let segments = raw.split(separator: "\u{000B}", omittingEmptySubsequences: false)
        return segments.enumerated().compactMap { index, segment in
            let normalized = normalizeInline(String(segment))
            guard !normalized.isEmpty else { return nil }
            let hardBreak = index < segments.count - 1 ? "  " : ""
            return protectLineStart(normalized) + hardBreak
        }
    }

    private static func normalizeInline(_ raw: String) -> String {
        raw
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .replacingOccurrences(of: "\u{000B}", with: " ")
            .replacingOccurrences(
                of: "[\\t\\r\\n\\f ]+",
                with: " ",
                options: .regularExpression
            )
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func protectLineStart(_ line: String) -> String {
        guard let first = line.first else { return line }
        if "#-+>".contains(first) {
            return "\\" + line
        }
        if first.isNumber, let dot = line.firstIndex(of: "."),
           line[..<dot].allSatisfy(\.isNumber) {
            return "\\" + line
        }
        return line
    }

    private static func escapeText(_ text: String, inTable: Bool = false) -> String {
        var result = ""
        result.reserveCapacity(text.count)

        for character in text {
            switch character {
            case "\\", "*", "_", "[", "]", "`", "<", ">":
                result.append("\\")
                result.append(character)
            case "|" where inTable:
                result.append("\\|")
            default:
                result.append(character)
            }
        }
        return result
    }

    private static func escapeURL(_ url: String) -> String {
        url
            .replacingOccurrences(of: ")", with: "%29")
            .replacingOccurrences(of: " ", with: "%20")
            .replacingOccurrences(of: "\"", with: "%22")
    }
}
