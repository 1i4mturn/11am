import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Johnny's Scripts: AppleScript, JavaScript, shell and Python in one library, with the apps' dictionaries and your Shortcuts.
@MainActor
final class ScriptsModel: ObservableObject {
    @Published private(set) var scripts: [ScriptDocument] = []
    @Published var selectedID: UUID?
    @Published private(set) var isRunning = false
    @Published private(set) var result = ""
    @Published private(set) var log = ""
    @Published var outputTab = 0
    @Published private(set) var status = "Scripts run on this Mac. AppleScript and JavaScript can control your apps; macOS asks once for each."
    @Published private(set) var problem: String?
    /// Apps a script wants to control that you haven't allowed yet.
    @Published var pendingApproval: [String] = []
    @Published private(set) var johnnyRun: BrainRun?
    @Published private(set) var johnnyWrites = false
    @Published private(set) var apps: [URL] = []
    @Published var dictionaryApp: URL? { didSet { if dictionaryApp != oldValue { loadDictionary() } } }
    @Published private(set) var dictionary: ScriptDictionary?
    @Published private(set) var loadingDictionary = false
    @Published var dictionaryQuery = ""
    @Published private(set) var shortcuts: [String] = []

    private let brain: Brain
    private var running: ScriptRun?
    private var saveTask: Task<Void, Never>?

    init(brain: Brain) {
        self.brain = brain
        scripts = JSONStore.load([ScriptDocument].self, from: "scripts") ?? Self.samples
        selectedID = scripts.first?.id
    }

    var selected: ScriptDocument? { scripts.first { $0.id == selectedID } }

    private var selectedIndex: Int? { scripts.firstIndex { $0.id == selectedID } }

    // MARK: Library

    static let samples: [ScriptDocument] = [
        ScriptDocument(name: "Say the time", language: .appleScript, source: """
            -- Says the time out loud and returns it.
            set now to time string of (current date)
            say "It's " & now
            return now
            """),
        ScriptDocument(name: "Unread mail", language: .appleScript, source: """
            -- How many unread emails are in Mail's inbox.
            tell application "Mail"
            \tset unread to count of (messages of inbox whose read status is false)
            end tell
            log "Counted the inbox"
            return (unread as text) & " unread"
            """),
        ScriptDocument(name: "Files selected in Finder", language: .javaScript, source: """
            // The names of the files selected in Finder, one per line.
            const finder = Application("Finder");
            const names = finder.selection().map(item => item.name());
            names.length ? names.join("\\n") : "Nothing selected in Finder";
            """),
        ScriptDocument(name: "Switch dark mode", language: .appleScript, source: """
            tell application "System Events"
            \ttell appearance preferences to set dark mode to not dark mode
            end tell
            """),
        ScriptDocument(name: "Free disk space", language: .shell, source: """
            # How much room is left on this Mac's disk.
            df -h / | tail -1 | awk '{print $4 " free of " $2}'
            """),
        ScriptDocument(name: "Count words", language: .python, source: """
            # Counts the words it's given (an automation's result, or nothing when run here).
            import sys
            text = sys.stdin.read()
            print(len(text.split()), "words")
            """),
    ]

    private func save() {
        saveTask?.cancel()
        saveTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 600_000_000)
            guard !Task.isCancelled else { return }
            JSONStore.save(scripts, to: "scripts")
        }
    }

    func flushSave() {
        saveTask?.cancel()
        JSONStore.save(scripts, to: "scripts")
    }

    func newScript(_ language: ScriptLanguage) {
        let starter: String
        switch language {
        case .appleScript: starter = "tell application \"Finder\"\n\t\nend tell\n"
        case .javaScript: starter = "const app = Application.currentApplication();\napp.includeStandardAdditions = true;\n\n"
        case .shell: starter = "#!/bin/zsh\n\n"
        case .python: starter = "import sys\n\n"
        }
        let script = ScriptDocument(name: "Untitled \(language.title)", language: language, source: starter)
        scripts.insert(script, at: 0)
        selectedID = script.id
        save()
    }

    func duplicate() {
        guard var copy = selected else { return }
        copy.id = UUID()
        copy.name += " copy"
        copy.approvedApps = []
        scripts.insert(copy, at: (selectedIndex ?? 0) + 1)
        selectedID = copy.id
        save()
    }

    func delete(_ id: UUID) {
        guard let index = scripts.firstIndex(where: { $0.id == id }) else { return }
        scripts.remove(at: index)
        if selectedID == id { selectedID = scripts.indices.contains(index) ? scripts[index].id : scripts.last?.id }
        save()
    }

    func update(_ change: (inout ScriptDocument) -> Void) {
        guard let index = selectedIndex else { return }
        let before = scripts[index]
        change(&scripts[index])
        guard scripts[index] != before else { return }
        scripts[index].modified = Date()
        if scripts[index].source != before.source { problem = nil }
        save()
    }

    // MARK: Checking and running

    func check() {
        guard let script = selected else { return }
        status = "Checking…"
        Task {
            let message = await ScriptCompiler.check(script.source, language: script.language)
            problem = message
            status = message == nil ? (script.language.isOSA || script.language == .shell ? "No problems found." : "Python is checked when it runs.") : "There's a problem; see below."
            if message != nil { outputTab = 1; log = message ?? "" }
        }
    }

    /// Runs the selected script. The first time it controls an app, Johnny asks first.
    func run(approved: Bool = false) {
        guard let script = selected, !isRunning else { return }
        let needed = ScriptApps.needingApproval(script)
        if !needed.isEmpty && !approved {
            pendingApproval = needed
            return
        }
        if approved && !needed.isEmpty {
            update { $0.approvedApps += needed }
        }
        pendingApproval = []
        result = ""
        log = ""
        problem = nil
        outputTab = 0
        do {
            let run = try ScriptRun(source: script.source, language: script.language)
            run.onOutput = { [weak self] text in self?.result += text }
            run.onLog = { [weak self] text in self?.log += text }
            run.onExit = { [weak self] code in
                guard let self else { return }
                self.isRunning = false
                self.running = nil
                if code == 0 {
                    self.status = "Finished."
                } else {
                    self.status = code == 15 ? "Stopped." : "It stopped with an error (\(code))."
                    if !self.log.isEmpty { self.outputTab = 1; self.problem = self.log.trimmingCharacters(in: .whitespacesAndNewlines) }
                }
            }
            try run.start()
            running = run
            isRunning = true
            status = "Running \(script.name)…"
        } catch {
            status = error.localizedDescription
        }
    }

    func cancelApproval() { pendingApproval = [] }

    func stop() {
        running?.stop()
    }

    /// For automations: runs a library script with an input, without asking (it must have been allowed in Scripts first).
    func runForAutomation(_ id: UUID, input: String) async -> (output: String, ok: Bool) {
        guard let script = scripts.first(where: { $0.id == id }) else { return ("That script isn't in the library any more.", false) }
        let needed = ScriptApps.needingApproval(script)
        guard needed.isEmpty else {
            return ("\(script.name) controls \(needed.joined(separator: ", ")). Run it once in Scripts to allow that.", false)
        }
        guard let outcome = try? await ScriptRun.run(script.source, language: script.language, input: input, timeout: 600) else {
            return ("\(script.name) couldn't start.", false)
        }
        return (outcome.output.isEmpty ? outcome.log : outcome.output, outcome.status == 0)
    }

    // MARK: Files

    func openFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = ["applescript", "scpt", "scptd", "js", "sh", "zsh", "command", "py"].compactMap { UTType(filenameExtension: $0) }
        guard panel.runModal() == .OK else { return }
        let urls = panel.urls
        Task {
            for url in urls {
                guard let language = ScriptLanguage.from(extension: url.pathExtension) else { continue }
                var source: String?
                if ["scpt", "scptd"].contains(url.pathExtension.lowercased()) {
                    source = await ScriptCompiler.decompile(url)
                } else {
                    source = try? String(contentsOf: url, encoding: .utf8)
                }
                guard let source else {
                    status = "\(url.lastPathComponent) couldn't be read."
                    continue
                }
                let script = ScriptDocument(name: url.deletingPathExtension().lastPathComponent, language: language, source: source)
                scripts.insert(script, at: 0)
                selectedID = script.id
            }
            save()
        }
    }

    func saveFile() {
        guard let script = selected else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(script.name).\(script.language.fileExtension)"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try script.source.write(to: url, atomically: true, encoding: .utf8)
            if script.language == .shell || script.language == .python {
                try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
            }
            status = "Saved \(url.lastPathComponent)."
        } catch {
            status = error.localizedDescription
        }
    }

    func export(_ output: ScriptCompiler.Output) {
        guard let script = selected, script.language.isOSA else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(script.name).\(output.rawValue)"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        status = "Compiling…"
        Task {
            if let message = await ScriptCompiler.compile(script.source, language: script.language, to: url) {
                problem = message
                status = "It didn't compile; see below."
                outputTab = 1
                log = message
            } else {
                status = "Saved \(url.lastPathComponent)."
                if output == .app { NSWorkspace.shared.activateFileViewerSelecting([url]) }
            }
        }
    }

    // MARK: Dictionaries and Shortcuts

    func loadApps() {
        guard apps.isEmpty else { return }
        Task.detached(priority: .utility) {
            let found = ScriptDictionary.scriptableApps()
            await MainActor.run {
                self.apps = found
                if self.dictionaryApp == nil {
                    self.dictionaryApp = found.first { $0.lastPathComponent == "Finder.app" } ?? found.first
                }
            }
        }
    }

    private func loadDictionary() {
        guard let app = dictionaryApp else { return }
        dictionary = nil
        loadingDictionary = true
        Task {
            let loaded = await ScriptDictionary.load(app: app)
            guard dictionaryApp == app else { return }
            dictionary = loaded
            loadingDictionary = false
        }
    }

    var dictionaryItems: [ScriptDictionary.Item] {
        guard let dictionary else { return [] }
        let query = dictionaryQuery.trimmingCharacters(in: .whitespaces)
        let items = dictionary.items.filter { $0.kind != .enumeration }
        guard !query.isEmpty else { return items }
        return items.filter { $0.name.localizedCaseInsensitiveContains(query) || $0.summary.localizedCaseInsensitiveContains(query) }
    }

    /// Copies a line that uses a dictionary entry, ready to paste into a script.
    func copyExample(_ item: ScriptDictionary.Item) {
        guard let app = dictionaryApp?.deletingPathExtension().lastPathComponent else { return }
        let language = selected?.language ?? .appleScript
        let line: String
        switch (language, item.kind) {
        case (.javaScript, .command): line = "Application(\"\(app)\").\(Self.camel(item.name))()"
        case (.javaScript, _): line = "Application(\"\(app)\").\(Self.camel(item.name))s()"
        case (_, .command): line = "tell application \"\(app)\" to \(item.name)"
        default: line = "tell application \"\(app)\" to get every \(item.name)"
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(line, forType: .string)
        status = "Copied: \(line)"
    }

    private static func camel(_ name: String) -> String {
        let words = name.split(separator: " ")
        guard let first = words.first else { return name }
        return first.lowercased() + words.dropFirst().map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined()
    }

    func loadShortcuts() {
        Task { shortcuts = await ShortcutsBridge.list() }
    }

    func runShortcut(_ name: String) {
        status = "Running the shortcut \(name)…"
        isRunning = true
        Task {
            let outcome = await ShortcutsBridge.run(name)
            isRunning = false
            result = outcome.output
            log = outcome.error ?? ""
            outputTab = outcome.error == nil ? 0 : 1
            status = outcome.error == nil ? "\(name) finished." : "\(name) didn't finish."
        }
    }

    // MARK: Johnny

    func write(_ request: String) {
        let request = request.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !request.isEmpty else { return }
        let language = selected?.language ?? .appleScript
        let system = """
        You are Johnny, the builder inside 11am, on macOS. Write a \(language.title) script that does what's asked\
        \(language == .javaScript ? " (JavaScript for Automation, run with osascript -l JavaScript)" : ""). \
        Put the whole script in one fenced code block, then one short sentence on what it does and which apps it controls. \
        Prefer reading over changing things; never delete files without asking in the script.
        """
        johnnyWrites = true
        johnnyRun = brain.run(BrainRequest(system: system, prompt: request, weight: .quick))
    }

    func explain() {
        guard let script = selected else { return }
        johnnyWrites = false
        let system = "You are Johnny, the builder inside 11am. Explain this \(script.language.title) script in plain words, step by step, briefly. Say which apps it controls and whether it changes anything."
        johnnyRun = brain.run(BrainRequest(system: system, prompt: script.source, weight: .quick))
    }

    func fix() {
        guard let script = selected else { return }
        johnnyWrites = true
        let system = """
        You are Johnny, the builder inside 11am, on macOS. This \(script.language.title) script has a problem. \
        Reply with the corrected script in one fenced code block, then one sentence on what was wrong.
        """
        let error = problem ?? log
        johnnyRun = brain.run(BrainRequest(system: system, prompt: "Script:\n\(script.source)\n\nError:\n\(error)", weight: .quick))
    }

    func dismissJohnny() { johnnyRun = nil }

    /// The script in Johnny's answer.
    static func code(in text: String) -> String? {
        guard let start = text.range(of: "```") else { return nil }
        let afterFence = text[start.upperBound...]
        guard let newline = afterFence.firstIndex(of: "\n") else { return nil }
        let body = afterFence[afterFence.index(after: newline)...]
        guard let end = body.range(of: "```") else { return String(body) }
        return String(body[..<end.lowerBound]).trimmingCharacters(in: .newlines)
    }

    func useJohnnysScript() {
        guard let text = johnnyRun?.text, let code = Self.code(in: text) else { return }
        update { $0.source = code }
        johnnyRun = nil
        status = "Johnny's script is in. Check it, then Run."
    }
}

// MARK: Views

struct ScriptsPane: View {
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var scripts: ScriptsModel
    @EnvironmentObject private var brain: Brain
    @Environment(\.colorScheme) private var scheme
    @State private var showsDictionary = false
    @State private var ask = ""

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ScriptLibrary()
                .frame(width: 210)
            VStack(alignment: .leading, spacing: 8) {
                if let script = scripts.selected {
                    ScriptToolbar(script: script, showsDictionary: $showsDictionary)
                    if !scripts.pendingApproval.isEmpty {
                        ApprovalBanner(apps: scripts.pendingApproval)
                    }
                    ScriptEditor(text: Binding(get: { scripts.selected?.source ?? "" }, set: { value in scripts.update { $0.source = value } }),
                                 language: script.language)
                        .id(script.id)
                        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(theme.edge(scheme), lineWidth: 0.5))
                    if let run = scripts.johnnyRun {
                        JohnnyScriptCard(run: run)
                    }
                    HStack(spacing: 8) {
                        AskField(placeholder: "Ask Johnny to write it: \"rename the selected photos by date\"", text: $ask) {
                            scripts.write(ask)
                        }
                        .disabled(brain.isBusy)
                        Button("Explain") { scripts.explain() }
                            .buttonStyle(.vellumSecondary)
                            .disabled(brain.isBusy)
                        if scripts.problem != nil {
                            Button("Fix it") { scripts.fix() }
                                .buttonStyle(.vellumPrimary)
                                .disabled(brain.isBusy)
                        }
                    }
                    ScriptOutput()
                        .frame(height: 150)
                } else {
                    Text("Make a script with + or open one.")
                        .font(.system(size: 12.5))
                        .foregroundStyle(theme.inkTertiary(scheme))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            if showsDictionary {
                DictionaryPanel()
                    .frame(width: 270)
                    .transition(.rise(theme.rise))
            }
        }
        .animation(theme.spring, value: showsDictionary)
    }
}

private struct ScriptLibrary: View {
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var scripts: ScriptsModel
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                SectionLabel(text: "Scripts")
                Spacer()
                Menu {
                    ForEach(ScriptLanguage.allCases) { language in
                        Button(language.title) { scripts.newScript(language) }
                    }
                } label: { Image(systemName: "plus") }
                    .menuStyle(.button)
                    .buttonStyle(.plain)
                    .fixedSize()
                    .help("New script")
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(scripts.scripts) { script in
                        Button { scripts.selectedID = script.id } label: {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(script.name)
                                    .font(.system(size: 12.5, weight: script.id == scripts.selectedID ? .semibold : .regular))
                                    .foregroundStyle(theme.ink(scheme))
                                    .lineLimit(1)
                                Text(script.language.title)
                                    .font(.system(size: 10.5))
                                    .foregroundStyle(theme.inkTertiary(scheme))
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(script.id == scripts.selectedID ? theme.well(scheme) : Color.clear))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button("Duplicate") {
                                scripts.selectedID = script.id
                                scripts.duplicate()
                            }
                            Button("Delete", role: .destructive) { scripts.delete(script.id) }
                        }
                    }
                }
            }
            SectionLabel(text: "Shortcuts")
            if scripts.shortcuts.isEmpty {
                Text("Your shortcuts from the Shortcuts app show here.")
                    .font(.system(size: 11))
                    .foregroundStyle(theme.inkTertiary(scheme))
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 1) {
                        ForEach(scripts.shortcuts, id: \.self) { name in
                            HStack {
                                Text(name)
                                    .font(.system(size: 12))
                                    .foregroundStyle(theme.ink(scheme))
                                    .lineLimit(1)
                                Spacer()
                                Button { scripts.runShortcut(name) } label: { Image(systemName: "play.fill").font(.system(size: 9)) }
                                    .buttonStyle(.plain)
                                    .foregroundStyle(theme.inkSecondary(scheme))
                                    .help("Run \(name)")
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                        }
                    }
                }
                .frame(maxHeight: 160)
            }
        }
        .padding(12)
        .frame(maxHeight: .infinity, alignment: .top)
        .vellum(level: 3, radius: max(theme.radius - 4, 8))
        .onAppear { scripts.loadShortcuts() }
    }
}

private struct ScriptToolbar: View {
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var scripts: ScriptsModel
    @Environment(\.colorScheme) private var scheme
    var script: ScriptDocument
    @Binding var showsDictionary: Bool

    var body: some View {
        HStack(spacing: 8) {
            TextField("Name", text: Binding(get: { script.name }, set: { value in scripts.update { $0.name = value } }))
                .textFieldStyle(.plain)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(theme.ink(scheme))
                .frame(minWidth: 120)
            Picker("", selection: Binding(get: { script.language }, set: { value in scripts.update { $0.language = value } })) {
                ForEach(ScriptLanguage.allCases) { language in Text(language.title).tag(language) }
            }
            .labelsHidden()
            .fixedSize()
            Spacer(minLength: 4)
            Button("Check") { scripts.check() }
                .buttonStyle(.vellumSecondary)
                .keyboardShortcut("k", modifiers: .command)
                .help("Check it without running (⌘K)")
            if scripts.isRunning {
                Button { scripts.stop() } label: { Label("Stop", systemImage: "stop.fill") }
                    .buttonStyle(.vellumSecondary)
                    .keyboardShortcut(".", modifiers: .command)
            } else {
                Button { scripts.run() } label: { Label("Run", systemImage: "play.fill") }
                    .buttonStyle(.vellumPrimary)
                    .keyboardShortcut("r", modifiers: .command)
                    .help("Run (⌘R)")
            }
            Menu {
                Button("Open…") { scripts.openFile() }
                Button("Save a copy…") { scripts.saveFile() }
                if script.language.isOSA {
                    Divider()
                    ForEach(ScriptCompiler.Output.allCases) { output in
                        Button(output.title) { scripts.export(output) }
                    }
                }
                Divider()
                Button("Duplicate") { scripts.duplicate() }
                Button("Delete", role: .destructive) { scripts.delete(script.id) }
            } label: { Image(systemName: "square.and.arrow.up") }
                .menuStyle(.button)
                .buttonStyle(.vellumSecondary)
                .fixedSize()
            Button { showsDictionary.toggle() } label: { Image(systemName: "book") }
                .buttonStyle(.vellumSecondary)
                .help("What each app can be told to do")
        }
    }
}

private struct ApprovalBanner: View {
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var scripts: ScriptsModel
    @Environment(\.colorScheme) private var scheme
    var apps: [String]

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "hand.raised")
            Text("This script will control \(ListFormatter.localizedString(byJoining: apps)). Johnny asks once; macOS may ask too.")
                .font(.system(size: 12))
            Spacer()
            Button("Allow and run") { scripts.run(approved: true) }.buttonStyle(.vellumPrimary)
            Button("Cancel") { scripts.cancelApproval() }.buttonStyle(.vellumSecondary)
        }
        .foregroundStyle(theme.ink(scheme))
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.orange.opacity(0.14)))
    }
}

private struct ScriptOutput: View {
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var scripts: ScriptsModel
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Picker("", selection: $scripts.outputTab) {
                    Text("Result").tag(0)
                    Text("Log and errors").tag(1)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                if scripts.isRunning { ProgressView().controlSize(.small) }
                Text(scripts.status)
                    .font(.system(size: 11.5))
                    .foregroundStyle(theme.inkTertiary(scheme))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            ScrollView {
                Text(text.isEmpty ? placeholder : text)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(text.isEmpty ? theme.inkTertiary(scheme) : theme.ink(scheme))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(10)
            }
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(theme.well(scheme)))
        }
    }

    private var text: String { scripts.outputTab == 0 ? scripts.result : scripts.log }

    private var placeholder: String {
        scripts.outputTab == 0 ? "What the script returns or prints shows here." : "AppleScript's log lines and any errors show here."
    }
}

private struct JohnnyScriptCard: View {
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var scripts: ScriptsModel
    @Environment(\.colorScheme) private var scheme
    @ObservedObject var run: BrainRun

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 6) {
                RunView(run: run)
                    .frame(maxHeight: 180)
                if run.status == .done && scripts.johnnyWrites && ScriptsModel.code(in: run.text) != nil {
                    Button("Use this script") { scripts.useJohnnysScript() }
                        .buttonStyle(.vellumPrimary)
                }
            }
            Spacer(minLength: 0)
            Button { scripts.dismissJohnny() } label: { Image(systemName: "xmark") }
                .buttonStyle(.plain)
                .foregroundStyle(theme.inkTertiary(scheme))
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(theme.well(scheme)))
    }
}

private struct DictionaryPanel: View {
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var scripts: ScriptsModel
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: "Dictionary")
            Picker("", selection: $scripts.dictionaryApp) {
                ForEach(scripts.apps, id: \.self) { app in
                    Text(app.deletingPathExtension().lastPathComponent).tag(Optional(app))
                }
            }
            .labelsHidden()
            TextField("Search commands and things", text: $scripts.dictionaryQuery)
                .textFieldStyle(.roundedBorder)
            if scripts.loadingDictionary {
                ProgressView().controlSize(.small)
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 6) {
                    ForEach(scripts.dictionaryItems) { item in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 5) {
                                Image(systemName: item.kind == .command ? "c.square" : "cube")
                                    .font(.system(size: 10))
                                    .foregroundStyle(theme.inkTertiary(scheme))
                                Text(item.name)
                                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(theme.ink(scheme))
                            }
                            if !item.summary.isEmpty {
                                Text(item.summary)
                                    .font(.system(size: 11))
                                    .foregroundStyle(theme.inkSecondary(scheme))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            if !item.details.isEmpty {
                                Text(item.details.prefix(8).map(\.name).joined(separator: " · "))
                                    .font(.system(size: 10.5, design: .monospaced))
                                    .foregroundStyle(theme.inkTertiary(scheme))
                                    .lineLimit(2)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { scripts.copyExample(item) }
                        .help("Click to copy an example line")
                    }
                }
            }
            Text("Click an entry to copy a line that uses it.")
                .font(.system(size: 10.5))
                .foregroundStyle(theme.inkTertiary(scheme))
        }
        .padding(12)
        .frame(maxHeight: .infinity, alignment: .top)
        .vellum(level: 3, radius: max(theme.radius - 4, 8))
        .onAppear { scripts.loadApps() }
    }
}

/// A code editor with colouring, for scripts.
struct ScriptEditor: NSViewRepresentable {
    @Binding var text: String
    var language: ScriptLanguage

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        guard let view = scroll.documentView as? NSTextView else { return scroll }
        view.isRichText = false
        view.allowsUndo = true
        view.font = NSFont.monospacedSystemFont(ofSize: 12.5, weight: .regular)
        view.isAutomaticQuoteSubstitutionEnabled = false
        view.isAutomaticDashSubstitutionEnabled = false
        view.isAutomaticTextReplacementEnabled = false
        view.isAutomaticSpellingCorrectionEnabled = false
        view.isContinuousSpellCheckingEnabled = false
        view.smartInsertDeleteEnabled = false
        view.textContainerInset = NSSize(width: 8, height: 10)
        view.backgroundColor = NSColor.textBackgroundColor.withAlphaComponent(0.6)
        view.drawsBackground = true
        view.string = text
        view.delegate = context.coordinator
        scroll.drawsBackground = false
        context.coordinator.highlight(view)
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let view = scroll.documentView as? NSTextView else { return }
        if view.string != text {
            view.string = text
            context.coordinator.highlight(view)
        } else if context.coordinator.language != language {
            context.coordinator.highlight(view)
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: ScriptEditor
        var language: ScriptLanguage

        init(_ parent: ScriptEditor) {
            self.parent = parent
            language = parent.language
        }

        func textDidChange(_ notification: Notification) {
            guard let view = notification.object as? NSTextView else { return }
            parent.text = view.string
            highlight(view)
        }

        func highlight(_ view: NSTextView) {
            language = parent.language
            guard let storage = view.textStorage else { return }
            let whole = NSRange(location: 0, length: storage.length)
            let font = NSFont.monospacedSystemFont(ofSize: 12.5, weight: .regular)
            storage.beginEditing()
            storage.setAttributes([.font: font, .foregroundColor: NSColor.labelColor], range: whole)
            for token in ScriptHighlighter.tokens(view.string, language: parent.language) where NSMaxRange(token.range) <= storage.length {
                switch token.kind {
                case .keyword:
                    storage.addAttributes([.foregroundColor: NSColor.systemPurple, .font: NSFont.monospacedSystemFont(ofSize: 12.5, weight: .semibold)], range: token.range)
                case .string: storage.addAttribute(.foregroundColor, value: NSColor.systemRed, range: token.range)
                case .comment: storage.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: token.range)
                case .number: storage.addAttribute(.foregroundColor, value: NSColor.systemBlue, range: token.range)
                case .application:
                    storage.addAttributes([.foregroundColor: NSColor.systemTeal, .font: NSFont.monospacedSystemFont(ofSize: 12.5, weight: .bold)], range: token.range)
                }
            }
            storage.endEditing()
            view.typingAttributes = [.font: font, .foregroundColor: NSColor.labelColor]
        }
    }
}
