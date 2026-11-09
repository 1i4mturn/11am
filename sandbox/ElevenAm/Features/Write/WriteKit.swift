import Foundation

// William's writing tools that don't need a brain: comments that follow their passage as the text changes, finding
// your own material for a draft, the shape of another document, a summary put in the right place, and long documents
// split for translating.

// MARK: - Comments

struct DocReply: Identifiable, Codable, Equatable, Sendable {
    var id = UUID()
    var author: String
    var body: String
    var created: Date
}

/// A comment on a passage, with its replies. It remembers the passage and a little of what came before it, so it
/// stays on the right words when the text around it changes.
struct DocComment: Identifiable, Codable, Equatable, Sendable {
    var id = UUID()
    var quote: String
    var before: String
    var body: String
    var author: String
    var created: Date
    var replies: [DocReply] = []
    var resolved = false

    var asksWilliam: Bool { DocAnchors.mentionsWilliam(body) || replies.last.map { DocAnchors.mentionsWilliam($0.body) } == true }
}

enum DocAnchors {
    static let context = 32

    /// A comment on the passage at this range.
    static func comment(on range: NSRange, in text: String, body: String, author: String = "You", date: Date = Date()) -> DocComment? {
        let ns = text as NSString
        guard range.location != NSNotFound, range.length > 0, NSMaxRange(range) <= ns.length else { return nil }
        let quote = ns.substring(with: range)
        guard !quote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let start = max(0, range.location - context)
        let before = ns.substring(with: NSRange(location: start, length: range.location - start))
        return DocComment(quote: quote, before: before, body: body, author: author, created: date)
    }

    /// Where the passage is now: of every place the words appear, the one whose lead-in matches best. Nil when the
    /// words are gone.
    static func locate(_ comment: DocComment, in text: String) -> NSRange? {
        let ns = text as NSString
        guard !comment.quote.isEmpty else { return nil }
        var found: [NSRange] = []
        var search = NSRange(location: 0, length: ns.length)
        while search.length > 0 {
            let range = ns.range(of: comment.quote, options: [], range: search)
            guard range.location != NSNotFound else { break }
            found.append(range)
            let next = range.location + max(1, range.length)
            search = NSRange(location: next, length: max(0, ns.length - next))
        }
        guard !found.isEmpty else { return nil }
        guard found.count > 1 else { return found[0] }
        let want = Array(comment.before.utf16)
        func score(_ range: NSRange) -> Int {
            let start = max(0, range.location - want.count)
            let have = Array(ns.substring(with: NSRange(location: start, length: range.location - start)).utf16)
            var matched = 0
            while matched < min(want.count, have.count), want[want.count - 1 - matched] == have[have.count - 1 - matched] { matched += 1 }
            return matched
        }
        var best = found[0]
        var bestScore = score(best)
        for range in found.dropFirst() {
            let value = score(range)
            if value > bestScore { best = range; bestScore = value }
        }
        return best
    }

    /// The words to show for a comment: the passage, shortened.
    static func excerpt(_ comment: DocComment, length: Int = 60) -> String {
        let flat = comment.quote.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespaces)
        return flat.count > length ? String(flat.prefix(length - 1)) + "…" : flat
    }

    static func mentionsWilliam(_ text: String) -> Bool {
        text.range(of: #"@william\b"#, options: [.regularExpression, .caseInsensitive]) != nil
    }

    /// Open comments first, in the order their passages appear; ones whose words are gone after those; resolved last.
    static func ordered(_ comments: [DocComment], in text: String) -> [DocComment] {
        func key(_ comment: DocComment) -> (Int, Int, Date) {
            if comment.resolved { return (2, 0, comment.created) }
            guard let range = locate(comment, in: text) else { return (1, 0, comment.created) }
            return (0, range.location, comment.created)
        }
        return comments.sorted { key($0) < key($1) }
    }
}

// MARK: - Your own material

/// A note, file or document Bolton found for a draft.
struct DraftMaterial: Identifiable, Equatable, Sendable {
    var id: String
    var title: String
    var kind: String
    var text: String
    var date: Date
}

enum MaterialFinder {
    static let ignored: Set<String> = ["the", "and", "for", "with", "from", "using", "use", "our", "your", "my", "a", "an", "of", "to", "in",
                                       "on", "last", "this", "that", "week", "weeks", "month", "write", "draft", "make", "about", "into",
                                       "based", "some", "notes", "note", "doc", "document", "file", "files", "please", "can", "you", "me",
                                       "what", "we", "it", "is", "are", "be", "out", "up"]

    /// The words that matter in a request: "a proposal for Acme using last week's call notes and our pricing sheet" →
    /// proposal, acme, call, pricing, sheet.
    static func terms(_ request: String) -> [String] {
        var seen: [String] = []
        let words = request.lowercased()
            .replacingOccurrences(of: "'s", with: "")
            .replacingOccurrences(of: "’s", with: "")
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
        for word in words where word.count >= 3 && !ignored.contains(word) && !seen.contains(word) {
            seen.append(word)
        }
        return seen
    }

    /// How far back the request looks: "last week" is two weeks, "this month" or "last month" six, otherwise none.
    static func window(_ request: String) -> TimeInterval? {
        let text = request.lowercased()
        if text.contains("today") || text.contains("yesterday") { return 2 * 86_400 }
        if text.contains("week") { return 14 * 86_400 }
        if text.contains("month") { return 42 * 86_400 }
        return nil
    }

    static func count(_ term: String, in text: String) -> Int {
        var total = 0
        var range = text.startIndex..<text.endIndex
        while let found = text.range(of: term, options: [.caseInsensitive, .diacriticInsensitive], range: range) {
            total += 1
            range = found.upperBound..<text.endIndex
            if total >= 20 { break }
        }
        return total
    }

    /// The best matches: words in the title count most, then in the text; recent items win ties, and items outside a
    /// "last week" window drop back.
    static func rank(_ request: String, _ items: [DraftMaterial], now: Date, limit: Int = 5) -> [DraftMaterial] {
        let words = terms(request)
        guard !words.isEmpty else { return [] }
        let window = window(request)
        let scored: [(item: DraftMaterial, score: Double)] = items.compactMap { item in
            var score = 0.0
            var matched = 0
            for word in words {
                let inTitle = count(word, in: item.title)
                let inText = count(word, in: item.text)
                if inTitle + inText > 0 { matched += 1 }
                score += Double(inTitle) * 4 + min(Double(inText), 6)
            }
            guard matched > 0 else { return nil }
            score *= Double(matched) / Double(words.count) + 0.5
            if let window {
                score *= now.timeIntervalSince(item.date) <= window ? 1.6 : 0.6
            }
            return (item, score)
        }
        return scored.sorted { $0.score == $1.score ? $0.item.date > $1.item.date : $0.score > $1.score }.prefix(limit).map(\.item)
    }

    /// The part of an item around the first word that matters, so the prompt holds what's relevant.
    static func excerpt(_ item: DraftMaterial, terms: [String], length: Int = 1_500) -> String {
        let text = item.text
        guard text.count > length else { return text }
        let first = terms.compactMap { text.range(of: $0, options: [.caseInsensitive, .diacriticInsensitive])?.lowerBound }.min() ?? text.startIndex
        let offset = text.distance(from: text.startIndex, to: first)
        let start = text.index(text.startIndex, offsetBy: max(0, min(offset - length / 4, text.count - length)))
        let end = text.index(start, offsetBy: length, limitedBy: text.endIndex) ?? text.endIndex
        return (start > text.startIndex ? "…" : "") + String(text[start..<end]) + (end < text.endIndex ? "…" : "")
    }
}

// MARK: - The shape of a document

enum DocShape {
    /// Another document's headings, as an outline to follow: "# Proposal\n## Background\n## Price".
    static func outline(_ markdown: String) -> String {
        MarkdownInfo.outline(markdown).map { String(repeating: "#", count: max(1, $0.level)) + " " + $0.title }.joined(separator: "\n")
    }

    static let summaryMark = "> **Summary:**"

    /// Puts a summary under the title as a quote that starts "Summary:", replacing one that's already there.
    static func insertSummary(_ summary: String, into markdown: String) -> String {
        let body = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return markdown }
        var lines = markdown.components(separatedBy: "\n")
        // An old summary goes first: its quote lines and the blank line after.
        if let start = lines.firstIndex(where: { $0.hasPrefix(summaryMark) }) {
            var end = start + 1
            while end < lines.count, lines[end].hasPrefix(">") { end += 1 }
            if end < lines.count, lines[end].trimmingCharacters(in: .whitespaces).isEmpty { end += 1 }
            lines.removeSubrange(start..<end)
        }
        let quoted = body.components(separatedBy: "\n").enumerated().map { index, line in
            index == 0 ? "\(summaryMark) \(line)" : (line.isEmpty ? ">" : "> \(line)")
        }
        let block = quoted + [""]
        if let title = lines.firstIndex(where: { $0.hasPrefix("# ") }) {
            var at = title + 1
            while at < lines.count, lines[at].trimmingCharacters(in: .whitespaces).isEmpty { at += 1 }
            lines.insert(contentsOf: block, at: at)
            if at == title + 1 { lines.insert("", at: at) }
        } else {
            lines.insert(contentsOf: block, at: 0)
        }
        return lines.joined(separator: "\n").replacingOccurrences(of: "\n\n\n+", with: "\n\n", options: .regularExpression)
    }

    /// Long documents in parts that break between paragraphs, for translating a piece at a time.
    static func chunks(_ markdown: String, limit: Int = 5_000) -> [String] {
        let paragraphs = markdown.components(separatedBy: "\n\n")
        var parts: [String] = []
        var current = ""
        for paragraph in paragraphs {
            let addition = current.isEmpty ? paragraph : "\n\n" + paragraph
            if current.count + addition.count > limit && !current.isEmpty {
                parts.append(current)
                current = paragraph
            } else {
                current += addition
            }
        }
        if !current.isEmpty || parts.isEmpty { parts.append(current) }
        return parts
    }

    static let languages = ["French", "Spanish", "Italian", "German", "Portuguese", "Japanese", "Chinese (Simplified)", "Korean",
                            "Vietnamese", "Indonesian", "Hindi", "Arabic", "Greek", "Dutch"]
}
