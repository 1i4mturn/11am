import AppKit
import SwiftUI

/// A tab: one or more shells side by side or stacked.
struct TerminalTab: Identifiable {
    let id = UUID()
    var panes: [TerminalSession]
    var vertical = false
    var focused: UUID

    init(_ session: TerminalSession) {
        panes = [session]
        focused = session.id
    }
}

private struct SavedTab: Codable {
    var directories: [String]
    var vertical: Bool
    var transcripts: [String]
}

/// Johnny's terminal: tabs and split panes of real shells, search, history, and help that never runs anything by itself.
@MainActor
final class TerminalWorkspace: ObservableObject {
    @Published private(set) var tabs: [TerminalTab] = []
    @Published var selectedTab: UUID?
    @Published var paletteName: String { didSet { UserDefaults.standard.set(paletteName, forKey: "terminal.palette") } }
    @Published var fontSize: Double { didSet { UserDefaults.standard.set(fontSize, forKey: "terminal.fontSize") } }
    @Published var optionIsMeta: Bool { didSet { UserDefaults.standard.set(optionIsMeta, forKey: "terminal.optionIsMeta") } }
    @Published var searching = false
    @Published var query = "" { didSet { if query != oldValue { find() } } }
    @Published private(set) var matches: [(line: Int, columns: Range<Int>)] = []
    @Published var currentMatch: Int?
    @Published private(set) var suggestion: BrainRun?
    @Published private(set) var explanation: BrainRun?
    @Published private(set) var explaining = ""

    private let brain: Brain
    private var restored = false

    init(brain: Brain) {
        self.brain = brain
        paletteName = UserDefaults.standard.string(forKey: "terminal.palette") ?? TerminalPalette.ink.name
        let size = UserDefaults.standard.double(forKey: "terminal.fontSize")
        fontSize = size >= 9 ? size : 12.5
        optionIsMeta = UserDefaults.standard.bool(forKey: "terminal.optionIsMeta")
    }

    var palette: TerminalPalette { TerminalPalette.all.first { $0.name == paletteName } ?? .ink }

    var currentTab: TerminalTab? { tabs.first { $0.id == selectedTab } ?? tabs.first }

    var activeSession: TerminalSession? {
        guard let tab = currentTab else { return nil }
        return tab.panes.first { $0.id == tab.focused } ?? tab.panes.first
    }

    /// Opens last time's tabs, or a first one.
    func restoreIfNeeded() {
        guard !restored else { return }
        restored = true
        if let saved = JSONStore.load([SavedTab].self, from: "terminal-tabs"), !saved.isEmpty {
            for item in saved {
                let sessions = item.directories.enumerated().map { index, folder in
                    TerminalSession(directory: FileManager.default.fileExists(atPath: folder) ? folder : nil,
                                    restoredText: item.transcripts.indices.contains(index) ? item.transcripts[index] : nil)
                }
                guard let first = sessions.first else { continue }
                var tab = TerminalTab(first)
                tab.panes = sessions
                tab.vertical = item.vertical
                tabs.append(tab)
            }
            selectedTab = tabs.first?.id
        }
        if tabs.isEmpty { newTab() }
    }

    func save() {
        let saved = tabs.map { tab in
            SavedTab(directories: tab.panes.map(\.directory), vertical: tab.vertical, transcripts: tab.panes.map { $0.transcript(lines: 1_000) })
        }
        JSONStore.save(saved, to: "terminal-tabs")
    }

    func newTab(directory: String? = nil) {
        let session = TerminalSession(directory: directory ?? activeSession?.directory)
        let tab = TerminalTab(session)
        tabs.append(tab)
        selectedTab = tab.id
    }

    /// A new shell in a folder, from Files or anywhere else.
    func open(folder: URL) {
        restoreIfNeeded()
        var isDirectory: ObjCBool = false
        let path = FileManager.default.fileExists(atPath: folder.path, isDirectory: &isDirectory) && !isDirectory.boolValue
            ? folder.deletingLastPathComponent().path : folder.path
        newTab(directory: path)
    }

    func select(_ id: UUID) {
        selectedTab = id
        find()
    }

    func closeTab(_ id: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        tabs[index].panes.forEach { $0.terminate() }
        tabs.remove(at: index)
        if selectedTab == id { selectedTab = tabs.indices.contains(index) ? tabs[index].id : tabs.last?.id }
        if tabs.isEmpty { newTab() }
    }

    func split(vertical: Bool) {
        guard let index = tabs.firstIndex(where: { $0.id == currentTab?.id }), tabs[index].panes.count < 4 else { return }
        let session = TerminalSession(directory: activeSession?.directory)
        if tabs[index].panes.count == 1 { tabs[index].vertical = vertical }
        let position = (tabs[index].panes.firstIndex { $0.id == tabs[index].focused } ?? tabs[index].panes.count - 1) + 1
        tabs[index].panes.insert(session, at: position)
        tabs[index].focused = session.id
    }

    /// Closes the focused pane, or the tab when it's the last one.
    func closePane() {
        guard let index = tabs.firstIndex(where: { $0.id == currentTab?.id }) else { return }
        guard tabs[index].panes.count > 1, let pane = tabs[index].panes.firstIndex(where: { $0.id == tabs[index].focused }) else {
            closeTab(tabs[index].id)
            return
        }
        tabs[index].panes[pane].terminate()
        tabs[index].panes.remove(at: pane)
        tabs[index].focused = tabs[index].panes[min(pane, tabs[index].panes.count - 1)].id
    }

    func focus(_ session: TerminalSession) {
        guard let index = tabs.firstIndex(where: { tab in tab.panes.contains { $0 === session } }) else { return }
        if tabs[index].focused != session.id { tabs[index].focused = session.id }
    }

    func cycleTabs(forward: Bool) {
        guard let current = tabs.firstIndex(where: { $0.id == currentTab?.id }), tabs.count > 1 else { return }
        select(tabs[(current + (forward ? 1 : tabs.count - 1)) % tabs.count].id)
    }

    // MARK: Search

    func find() {
        guard searching, !query.isEmpty, let session = activeSession else {
            matches = []
            currentMatch = nil
            return
        }
        matches = session.emulator.find(query)
        currentMatch = matches.isEmpty ? nil : matches.count - 1
    }

    func nextMatch(forward: Bool) {
        guard !matches.isEmpty else { return }
        let current = currentMatch ?? matches.count - 1
        currentMatch = (current + (forward ? 1 : matches.count - 1)) % matches.count
    }

    // MARK: History

    /// Commands from this session and your shell history, newest first, without repeats.
    func history() -> [String] {
        var seen = Set<String>()
        var commands: [String] = []
        for command in (activeSession?.emulator.commands().map(\.command) ?? []).reversed() + Self.shellHistory() {
            let trimmed = command.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, seen.insert(trimmed).inserted else { continue }
            commands.append(trimmed)
        }
        return commands
    }

    static func shellHistory() -> [String] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        var lines: [String] = []
        for name in [".zsh_history", ".bash_history"] {
            guard let data = try? Data(contentsOf: home.appendingPathComponent(name)) else { continue }
            // zsh can write bytes that aren't valid UTF-8; read them leniently.
            for raw in String(decoding: data, as: UTF8.self).split(separator: "\n") {
                var line = String(raw)
                if line.hasPrefix(": "), let semicolon = line.firstIndex(of: ";") { line = String(line[line.index(after: semicolon)...]) }
                lines.append(line)
            }
        }
        return lines.reversed()
    }

    /// Letters in order, not necessarily together: "gco" finds "git checkout".
    static func fuzzy(_ query: String, _ text: String) -> Bool {
        let needle = query.lowercased().filter { !$0.isWhitespace }
        guard !needle.isEmpty else { return true }
        var index = needle.startIndex
        for character in text.lowercased() where character == needle[index] {
            index = needle.index(after: index)
            if index == needle.endIndex { return true }
        }
        return false
    }

    /// Types text at the prompt without pressing Return.
    func type(_ text: String) {
        activeSession?.write(Array(text.utf8))
    }

    // MARK: Johnny

    static let riskyPatterns = [
        "rm -", "rm ", "sudo", "mkfs", "dd if=", "diskutil", ":(){", "chmod -r", "chown -r", "> /dev/",
        "| sh", "| bash", "| zsh", "|sh", "|bash", "killall", "shutdown", "reboot", "launchctl", "defaults delete",
        "mv /", "git reset --hard", "git clean -f", "git push --force", "git push -f", "truncate", "srm ", "> ~",
    ]

    static func isRisky(_ command: String) -> Bool {
        let text = command.lowercased()
        if (text.contains("curl ") || text.contains("wget ")) && text.contains("|") { return true }
        return riskyPatterns.contains { text.contains($0) }
    }

    func suggestCommand(for request: String) {
        let request = request.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !request.isEmpty else { return }
        let folder = activeSession?.directory ?? "~"
        let system = """
        You are Johnny, the builder inside 11am, on macOS with \(URL(fileURLWithPath: TerminalSession.shellPath).lastPathComponent). \
        The shell is in \(folder). Reply in exactly two lines:
        COMMAND: a single shell command that does what's asked
        WHY: one short sentence explaining it
        Never use sudo. Prefer read-only commands. If it can't be done safely in one command, say so on the WHY line and leave COMMAND empty.
        """
        suggestion = brain.run(BrainRequest(system: system, prompt: request, weight: .quick))
    }

    func dismissSuggestion() { suggestion = nil }

    /// Explains the last command's output, or why it failed and how to fix it.
    func explainLast(fix: Bool) {
        guard let session = activeSession, let command = session.emulator.commands().last else { return }
        let output = String(session.emulator.output(of: command).suffix(6_000))
        let status = command.exitStatus.map { "It exited with status \($0)." } ?? ""
        explaining = command.command
        let system = fix
            ? """
              You are Johnny, the builder inside 11am, on macOS. A shell command failed. In two or three sentences say why, plainly. \
              Then give the corrected command on its own line starting with COMMAND:. Never use sudo unless it is the only fix, and say so.
              """
            : """
              You are Johnny, the builder inside 11am, on macOS. Explain what this command did and what its output means, \
              in a few short sentences for someone who isn't a programmer. Point out anything that needs attention.
              """
        explanation = brain.run(BrainRequest(system: system, prompt: "$ \(command.command)\n\(output)\n\(status)", weight: .quick))
    }

    func dismissExplanation() { explanation = nil }

}

// MARK: Views

struct TerminalPane: View {
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var terminal: TerminalWorkspace
    @EnvironmentObject private var brain: Brain
    @Environment(\.colorScheme) private var scheme
    @State private var ask = ""
    @State private var showsHistory = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TabStrip(showsHistory: $showsHistory)
            if terminal.searching { SearchBar().transition(.rise(theme.rise)) }
            if let tab = terminal.currentTab {
                PaneGroup(tab: tab)
                    .id(tab.id)
                    .clipShape(RoundedRectangle(cornerRadius: max(theme.radius - 4, 8), style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: max(theme.radius - 4, 8), style: .continuous).strokeBorder(theme.edge(scheme), lineWidth: 0.5)
                    }
            }
            if let session = terminal.activeSession {
                RiskBanner(session: session)
            }
            if let run = terminal.suggestion {
                CommandSuggestion(run: run)
                    .transition(.rise(theme.rise))
            }
            if let run = terminal.explanation {
                Explanation(run: run)
                    .transition(.rise(theme.rise))
            }
            HStack(spacing: 8) {
                AskField(placeholder: "Ask Johnny for a command: \"largest files in Downloads\"", text: $ask) {
                    terminal.suggestCommand(for: ask)
                }
                .disabled(brain.isBusy)
                if let session = terminal.activeSession {
                    LastCommandButtons(session: session)
                }
            }
        }
        .animation(theme.spring, value: terminal.searching)
        .onAppear { terminal.restoreIfNeeded() }
    }
}

/// Explain and Fix it, following the shell's last command.
private struct LastCommandButtons: View {
    @EnvironmentObject private var terminal: TerminalWorkspace
    @EnvironmentObject private var brain: Brain
    @ObservedObject var session: TerminalSession

    var body: some View {
        Button("Explain") { terminal.explainLast(fix: false) }
            .buttonStyle(.vellumSecondary)
            .disabled(session.lastCommand == nil || brain.isBusy)
            .help("Johnny explains what the last command did and what its output means")
        if let status = session.lastCommand?.exitStatus, status != 0 {
            Button("Fix it") { terminal.explainLast(fix: true) }
                .buttonStyle(.vellumPrimary)
                .disabled(brain.isBusy)
                .help("Johnny says why the last command failed and suggests a fix")
        }
    }
}

private struct TabStrip: View {
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var terminal: TerminalWorkspace
    @Environment(\.colorScheme) private var scheme
    @Binding var showsHistory: Bool

    var body: some View {
        HStack(spacing: 6) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(terminal.tabs) { tab in
                        TabChip(tab: tab, selected: tab.id == terminal.currentTab?.id)
                    }
                }
            }
            Button { terminal.newTab() } label: { Image(systemName: "plus") }
                .buttonStyle(.vellumSecondary)
                .keyboardShortcut("t", modifiers: .command)
                .help("New tab (⌘T)")
            Button { terminal.split(vertical: false) } label: { Image(systemName: "rectangle.split.2x1") }
                .buttonStyle(.vellumSecondary)
                .keyboardShortcut("d", modifiers: .command)
                .help("Split side by side (⌘D)")
            Button { terminal.split(vertical: true) } label: { Image(systemName: "rectangle.split.1x2") }
                .buttonStyle(.vellumSecondary)
                .keyboardShortcut("d", modifiers: [.command, .shift])
                .help("Split top and bottom (⇧⌘D)")
            Button { showsHistory.toggle() } label: { Image(systemName: "clock.arrow.circlepath") }
                .buttonStyle(.vellumSecondary)
                .keyboardShortcut("r", modifiers: [.command, .option])
                .help("Search your command history (⌥⌘R)")
                .popover(isPresented: $showsHistory, arrowEdge: .bottom) { HistoryPicker(shown: $showsHistory) }
            Button {
                terminal.searching.toggle()
                if !terminal.searching { terminal.query = "" }
                terminal.find()
            } label: { Image(systemName: "magnifyingglass") }
                .buttonStyle(.vellumSecondary)
                .keyboardShortcut("f", modifiers: .command)
                .help("Find in the scrollback (⌘F)")
            Menu {
                Picker("Colours", selection: $terminal.paletteName) {
                    ForEach(TerminalPalette.all, id: \.name) { palette in Text(palette.name).tag(palette.name) }
                }
                Divider()
                Button("Bigger text") { terminal.fontSize = min(terminal.fontSize + 1, 24) }
                Button("Smaller text") { terminal.fontSize = max(terminal.fontSize - 1, 9) }
                Toggle("Use Option as Meta", isOn: $terminal.optionIsMeta)
                Divider()
                Button("Clear the scrollback") { terminal.activeSession?.emulator.feed("\u{1B}[3J"); terminal.type("\u{0C}") }
                Button("Close pane") { terminal.closePane() }
            } label: {
                Image(systemName: "slider.horizontal.3")
            }
            .menuStyle(.button)
            .buttonStyle(.vellumSecondary)
            .fixedSize()
            Button("") { terminal.closePane() }
                .keyboardShortcut("w", modifiers: .command)
                .opacity(0)
                .frame(width: 0, height: 0)
            Button("") { terminal.cycleTabs(forward: true) }
                .keyboardShortcut(.tab, modifiers: .control)
                .opacity(0)
                .frame(width: 0, height: 0)
            Button("") { terminal.cycleTabs(forward: false) }
                .keyboardShortcut(.tab, modifiers: [.control, .shift])
                .opacity(0)
                .frame(width: 0, height: 0)
            Button("") { terminal.fontSize = min(terminal.fontSize + 1, 24) }
                .keyboardShortcut("=", modifiers: .command)
                .opacity(0)
                .frame(width: 0, height: 0)
            Button("") { terminal.fontSize = max(terminal.fontSize - 1, 9) }
                .keyboardShortcut("-", modifiers: .command)
                .opacity(0)
                .frame(width: 0, height: 0)
        }
    }
}

private struct TabChip: View {
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var terminal: TerminalWorkspace
    @Environment(\.colorScheme) private var scheme
    var tab: TerminalTab
    var selected: Bool
    @State private var hovering = false

    var body: some View {
        let session = tab.panes.first { $0.id == tab.focused } ?? tab.panes[0]
        ChipLabel(session: session, panes: tab.panes.count, selected: selected)
            .padding(.leading, 10)
            .padding(.trailing, 4)
            .padding(.vertical, 5)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(selected ? theme.well(scheme) : (hovering ? theme.well(scheme).opacity(0.5) : Color.clear))
            }
            .overlay(alignment: .trailing) {
                Button { terminal.closeTab(tab.id) } label: { Image(systemName: "xmark").font(.system(size: 8.5, weight: .bold)) }
                    .buttonStyle(.plain)
                    .foregroundStyle(theme.inkTertiary(scheme))
                    .padding(.trailing, 6)
                    .opacity(hovering || selected ? 1 : 0)
                    .help("Close tab")
            }
            .contentShape(Rectangle())
            .onTapGesture { terminal.select(tab.id) }
            .onHover { hovering = $0 }
    }
}

private struct ChipLabel: View {
    @EnvironmentObject private var theme: Theme
    @Environment(\.colorScheme) private var scheme
    @ObservedObject var session: TerminalSession
    var panes: Int
    var selected: Bool

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(session.isRunning ? Color.green.opacity(0.75) : theme.inkTertiary(scheme))
                .frame(width: 5, height: 5)
            Text(label)
                .font(.system(size: 11.5, weight: selected ? .semibold : .regular))
                .foregroundStyle(selected ? theme.ink(scheme) : theme.inkSecondary(scheme))
                .lineLimit(1)
            if panes > 1 {
                Text("\(panes)")
                    .font(.system(size: 9.5, weight: .semibold).monospacedDigit())
                    .foregroundStyle(theme.inkTertiary(scheme))
            }
            Color.clear.frame(width: 12, height: 1)
        }
        .frame(maxWidth: 220)
    }

    private var label: String {
        let folder = session.directory == NSHomeDirectory() ? "~" : URL(fileURLWithPath: session.directory).lastPathComponent
        let title = session.title
        return title.isEmpty || title == "zsh" || title == "bash" ? folder : title
    }
}

private struct PaneGroup: View {
    @EnvironmentObject private var terminal: TerminalWorkspace
    var tab: TerminalTab

    var body: some View {
        let layout = tab.vertical ? AnyLayout(VStackLayout(spacing: 1)) : AnyLayout(HStackLayout(spacing: 1))
        layout {
            ForEach(tab.panes) { session in
                PaneView(session: session, focused: session.id == tab.focused || tab.panes.count == 1, single: tab.panes.count == 1)
            }
        }
        .background(Color.black.opacity(0.35))
    }
}

private struct PaneView: View {
    @EnvironmentObject private var terminal: TerminalWorkspace
    @ObservedObject var session: TerminalSession
    var focused: Bool
    var single: Bool

    var body: some View {
        TerminalSurface(
            session: session,
            palette: terminal.palette,
            fontSize: CGFloat(terminal.fontSize),
            optionIsMeta: terminal.optionIsMeta,
            highlights: focused ? terminal.matches : [],
            currentHighlight: focused ? terminal.currentMatch : nil,
            focusOnAppear: focused,
            onFocus: { terminal.focus(session) },
            riskCheck: { TerminalWorkspace.isRisky($0) }
        )
        .overlay(alignment: .top) {
            if !single && focused {
                Rectangle().fill(Color.accentColor.opacity(0.7)).frame(height: 2)
            }
        }
        .frame(minWidth: 160, minHeight: 80)
    }
}

private struct SearchBar: View {
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var terminal: TerminalWorkspace
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(theme.inkTertiary(scheme))
            TextField("Find in the scrollback", text: $terminal.query)
                .textFieldStyle(.plain)
                .font(.system(size: 12.5))
                .onSubmit { terminal.nextMatch(forward: false) }
            Text(terminal.matches.isEmpty ? (terminal.query.isEmpty ? "" : "No matches") : "\((terminal.currentMatch ?? 0) + 1) of \(terminal.matches.count)")
                .font(.system(size: 11).monospacedDigit())
                .foregroundStyle(theme.inkTertiary(scheme))
            Button { terminal.nextMatch(forward: false) } label: { Image(systemName: "chevron.up") }
                .buttonStyle(.plain)
                .disabled(terminal.matches.isEmpty)
                .help("Earlier")
            Button { terminal.nextMatch(forward: true) } label: { Image(systemName: "chevron.down") }
                .buttonStyle(.plain)
                .disabled(terminal.matches.isEmpty)
                .help("Later")
            Button {
                terminal.searching = false
                terminal.query = ""
            } label: { Image(systemName: "xmark") }
                .buttonStyle(.plain)
                .keyboardShortcut(.escape, modifiers: [])
        }
        .foregroundStyle(theme.inkSecondary(scheme))
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(theme.well(scheme)))
    }
}

private struct HistoryPicker: View {
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var terminal: TerminalWorkspace
    @Environment(\.colorScheme) private var scheme
    @Binding var shown: Bool
    @State private var query = ""
    @State private var all: [String] = []

    var body: some View {
        let results = Array(all.filter { TerminalWorkspace.fuzzy(query, $0) }.prefix(60))
        VStack(alignment: .leading, spacing: 8) {
            TextField("Search history (letters in order: gco finds git checkout)", text: $query)
                .textFieldStyle(.roundedBorder)
                .onSubmit {
                    if let first = results.first { pick(first) }
                }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    ForEach(results, id: \.self) { command in
                        Button { pick(command) } label: {
                            Text(command)
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(theme.ink(scheme))
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 4)
                                .padding(.horizontal, 6)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(height: 280)
            Text("Picking one types it at the prompt. Nothing runs until you press Return.")
                .font(.system(size: 11))
                .foregroundStyle(theme.inkTertiary(scheme))
        }
        .padding(12)
        .frame(width: 460)
        .onAppear { all = terminal.history() }
    }

    private func pick(_ command: String) {
        terminal.type(command)
        shown = false
    }
}

private struct RiskBanner: View {
    @EnvironmentObject private var theme: Theme
    @Environment(\.colorScheme) private var scheme
    @ObservedObject var session: TerminalSession

    var body: some View {
        if let risky = session.pendingRisk {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle")
                Text("\(risky) can change or delete things. Press Return again to run it, or edit it first.")
                    .font(.system(size: 12))
                    .lineLimit(2)
                Spacer()
                Button("Don't run it") {
                    session.pendingRisk = nil
                    session.write([0x15])
                }
                .buttonStyle(.vellumSecondary)
            }
            .foregroundStyle(theme.ink(scheme))
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.orange.opacity(0.14)))
        }
    }
}

private struct CommandSuggestion: View {
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var terminal: TerminalWorkspace
    @Environment(\.colorScheme) private var scheme
    @ObservedObject var run: BrainRun

    var body: some View {
        let suggestion = BuildModel.parseSuggestion(run.text)
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 6) {
                if run.status == .done && !suggestion.command.isEmpty {
                    Text(suggestion.command)
                        .font(.system(size: 12.5, design: .monospaced))
                        .foregroundStyle(theme.ink(scheme))
                        .textSelection(.enabled)
                    if !suggestion.why.isEmpty {
                        Text(suggestion.why).font(.system(size: 11.5)).foregroundStyle(theme.inkSecondary(scheme))
                    }
                    HStack(spacing: 6) {
                        Button("Type it in") {
                            terminal.type(suggestion.command)
                            terminal.dismissSuggestion()
                        }
                        .buttonStyle(.vellumPrimary)
                        if TerminalWorkspace.isRisky(suggestion.command) {
                            Label("Can change or delete things", systemImage: "exclamationmark.triangle")
                                .font(.system(size: 11))
                                .foregroundStyle(Color.orange)
                        }
                    }
                } else {
                    RunView(run: run)
                }
            }
            Spacer(minLength: 0)
            Button { terminal.dismissSuggestion() } label: { Image(systemName: "xmark") }
                .buttonStyle(.plain)
                .foregroundStyle(theme.inkTertiary(scheme))
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(theme.well(scheme)))
    }
}

private struct Explanation: View {
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var terminal: TerminalWorkspace
    @Environment(\.colorScheme) private var scheme
    @ObservedObject var run: BrainRun

    var body: some View {
        let fix = BuildModel.parseSuggestion(run.text).command
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 6) {
                Text("$ \(terminal.explaining)")
                    .font(.system(size: 11.5, design: .monospaced))
                    .foregroundStyle(theme.inkTertiary(scheme))
                    .lineLimit(1)
                RunView(run: run)
                if run.status == .done && !fix.isEmpty {
                    Button("Type the fix in") {
                        terminal.type(fix)
                        terminal.dismissExplanation()
                    }
                    .buttonStyle(.vellumPrimary)
                }
            }
            Spacer(minLength: 0)
            Button { terminal.dismissExplanation() } label: { Image(systemName: "xmark") }
                .buttonStyle(.plain)
                .foregroundStyle(theme.inkTertiary(scheme))
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(theme.well(scheme)))
    }
}
