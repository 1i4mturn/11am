import CryptoKit
import Foundation

// Bolton's extras: smart folders (a saved search, like "#acme has:todo edited:week") and locked notes
// (the words sealed with a key kept in the Keychain, opened with Touch ID or your Mac password).
// Foundation and CryptoKit only, so they're tested on their own.

struct SmartFolder: Codable, Identifiable, Hashable, Sendable {
    var id = UUID()
    var name: String
    var query: String
}

/// A search you can save. Words must all appear; `#tag`, `is:pinned`, `has:todo`, `has:link`, `in:Folder`
/// and `edited:today`, `edited:week`, `edited:month` or `edited:3d` narrow it down.
struct NoteQuery: Equatable, Sendable {
    var words: [String] = []
    var tags: [String] = []
    var pinned: Bool?
    var hasOpenTodo = false
    var hasLink = false
    var folder: String?
    /// 0 is today.
    var editedWithinDays: Int?

    static let suggestions: [SmartFolder] = [
        SmartFolder(name: "To do", query: "has:todo"),
        SmartFolder(name: "This week", query: "edited:week"),
    ]

    static func parse(_ text: String) -> NoteQuery {
        var query = NoteQuery()
        for token in text.split(separator: " ").map(String.init) where !token.isEmpty {
            let lower = token.lowercased()
            if lower.hasPrefix("#"), lower.count > 1 {
                query.tags.append(String(lower.dropFirst()))
            } else if lower == "is:pinned" {
                query.pinned = true
            } else if lower == "has:todo" || lower == "has:todos" {
                query.hasOpenTodo = true
            } else if lower == "has:link" || lower == "has:links" {
                query.hasLink = true
            } else if lower.hasPrefix("in:"), lower.count > 3 {
                query.folder = String(token.dropFirst(3)).replacingOccurrences(of: "_", with: " ")
            } else if lower.hasPrefix("edited:") {
                let value = String(lower.dropFirst("edited:".count))
                switch value {
                case "today": query.editedWithinDays = 0
                case "week": query.editedWithinDays = 7
                case "month": query.editedWithinDays = 31
                default:
                    if value.hasSuffix("d"), let days = Int(value.dropLast()) { query.editedWithinDays = days }
                }
            } else {
                query.words.append(lower)
            }
        }
        return query
    }

    var isEmpty: Bool {
        words.isEmpty && tags.isEmpty && pinned == nil && !hasOpenTodo && !hasLink && folder == nil && editedWithinDays == nil
    }

    func matches(text: String, folder: String, pinned: Bool, modified: Date, now: Date, calendar: Calendar) -> Bool {
        let lower = text.lowercased()
        if !words.allSatisfy({ lower.contains($0) }) { return false }
        if !tags.isEmpty {
            let present = Set(NoteQuery.tags(in: text))
            if !tags.allSatisfy({ present.contains($0) }) { return false }
        }
        if let wanted = self.pinned, wanted != pinned { return false }
        if hasOpenTodo, !(lower.contains("- [ ] ") || lower.contains("* [ ] ")) { return false }
        if hasLink, !(text.contains("[[") || lower.contains("http://") || lower.contains("https://")) { return false }
        if let wanted = self.folder, wanted.caseInsensitiveCompare(folder) != .orderedSame { return false }
        if let days = editedWithinDays {
            let start = calendar.date(byAdding: .day, value: -days, to: calendar.startOfDay(for: now)) ?? now
            if modified < start { return false }
        }
        return true
    }

    /// "#acme" and "#Board-deck" → ["acme", "board-deck"], not "#1" or the # in a heading.
    static func tags(in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: #"(?<![\w#&/])#([A-Za-z][\w-]*)"#) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            Range(match.range(at: 1), in: text).map { String(text[$0]).lowercased() }
        }
    }
}

enum NoteLock {
    static let marker = "11am-locked:v1:"

    enum Problem: Error, Equatable { case notLocked, damaged }

    static func isLocked(_ text: String) -> Bool { text.contains(marker) }

    /// The title stays readable (so the note can be found by name); everything else is sealed.
    static func seal(_ text: String, title: String, key: SymmetricKey) throws -> String {
        let box = try AES.GCM.seal(Data(text.utf8), using: key)
        guard let combined = box.combined else { throw Problem.damaged }
        return "# \(title)\n\n\(marker)\(combined.base64EncodedString())\n"
    }

    static func open(_ sealed: String, key: SymmetricKey) throws -> String {
        guard let range = sealed.range(of: marker) else { throw Problem.notLocked }
        let encoded = sealed[range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = Data(base64Encoded: encoded) else { throw Problem.damaged }
        do {
            let box = try AES.GCM.SealedBox(combined: data)
            let plain = try AES.GCM.open(box, using: key)
            guard let text = String(data: plain, encoding: .utf8) else { throw Problem.damaged }
            return text
        } catch let problem as Problem {
            throw problem
        } catch {
            throw Problem.damaged
        }
    }

    static func newKey() -> SymmetricKey { SymmetricKey(size: .bits256) }

    static func keyText(_ key: SymmetricKey) -> String {
        key.withUnsafeBytes { Data($0).base64EncodedString() }
    }

    static func key(from text: String) -> SymmetricKey? {
        guard let data = Data(base64Encoded: text), data.count == 32 else { return nil }
        return SymmetricKey(data: data)
    }
}
