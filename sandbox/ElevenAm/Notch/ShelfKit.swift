import Foundation

/// What a file on the shelf is, by its extension, so each agent knows whether it can take it.
enum ShelfKind: String, Codable, CaseIterable, Sendable {
    case pdf, image, video, audio, document, sheet, deck, calendar, code, folder, other

    static func of(_ url: URL, isFolder: Bool) -> ShelfKind {
        isFolder ? .folder : of(extension: url.pathExtension)
    }

    static func of(extension ext: String) -> ShelfKind {
        switch ext.lowercased() {
        case "pdf": return .pdf
        case "png", "jpg", "jpeg", "heic", "heif", "tif", "tiff", "gif", "webp", "bmp", "dng", "cr2", "cr3", "nef", "arw", "raf": return .image
        case "mov", "mp4", "m4v", "avi", "mkv", "webm": return .video
        case "mp3", "m4a", "wav", "aif", "aiff", "caf", "flac", "aac", "ogg": return .audio
        case "txt", "md", "markdown", "rtf", "docx", "doc", "html", "htm", "odt": return .document
        case "csv", "tsv", "xlsx", "xls", "numbers": return .sheet
        case "pptx", "ppt", "key": return .deck
        case "ics": return .calendar
        case "sh", "zsh", "bash", "command", "py", "js", "mjs", "ts", "swift", "rb", "go", "rs", "c", "h", "m", "json", "yml", "yaml", "toml": return .code
        default: return .other
        }
    }
}

/// What happens to a file handed to an agent.
enum ShelfAction: Equatable, Sendable {
    case ask, task, email, write, source, receipt, sheet, deck, photo, video, audio, terminal, pdf, files, note

    /// Actions that open the app so you can carry on there; the rest happen quietly and say so in the drop.
    var opensApp: Bool {
        switch self {
        case .task, .source, .receipt, .note: return false
        default: return true
        }
    }
}

/// Who takes what from the shelf, and what they do with it. One rule each, so it's clear before you let go:
/// an agent's ring opens only for files it can take.
enum ShelfRouting {
    static func action(agent: String, kinds: [ShelfKind]) -> ShelfAction? {
        guard !kinds.isEmpty else { return nil }
        func all(_ allowed: Set<ShelfKind>) -> Bool { kinds.allSatisfy { allowed.contains($0) } }
        let one = kinds.count == 1
        let noFolders = !kinds.contains(.folder)
        switch brand(agent) {
        case "11": return one && noFolders ? .ask : nil
        case "le": return noFolders && kinds.count <= 10 ? .task : nil
        case "mr": return noFolders ? .email : nil
        case "wi": return all([.document]) ? .write : nil
        case "jm": return all([.pdf, .document]) ? .source : nil
        case "ge":
            if all([.pdf, .image]) { return .receipt }
            if one && all([.sheet]) { return .sheet }
            return nil
        case "cr": return one && all([.document]) ? .deck : nil
        case "rb": return one && all([.image]) ? .photo : nil
        case "ce":
            if all([.video]) { return .video }
            if all([.audio]) { return .audio }
            return nil
        case "jo": return one && all([.folder, .code]) ? .terminal : nil
        case "bn":
            if one && all([.pdf]) { return .pdf }
            if one && all([.folder]) { return .files }
            return noFolders ? .note : nil
        default: return nil
        }
    }

    /// The words under the circles while a file hovers: "email it", "file the receipts".
    static func verb(_ action: ShelfAction, count: Int) -> String {
        let it = count == 1 ? "it" : "them"
        switch action {
        case .ask: return "ask about it"
        case .task: return count == 1 ? "make it a task" : "make them tasks"
        case .email: return "email \(it)"
        case .write: return "open \(it) in write"
        case .source: return count == 1 ? "keep it as a source" : "keep them as sources"
        case .receipt: return count == 1 ? "file the receipt" : "file the receipts"
        case .sheet: return "open it in sheets"
        case .deck: return "make a deck from it"
        case .photo: return "edit it in photo"
        case .video: return "add \(it) to video"
        case .audio: return "add \(it) to audio"
        case .terminal: return "open a terminal there"
        case .pdf: return "open it in pdf"
        case .files: return "show it in files"
        case .note: return "keep \(it) in notes"
        }
    }

    /// Older saved codes still route: mc is Marc, wm William, rt Robert, co Cole.
    private static func brand(_ code: String) -> String {
        switch code {
        case "mc": return "mr"
        case "wm": return "wi"
        case "rt": return "rb"
        case "co": return "ce"
        default: return code
        }
    }
}

/// Files kept on the shelf between drags: what was there, in order, without the ones that have gone.
enum ShelfList {
    static let limit = 24

    /// Adds files to the front, moving any already there, and keeps the shelf to its limit.
    static func adding(_ new: [String], to list: [String]) -> [String] {
        var result = list.filter { !new.contains($0) }
        result.insert(contentsOf: new.reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }, at: 0)
        return Array(result.prefix(limit))
    }

    /// A short name for a chip: the file name, with the middle taken out of a long one.
    static func chipName(_ name: String, max: Int = 26) -> String {
        guard name.count > max else { return name }
        let ext = (name as NSString).pathExtension
        let stem = (name as NSString).deletingPathExtension
        let keep = max - ext.count - 2
        guard keep > 6 else { return String(name.prefix(max - 1)) + "…" }
        let head = stem.prefix(keep - keep / 3)
        let tail = stem.suffix(keep / 3)
        return "\(head)…\(tail)" + (ext.isEmpty ? "" : ".\(ext)")
    }
}
