import AppKit
import Foundation
import NaturalLanguage
import PDFKit

struct IndexedFile: Codable, Identifiable, Hashable {
    var path: String
    var name: String
    var kind: String
    var modified: Date
    var size: Int
    /// The first few thousand characters: enough for search and snippets, small enough for 8 GB.
    var text: String
    /// Sentence embedding from Apple's NaturalLanguage framework (on-device, no model download).
    var vector: [Double]?

    var id: String { path }
    var url: URL { URL(fileURLWithPath: path) }
}

struct SearchHit: Identifiable {
    let file: IndexedFile
    let score: Double
    let snippet: String
    let reason: String

    var id: String { file.path }
}

/// Bolton-lite: a small, local, incremental index of the folders you choose.
@MainActor
final class FileIndex: ObservableObject {
    @Published private(set) var folders: [URL] = []
    @Published private(set) var files: [IndexedFile] = []
    @Published private(set) var isIndexing = false
    @Published private(set) var status = "No folders yet"
    @Published private(set) var lastIndexed: Date?

    private let embedding = NLEmbedding.sentenceEmbedding(for: .english)

    private static var storeURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("11am-sandbox", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("index.json")
    }

    func load() {
        folders = (UserDefaults.standard.stringArray(forKey: "files.folders") ?? []).map { URL(fileURLWithPath: $0) }
        let url = FileIndex.storeURL
        Task { @MainActor in
            let loaded = await Task.detached(priority: .utility) { () -> [IndexedFile] in
                guard let data = try? Data(contentsOf: url) else { return [] }
                return (try? JSONDecoder().decode([IndexedFile].self, from: data)) ?? []
            }.value
            self.files = loaded
            self.status = loaded.isEmpty ? (self.folders.isEmpty ? "No folders yet" : "Not indexed yet") : "\(loaded.count) files ready"
        }
    }

    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.prompt = "Add to 11am"
        panel.message = "Choose folders for 11am to index. Files stay where they are; only a small search index is kept."
        guard panel.runModal() == .OK else { return }
        for url in panel.urls where !folders.contains(url) {
            folders.append(url)
        }
        saveFolders()
        Task { await reindex() }
    }

    func removeFolder(_ url: URL) {
        folders.removeAll { $0 == url }
        files.removeAll { $0.path.hasPrefix(url.path) }
        saveFolders()
        persist()
    }

    func reindex() async {
        guard !isIndexing else { return }
        guard !folders.isEmpty else {
            status = "Add a folder to start"
            return
        }
        isIndexing = true
        status = "Reading files…"
        let folders = self.folders
        let previous = self.files
        let result = await Task.detached(priority: .utility) {
            FileScanner.scan(folders: folders, previous: previous)
        }.value
        files = result
        lastIndexed = Date()
        isIndexing = false
        status = "\(result.count) files ready"
        persist()
    }

    func search(_ query: String) -> [SearchHit] {
        let terms = FileIndex.terms(query)
        guard !terms.isEmpty else { return [] }
        let queryVector = embedding?.vector(for: query)

        var hits: [SearchHit] = []
        for file in files {
            let name = file.name.lowercased()
            let text = file.text.lowercased()
            var score = 0.0
            var reasons: [String] = []

            let nameMatches = terms.filter { name.contains($0) }.count
            if nameMatches > 0 {
                score += Double(nameMatches) * 3
                reasons.append("name")
            }
            let textMatches = terms.filter { text.contains($0) }.count
            if textMatches > 0 {
                score += Double(textMatches) * 1.2
                reasons.append("content")
            }
            if let queryVector, let vector = file.vector {
                let similarity = FileIndex.cosine(queryVector, vector)
                if similarity > 0.35 {
                    score += similarity * 3
                    reasons.append("meaning")
                }
            }
            guard score > 0.9 else { continue }
            hits.append(SearchHit(
                file: file,
                score: score,
                snippet: FileIndex.snippet(in: file.text, terms: terms),
                reason: "matched " + reasons.joined(separator: " + ")
            ))
        }
        return Array(hits.sorted { $0.score > $1.score }.prefix(30))
    }

    /// Files changed recently, for the brief.
    func recentlyChanged(within hours: Double = 24) -> [IndexedFile] {
        let cutoff = Date().addingTimeInterval(-hours * 3600)
        return files.filter { $0.modified > cutoff }.sorted { $0.modified > $1.modified }
    }

    private func saveFolders() {
        UserDefaults.standard.set(folders.map(\.path), forKey: "files.folders")
        if folders.isEmpty { status = "No folders yet" }
    }

    private func persist() {
        let snapshot = files
        let url = FileIndex.storeURL
        Task.detached(priority: .background) {
            if let data = try? JSONEncoder().encode(snapshot) {
                try? data.write(to: url, options: .atomic)
            }
        }
    }

    // MARK: Helpers

    nonisolated static func terms(_ query: String) -> [String] {
        query.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 2 }
    }

    nonisolated static func cosine(_ a: [Double], _ b: [Double]) -> Double {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var dot = 0.0, na = 0.0, nb = 0.0
        for i in 0..<a.count {
            dot += a[i] * b[i]
            na += a[i] * a[i]
            nb += b[i] * b[i]
        }
        guard na > 0, nb > 0 else { return 0 }
        return dot / (na.squareRoot() * nb.squareRoot())
    }

    nonisolated static func snippet(in text: String, terms: [String]) -> String {
        let lower = text.lowercased()
        for term in terms {
            if let range = lower.range(of: term) {
                let offset = lower.distance(from: lower.startIndex, to: range.lowerBound)
                let start = text.index(text.startIndex, offsetBy: max(0, offset - 70), limitedBy: text.endIndex) ?? text.startIndex
                let end = text.index(start, offsetBy: 200, limitedBy: text.endIndex) ?? text.endIndex
                let piece = text[start..<end].replacingOccurrences(of: "\n", with: " ")
                return (start == text.startIndex ? "" : "…") + piece.trimmingCharacters(in: .whitespaces) + "…"
            }
        }
        return String(text.prefix(160)).replacingOccurrences(of: "\n", with: " ")
    }
}

/// Reads files off the main thread. Sequential and capped, so memory stays flat.
enum FileScanner {
    static let textExtensions: Set<String> = ["txt", "md", "markdown", "csv", "json", "swift", "py", "js", "ts", "html", "css", "yaml", "yml", "log"]
    static let richExtensions: Set<String> = ["rtf", "rtfd", "docx", "doc", "odt"]
    static let maxFiles = 4_000
    static let maxBytes = 25 * 1_024 * 1_024
    static let keptCharacters = 4_000

    static func scan(folders: [URL], previous: [IndexedFile]) -> [IndexedFile] {
        let byPath = Dictionary(previous.map { ($0.path, $0) }, uniquingKeysWith: { first, _ in first })
        let embedding = NLEmbedding.sentenceEmbedding(for: .english)
        let keys: [URLResourceKey] = [.isRegularFileKey, .contentModificationDateKey, .fileSizeKey]
        var results: [IndexedFile] = []

        for folder in folders {
            guard let enumerator = FileManager.default.enumerator(
                at: folder,
                includingPropertiesForKeys: keys,
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else { continue }

            for case let url as URL in enumerator {
                if results.count >= maxFiles { break }
                let ext = url.pathExtension.lowercased()
                guard textExtensions.contains(ext) || richExtensions.contains(ext) || ext == "pdf" else { continue }
                guard let values = try? url.resourceValues(forKeys: Set(keys)), values.isRegularFile == true else { continue }
                let size = values.fileSize ?? 0
                guard size <= maxBytes else { continue }
                let modified = values.contentModificationDate ?? Date.distantPast

                // Unchanged since last time: keep the old entry, skip the work.
                if let old = byPath[url.path], old.modified == modified, old.size == size {
                    results.append(old)
                    continue
                }

                autoreleasepool {
                    let text = extractText(url: url, ext: ext)
                    let kept = String(text.prefix(keptCharacters))
                    let sample = url.deletingPathExtension().lastPathComponent + ". " + String(kept.prefix(600))
                    results.append(IndexedFile(
                        path: url.path,
                        name: url.lastPathComponent,
                        kind: ext,
                        modified: modified,
                        size: size,
                        text: kept,
                        vector: embedding?.vector(for: sample)
                    ))
                }
            }
        }
        return results
    }

    static func extractText(url: URL, ext: String) -> String {
        if ext == "pdf" {
            guard let document = PDFDocument(url: url) else { return "" }
            var text = ""
            for index in 0..<min(document.pageCount, 6) {
                text += document.page(at: index)?.string ?? ""
                text += "\n"
                if text.count > keptCharacters { break }
            }
            return text
        }
        if richExtensions.contains(ext) {
            let attributed = try? NSAttributedString(url: url, options: [:], documentAttributes: nil)
            return attributed?.string ?? ""
        }
        if let text = try? String(contentsOf: url, encoding: .utf8) { return text }
        if let text = try? String(contentsOf: url, encoding: .isoLatin1) { return text }
        return ""
    }
}
