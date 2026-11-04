import Foundation

// Johnny's scripts engine: languages, running, which apps a script controls, scripting dictionaries and colouring.
// No UI here, so it's tested on its own.

enum ScriptLanguage: String, Codable, CaseIterable, Identifiable, Sendable {
    case appleScript, javaScript, shell, python

    var id: String { rawValue }

    var title: String {
        switch self {
        case .appleScript: return "AppleScript"
        case .javaScript: return "JavaScript"
        case .shell: return "Shell"
        case .python: return "Python"
        }
    }

    var fileExtension: String {
        switch self {
        case .appleScript: return "applescript"
        case .javaScript: return "js"
        case .shell: return "sh"
        case .python: return "py"
        }
    }

    /// AppleScript and JavaScript for Automation run through macOS's own scripting engine.
    var isOSA: Bool { self == .appleScript || self == .javaScript }

    static func from(extension value: String) -> ScriptLanguage? {
        switch value.lowercased() {
        case "applescript", "scpt", "scptd": return .appleScript
        case "js", "jxa": return .javaScript
        case "sh", "zsh", "bash", "command": return .shell
        case "py": return .python
        default: return nil
        }
    }

    /// The program that runs a script file, and its arguments.
    func command(for file: URL) -> (executable: String, arguments: [String]) {
        switch self {
        case .appleScript: return ("/usr/bin/osascript", [file.path])
        case .javaScript: return ("/usr/bin/osascript", ["-l", "JavaScript", file.path])
        case .shell: return ("/bin/zsh", [file.path])
        case .python: return ("/usr/bin/env", ["python3", file.path])
        }
    }

    /// One-line comments, for "comment out" and the colouring.
    var lineComment: String {
        switch self {
        case .appleScript: return "--"
        case .javaScript: return "//"
        case .shell, .python: return "#"
        }
    }
}

/// A script as kept in the library.
struct ScriptDocument: Codable, Identifiable, Hashable, Sendable {
    var id = UUID()
    var name: String
    var language: ScriptLanguage
    var source: String
    var modified = Date()
    /// The set of apps you said this script may control.
    var approvedApps: [String] = []
}

/// The apps a script will control, read from its source.
enum ScriptApps {
    static func controlled(by source: String, language: ScriptLanguage) -> [String] {
        let patterns: [String]
        switch language {
        case .appleScript:
            patterns = [#"\btell\s+(?:application|app)\s+"([^"]+)""#, #"\b(?:application|app)\s+"([^"]+)""#]
        case .javaScript:
            patterns = [#"Application\(\s*["']([^"']+)["']\s*\)"#]
        case .shell, .python:
            patterns = [#"osascript[^\n]*tell\s+(?:application|app)\s+\\?"([^"\\]+)\\?""#, #"open\s+-a\s+["']?([A-Za-z0-9 ._-]+?)["']?(?:\s|$)"#]
        }
        var found: [String] = []
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
            let range = NSRange(source.startIndex..., in: source)
            for match in regex.matches(in: source, range: range) {
                guard let captured = Range(match.range(at: 1), in: source) else { continue }
                let name = String(source[captured]).trimmingCharacters(in: .whitespaces)
                if !name.isEmpty, !found.contains(where: { $0.caseInsensitiveCompare(name) == .orderedSame }),
                   !["currentapplication", "current application"].contains(name.lowercased()) {
                    found.append(name)
                }
            }
        }
        return found
    }

    /// The apps that still need your OK before the script runs.
    static func needingApproval(_ document: ScriptDocument) -> [String] {
        let approved = Set(document.approvedApps.map { $0.lowercased() })
        return controlled(by: document.source, language: document.language).filter { !approved.contains($0.lowercased()) }
    }
}

/// Runs a script in its own process, streaming what it prints. AppleScript's `log` and errors arrive on the error stream.
final class ScriptRun: @unchecked Sendable {
    private let process = Process()
    private let output = Pipe()
    private let errors = Pipe()
    private(set) var file: URL
    var onOutput: ((String) -> Void)?
    var onLog: ((String) -> Void)?
    var onExit: ((Int32) -> Void)?

    init(source: String, language: ScriptLanguage, input: String? = nil, directory: URL? = nil, environment: [String: String] = [:]) throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("11am-scripts", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        file = folder.appendingPathComponent("run-\(UUID().uuidString).\(language.fileExtension)")
        try source.write(to: file, atomically: true, encoding: .utf8)
        let command = language.command(for: file)
        process.executableURL = URL(fileURLWithPath: command.executable)
        process.arguments = command.arguments
        process.currentDirectoryURL = directory ?? FileManager.default.homeDirectoryForCurrentUser
        var env = ProcessInfo.processInfo.environment
        env.merge(environment) { _, new in new }
        if let input { env["ELEVENAM_INPUT"] = input }
        process.environment = env
        process.standardOutput = output
        process.standardError = errors
        if let input {
            let feed = Pipe()
            process.standardInput = feed
            feed.fileHandleForWriting.write(Data(input.utf8))
            try? feed.fileHandleForWriting.close()
        } else {
            process.standardInput = FileHandle.nullDevice
        }
    }

    func start() throws {
        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            let text = String(decoding: data, as: UTF8.self)
            DispatchQueue.main.async { self?.onOutput?(text) }
        }
        errors.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            let text = String(decoding: data, as: UTF8.self)
            DispatchQueue.main.async { self?.onLog?(text) }
        }
        process.terminationHandler = { [weak self] finished in
            guard let self else { return }
            // Whatever is still in the pipes comes first.
            let rest = self.output.fileHandleForReading.readDataToEndOfFile()
            let restLog = self.errors.fileHandleForReading.readDataToEndOfFile()
            self.output.fileHandleForReading.readabilityHandler = nil
            self.errors.fileHandleForReading.readabilityHandler = nil
            let status = finished.terminationStatus
            try? FileManager.default.removeItem(at: self.file)
            DispatchQueue.main.async {
                if !rest.isEmpty { self.onOutput?(String(decoding: rest, as: UTF8.self)) }
                if !restLog.isEmpty { self.onLog?(String(decoding: restLog, as: UTF8.self)) }
                self.onExit?(status)
            }
        }
        try process.run()
    }

    func stop() {
        if process.isRunning { process.terminate() }
    }

    var isRunning: Bool { process.isRunning }

    /// Runs to the end and returns what it printed, for automations and tests.
    static func run(_ source: String, language: ScriptLanguage, input: String? = nil, timeout: TimeInterval = 120) async throws -> (output: String, log: String, status: Int32) {
        let run = try ScriptRun(source: source, language: language, input: input)
        return try await withCheckedThrowingContinuation { continuation in
            var output = "", log = ""
            run.onOutput = { output += $0 }
            run.onLog = { log += $0 }
            run.onExit = { status in continuation.resume(returning: (output, log, status)) }
            do {
                try run.start()
                DispatchQueue.main.asyncAfter(deadline: .now() + timeout) { run.stop() }
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}

/// Saves AppleScript and JavaScript as compiled scripts, script bundles or double-clickable apps, with macOS's own compiler.
enum ScriptCompiler {
    enum Output: String, CaseIterable, Identifiable {
        case script = "scpt", bundle = "scptd", app = "app"

        var id: String { rawValue }

        var title: String {
            switch self {
            case .script: return "Compiled script (.scpt)"
            case .bundle: return "Script bundle (.scptd)"
            case .app: return "App you can double-click (.app)"
            }
        }
    }

    /// Checks a script without running it. Returns nil when it's fine, or the error with its line.
    static func check(_ source: String, language: ScriptLanguage) async -> String? {
        guard language.isOSA else {
            // Shell scripts are only parsed (zsh -n), never run, to check them.
            return language == .shell ? await shellSyntax(source) : nil
        }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("11am-scripts", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let output = folder.appendingPathComponent("check-\(UUID().uuidString).scpt")
        defer { try? FileManager.default.removeItem(at: output) }
        let result = await compile(source, language: language, to: output)
        return result
    }

    private static func shellSyntax(_ source: String) async -> String? {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("11am-scripts", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appendingPathComponent("check-\(UUID().uuidString).sh")
        try? source.write(to: file, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: file) }
        let result = await runTool("/bin/zsh", ["-n", file.path])
        return result.status == 0 ? nil : result.error.replacingOccurrences(of: file.path + ":", with: "line ").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Compiles to a file. Returns nil on success, or the compiler's message.
    static func compile(_ source: String, language: ScriptLanguage, to destination: URL) async -> String? {
        guard language.isOSA else { return "Only AppleScript and JavaScript can be compiled." }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("11am-scripts", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appendingPathComponent("source-\(UUID().uuidString).\(language.fileExtension)")
        try? source.write(to: file, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: file) }
        try? FileManager.default.removeItem(at: destination)
        var arguments = ["-o", destination.path]
        if language == .javaScript { arguments = ["-l", "JavaScript"] + arguments }
        let result = await runTool("/usr/bin/osacompile", arguments + [file.path])
        guard result.status != 0 else { return nil }
        return result.error.replacingOccurrences(of: file.path + ":", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The source of a compiled script.
    static func decompile(_ file: URL) async -> String? {
        let result = await runTool("/usr/bin/osadecompile", [file.path])
        return result.status == 0 ? result.output : nil
    }

    static func runTool(_ executable: String, _ arguments: [String]) async -> (output: String, error: String, status: Int32) {
        await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            let output = Pipe(), errors = Pipe()
            process.standardOutput = output
            process.standardError = errors
            process.terminationHandler = { finished in
                let out = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                let err = String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                continuation.resume(returning: (out, err, finished.terminationStatus))
            }
            do {
                try process.run()
            } catch {
                continuation.resume(returning: ("", error.localizedDescription, -1))
            }
        }
    }
}

/// An app's scripting dictionary: what you can tell it to do.
struct ScriptDictionary: Sendable {
    struct Item: Identifiable, Hashable, Sendable {
        enum Kind: String, Sendable { case command, `class`, enumeration }
        var id: String { "\(suite).\(kind.rawValue).\(name)" }
        var kind: Kind
        var name: String
        var summary: String
        var suite: String
        /// Parameters for commands, properties for classes, values for enumerations.
        var details: [(name: String, summary: String)]

        static func == (a: Item, b: Item) -> Bool { a.id == b.id }
        func hash(into hasher: inout Hasher) { hasher.combine(id) }
    }

    var suites: [String] = []
    var items: [Item] = []

    var commands: [Item] { items.filter { $0.kind == .command } }
    var classes: [Item] { items.filter { $0.kind == .class } }

    /// Reads the XML that `sdef` prints.
    static func parse(_ data: Data) -> ScriptDictionary {
        let reader = SdefReader()
        let parser = XMLParser(data: data)
        parser.delegate = reader
        parser.shouldResolveExternalEntities = false
        parser.parse()
        return reader.dictionary
    }

    /// Loads an app's dictionary with the system's `sdef` tool.
    static func load(app: URL) async -> ScriptDictionary? {
        let result = await ScriptCompiler.runTool("/usr/bin/sdef", [app.path])
        guard result.status == 0, !result.output.isEmpty else { return nil }
        let dictionary = parse(Data(result.output.utf8))
        return dictionary.items.isEmpty ? nil : dictionary
    }

    /// Apps on this Mac that can be scripted.
    static func scriptableApps() -> [URL] {
        let folders = ["/Applications", "/System/Applications", "/System/Applications/Utilities", "/System/Library/CoreServices",
                       NSHomeDirectory() + "/Applications"]
        var apps: [URL] = []
        for folder in folders {
            guard let names = try? FileManager.default.contentsOfDirectory(atPath: folder) else { continue }
            for name in names where name.hasSuffix(".app") {
                let url = URL(fileURLWithPath: folder).appendingPathComponent(name)
                guard let info = NSDictionary(contentsOf: url.appendingPathComponent("Contents/Info.plist")) else { continue }
                if info["OSAScriptingDefinition"] != nil || (info["NSAppleScriptEnabled"] as? Bool) == true
                    || (info["NSAppleScriptEnabled"] as? String)?.uppercased() == "YES" {
                    apps.append(url)
                }
            }
        }
        return apps.sorted { $0.deletingPathExtension().lastPathComponent.localizedCaseInsensitiveCompare($1.deletingPathExtension().lastPathComponent) == .orderedAscending }
    }
}

private final class SdefReader: NSObject, XMLParserDelegate {
    var dictionary = ScriptDictionary()
    private var suite = ""
    private var current: ScriptDictionary.Item?
    private var depth = 0
    private var itemDepth = 0

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String] = [:]) {
        depth += 1
        let label = attributes["name"] ?? ""
        let summary = attributes["description"] ?? ""
        switch name {
        case "suite":
            suite = label
            if !label.isEmpty && !dictionary.suites.contains(label) { dictionary.suites.append(label) }
        case "command", "class", "enumeration", "class-extension":
            guard current == nil else { return }
            let kind: ScriptDictionary.Item.Kind = name == "command" ? .command : (name == "enumeration" ? .enumeration : .class)
            let itemName = name == "class-extension" ? (attributes["extends"] ?? label) : label
            current = ScriptDictionary.Item(kind: kind, name: itemName, summary: summary, suite: suite, details: [])
            itemDepth = depth
        case "parameter", "property", "enumerator", "direct-parameter", "element":
            guard current != nil else { return }
            let detail = name == "direct-parameter" ? "(direct)" : (name == "element" ? (attributes["type"] ?? "") : label)
            current?.details.append((detail, summary.isEmpty && name == "element" ? "elements" : summary))
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        if let item = current, depth == itemDepth, ["command", "class", "enumeration", "class-extension"].contains(name) {
            if let index = dictionary.items.firstIndex(where: { $0.id == item.id }) {
                dictionary.items[index].details += item.details
                if dictionary.items[index].summary.isEmpty { dictionary.items[index].summary = item.summary }
            } else if !item.name.isEmpty {
                dictionary.items.append(item)
            }
            current = nil
        }
        depth -= 1
    }
}

/// Colouring for the editor: keywords, strings, comments, numbers, app names.
enum ScriptHighlighter {
    enum Kind: Sendable { case keyword, string, comment, number, application }

    struct Token: Equatable, Sendable {
        let range: NSRange
        let kind: Kind
    }

    private static let keywords: [ScriptLanguage: [String]] = [
        .appleScript: ["tell", "end", "to", "set", "get", "copy", "return", "if", "then", "else", "repeat", "with", "while", "until",
                       "times", "in", "of", "on", "try", "error", "considering", "ignoring", "using", "terms", "from", "by",
                       "the", "my", "it", "me", "and", "or", "not", "is", "contains", "whose", "where", "every", "some", "true",
                       "false", "missing", "value", "property", "global", "local", "script", "run", "activate", "log", "exit",
                       "application", "as", "given", "returning", "timeout", "transaction", "first", "last", "count", "display",
                       "dialog", "say", "do", "shell"],
        .javaScript: ["var", "let", "const", "function", "return", "if", "else", "for", "while", "do", "of", "in", "new", "true",
                      "false", "null", "undefined", "this", "try", "catch", "finally", "throw", "typeof", "instanceof", "break",
                      "continue", "switch", "case", "default", "class", "extends", "async", "await", "delay"],
        .shell: ["if", "then", "else", "elif", "fi", "for", "in", "do", "done", "while", "until", "case", "esac", "function",
                 "return", "export", "local", "echo", "cd", "set", "unset", "source", "exit", "true", "false", "read", "printf"],
        .python: ["def", "return", "if", "elif", "else", "for", "while", "in", "import", "from", "as", "class", "try", "except",
                  "finally", "raise", "with", "lambda", "yield", "pass", "break", "continue", "and", "or", "not", "is",
                  "None", "True", "False", "print", "global", "nonlocal", "async", "await"],
    ]

    static func tokens(_ source: String, language: ScriptLanguage) -> [Token] {
        let text = source as NSString
        var tokens: [Token] = []
        var covered = IndexSet()
        func add(_ pattern: String, _ kind: Kind, options: NSRegularExpression.Options = [], group: Int = 0) {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return }
            for match in regex.matches(in: source, range: NSRange(location: 0, length: text.length)) {
                let range = match.range(at: group)
                guard range.location != NSNotFound, range.length > 0 else { continue }
                if covered.intersects(integersIn: range.location..<(range.location + range.length)) { continue }
                covered.insert(integersIn: range.location..<(range.location + range.length))
                tokens.append(Token(range: range, kind: kind))
            }
        }
        // Comments and strings first, so keywords inside them stay plain.
        switch language {
        case .appleScript:
            add(#"\(\*[\s\S]*?\*\)"#, .comment)
            add(#"(--|#)[^\n]*"#, .comment)
            add(#"application\s+("(?:[^"\\]|\\.)*")"#, .application, options: .caseInsensitive, group: 1)
            add(#""(?:[^"\\]|\\.)*""#, .string)
        case .javaScript:
            add(#"/\*[\s\S]*?\*/"#, .comment)
            add(#"//[^\n]*"#, .comment)
            add(#"Application\(\s*(["'][^"']*["'])"#, .application, group: 1)
            add(#""(?:[^"\\]|\\.)*"|'(?:[^'\\]|\\.)*'|`(?:[^`\\]|\\.)*`"#, .string)
        case .shell, .python:
            add(#"(?m)(^|\s)(#[^\n]*)"#, .comment, group: 2)
            if language == .python { add(#"(\"\"\"[\s\S]*?\"\"\"|'''[\s\S]*?''')"#, .string) }
            add(#""(?:[^"\\]|\\.)*"|'[^']*'"#, .string)
        }
        add(#"\b\d+(\.\d+)?\b"#, .number)
        let words = keywords[language] ?? []
        if !words.isEmpty {
            let options: NSRegularExpression.Options = language == .appleScript ? .caseInsensitive : []
            add("\\b(" + words.map(NSRegularExpression.escapedPattern(for:)).joined(separator: "|") + ")\\b", .keyword, options: options)
        }
        return tokens.sorted { $0.range.location < $1.range.location }
    }
}

/// Apple's Shortcuts, run by name with the `shortcuts` tool.
enum ShortcutsBridge {
    static func list() async -> [String] {
        let result = await ScriptCompiler.runTool("/usr/bin/shortcuts", ["list"])
        guard result.status == 0 else { return [] }
        return result.output.split(separator: "\n").map(String.init).filter { !$0.isEmpty }
    }

    /// Runs a shortcut, giving it text, and returns what it gave back.
    static func run(_ name: String, input: String? = nil) async -> (output: String, error: String?) {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("11am-scripts", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let out = folder.appendingPathComponent("shortcut-\(UUID().uuidString).txt")
        var arguments = ["run", name, "--output-path", out.path, "--output-type", "public.plain-text"]
        if let input {
            let inFile = folder.appendingPathComponent("shortcut-in-\(UUID().uuidString).txt")
            try? input.write(to: inFile, atomically: true, encoding: .utf8)
            arguments += ["--input-path", inFile.path]
        }
        let result = await ScriptCompiler.runTool("/usr/bin/shortcuts", arguments)
        let text = (try? String(contentsOf: out, encoding: .utf8)) ?? ""
        try? FileManager.default.removeItem(at: out)
        return (text, result.status == 0 ? nil : result.error.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}
