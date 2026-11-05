import Foundation

// Bolton's pages: notes that nest like a wiki, with breadcrumbs, favourites, icons, a history of versions,
// live blocks (tasks, a sheet, another page, the calendar) written as one line, comments the agents answer,
// checkboxes that become tasks, and a Notion export brought in with its nesting.
// Foundation only, so it's tested on its own.

// MARK: - The tree

/// Where a page sits and how it looks. Kept beside the Markdown file, which stays plain.
struct PageMeta: Codable, Equatable, Sendable {
    var parent: UUID?
    /// An emoji, or nil for the plain page icon.
    var icon: String?
    var favourite = false
    var order: Double = 0

    init(parent: UUID? = nil, icon: String? = nil, favourite: Bool = false, order: Double = 0) {
        self.parent = parent
        self.icon = icon
        self.favourite = favourite
        self.order = order
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        parent = try c.decodeIfPresent(UUID.self, forKey: .parent)
        icon = try c.decodeIfPresent(String.self, forKey: .icon)
        favourite = try c.decodeIfPresent(Bool.self, forKey: .favourite) ?? false
        order = try c.decodeIfPresent(Double.self, forKey: .order) ?? 0
    }

    private enum CodingKeys: String, CodingKey { case parent, icon, favourite, order }
}

enum PageTree {
    struct Row: Equatable, Sendable {
        var id: UUID
        var depth: Int
        var hasChildren: Bool
    }

    /// A page's parent, ignoring parents that no longer exist.
    static func parent(of id: UUID, metas: [UUID: PageMeta], existing: Set<UUID>) -> UUID? {
        guard let parent = metas[id]?.parent, existing.contains(parent), parent != id else { return nil }
        return parent
    }

    /// The pages directly under `parent` (nil for the top), in your order, then by title.
    static func children(of parent: UUID?, ids: [UUID], metas: [UUID: PageMeta], title: (UUID) -> String) -> [UUID] {
        let existing = Set(ids)
        return ids.filter { self.parent(of: $0, metas: metas, existing: existing) == parent }
            .sorted { a, b in
                let oa = metas[a]?.order ?? 0, ob = metas[b]?.order ?? 0
                if oa != ob { return oa < ob }
                return title(a).localizedStandardCompare(title(b)) == .orderedAscending
            }
    }

    /// The pages above this one, from the top down: the breadcrumbs. Safe against loops.
    static func path(to id: UUID, ids: [UUID], metas: [UUID: PageMeta]) -> [UUID] {
        let existing = Set(ids)
        var chain: [UUID] = []
        var seen: Set<UUID> = [id]
        var current = parent(of: id, metas: metas, existing: existing)
        while let page = current, !seen.contains(page) {
            chain.insert(page, at: 0)
            seen.insert(page)
            current = parent(of: page, metas: metas, existing: existing)
        }
        return chain
    }

    /// Everything nested under a page, at any depth.
    static func descendants(of id: UUID, ids: [UUID], metas: [UUID: PageMeta]) -> [UUID] {
        let existing = Set(ids)
        var result: [UUID] = []
        var queue = [id]
        var seen: Set<UUID> = [id]
        while !queue.isEmpty {
            let current = queue.removeFirst()
            for child in ids where parent(of: child, metas: metas, existing: existing) == current && !seen.contains(child) {
                seen.insert(child)
                result.append(child)
                queue.append(child)
            }
        }
        return result
    }

    /// A page can't go inside itself or one of its own sub-pages.
    static func canMove(_ id: UUID, under parent: UUID?, ids: [UUID], metas: [UUID: PageMeta]) -> Bool {
        guard let parent else { return true }
        return parent != id && !descendants(of: id, ids: ids, metas: metas).contains(parent)
    }

    /// The tree as rows for the sidebar, showing the children of expanded pages.
    static func rows(ids: [UUID], metas: [UUID: PageMeta], expanded: Set<UUID>, title: (UUID) -> String) -> [Row] {
        var rows: [Row] = []
        var seen: Set<UUID> = []
        func walk(_ parent: UUID?, depth: Int) {
            for id in children(of: parent, ids: ids, metas: metas, title: title) where !seen.contains(id) {
                seen.insert(id)
                let kids = children(of: id, ids: ids, metas: metas, title: title)
                rows.append(Row(id: id, depth: depth, hasChildren: !kids.isEmpty))
                if expanded.contains(id) && depth < 12 { walk(id, depth: depth + 1) }
            }
        }
        walk(nil, depth: 0)
        return rows
    }

    /// An order value that puts a page after its siblings.
    static func nextOrder(under parent: UUID?, ids: [UUID], metas: [UUID: PageMeta]) -> Double {
        let existing = Set(ids)
        let siblings = ids.filter { self.parent(of: $0, metas: metas, existing: existing) == parent }
        return (siblings.compactMap { metas[$0]?.order }.max() ?? 0) + 1
    }
}

// MARK: - Live blocks

/// A line like `{{tasks: Website relaunch}}` that shows something live in a page.
enum PageBlock: Equatable, Sendable {
    /// "today", "upcoming", "inbox", "someday", a project's name or a #tag.
    case tasks(String)
    /// A workbook's name, optionally with "!Sheet".
    case sheet(String)
    /// Another page by title: the same words in two places, always up to date.
    case page(String)
    /// "today" or "week".
    case events(String)

    var argument: String {
        switch self {
        case .tasks(let value), .sheet(let value), .page(let value), .events(let value): return value
        }
    }

    var kind: String {
        switch self {
        case .tasks: return "tasks"
        case .sheet: return "sheet"
        case .page: return "page"
        case .events: return "events"
        }
    }

    /// The line to put in a page.
    var markdown: String { "{{\(kind): \(argument)}}" }
}

enum PageBlocks {
    /// The block on a line, if the whole line is one.
    static func parse(_ line: String) -> PageBlock? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("{{"), trimmed.hasSuffix("}}"), trimmed.count > 4 else { return nil }
        let inner = trimmed.dropFirst(2).dropLast(2)
        guard let colon = inner.firstIndex(of: ":") else { return nil }
        let kind = inner[inner.startIndex..<colon].trimmingCharacters(in: .whitespaces).lowercased()
        let argument = inner[inner.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        guard !argument.isEmpty else { return nil }
        switch kind {
        case "tasks", "task", "todo": return .tasks(argument)
        case "sheet", "table": return .sheet(argument)
        case "page", "synced", "embed": return .page(argument)
        case "events", "calendar": return .events(argument)
        default: return nil
        }
    }

    /// Every block in a page, with its line number (from 0). Not inside code fences.
    static func find(in text: String) -> [(line: Int, block: PageBlock)] {
        var found: [(Int, PageBlock)] = []
        var inFence = false
        for (index, line) in text.components(separatedBy: "\n").enumerated() {
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") { inFence.toggle(); continue }
            if !inFence, let block = parse(line) { found.append((index, block)) }
        }
        return found.map { (line: $0.0, block: $0.1) }
    }

    /// Pages shown inside this one, and inside those, without going round in circles.
    static func embeddedPages(from title: String, text: (String) -> String?, limit: Int = 20) -> [String] {
        var result: [String] = []
        var seen: Set<String> = [title.lowercased()]
        var queue = [title]
        while let current = queue.first, result.count < limit {
            queue.removeFirst()
            guard let body = text(current) else { continue }
            for (_, block) in find(in: body) {
                guard case .page(let name) = block, !seen.contains(name.lowercased()) else { continue }
                seen.insert(name.lowercased())
                result.append(name)
                queue.append(name)
            }
        }
        return result
    }
}

// MARK: - History

/// A version of a page is kept when you've been writing for a while, not on every keystroke.
enum PageHistory {
    /// Keep a version when the last one is older than `interval` (10 minutes) and the words changed.
    static func shouldKeep(last: Date?, lastText: String?, now: Date, text: String, interval: TimeInterval = 600) -> Bool {
        guard text != lastText else { return false }
        guard let last else { return true }
        return now.timeIntervalSince(last) >= interval
    }

    /// Which versions to let go: the newest `recent` stay, then one a day for `days` days, then none.
    static func toDelete(_ dates: [Date], recent: Int = 20, days: Int = 60, now: Date, calendar: Calendar) -> [Date] {
        let sorted = dates.sorted(by: >)
        var keep = Set(sorted.prefix(recent))
        var daysKept: Set<Date> = []
        let cutoff = calendar.date(byAdding: .day, value: -days, to: now) ?? now
        for date in sorted.dropFirst(recent) where date >= cutoff {
            let day = calendar.startOfDay(for: date)
            if !daysKept.contains(day) {
                daysKept.insert(day)
                keep.insert(date)
            }
        }
        return sorted.filter { !keep.contains($0) }
    }

    /// "2026-11-05T09-30-12Z.md": sortable and safe in a file name.
    static func fileName(for date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date).replacingOccurrences(of: ":", with: "-") + ".md"
    }

    static func date(fromFileName name: String) -> Date? {
        guard name.hasSuffix(".md") else { return nil }
        var stem = String(name.dropLast(3))
        // Put the colons back in the time only.
        if let t = stem.firstIndex(of: "T") {
            let time = stem[stem.index(after: t)...].replacingOccurrences(of: "-", with: ":")
            stem = String(stem[...t]) + time
        }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: stem)
    }

    /// A short summary of what changed between two versions: "+3 lines, −1 line".
    static func change(from old: String, to new: String) -> String {
        let a = old.components(separatedBy: "\n")
        let b = new.components(separatedBy: "\n")
        var counts: [String: Int] = [:]
        for line in a { counts[line, default: 0] += 1 }
        var added = 0
        for line in b {
            if let n = counts[line], n > 0 { counts[line] = n - 1 } else { added += 1 }
        }
        let removed = counts.values.reduce(0, +)
        if added == 0 && removed == 0 { return "No changes" }
        var parts: [String] = []
        if added > 0 { parts.append("+\(added) line\(added == 1 ? "" : "s")") }
        if removed > 0 { parts.append("−\(removed) line\(removed == 1 ? "" : "s")") }
        return parts.joined(separator: ", ")
    }
}

// MARK: - Checkboxes

enum PageCheckboxes {
    struct Item: Equatable, Sendable {
        var line: Int
        var text: String
        var done: Bool
    }

    /// "- [ ] Call Tom tomorrow" and "* [x] Done thing", with their line numbers. Not inside code fences.
    static func items(in text: String) -> [Item] {
        var result: [Item] = []
        var inFence = false
        for (index, line) in text.components(separatedBy: "\n").enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") { inFence.toggle(); continue }
            guard !inFence else { continue }
            for marker in ["- [ ] ", "* [ ] ", "- [x] ", "* [x] ", "- [X] ", "* [X] "] where trimmed.hasPrefix(marker) {
                let body = String(trimmed.dropFirst(marker.count)).trimmingCharacters(in: .whitespaces)
                if !body.isEmpty { result.append(Item(line: index, text: body, done: marker.contains("x") || marker.contains("X"))) }
                break
            }
        }
        return result
    }

    static func open(in text: String) -> [Item] { items(in: text).filter { !$0.done } }

    /// Ticks the box on a line and, optionally, notes where the task went: "- [x] Call Tom → Tasks".
    static func tick(line: Int, in text: String, note: String? = nil) -> String {
        var lines = text.components(separatedBy: "\n")
        guard lines.indices.contains(line) else { return text }
        var row = lines[line]
        for marker in ["- [ ] ", "* [ ] "] {
            if let range = row.range(of: marker) {
                row.replaceSubrange(range, with: marker.replacingOccurrences(of: "[ ]", with: "[x]"))
                if let note, !row.hasSuffix(note) { row += " " + note }
                break
            }
        }
        lines[line] = row
        return lines.joined(separator: "\n")
    }
}

// MARK: - Comments and mentions

struct PageComment: Codable, Identifiable, Equatable, Sendable {
    var id = UUID()
    /// "you", or an agent's monogram.
    var author: String
    var text: String
    var date: Date
    var resolved = false

    init(id: UUID = UUID(), author: String, text: String, date: Date, resolved: Bool = false) {
        self.id = id
        self.author = author
        self.text = text
        self.date = date
        self.resolved = resolved
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        author = try c.decodeIfPresent(String.self, forKey: .author) ?? "you"
        text = try c.decodeIfPresent(String.self, forKey: .text) ?? ""
        date = try c.decodeIfPresent(Date.self, forKey: .date) ?? Date()
        resolved = try c.decodeIfPresent(Bool.self, forKey: .resolved) ?? false
    }

    private enum CodingKeys: String, CodingKey { case id, author, text, date, resolved }
}

enum Mentions {
    static let agents: [(name: String, monogram: String)] = [
        ("Leo", "le"), ("Marc", "mc"), ("William", "wm"), ("Bolton", "bn"), ("James", "jm"), ("George", "ge"),
        ("Conner", "cr"), ("Robert", "rt"), ("Cole", "co"), ("Harris", "hr"), ("Johnny", "jo"),
    ]

    /// The agents mentioned, in order: "@Leo and @george" → ["le", "ge"].
    static func agents(in text: String) -> [String] {
        var found: [String] = []
        let words = text.components(separatedBy: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ",.;:!?()")))
        for word in words where word.hasPrefix("@") && word.count > 1 {
            let name = word.dropFirst().lowercased()
            if let agent = agents.first(where: { $0.name.lowercased() == name }), !found.contains(agent.monogram) {
                found.append(agent.monogram)
            }
        }
        return found
    }

    /// The name to complete "@Le" with.
    static func completion(for partial: String) -> String? {
        guard partial.hasPrefix("@"), partial.count > 1 else { return nil }
        let start = partial.dropFirst().lowercased()
        return agents.first { $0.name.lowercased().hasPrefix(start) }?.name
    }
}

// MARK: - Notion exports

/// A Notion export keeps sub-pages in a folder beside the page: "Projects 1a2b….md" and "Projects 1a2b…/Website 3c4d….md".
/// Databases come as "Tasks 5e6f….csv", with each row's page in a folder of the same name.
enum NotionExport {
    struct Entry: Equatable, Sendable {
        /// The path inside the export, with "/" between folders.
        var path: String
        var title: String
        /// The path of the page this one sits under, if any.
        var parentPath: String?
        /// A database to bring in as a sheet rather than a page.
        var isDatabase: Bool
        /// A folder with no page of its own, which becomes a page to hold its children.
        var isFolderOnly: Bool
    }

    /// "Website relaunch 1a2b3c4d5e6f7a8b9c0d1e2f3a4b5c6d" → "Website relaunch". Also drops the extension.
    static func cleanName(_ name: String) -> String {
        var stem = name
        for ext in [".md", ".csv", ".markdown"] where stem.lowercased().hasSuffix(ext) { stem = String(stem.dropLast(ext.count)) }
        let pieces = stem.split(separator: " ")
        if let last = pieces.last, last.count == 32, last.allSatisfy(\.isHexDigit) {
            stem = pieces.dropLast().joined(separator: " ")
        }
        return stem.trimmingCharacters(in: .whitespaces)
    }

    /// Pages, databases and the folders between them, parents before children.
    static func entries(paths: [String]) -> [Entry] {
        let files = paths.filter { path in
            let lower = path.lowercased()
            return lower.hasSuffix(".md") || lower.hasSuffix(".markdown") || (lower.hasSuffix(".csv") && !lower.hasSuffix("_all.csv"))
        }
        var pageByFolder: [String: String] = [:]
        for file in files where !file.lowercased().hasSuffix(".csv") {
            pageByFolder[stripExtension(file)] = file
        }
        // A database's folder of row pages belongs to the database.
        var databaseByFolder: [String: String] = [:]
        for file in files where file.lowercased().hasSuffix(".csv") {
            databaseByFolder[stripExtension(file)] = file
        }
        // The page a path sits under: the folder's own page, its database, or the folder itself.
        func parent(of path: String) -> String? {
            let parts = path.split(separator: "/").map(String.init)
            guard parts.count > 1 else { return nil }
            let folder = parts.dropLast().joined(separator: "/")
            return pageByFolder[folder] ?? databaseByFolder[folder] ?? folder
        }
        var entries: [Entry] = []
        var folderPages: Set<String> = []
        let sortedFiles = files.sorted { a, b in
            let da = a.split(separator: "/").count, db = b.split(separator: "/").count
            return da != db ? da < db : a < b
        }
        for file in sortedFiles {
            let parts = file.split(separator: "/").map(String.init)
            // Folders with no page of their own become pages that hold their children.
            if parts.count > 1 {
                for depth in 1..<parts.count {
                    let folder = parts.prefix(depth).joined(separator: "/")
                    guard pageByFolder[folder] == nil, databaseByFolder[folder] == nil, !folderPages.contains(folder) else { continue }
                    folderPages.insert(folder)
                    entries.append(Entry(path: folder, title: cleanName(parts[depth - 1]), parentPath: parent(of: folder),
                                         isDatabase: false, isFolderOnly: true))
                }
            }
            entries.append(Entry(path: file, title: cleanName(parts.last ?? file), parentPath: parent(of: file),
                                 isDatabase: file.lowercased().hasSuffix(".csv"), isFolderOnly: false))
        }
        // Parents first.
        var ordered: [Entry] = []
        var placed: Set<String> = []
        var remaining = entries
        while !remaining.isEmpty {
            let before = remaining.count
            remaining.removeAll { entry in
                guard entry.parentPath.map({ placed.contains($0) }) ?? true else { return false }
                ordered.append(entry)
                placed.insert(entry.path)
                return true
            }
            if remaining.count == before {
                ordered += remaining
                break
            }
        }
        return ordered
    }

    /// An export unzips into one folder ("Export-1a2b…/"); the pages inside it are the top level.
    static func withoutCommonRoot(_ paths: [String]) -> [String] {
        let firsts = Set(paths.map { $0.split(separator: "/").first.map(String.init) ?? "" })
        guard firsts.count == 1, let root = firsts.first, !root.isEmpty,
              paths.allSatisfy({ $0.split(separator: "/").count > 1 }) else { return paths }
        return paths.map { String($0.dropFirst(root.count + 1)) }
    }

    private static func stripExtension(_ path: String) -> String {
        guard let dot = path.lastIndex(of: "."), !path[dot...].contains("/") else { return path }
        return String(path[..<dot])
    }

    /// Notion's `[Page](Page%201a2b….md)` and `[Page](Folder/Page%201a2b….md)` links become `[[Page]]`.
    static func wikiLinks(_ text: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: #"\[([^\]]+)\]\(([^)\s]+?\.md)\)"#) else { return text }
        let range = NSRange(text.startIndex..., in: text)
        var result = text
        for match in regex.matches(in: text, range: range).reversed() {
            guard let whole = Range(match.range, in: result), let label = Range(match.range(at: 1), in: result) else { continue }
            result.replaceSubrange(whole, with: "[[\(result[label])]]")
        }
        return result
    }
}
