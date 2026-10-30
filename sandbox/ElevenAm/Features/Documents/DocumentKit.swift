import Foundation

/// William's document engine: Markdown in, structure out. Documents and notes are plain Markdown files on the Mac;
/// this reads them into lines (for the live-styled editor), blocks (for export) and inline runs (for both).
/// Foundation only, so the tests run it as it is.

// MARK: Lines

enum DocCallout: String, CaseIterable, Sendable {
    case note, tip, important, warning, caution

    var title: String { rawValue.capitalized }
}

/// One source line, classified, with where its syntax and its text are.
struct DocLine: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case blank, paragraph, heading, listItem, quote, fence, code, divider, tableRow, tableDelimiter, image
    }

    var kind: Kind
    /// The whole line, without its line break.
    var range: NSRange
    /// The syntax at the start ("## ", "- [ ] ", "> "). Empty when there is none.
    var markerRange: NSRange
    /// What reads as text, after the marker.
    var contentRange: NSRange
    /// Heading level, or list indent level (0 for the outermost).
    var level = 0
    var ordered = false
    var number = 0
    /// nil when it isn't a task item; otherwise whether it's ticked.
    var task: Bool?
    var checkboxRange: NSRange?
    var language = ""
    var callout: DocCallout?
}

enum MarkdownLines {
    static func lines(_ text: String) -> [DocLine] {
        let units = Array(text.utf16)
        let ns = text as NSString
        var ranges: [NSRange] = []
        var start = 0
        for (index, unit) in units.enumerated() where unit == 10 {
            var end = index
            if end > start && units[end - 1] == 13 { end -= 1 }
            ranges.append(NSRange(location: start, length: end - start))
            start = index + 1
        }
        var last = units.count
        if last > start && units[last - 1] == 13 { last -= 1 }
        ranges.append(NSRange(location: start, length: last - start))

        var result: [DocLine] = []
        result.reserveCapacity(ranges.count)
        var fence: (unit: UInt16, count: Int)?
        var inTable = false
        var index = 0
        while index < ranges.count {
            let range = ranges[index]
            let line = ns.substring(with: range)
            let empty = NSRange(location: range.location, length: 0)

            if let open = fence {
                if closesFence(line, open.unit, open.count) {
                    result.append(DocLine(kind: .fence, range: range, markerRange: range, contentRange: NSRange(location: NSMaxRange(range), length: 0)))
                    fence = nil
                } else {
                    result.append(DocLine(kind: .code, range: range, markerRange: empty, contentRange: range))
                }
                index += 1
                continue
            }

            if line.trimmingCharacters(in: .whitespaces).isEmpty {
                result.append(DocLine(kind: .blank, range: range, markerRange: empty, contentRange: range))
                inTable = false
                index += 1
                continue
            }

            if let match = fenceOpen.firstMatch(in: line, range: NSRange(location: 0, length: (line as NSString).length)) {
                let marker = (line as NSString).substring(with: match.range(at: 1))
                var item = DocLine(kind: .fence, range: range, markerRange: range, contentRange: NSRange(location: NSMaxRange(range), length: 0))
                item.language = match.range(at: 2).length > 0 ? (line as NSString).substring(with: match.range(at: 2)) : ""
                result.append(item)
                fence = ((marker as NSString).character(at: 0), (marker as NSString).length)
                inTable = false
                index += 1
                continue
            }

            if hasPipe(line) {
                if inTable {
                    result.append(DocLine(kind: .tableRow, range: range, markerRange: empty, contentRange: range))
                    index += 1
                    continue
                }
                if index + 1 < ranges.count, isDelimiterRow(ns.substring(with: ranges[index + 1])) {
                    result.append(DocLine(kind: .tableRow, range: range, markerRange: empty, contentRange: range))
                    let next = ranges[index + 1]
                    result.append(DocLine(kind: .tableDelimiter, range: next, markerRange: next, contentRange: NSRange(location: NSMaxRange(next), length: 0)))
                    inTable = true
                    index += 2
                    continue
                }
            }
            inTable = false

            let local = NSRange(location: 0, length: (line as NSString).length)
            if let match = heading.firstMatch(in: line, range: local) {
                let marker = shift(match.range, by: range.location)
                var item = DocLine(kind: .heading, range: range, markerRange: marker,
                                   contentRange: NSRange(location: NSMaxRange(marker), length: NSMaxRange(range) - NSMaxRange(marker)))
                item.level = match.range(at: 1).length
                result.append(item)
            } else if divider.firstMatch(in: line, range: local) != nil {
                result.append(DocLine(kind: .divider, range: range, markerRange: range, contentRange: NSRange(location: NSMaxRange(range), length: 0)))
            } else if let match = listItem.firstMatch(in: line, range: local) {
                let marker = shift(match.range, by: range.location)
                var item = DocLine(kind: .listItem, range: range, markerRange: marker,
                                   contentRange: NSRange(location: NSMaxRange(marker), length: NSMaxRange(range) - NSMaxRange(marker)))
                let indent = (line as NSString).substring(with: match.range(at: 1))
                let columns = indent.reduce(0) { $0 + ($1 == "\t" ? 4 : 1) }
                let previousLevel = result.last(where: { $0.kind == .listItem }).map(\.level) ?? -1
                item.level = min(columns / 2, previousLevel + 1)
                let symbol = (line as NSString).substring(with: match.range(at: 2))
                item.ordered = symbol.first?.isNumber == true
                item.number = Int(symbol.dropLast()) ?? 1
                if match.range(at: 4).length > 0 {
                    item.checkboxRange = shift(match.range(at: 4), by: range.location)
                    item.task = (line as NSString).substring(with: match.range(at: 5)).lowercased() == "x"
                }
                result.append(item)
            } else if let match = quote.firstMatch(in: line, range: local) {
                var marker = shift(match.range, by: range.location)
                var item = DocLine(kind: .quote, range: range, markerRange: marker, contentRange: range)
                let rest = (line as NSString).substring(from: match.range.length)
                if let tag = calloutTag.firstMatch(in: rest, range: NSRange(location: 0, length: (rest as NSString).length)),
                   let kind = DocCallout(rawValue: (rest as NSString).substring(with: tag.range(at: 1)).lowercased()) {
                    item.callout = kind
                    marker.length += tag.range.length
                }
                item.markerRange = marker
                item.contentRange = NSRange(location: NSMaxRange(marker), length: NSMaxRange(range) - NSMaxRange(marker))
                result.append(item)
            } else if imageLine.firstMatch(in: line, range: local) != nil {
                result.append(DocLine(kind: .image, range: range, markerRange: empty, contentRange: range))
            } else {
                result.append(DocLine(kind: .paragraph, range: range, markerRange: empty, contentRange: range))
            }
            index += 1
        }
        return result
    }

    private static let fenceOpen = regex(#"^ {0,3}(`{3,}|~{3,})[ \t]*([^`\s]*)"#)
    private static let heading = regex(#"^ {0,3}(#{1,6})(?:[ \t]+|$)"#)
    private static let divider = regex(#"^ {0,3}([-*_])(?:[ \t]*\1){2,}[ \t]*$"#)
    private static let listItem = regex(#"^([ \t]*)([-*+]|\d{1,9}[.)])(?:[ \t]+|$)(\[([ xX])\](?:[ \t]+|$))?"#)
    private static let quote = regex(#"^ {0,3}>[ \t]?"#)
    private static let calloutTag = regex(#"^\[!(\w+)\][ \t]*"#)
    private static let imageLine = regex(#"^[ \t]*!\[[^\]]*\]\([^)]*\)[ \t]*$"#)

    static func regex(_ pattern: String) -> NSRegularExpression {
        // The patterns are fixed and tested; a typo should fail loudly in the tests.
        try! NSRegularExpression(pattern: pattern)
    }

    private static func shift(_ range: NSRange, by offset: Int) -> NSRange {
        NSRange(location: range.location + offset, length: range.length)
    }

    private static func closesFence(_ line: String, _ unit: UInt16, _ count: Int) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        let units = Array(trimmed.utf16)
        return units.count >= count && units.allSatisfy { $0 == unit }
    }

    static func hasPipe(_ line: String) -> Bool {
        var escaped = false
        for unit in line.utf16 {
            if escaped { escaped = false; continue }
            if unit == 92 { escaped = true; continue }
            if unit == 124 { return true }
        }
        return false
    }

    static func isDelimiterRow(_ line: String) -> Bool {
        guard hasPipe(line) || line.contains("-") else { return false }
        let cells = tableCells(line)
        guard !cells.isEmpty, hasPipe(line) else { return false }
        return cells.allSatisfy { cell in
            var body = cell
            if body.hasPrefix(":") { body.removeFirst() }
            if body.hasSuffix(":") { body.removeLast() }
            return !body.isEmpty && body.allSatisfy { $0 == "-" }
        }
    }

    /// A table row's cells, split on pipes outside code and escapes, trimmed.
    static func tableCells(_ line: String) -> [String] {
        var cells: [String] = []
        var current: [UInt16] = []
        var escaped = false
        var inCode = false
        for unit in line.utf16 {
            if escaped {
                if unit != 124 { current.append(92) }
                current.append(unit)
                escaped = false
                continue
            }
            if unit == 92 { escaped = true; continue }
            if unit == 96 { inCode.toggle() }
            if unit == 124 && !inCode {
                cells.append(String(decoding: current, as: UTF16.self))
                current = []
                continue
            }
            current.append(unit)
        }
        if escaped { current.append(92) }
        cells.append(String(decoding: current, as: UTF16.self))
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("|"), !cells.isEmpty { cells.removeFirst() }
        if trimmed.hasSuffix("|"), trimmed.count > 1, !cells.isEmpty { cells.removeLast() }
        return cells.map { $0.trimmingCharacters(in: .whitespaces) }
    }
}

// MARK: Blocks

struct DocTable: Equatable, Sendable {
    enum Alignment: Equatable, Sendable { case left, center, right }

    var header: [String]
    var alignments: [Alignment]
    var rows: [[String]]

    var columns: Int { max(header.count, rows.map(\.count).max() ?? 0) }
}

struct DocBlock: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case heading(Int)
        case paragraph
        case listItem(level: Int, ordered: Bool, number: Int, task: Bool?)
        case quote(DocCallout?)
        case code(language: String)
        case table(DocTable)
        case divider
        case image(alt: String, source: String)
    }

    var kind: Kind
    /// Inline Markdown for text blocks (lines joined with line breaks), the code for code blocks.
    var text: String
    /// The lines it came from.
    var range: NSRange
}

enum MarkdownBlocks {
    static func blocks(_ markdown: String) -> [DocBlock] {
        let ns = markdown as NSString
        let lines = MarkdownLines.lines(markdown)
        var blocks: [DocBlock] = []
        var index = 0
        func content(_ line: DocLine) -> String { ns.substring(with: line.contentRange) }
        func union(_ a: NSRange, _ b: NSRange) -> NSRange { NSUnionRange(a, b) }
        func indented(_ line: DocLine) -> Bool {
            let text = ns.substring(with: line.range)
            return text.hasPrefix("  ") || text.hasPrefix("\t")
        }

        while index < lines.count {
            let line = lines[index]
            switch line.kind {
            case .blank, .code:
                index += 1
            case .heading:
                var title = content(line).trimmingCharacters(in: .whitespaces)
                // "## Title ##": closing hashes aren't part of the title.
                if let closing = title.range(of: #"\s+#+$"#, options: .regularExpression) { title.removeSubrange(closing) }
                if title.allSatisfy({ $0 == "#" }) { title = "" }
                blocks.append(DocBlock(kind: .heading(line.level), text: title, range: line.range))
                index += 1
            case .divider:
                blocks.append(DocBlock(kind: .divider, text: "", range: line.range))
                index += 1
            case .image:
                let image = MarkdownInline.parse(content(line)).first { $0.kind == .image }
                blocks.append(DocBlock(kind: .image(alt: image?.text ?? "", source: image?.url ?? ""), text: "", range: line.range))
                index += 1
            case .fence:
                var body: [String] = []
                var range = line.range
                index += 1
                while index < lines.count, lines[index].kind == .code {
                    body.append(ns.substring(with: lines[index].range))
                    range = union(range, lines[index].range)
                    index += 1
                }
                if index < lines.count, lines[index].kind == .fence {
                    range = union(range, lines[index].range)
                    index += 1
                }
                blocks.append(DocBlock(kind: .code(language: line.language), text: body.joined(separator: "\n"), range: range))
            case .tableRow, .tableDelimiter:
                var rows: [[String]] = []
                var alignments: [DocTable.Alignment] = []
                var range = line.range
                while index < lines.count, lines[index].kind == .tableRow || lines[index].kind == .tableDelimiter {
                    let current = lines[index]
                    let cells = MarkdownLines.tableCells(ns.substring(with: current.range))
                    if current.kind == .tableDelimiter {
                        alignments = cells.map { cell -> DocTable.Alignment in
                            switch (cell.hasPrefix(":"), cell.hasSuffix(":")) {
                            case (true, true): return .center
                            case (false, true): return .right
                            default: return .left
                            }
                        }
                    } else {
                        rows.append(cells)
                    }
                    range = union(range, current.range)
                    index += 1
                }
                let header = rows.first ?? []
                let table = DocTable(header: header, alignments: alignments, rows: Array(rows.dropFirst()))
                blocks.append(DocBlock(kind: .table(table), text: "", range: range))
            case .listItem:
                var text = content(line)
                var range = line.range
                index += 1
                // Indented lines straight after an item belong to it.
                while index < lines.count, lines[index].kind == .paragraph, indented(lines[index]) {
                    text += "\n" + content(lines[index]).trimmingCharacters(in: .whitespaces)
                    range = union(range, lines[index].range)
                    index += 1
                }
                let kind = DocBlock.Kind.listItem(level: line.level, ordered: line.ordered, number: line.number, task: line.task)
                blocks.append(DocBlock(kind: kind, text: text, range: range))
            case .quote:
                var parts = [content(line)]
                var range = line.range
                index += 1
                while index < lines.count, lines[index].kind == .quote, lines[index].callout == nil {
                    parts.append(content(lines[index]))
                    range = union(range, lines[index].range)
                    index += 1
                }
                while parts.count > 1, parts.last?.trimmingCharacters(in: .whitespaces).isEmpty == true { parts.removeLast() }
                blocks.append(DocBlock(kind: .quote(line.callout), text: parts.joined(separator: "\n"), range: range))
            case .paragraph:
                var parts = [content(line).trimmingCharacters(in: .whitespaces)]
                var range = line.range
                index += 1
                while index < lines.count, lines[index].kind == .paragraph {
                    parts.append(content(lines[index]).trimmingCharacters(in: .whitespaces))
                    range = union(range, lines[index].range)
                    index += 1
                }
                blocks.append(DocBlock(kind: .paragraph, text: parts.joined(separator: "\n"), range: range))
            }
        }
        return blocks
    }
}

// MARK: Inline

struct DocInline: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case text, strong, emphasis, strike, highlight, underline, code, link, wikiLink, image, tag, lineBreak
    }

    var kind: Kind
    /// Text, code, alt text, a wiki link's target or a tag's name.
    var text = ""
    var url = ""
    var children: [DocInline] = []
    /// The whole thing in the source, markers included.
    var range: NSRange
    /// The part that reads as text.
    var contentRange: NSRange
}

enum MarkdownInline {
    /// `offset` is added to every range, so the editor can pass a line's content and get document positions back.
    static func parse(_ text: String, offset: Int = 0) -> [DocInline] {
        let parser = InlineParser(units: Array(text.utf16), offset: offset)
        return parser.parse(0, parser.units.count)
    }

    /// What it reads as, with the Markdown taken out.
    static func plain(_ inlines: [DocInline]) -> String {
        inlines.map { inline in
            switch inline.kind {
            case .text, .code: return inline.text
            case .image: return inline.text
            case .tag: return "#" + inline.text
            case .lineBreak: return "\n"
            default: return plain(inline.children)
            }
        }.joined()
    }

    static func plain(_ text: String) -> String { plain(parse(text)) }

    /// Every tag and wiki link in a run of inlines, at any depth.
    static func walk(_ inlines: [DocInline], _ visit: (DocInline) -> Void) {
        for inline in inlines {
            visit(inline)
            walk(inline.children, visit)
        }
    }
}

private struct InlineParser {
    let units: [UInt16]
    let offset: Int

    private static let backslash: UInt16 = 92, backtick: UInt16 = 96, bang: UInt16 = 33, open: UInt16 = 91, close: UInt16 = 93
    private static let paren: UInt16 = 40, closeParen: UInt16 = 41, star: UInt16 = 42, underscore: UInt16 = 95
    private static let tilde: UInt16 = 126, equals: UInt16 = 61, plus: UInt16 = 43, hash: UInt16 = 35, less: UInt16 = 60
    private static let greater: UInt16 = 62, newline: UInt16 = 10, pipe: UInt16 = 124

    func range(_ start: Int, _ end: Int) -> NSRange { NSRange(location: start + offset, length: end - start) }
    func string(_ start: Int, _ end: Int) -> String { String(decoding: units[start..<end], as: UTF16.self) }

    func isSpace(_ unit: UInt16) -> Bool { unit == 32 || unit == 9 || unit == 10 || unit == 13 || unit == 0xA0 }
    func isWordUnit(_ unit: UInt16) -> Bool {
        (unit >= 48 && unit <= 57) || (unit >= 65 && unit <= 90) || (unit >= 97 && unit <= 122) || (unit > 127 && unit != 0xA0)
    }
    func isLetter(_ unit: UInt16) -> Bool { (unit >= 65 && unit <= 90) || (unit >= 97 && unit <= 122) || (unit > 127 && unit != 0xA0) }
    func isPunctuation(_ unit: UInt16) -> Bool {
        (unit >= 33 && unit <= 47) || (unit >= 58 && unit <= 64) || (unit >= 91 && unit <= 96) || (unit >= 123 && unit <= 126)
    }

    func run(_ index: Int, _ end: Int) -> Int {
        var next = index
        while next < end && units[next] == units[index] { next += 1 }
        return next - index
    }

    func parse(_ start: Int, _ end: Int) -> [DocInline] {
        var result: [DocInline] = []
        var textStart = start
        var index = start

        func flush(_ upTo: Int) {
            if upTo > textStart {
                result.append(DocInline(kind: .text, text: string(textStart, upTo), range: range(textStart, upTo), contentRange: range(textStart, upTo)))
            }
        }

        while index < end {
            let unit = units[index]
            switch unit {
            case Self.backslash where index + 1 < end && isPunctuation(units[index + 1]):
                flush(index)
                result.append(DocInline(kind: .text, text: string(index + 1, index + 2), range: range(index, index + 2), contentRange: range(index + 1, index + 2)))
                index += 2
                textStart = index
                continue
            case Self.newline:
                flush(index)
                result.append(DocInline(kind: .lineBreak, range: range(index, index + 1), contentRange: range(index, index + 1)))
                index += 1
                textStart = index
                continue
            case Self.backtick:
                if let node = codeSpan(index, end) {
                    flush(index)
                    result.append(node)
                    index = node.range.location - offset + node.range.length
                    textStart = index
                    continue
                }
                index += run(index, end)
                continue
            case Self.bang where index + 1 < end && units[index + 1] == Self.open:
                if let node = link(index + 1, end, image: true) {
                    flush(index)
                    result.append(node)
                    index = NSMaxRange(node.range) - offset
                    textStart = index
                    continue
                }
            case Self.open:
                if index + 1 < end && units[index + 1] == Self.open, let node = wikiLink(index, end) {
                    flush(index)
                    result.append(node)
                    index = NSMaxRange(node.range) - offset
                    textStart = index
                    continue
                }
                if let node = link(index, end, image: false) {
                    flush(index)
                    result.append(node)
                    index = NSMaxRange(node.range) - offset
                    textStart = index
                    continue
                }
            case Self.star, Self.underscore:
                let length = run(index, end)
                if let found = emphasis(index, length, end) {
                    flush(index + found.leftover)
                    result.append(found.node)
                    index = found.next
                    textStart = index
                    continue
                }
                index += length
                continue
            case Self.tilde, Self.equals, Self.plus:
                let length = run(index, end)
                if length >= 2, let found = paired(index, length, end) {
                    flush(index + length - 2)
                    result.append(found.node)
                    index = found.next
                    textStart = index
                    continue
                }
                index += length
                continue
            case Self.hash:
                if let node = tag(index, end) {
                    flush(index)
                    result.append(node)
                    index = NSMaxRange(node.range) - offset
                    textStart = index
                    continue
                }
            case Self.less:
                if let node = autolink(index, end) {
                    flush(index)
                    result.append(node)
                    index = NSMaxRange(node.range) - offset
                    textStart = index
                    continue
                }
            case 104, 119: // h, w
                if let node = bareURL(index, end) {
                    flush(index)
                    result.append(node)
                    index = NSMaxRange(node.range) - offset
                    textStart = index
                    continue
                }
            default:
                break
            }
            index += 1
        }
        flush(end)
        return result
    }

    private func codeSpan(_ start: Int, _ end: Int) -> DocInline? {
        let length = run(start, end)
        var index = start + length
        while index < end {
            if units[index] == Self.backtick {
                let closing = run(index, end)
                if closing == length {
                    var from = start + length
                    var to = index
                    // One space inside each end is padding: "`` `x` ``".
                    if to - from >= 2 && units[from] == 32 && units[to - 1] == 32 { from += 1; to -= 1 }
                    return DocInline(kind: .code, text: string(from, to), range: range(start, index + closing), contentRange: range(from, to))
                }
                index += closing
                continue
            }
            index += 1
        }
        return nil
    }

    /// `[text](url)`, or `![alt](source)` when `image` is set (start is the `[`).
    private func link(_ start: Int, _ end: Int, image: Bool) -> DocInline? {
        var depth = 0
        var index = start
        var closeBracket: Int?
        while index < end {
            let unit = units[index]
            if unit == Self.backslash { index += 2; continue }
            if unit == Self.backtick, let span = codeSpan(index, end) { index = NSMaxRange(span.range) - offset; continue }
            if unit == Self.open { depth += 1 }
            if unit == Self.close {
                depth -= 1
                if depth == 0 { closeBracket = index; break }
            }
            index += 1
        }
        guard let bracket = closeBracket, bracket + 1 < end, units[bracket + 1] == Self.paren else { return nil }
        var parens = 0
        var cursor = bracket + 1
        var closing: Int?
        while cursor < end {
            let unit = units[cursor]
            if unit == Self.backslash { cursor += 2; continue }
            if unit == Self.paren { parens += 1 }
            if unit == Self.closeParen {
                parens -= 1
                if parens == 0 { closing = cursor; break }
            }
            cursor += 1
        }
        guard let paren = closing else { return nil }
        var target = string(bracket + 2, paren).trimmingCharacters(in: .whitespaces)
        if target.hasPrefix("<"), let closeAngle = target.firstIndex(of: ">") {
            target = String(target[target.index(after: target.startIndex)..<closeAngle])
        } else if let space = target.firstIndex(where: { $0 == " " || $0 == "\t" }) {
            target = String(target[..<space]) // drop a "title"
        }
        let whole = range(image ? start - 1 : start, paren + 1)
        if image {
            return DocInline(kind: .image, text: string(start + 1, bracket), url: target, range: whole, contentRange: range(start + 1, bracket))
        }
        return DocInline(kind: .link, url: target, children: parse(start + 1, bracket), range: whole, contentRange: range(start + 1, bracket))
    }

    /// `[[Note]]` or `[[Note|what it says]]`.
    private func wikiLink(_ start: Int, _ end: Int) -> DocInline? {
        var index = start + 2
        while index + 1 < end {
            if units[index] == Self.newline || units[index] == Self.open { return nil }
            if units[index] == Self.close && units[index + 1] == Self.close {
                guard index > start + 2 else { return nil }
                var targetEnd = index
                var shown = (start + 2, index)
                if let bar = (start + 2..<index).first(where: { units[$0] == Self.pipe }) {
                    targetEnd = bar
                    shown = (bar + 1, index)
                }
                let target = string(start + 2, targetEnd).trimmingCharacters(in: .whitespaces)
                let label = DocInline(kind: .text, text: string(shown.0, shown.1), range: range(shown.0, shown.1), contentRange: range(shown.0, shown.1))
                return DocInline(kind: .wikiLink, text: target, children: [label], range: range(start, index + 2), contentRange: range(shown.0, shown.1))
            }
            index += 1
        }
        return nil
    }

    /// `*em*`, `**strong**`, `***both***`, and the same with underscores.
    /// Returns the node, where parsing continues, and how many opening characters are left as text.
    private func emphasis(_ start: Int, _ length: Int, _ end: Int) -> (node: DocInline, next: Int, leftover: Int)? {
        let unit = units[start]
        let after = start + length < end ? units[start + length] : 32
        let before = start > 0 ? units[start - 1] : 32
        guard !isSpace(after), unit != Self.underscore || !isWordUnit(before) else { return nil }
        var index = start + length
        while index < end {
            let current = units[index]
            if current == Self.backslash { index += 2; continue }
            if current == Self.backtick, let span = codeSpan(index, end) { index = NSMaxRange(span.range) - offset; continue }
            if current == Self.open, let node = link(index, end, image: false) { index = NSMaxRange(node.range) - offset; continue }
            if current == unit {
                let closing = run(index, end)
                let previous = units[index - 1]
                let next = index + closing < end ? units[index + closing] : 32
                if !isSpace(previous) && (unit != Self.underscore || !isWordUnit(next)) {
                    let use = min(length, closing, 3)
                    let openAt = start + length - use
                    let contentStart = start + length
                    let children = parse(contentStart, index)
                    let whole = range(openAt, index + use)
                    let node: DocInline
                    switch use {
                    case 1:
                        node = DocInline(kind: .emphasis, children: children, range: whole, contentRange: range(contentStart, index))
                    case 2:
                        node = DocInline(kind: .strong, children: children, range: whole, contentRange: range(contentStart, index))
                    default:
                        let inner = DocInline(kind: .emphasis, children: children, range: range(openAt + 2, index + 1), contentRange: range(contentStart, index))
                        node = DocInline(kind: .strong, children: [inner], range: whole, contentRange: range(openAt + 2, index + 1))
                    }
                    return (node, index + use, length - use)
                }
                index += closing
                continue
            }
            index += 1
        }
        return nil
    }

    /// `~~strike~~`, `==highlight==`, `++underline++`.
    private func paired(_ start: Int, _ length: Int, _ end: Int) -> (node: DocInline, next: Int)? {
        let unit = units[start]
        let openAt = start + length - 2
        let contentStart = start + length
        guard contentStart < end, !isSpace(units[contentStart]) else { return nil }
        var index = contentStart
        while index < end {
            let current = units[index]
            if current == Self.backslash { index += 2; continue }
            if current == Self.backtick, let span = codeSpan(index, end) { index = NSMaxRange(span.range) - offset; continue }
            if current == unit {
                let closing = run(index, end)
                if closing >= 2 && !isSpace(units[index - 1]) {
                    let kind: DocInline.Kind = unit == Self.tilde ? .strike : (unit == Self.equals ? .highlight : .underline)
                    let node = DocInline(kind: kind, children: parse(contentStart, index), range: range(openAt, index + 2), contentRange: range(contentStart, index))
                    return (node, index + 2)
                }
                index += closing
                continue
            }
            index += 1
        }
        return nil
    }

    /// `#tag` at the start of a word, starting with a letter: `#acme`, `#q3/plan`.
    private func tag(_ start: Int, _ end: Int) -> DocInline? {
        guard start + 1 < end, isLetter(units[start + 1]) else { return nil }
        if start > 0 {
            let before = units[start - 1]
            guard isSpace(before) || before == Self.paren else { return nil }
        }
        var index = start + 1
        while index < end, isWordUnit(units[index]) || units[index] == Self.underscore || units[index] == 45 || units[index] == 47 { index += 1 }
        while index > start + 2, units[index - 1] == 45 || units[index - 1] == 47 { index -= 1 }
        return DocInline(kind: .tag, text: string(start + 1, index), range: range(start, index), contentRange: range(start, index))
    }

    /// `<https://example.com>`
    private func autolink(_ start: Int, _ end: Int) -> DocInline? {
        var index = start + 1
        while index < end, units[index] != Self.greater {
            if isSpace(units[index]) || units[index] == Self.less { return nil }
            index += 1
        }
        guard index < end else { return nil }
        let target = string(start + 1, index)
        guard target.contains("://") || target.hasPrefix("mailto:") else { return nil }
        let label = DocInline(kind: .text, text: target, range: range(start + 1, index), contentRange: range(start + 1, index))
        return DocInline(kind: .link, url: target, children: [label], range: range(start, index + 1), contentRange: range(start + 1, index))
    }

    /// A bare `https://…` or `www.…` address.
    private func bareURL(_ start: Int, _ end: Int) -> DocInline? {
        if start > 0 {
            let before = units[start - 1]
            guard isSpace(before) || before == Self.paren else { return nil }
        }
        let rest = string(start, min(end, start + 8)).lowercased()
        guard rest.hasPrefix("http://") || rest.hasPrefix("https://") || rest.hasPrefix("www.") else { return nil }
        var index = start
        while index < end, !isSpace(units[index]), units[index] != Self.less { index += 1 }
        // Trailing punctuation belongs to the sentence, and a ")" only if it opened in the address.
        while index > start {
            let last = units[index - 1]
            if [46, 44, 58, 59, 33, 63, 34, 39].contains(last) { index -= 1; continue }
            if last == Self.closeParen {
                let opens = units[start..<index].filter { $0 == Self.paren }.count
                let closes = units[start..<index].filter { $0 == Self.closeParen }.count
                if closes > opens { index -= 1; continue }
            }
            break
        }
        guard index - start > 8 || (rest.hasPrefix("www.") && index - start > 5) else { return nil }
        let text = string(start, index)
        let url = text.lowercased().hasPrefix("www.") ? "https://" + text : text
        let label = DocInline(kind: .text, text: text, range: range(start, index), contentRange: range(start, index))
        return DocInline(kind: .link, url: url, children: [label], range: range(start, index), contentRange: range(start, index))
    }
}

// MARK: What's in a document

struct DocHeading: Equatable, Sendable, Identifiable {
    var level: Int
    var title: String
    /// Where the heading line starts in the source (UTF-16).
    var location: Int

    var id: Int { location }
}

struct DocStats: Equatable, Sendable {
    var words: Int
    var characters: Int
    var readingMinutes: Int
}

enum MarkdownInfo {
    static func outline(_ markdown: String) -> [DocHeading] {
        let ns = markdown as NSString
        return MarkdownLines.lines(markdown).compactMap { line in
            guard line.kind == .heading else { return nil }
            let title = MarkdownInline.plain(ns.substring(with: line.contentRange)).trimmingCharacters(in: .whitespaces)
            guard !title.isEmpty else { return nil }
            return DocHeading(level: line.level, title: title, location: line.range.location)
        }
    }

    static func stats(_ markdown: String) -> DocStats {
        let text = MarkdownPlain.text(markdown)
        var words = 0
        text.enumerateSubstrings(in: text.startIndex..<text.endIndex, options: [.byWords, .substringNotRequired]) { _, _, _, _ in words += 1 }
        let characters = text.filter { !$0.isNewline }.count
        return DocStats(words: words, characters: characters, readingMinutes: words == 0 ? 0 : max(1, Int((Double(words) / 230).rounded(.up))))
    }

    /// The first line, as a title.
    static func title(_ markdown: String) -> String {
        for block in MarkdownBlocks.blocks(markdown) {
            switch block.kind {
            case .heading, .paragraph, .listItem, .quote:
                let line = MarkdownInline.plain(block.text).split(separator: "\n").first.map(String.init) ?? ""
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty { return String(trimmed.prefix(80)) }
            default:
                continue
            }
        }
        return ""
    }

    /// `#tags`, lowercased, in order of first use.
    static func tags(_ markdown: String) -> [String] {
        var seen: [String] = []
        visitInlines(markdown) { inline in
            if inline.kind == .tag {
                let tag = inline.text.lowercased()
                if !seen.contains(tag) { seen.append(tag) }
            }
        }
        return seen
    }

    /// The notes it links to with `[[…]]`.
    static func wikiLinks(_ markdown: String) -> [String] {
        var seen: [String] = []
        visitInlines(markdown) { inline in
            if inline.kind == .wikiLink, !seen.contains(where: { $0.caseInsensitiveCompare(inline.text) == .orderedSame }) {
                seen.append(inline.text)
            }
        }
        return seen
    }

    /// Image sources, for attachments.
    static func images(_ markdown: String) -> [String] {
        var sources: [String] = []
        for block in MarkdownBlocks.blocks(markdown) {
            if case .image(_, let source) = block.kind { sources.append(source) }
        }
        visitInlines(markdown) { inline in
            if inline.kind == .image, !sources.contains(inline.url) { sources.append(inline.url) }
        }
        return sources
    }

    private static func visitInlines(_ markdown: String, _ visit: (DocInline) -> Void) {
        for block in MarkdownBlocks.blocks(markdown) {
            switch block.kind {
            case .heading, .paragraph, .listItem, .quote:
                MarkdownInline.walk(MarkdownInline.parse(block.text), visit)
            case .table(let table):
                for cell in table.header + table.rows.flatMap({ $0 }) {
                    MarkdownInline.walk(MarkdownInline.parse(cell), visit)
                }
            default:
                continue
            }
        }
    }
}

// MARK: Plain text

enum MarkdownPlain {
    static func text(_ markdown: String) -> String {
        var lines: [String] = []
        for block in MarkdownBlocks.blocks(markdown) {
            switch block.kind {
            case .heading, .paragraph:
                lines.append(MarkdownInline.plain(block.text))
            case .quote(let callout):
                let body = MarkdownInline.plain(block.text)
                lines.append(callout.map { "\($0.title): \(body)" } ?? body)
            case .listItem(let level, let ordered, let number, let task):
                let indent = String(repeating: "    ", count: level)
                let marker = task.map { $0 ? "☑" : "☐" } ?? (ordered ? "\(number)." : "•")
                lines.append("\(indent)\(marker) \(MarkdownInline.plain(block.text))")
            case .code:
                lines.append(block.text)
            case .table(let table):
                for row in [table.header] + table.rows {
                    lines.append(row.map { MarkdownInline.plain($0) }.joined(separator: "\t"))
                }
            case .divider:
                lines.append("———")
            case .image(let alt, _):
                if !alt.isEmpty { lines.append("[\(alt)]") }
            }
        }
        return lines.joined(separator: "\n")
    }
}

// MARK: HTML

enum MarkdownHTML {
    /// A whole page, ready to open in a browser or paste into a web app.
    static func document(_ markdown: String, title: String) -> String {
        """
        <!doctype html>
        <html lang="en">
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>\(escape(title))</title>
        <style>
        body { font: 17px/1.6 -apple-system, "New York", Georgia, serif; color: #1c1c1e; max-width: 46rem; margin: 3rem auto; padding: 0 1.25rem; }
        h1, h2, h3, h4, h5, h6 { font-family: -apple-system, "Helvetica Neue", sans-serif; line-height: 1.25; margin: 1.6em 0 .5em; }
        h1 { font-size: 2em; } h2 { font-size: 1.5em; } h3 { font-size: 1.25em; }
        pre { background: #f4f3f0; padding: .9rem 1rem; border-radius: 8px; overflow: auto; font-size: .85em; }
        code { font-family: ui-monospace, Menlo, monospace; background: #f4f3f0; padding: .1em .3em; border-radius: 4px; font-size: .9em; }
        pre code { background: none; padding: 0; }
        blockquote { margin: 1em 0; padding: .2em 1em; border-left: 3px solid #c8c6c0; color: #555; }
        .callout { border: 1px solid #dedcd6; border-left-width: 4px; background: #faf9f6; padding: .6em 1em; border-radius: 6px; color: inherit; }
        .callout strong.kind { display: block; font-family: -apple-system, sans-serif; font-size: .8em; letter-spacing: .06em; text-transform: uppercase; }
        table { border-collapse: collapse; margin: 1em 0; } th, td { border: 1px solid #dedcd6; padding: .4em .7em; } th { background: #f4f3f0; }
        mark { background: #fff3a3; } img { max-width: 100%; } hr { border: 0; border-top: 1px solid #dedcd6; margin: 2em 0; }
        ul.tasks { list-style: none; padding-left: 1.2em; } .tag { color: #6b6b6b; }
        </style>
        </head>
        <body>
        \(body(markdown))
        </body>
        </html>
        """
    }

    static func body(_ markdown: String) -> String {
        var html: [String] = []
        var lists: [(ordered: Bool, task: Bool, itemOpen: Bool)] = []

        func closeItem() {
            if !html.isEmpty { html[html.count - 1] += "</li>" }
        }
        func closeLists(to depth: Int) {
            while lists.count > depth {
                let list = lists.removeLast()
                if list.itemOpen { closeItem() }
                html.append(list.ordered ? "</ol>" : "</ul>")
            }
        }

        for block in MarkdownBlocks.blocks(markdown) {
            if case .listItem(let level, let ordered, let number, let task) = block.kind {
                closeLists(to: level + 1)
                if lists.count == level + 1 {
                    if lists[level].ordered != ordered || lists[level].task != (task != nil) {
                        closeLists(to: level)
                    } else if lists[level].itemOpen {
                        closeItem()
                        lists[level].itemOpen = false
                    }
                }
                while lists.count < level + 1 {
                    let tasks = task != nil && lists.count == level
                    if ordered && lists.count == level {
                        html.append(number == 1 ? "<ol>" : "<ol start=\"\(number)\">")
                    } else {
                        html.append(tasks ? "<ul class=\"tasks\">" : "<ul>")
                    }
                    lists.append((ordered && lists.count == level, tasks, false))
                }
                let box = task.map { $0 ? "<input type=\"checkbox\" checked disabled> " : "<input type=\"checkbox\" disabled> " } ?? ""
                html.append("<li>\(box)\(inline(block.text))")
                lists[level].itemOpen = true
                continue
            }
            closeLists(to: 0)
            switch block.kind {
            case .heading(let level):
                html.append("<h\(level)>\(inline(block.text))</h\(level)>")
            case .paragraph:
                html.append("<p>\(inline(block.text))</p>")
            case .quote(let callout):
                if let callout {
                    html.append("<blockquote class=\"callout \(callout.rawValue)\"><strong class=\"kind\">\(callout.title)</strong>\(inline(block.text))</blockquote>")
                } else {
                    html.append("<blockquote><p>\(inline(block.text))</p></blockquote>")
                }
            case .code(let language):
                let attribute = language.isEmpty ? "" : " class=\"language-\(escape(language))\""
                html.append("<pre><code\(attribute)>\(escape(block.text))</code></pre>")
            case .table(let table):
                var rows = ["<table>", "<thead><tr>"]
                for (column, cell) in table.header.enumerated() {
                    rows.append("<th\(align(table, column))>\(inline(cell))</th>")
                }
                rows.append("</tr></thead><tbody>")
                for row in table.rows {
                    rows.append("<tr>")
                    for column in 0..<table.columns {
                        rows.append("<td\(align(table, column))>\(inline(column < row.count ? row[column] : ""))</td>")
                    }
                    rows.append("</tr>")
                }
                rows.append("</tbody></table>")
                html.append(rows.joined())
            case .divider:
                html.append("<hr>")
            case .image(let alt, let source):
                html.append("<figure><img src=\"\(escape(source))\" alt=\"\(escape(alt))\">\(alt.isEmpty ? "" : "<figcaption>\(escape(alt))</figcaption>")</figure>")
            case .listItem:
                break
            }
        }
        closeLists(to: 0)
        return html.joined(separator: "\n")
    }

    static func inline(_ markdown: String) -> String { render(MarkdownInline.parse(markdown)) }

    static func render(_ inlines: [DocInline]) -> String {
        inlines.map { inline in
            switch inline.kind {
            case .text: return escape(inline.text)
            case .strong: return "<strong>\(render(inline.children))</strong>"
            case .emphasis: return "<em>\(render(inline.children))</em>"
            case .strike: return "<del>\(render(inline.children))</del>"
            case .highlight: return "<mark>\(render(inline.children))</mark>"
            case .underline: return "<u>\(render(inline.children))</u>"
            case .code: return "<code>\(escape(inline.text))</code>"
            case .link: return "<a href=\"\(escape(inline.url))\">\(render(inline.children))</a>"
            case .wikiLink: return "<a class=\"note\" href=\"#\(escape(inline.text))\">\(render(inline.children))</a>"
            case .image: return "<img src=\"\(escape(inline.url))\" alt=\"\(escape(inline.text))\">"
            case .tag: return "<span class=\"tag\">#\(escape(inline.text))</span>"
            case .lineBreak: return "<br>\n"
            }
        }.joined()
    }

    private static func align(_ table: DocTable, _ column: Int) -> String {
        guard column < table.alignments.count else { return "" }
        switch table.alignments[column] {
        case .left: return ""
        case .center: return " style=\"text-align:center\""
        case .right: return " style=\"text-align:right\""
        }
    }

    static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}

// MARK: Page setup

/// How a document prints and exports: paper, orientation, margins, header and page numbers.
struct PageSetup: Codable, Equatable, Sendable {
    enum Paper: String, Codable, CaseIterable, Identifiable, Sendable {
        case a4, letter, legal

        var id: String { rawValue }
        var title: String { self == .a4 ? "A4" : rawValue.capitalized }

        /// In points, portrait.
        var size: (width: Double, height: Double) {
            switch self {
            case .a4: return (595.28, 841.89)
            case .letter: return (612, 792)
            case .legal: return (612, 1008)
            }
        }
    }

    var paper: Paper = Locale.current.region?.identifier == "US" ? .letter : .a4
    var landscape = false
    /// In points (72 to the inch).
    var margin: Double = 64
    var showsTitle = true
    var pageNumbers = true

    var pageSize: (width: Double, height: Double) {
        let size = paper.size
        return landscape ? (size.height, size.width) : size
    }
}
