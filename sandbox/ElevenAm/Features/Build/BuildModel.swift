import Foundation

struct TuneChange: Identifiable, Hashable {
    var id: String { name }
    let name: String
    let from: String
    let to: String
}

struct TuneRecord: Identifiable {
    let id = UUID()
    let request: String
    let before: ThemeValues
    let after: ThemeValues
    let date = Date()
}

/// Plain-English requests that change the look, understood without any model at all.
enum TuneRules {
    static func apply(_ request: String, to values: ThemeValues) -> ThemeValues {
        let text = request.lowercased()
        var v = values
        func has(_ words: String...) -> Bool { words.contains { text.contains($0) } }
        let lot = has("a lot", "much", "very", "way more", "really")
        let step = lot ? 0.3 : 0.15

        if has("reset", "default", "start over") { return ThemeValues() }
        if has("warmer", "warm", "cream", "vellum") { v.paperTone += step * 1.5 }
        if has("cooler", "whiter", "pure white", "colder") { v.paperTone -= step * 1.5 }
        if has("more transparent", "see-through", "see through", "clearer", "more glass", "see behind", "more clarity") {
            v.clarity += step
            v.frost -= step / 2
        }
        if has("less transparent", "more solid", "opaque", "frostier", "more frost", "less see") {
            v.clarity -= step
            v.frost += step / 2
        }
        if has("dark mode", "darker", "dark theme", "night") { v.appearance = .dark }
        if has("light mode", "lighter theme", "light theme") { v.appearance = .light }
        if has("follow the system", "match the system", "automatic") { v.appearance = .system }
        if has("rounder", "softer corners", "more rounded") { v.cornerRadius += lot ? 8 : 4 }
        if has("sharper", "squarer", "less rounded", "tighter corners") { v.cornerRadius -= lot ? 6 : 3 }
        if has("calmer", "less motion", "less movement", "still", "no animation") { v.motion -= lot ? 0.5 : 0.25 }
        if has("livelier", "more motion", "more movement", "bouncier", "more animation") { v.motion += lot ? 0.4 : 0.2 }
        if has("more grain", "more texture", "grainier", "papery") { v.grain += step }
        if has("less grain", "smoother", "no grain", "cleaner") { v.grain -= step }
        if has("softer text", "graphite", "softer ink") { v.inkSoftness += step * 2 }
        if has("crisper", "blacker", "more contrast", "sharper text", "darker text") { v.inkSoftness -= step * 2 }
        if has("deeper", "more depth", "more shadow", "layered") { v.depth += step }
        if has("flatter", "less shadow", "no shadow") { v.depth -= step }
        if has("serif", "new york") { v.displayFace = .newYork }
        if has("alte haas", "grotesk") { v.displayFace = .alteHaas }
        if has("sf pro", "system font", "san francisco") { v.displayFace = .sfPro }
        return clamped(v)
    }

    static func clamped(_ values: ThemeValues) -> ThemeValues {
        var v = values
        v.paperTone = min(max(v.paperTone, 0), 1)
        v.frost = min(max(v.frost, 0), 1)
        v.clarity = min(max(v.clarity, 0), 1)
        v.grain = min(max(v.grain, 0), 1)
        v.depth = min(max(v.depth, 0), 1)
        v.inkSoftness = min(max(v.inkSoftness, 0), 1)
        v.motion = min(max(v.motion, 0), 1)
        v.cornerRadius = min(max(v.cornerRadius, 6), 30)
        return v
    }

    /// What changed, in words, for the preview.
    static func changes(from old: ThemeValues, to new: ThemeValues) -> [TuneChange] {
        var list: [TuneChange] = []
        func number(_ name: String, _ a: Double, _ b: Double) {
            if abs(a - b) > 0.001 { list.append(TuneChange(name: name, from: String(format: "%.2f", a), to: String(format: "%.2f", b))) }
        }
        if old.appearance != new.appearance { list.append(TuneChange(name: "Appearance", from: old.appearance.title, to: new.appearance.title)) }
        number("Paper tone", old.paperTone, new.paperTone)
        number("Frost", old.frost, new.frost)
        number("Clarity", old.clarity, new.clarity)
        number("Grain", old.grain, new.grain)
        number("Depth", old.depth, new.depth)
        number("Ink softness", old.inkSoftness, new.inkSoftness)
        number("Motion", old.motion, new.motion)
        if abs(old.cornerRadius - new.cornerRadius) > 0.01 {
            list.append(TuneChange(name: "Corner radius", from: "\(Int(old.cornerRadius))", to: "\(Int(new.cornerRadius))"))
        }
        if old.displayFace != new.displayFace { list.append(TuneChange(name: "Display face", from: old.displayFace.title, to: new.displayFace.title)) }
        if old.backdrop != new.backdrop { list.append(TuneChange(name: "Backdrop", from: old.backdrop.title, to: new.backdrop.title)) }
        return list
    }
}

/// Johnny in the sandbox: Tune (describe a change to 11am, preview it, apply it, undo it) and a terminal
/// where Johnny can suggest commands but nothing runs until you press Run.
@MainActor
final class BuildModel: ObservableObject {
    // Tune
    @Published var request = ""
    @Published private(set) var proposal: ThemeValues?
    @Published private(set) var proposalRequest = ""
    @Published private(set) var history: [TuneRecord] = []
    @Published private(set) var tuneRun: BrainRun?
    @Published var tuneNotice: String?

    // Terminal
    @Published var command = ""
    @Published private(set) var output = ""
    @Published private(set) var isRunning = false
    @Published private(set) var lastExit: Int32?
    @Published private(set) var needsConfirmation = false
    @Published private(set) var commandRun: BrainRun?

    private let brain: Brain
    private let theme: Theme
    private var process: Process?
    private var pipe: Pipe?

    init(brain: Brain, theme: Theme) {
        self.brain = brain
        self.theme = theme
    }

    var proposalChanges: [TuneChange] {
        guard let proposal else { return [] }
        return TuneRules.changes(from: theme.values, to: proposal)
    }

    // MARK: Tune

    func propose() {
        let text = request.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        tuneNotice = nil
        proposalRequest = text
        let ruled = TuneRules.apply(text, to: theme.values)
        if ruled != theme.values {
            proposal = ruled
            return
        }
        // Not a phrase Johnny knows by heart: ask the brain for a spec diff.
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let current = (try? encoder.encode(theme.values)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        let system = """
        You are Johnny, the builder inside 11am. Turn the request into changes to 11am's look. \
        Reply with only a JSON object containing the keys you'd change. Allowed keys: \
        appearance ("system", "light", "dark"), paperTone (0 white to 1 warm), frost (0 clear to 1 milky), \
        clarity (0 frosted to 1 see-through), grain, depth, inkSoftness (0 black to 1 graphite), motion (all 0 to 1), \
        cornerRadius (6 to 30), displayFace ("alteHaas", "sfPro", "newYork"), backdrop ("underWindow", "sidebar", "hud", "popover", "menu").
        """
        tuneRun = brain.run(BrainRequest(system: system, prompt: "Current: \(current)\nRequest: \(text)", weight: .quick))
    }

    /// Reads the JSON the brain wrote and turns it into a proposal. Unknown keys are ignored; values are clamped.
    func adoptBrainProposal(from text: String) {
        defer { tuneRun = nil }
        guard let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}"),
              let data = String(text[start...end]).data(using: .utf8),
              let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            tuneNotice = "Johnny couldn't turn that into a change. Try \"warmer\", \"more see-through\" or \"calmer\"."
            return
        }
        var v = theme.values
        if let raw = object["appearance"] as? String, let value = Appearance(rawValue: raw) { v.appearance = value }
        if let raw = object["displayFace"] as? String, let value = DisplayFace(rawValue: raw) { v.displayFace = value }
        if let raw = object["backdrop"] as? String, let value = BackdropMaterial(rawValue: raw) { v.backdrop = value }
        func number(_ key: String) -> Double? { (object[key] as? NSNumber)?.doubleValue }
        if let value = number("paperTone") { v.paperTone = value }
        if let value = number("frost") { v.frost = value }
        if let value = number("clarity") { v.clarity = value }
        if let value = number("grain") { v.grain = value }
        if let value = number("depth") { v.depth = value }
        if let value = number("inkSoftness") { v.inkSoftness = value }
        if let value = number("motion") { v.motion = value }
        if let value = number("cornerRadius") { v.cornerRadius = value }
        let result = TuneRules.clamped(v)
        if result == theme.values {
            tuneNotice = "That wouldn't change anything."
        } else {
            proposal = result
        }
    }

    func applyProposal() {
        guard let proposal else { return }
        history.insert(TuneRecord(request: proposalRequest, before: theme.values, after: proposal), at: 0)
        theme.values = proposal
        self.proposal = nil
        request = ""
    }

    func discardProposal() {
        proposal = nil
    }

    func revert(_ record: TuneRecord) {
        history.insert(TuneRecord(request: "Undo: \(record.request)", before: theme.values, after: record.before), at: 0)
        theme.values = record.before
    }

    // MARK: Terminal

    private static let riskyPatterns = [
        "rm -", "rm ", "sudo", "mkfs", "dd if=", "diskutil", ":(){", "chmod -r", "chown -r", "> /dev/",
        "| sh", "| bash", "| zsh", "curl ", "killall", "shutdown", "reboot", "launchctl", "defaults delete", "mv /",
    ]

    var commandLooksRisky: Bool {
        let text = command.lowercased()
        return BuildModel.riskyPatterns.contains { text.contains($0) }
    }

    /// Runs the command in zsh, in your home folder. Risky commands ask once more first.
    func run(confirmed: Bool = false) {
        let text = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isRunning else { return }
        if commandLooksRisky && !confirmed {
            needsConfirmation = true
            return
        }
        needsConfirmation = false
        output += "$ \(text)\n"
        lastExit = nil
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", text]
        process.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            let chunk = String(decoding: data, as: UTF8.self)
            Task { @MainActor in self?.append(chunk) }
        }
        process.terminationHandler = { [weak self] finished in
            let status = finished.terminationStatus
            Task { @MainActor in self?.finish(status) }
        }
        do {
            try process.run()
            self.process = process
            self.pipe = pipe
            isRunning = true
        } catch {
            output += "Couldn't start: \(error.localizedDescription)\n"
        }
    }

    func cancelConfirmation() {
        needsConfirmation = false
    }

    func stop() {
        process?.terminate()
    }

    func clearOutput() {
        output = ""
        lastExit = nil
    }

    private func append(_ chunk: String) {
        output += chunk
        // Keep the scrollback small; this is a sandbox, not a log archive.
        if output.count > 60_000 { output = String(output.suffix(50_000)) }
    }

    private func finish(_ status: Int32) {
        pipe?.fileHandleForReading.readabilityHandler = nil
        pipe = nil
        process = nil
        isRunning = false
        lastExit = status
        output += status == 0 ? "\n" : "(exit \(status))\n\n"
    }

    /// Johnny writes the command; you decide whether it runs.
    func suggestCommand(for request: String) {
        let request = request.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !request.isEmpty else { return }
        let system = """
        You are Johnny, the builder inside 11am, on macOS with zsh. Reply in exactly two lines:
        COMMAND: a single shell command that does what's asked
        WHY: one short sentence explaining it
        Never use sudo. Prefer read-only commands. If it can't be done safely in one command, say so on the WHY line and leave COMMAND empty.
        """
        commandRun = brain.run(BrainRequest(system: system, prompt: request, weight: .quick))
    }

    static func parseSuggestion(_ text: String) -> (command: String, why: String) {
        var command = ""
        var why = ""
        for raw in text.split(separator: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.uppercased().hasPrefix("COMMAND:") {
                command = line.dropFirst(8).trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "`"))
            } else if line.uppercased().hasPrefix("WHY:") {
                why = line.dropFirst(4).trimmingCharacters(in: .whitespaces)
            }
        }
        return (command, why)
    }

    func useSuggestion(_ suggestion: String) {
        command = suggestion
        commandRun = nil
    }
}
