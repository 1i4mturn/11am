import Foundation

/// The smallest possible router: file questions go to Bolton (with search results attached),
/// everything else goes to Leo. Deterministic first, so it's instant and free.
@MainActor
enum AskRouter {
    private static let fileWords = [
        "find", "file", "files", "document", "doc", "pdf", "contract", "invoice",
        "note", "notes", "where is", "folder", "search", "spreadsheet",
    ]

    static let leoSystem = """
    You are Leo, the chief of staff inside 11am, a Mac app for founders and busy operators. \
    Answer in plain, short sentences. No emoji, no headings unless asked. If you don't know, say so.
    """

    static let boltonSystem = """
    You are Bolton, the memory and files agent inside 11am. Answer using only the excerpts provided. \
    Name the file each fact came from. If the excerpts don't answer the question, say which files look closest.
    """

    static func agent(for text: String) -> (monogram: String, name: String) {
        isAboutFiles(text) ? ("bn", "Bolton") : ("le", "Leo")
    }

    static func request(for text: String, files: FileIndex) -> BrainRequest {
        guard isAboutFiles(text), !files.files.isEmpty else {
            return BrainRequest(system: leoSystem, prompt: text, weight: .quick)
        }
        let hits = files.search(text).prefix(5)
        let context = hits.map { hit in
            "File: \(hit.file.name)\nPath: \(hit.file.path)\nExcerpt: \(hit.snippet)"
        }.joined(separator: "\n\n")
        let prompt = """
        Question: \(text)

        Possibly relevant files:
        \(context.isEmpty ? "None found." : context)
        """
        return BrainRequest(system: boltonSystem, prompt: prompt, weight: .quick)
    }

    private static func isAboutFiles(_ text: String) -> Bool {
        let lower = text.lowercased()
        return fileWords.contains { lower.contains($0) }
    }
}
