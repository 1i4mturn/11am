import AppKit
import PDFKit
import SwiftUI
import UserNotifications

/// Runs your automations: watches the clock, folders, mail and the calendar, and keeps a history of every run.
@MainActor
final class AutomationsModel: ObservableObject {
    @Published private(set) var automations: [Automation] = []
    @Published var selectedID: UUID?
    @Published private(set) var runs: [AutomationRun] = []
    /// Runs waiting for your OK, with what they're asking.
    @Published private(set) var approvals: [UUID: String] = [:]

    private let brain: Brain
    private let scripts: ScriptsModel
    private let notes: NotesModel
    private let mail: MailModel
    private let calendar: CalendarModel
    private var timer: Timer?
    private var nextFire: [UUID: Date] = [:]
    private var folders: [UUID: (path: String, snapshot: FolderSnapshot, source: DispatchSourceFileSystemObject)] = [:]
    private var seenMail: Set<String>?
    private var firedEvents: Set<String> = []
    private var waiters: [UUID: CheckedContinuation<Bool, Never>] = [:]
    private var stopping: Set<UUID> = []
    private var saveTask: Task<Void, Never>?

    init(brain: Brain, scripts: ScriptsModel, notes: NotesModel, mail: MailModel, calendar: CalendarModel) {
        self.brain = brain
        self.scripts = scripts
        self.notes = notes
        self.mail = mail
        self.calendar = calendar
        automations = JSONStore.load([Automation].self, from: "automations") ?? AutomationTemplates.all()
        runs = JSONStore.load([AutomationRun].self, from: "automation-runs") ?? []
        // A run that was going when 11am quit didn't finish.
        for index in runs.indices where runs[index].status == .running || runs[index].status == .waiting {
            runs[index].status = .stopped
            runs[index].log.append("11am quit before this finished.")
        }
        selectedID = automations.first?.id
    }

    var selected: Automation? { automations.first { $0.id == selectedID } }

    func start() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        rewatch()
        tick()
    }

    // MARK: Editing

    private func changed() {
        rewatch()
        saveTask?.cancel()
        saveTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled else { return }
            JSONStore.save(automations, to: "automations")
        }
    }

    func flushSave() {
        saveTask?.cancel()
        JSONStore.save(automations, to: "automations")
        JSONStore.save(Array(runs.prefix(200)), to: "automation-runs")
    }

    func newAutomation() {
        let automation = Automation(name: "New automation", enabled: false, trigger: .button,
                                    steps: [.shell("echo Hello from 11am"), .notify(title: "Automation ran", body: "{{input}}")])
        automations.insert(automation, at: 0)
        selectedID = automation.id
        changed()
    }

    func add(template: Automation) {
        var copy = template
        copy.id = UUID()
        copy.created = Date()
        automations.insert(copy, at: 0)
        selectedID = copy.id
        changed()
    }

    func update(_ id: UUID, _ change: (inout Automation) -> Void) {
        guard let index = automations.firstIndex(where: { $0.id == id }) else { return }
        let before = automations[index]
        change(&automations[index])
        guard automations[index] != before else { return }
        if automations[index].trigger != before.trigger || automations[index].enabled != before.enabled { nextFire[id] = nil }
        changed()
    }

    func delete(_ id: UUID) {
        guard let index = automations.firstIndex(where: { $0.id == id }) else { return }
        automations.remove(at: index)
        if selectedID == id { selectedID = automations.indices.contains(index) ? automations[index].id : automations.last?.id }
        changed()
    }

    func duplicate(_ id: UUID) {
        guard var copy = automations.first(where: { $0.id == id }) else { return }
        copy.id = UUID()
        copy.name += " copy"
        copy.enabled = false
        automations.insert(copy, at: 0)
        selectedID = copy.id
        changed()
    }

    // MARK: Triggers

    private func tick() {
        let now = Date()
        for automation in automations where automation.enabled {
            switch automation.trigger {
            case .schedule(let schedule):
                guard let due = nextFire[automation.id] else {
                    nextFire[automation.id] = schedule.next(after: now)
                    continue
                }
                if now >= due {
                    nextFire[automation.id] = schedule.next(after: now)
                    fire(automation, trigger: "Scheduled · \(schedule.summary)")
                }
            case .calendar(let minutes, let title):
                for event in calendar.events where !event.isAllDay {
                    let until = event.start.timeIntervalSince(now)
                    guard until > 0, until <= Double(minutes * 60) + 30 else { continue }
                    guard title.isEmpty || event.title.localizedCaseInsensitiveContains(title) else { continue }
                    let key = "\(automation.id)|\(event.id)|\(event.start.timeIntervalSince1970)"
                    guard firedEvents.insert(key).inserted else { continue }
                    let time = event.start.formatted(date: .omitted, time: .shortened)
                    let people = event.attendees.prefix(6).map(\.name).filter { !$0.isEmpty }
                    var description = "\(event.title) at \(time)"
                    if !people.isEmpty { description += " with \(people.joined(separator: ", "))" }
                    if let location = event.location, !location.isEmpty { description += " (\(location))" }
                    fire(automation, trigger: description)
                }
            default:
                break
            }
        }
        checkMail()
    }

    private func checkMail() {
        let ids = Set(mail.messages.map(\.id))
        guard let seen = seenMail else {
            // Mail already here when 11am starts doesn't count as new.
            seenMail = ids
            return
        }
        let fresh = mail.messages.filter { !seen.contains($0.id) }
        seenMail = seen.union(ids)
        guard !fresh.isEmpty else { return }
        for automation in automations where automation.enabled {
            guard case .mail(let from, let subject) = automation.trigger else { continue }
            for message in fresh {
                let sender = "\(message.fromName) \(message.fromAddress)"
                guard from.isEmpty || sender.localizedCaseInsensitiveContains(from) else { continue }
                guard subject.isEmpty || message.subject.localizedCaseInsensitiveContains(subject) else { continue }
                fire(automation, trigger: "\(message.subject) — from \(message.fromName.isEmpty ? message.fromAddress : message.fromName)")
            }
        }
    }

    /// Watches the folders that folder triggers name.
    private func rewatch() {
        var wanted: [UUID: (path: String, pattern: String)] = [:]
        for automation in automations where automation.enabled {
            if case .folder(let path, let pattern) = automation.trigger {
                wanted[automation.id] = ((path as NSString).expandingTildeInPath, pattern)
            }
        }
        for (id, watch) in folders where wanted[id]?.path != watch.path {
            watch.source.cancel()
            folders[id] = nil
        }
        for (id, want) in wanted where folders[id] == nil {
            let descriptor = open(want.path, O_EVTONLY)
            guard descriptor >= 0 else { continue }
            let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor, eventMask: [.write, .rename], queue: .main)
            source.setEventHandler { [weak self] in
                // Downloads arrive in pieces; look a moment later.
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { self?.folderChanged(id) }
            }
            source.setCancelHandler { close(descriptor) }
            source.resume()
            folders[id] = (want.path, FolderSnapshot(path: want.path), source)
        }
    }

    private func folderChanged(_ id: UUID) {
        guard var watch = folders[id], let automation = automations.first(where: { $0.id == id }), automation.enabled,
              case .folder(_, let pattern) = automation.trigger else { return }
        let files = watch.snapshot.newFiles(in: watch.path, matching: pattern)
        folders[id] = watch
        for file in files { fire(automation, trigger: file) }
    }

    // MARK: Running

    func runNow(_ automation: Automation) {
        fire(automation, trigger: "Run by hand")
    }

    func retry(_ run: AutomationRun) {
        guard let automation = automations.first(where: { $0.id == run.automationID }) else { return }
        fire(automation, trigger: run.trigger)
    }

    func stop(_ run: AutomationRun) {
        stopping.insert(run.id)
        if let waiter = waiters.removeValue(forKey: run.id) {
            approvals[run.id] = nil
            waiter.resume(returning: false)
        }
    }

    func answer(_ runID: UUID, yes: Bool) {
        approvals[runID] = nil
        waiters.removeValue(forKey: runID)?.resume(returning: yes)
    }

    private func fire(_ automation: Automation, trigger: String) {
        let record = AutomationRun(automationID: automation.id, name: automation.name, trigger: trigger)
        runs.insert(record, at: 0)
        if runs.count > 200 { runs.removeLast(runs.count - 200) }
        let id = record.id
        let services = makeServices(runID: id, automation: automation)
        Task { @MainActor in
            let outcome = await AutomationRunner.run(
                automation, trigger: trigger, services: services,
                log: { [weak self] line in self?.edit(id) { $0.log.append(line) } },
                waiting: { [weak self] waiting in self?.edit(id) { $0.status = waiting ? .waiting : .running } },
                stopped: { [weak self] in self?.stopping.contains(id) ?? true }
            )
            edit(id) { run in
                run.status = outcome.status
                run.output = String(outcome.output.prefix(4_000))
                run.finished = Date()
            }
            stopping.remove(id)
            JSONStore.save(Array(runs.prefix(200)), to: "automation-runs")
        }
    }

    private func edit(_ id: UUID, _ change: (inout AutomationRun) -> Void) {
        guard let index = runs.firstIndex(where: { $0.id == id }) else { return }
        change(&runs[index])
    }

    private func makeServices(runID: UUID, automation: Automation) -> AutomationServices {
        AutomationServices(
            shell: { command, input in await AutomationServices.runShell(command, input: input) },
            script: { [weak self] id, input in
                guard let self else { return ("", false) }
                return await self.scripts.runForAutomation(id, input: input)
            },
            agent: { [weak self] prompt in
                guard let self else { return nil }
                let run = self.brain.run(BrainRequest(
                    system: "You are Johnny, running an automation inside 11am for its owner. Do exactly what's asked, briefly, with no preamble.",
                    prompt: prompt, weight: .quick))
                await run.finished()
                if case .failed = run.status { return nil }
                return run.text
            },
            notify: { title, body in Self.notify(title: title, body: body) },
            appendNote: { [weak self] title, text in self?.append(text, toNote: title) },
            approve: { [weak self] message in
                guard let self else { return false }
                Self.notify(title: "\(automation.name) needs your OK", body: message)
                return await withCheckedContinuation { continuation in
                    self.waiters[runID] = continuation
                    self.approvals[runID] = message
                }
            },
            shortcut: { name, input in
                let outcome = await ShortcutsBridge.run(name, input: input)
                return (outcome.output, outcome.error == nil)
            },
            readText: { path in Self.text(of: URL(fileURLWithPath: path)) }
        )
    }

    private func append(_ text: String, toNote title: String) {
        if let note = notes.note(titled: title) {
            notes.update(note.id, text: note.text.trimmingCharacters(in: .newlines) + "\n\n" + text)
        } else {
            _ = notes.newNote(text: "# \(title)\n\n\(text)")
        }
    }

    static func notify(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = String(body.prefix(400))
        let center = UNUserNotificationCenter.current()
        Task {
            guard (try? await center.requestAuthorization(options: [.alert, .sound])) == true else { return }
            try? await center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
        }
    }

    /// The text of a PDF, Word, RTF, web page or plain text file.
    static func text(of url: URL) -> String? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        if url.pathExtension.lowercased() == "pdf" { return PDFDocument(url: url)?.string }
        if let attributed = try? NSAttributedString(url: url, options: [:], documentAttributes: nil) { return attributed.string }
        return try? String(contentsOf: url, encoding: .utf8)
    }

    func runs(for id: UUID) -> [AutomationRun] { runs.filter { $0.automationID == id } }
}

// MARK: Views

struct AutomationsPane: View {
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var automations: AutomationsModel
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        GeometryReader { proxy in
            // Three columns when there's room; on a smaller window the runs go under the steps.
            let wide = proxy.size.width >= 1_020
            HStack(alignment: .top, spacing: 12) {
                AutomationList()
                    .frame(width: wide ? 230 : 200)
                if let automation = automations.selected {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            AutomationEditor(automation: automation)
                            if !wide {
                                RunHistory(automation: automation, scrolls: false)
                            }
                        }
                        .padding(.trailing, 4)
                    }
                    .scrollContentBackground(.hidden)
                    .frame(maxWidth: .infinity)
                    if wide {
                        RunHistory(automation: automation, scrolls: true)
                            .frame(width: 290)
                    }
                } else {
                    empty
                }
            }
        }
    }

    private var empty: some View {
        Group {
                Text("Make an automation with + or start from one of Johnny's.")
                    .font(.system(size: 12.5))
                    .foregroundStyle(theme.inkTertiary(scheme))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct AutomationList: View {
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var automations: AutomationsModel
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                SectionLabel(text: "Automations")
                Spacer()
                Menu {
                    Button("Blank automation") { automations.newAutomation() }
                    Divider()
                    ForEach(AutomationTemplates.all(), id: \.name) { template in
                        Button(template.name) { automations.add(template: template) }
                    }
                } label: { Image(systemName: "plus") }
                    .menuStyle(.button)
                    .buttonStyle(.plain)
                    .fixedSize()
                    .help("New automation")
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(automations.automations) { automation in
                        Button { automations.selectedID = automation.id } label: {
                            HStack(alignment: .top, spacing: 8) {
                                Circle()
                                    .fill(automation.enabled ? Color.green.opacity(0.8) : theme.inkTertiary(scheme).opacity(0.5))
                                    .frame(width: 6, height: 6)
                                    .padding(.top, 5)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(automation.name)
                                        .font(.system(size: 12.5, weight: automation.id == automations.selectedID ? .semibold : .regular))
                                        .foregroundStyle(theme.ink(scheme))
                                        .lineLimit(2)
                                    Text(automation.trigger.summary)
                                        .font(.system(size: 10.5))
                                        .foregroundStyle(theme.inkTertiary(scheme))
                                        .lineLimit(1)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .background(RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(automation.id == automations.selectedID ? theme.well(scheme) : Color.clear))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button("Duplicate") { automations.duplicate(automation.id) }
                            Button("Delete", role: .destructive) { automations.delete(automation.id) }
                        }
                    }
                }
            }
        }
        .padding(12)
        .frame(maxHeight: .infinity, alignment: .top)
        .vellum(level: 3, radius: max(theme.radius - 4, 8))
    }
}

private struct AutomationEditor: View {
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var automations: AutomationsModel
    @EnvironmentObject private var scripts: ScriptsModel
    @Environment(\.colorScheme) private var scheme
    var automation: Automation

    private func edit(_ change: (inout Automation) -> Void) { automations.update(automation.id, change) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                TextField("Name", text: Binding(get: { automation.name }, set: { value in edit { $0.name = value } }))
                    .textFieldStyle(.plain)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(theme.ink(scheme))
                Spacer()
                Toggle("On", isOn: Binding(get: { automation.enabled }, set: { value in edit { $0.enabled = value } }))
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .help(automation.enabled ? "It runs by itself when its trigger happens" : "It only runs when you press Run")
                Button { automations.runNow(automation) } label: { Label("Run", systemImage: "play.fill") }
                    .buttonStyle(.vellumPrimary)
            }

            SectionLabel(text: "When")
            TriggerEditor(trigger: Binding(get: { automation.trigger }, set: { value in edit { $0.trigger = value } }))

            SectionLabel(text: "Do")
            ForEach(Array(automation.steps.enumerated()), id: \.offset) { index, step in
                StepRow(index: index, step: step, count: automation.steps.count,
                        onChange: { value in edit { $0.steps[index] = value } },
                        onMove: { offset in
                            edit { automation in
                                let target = index + offset
                                guard automation.steps.indices.contains(target) else { return }
                                automation.steps.swapAt(index, target)
                            }
                        },
                        onDelete: { edit { $0.steps.remove(at: index) } })
            }
            Menu {
                Button("Run a shell command") { edit { $0.steps.append(.shell("echo {{input}}")) } }
                Button("Run a script") { edit { $0.steps.append(.script(scripts.scripts.first?.id ?? UUID())) } }
                Button("Ask an agent") { edit { $0.steps.append(.agent("Summarise this in one line: {{input}}")) } }
                Button("Read a document's text") { edit { $0.steps.append(.readText("{{trigger}}")) } }
                Button("Run a shortcut") { edit { $0.steps.append(.shortcut(scripts.shortcuts.first ?? "")) } }
                Divider()
                Button("Only continue if…") { edit { $0.steps.append(.condition(AutomationCondition())) } }
                Button("For each line…") { edit { $0.steps.append(.forEach("echo {{item}}")) } }
                Button("Ask me first") { edit { $0.steps.append(.approval("Carry on with {{input}}?")) } }
                Divider()
                Button("Add to a note") { edit { $0.steps.append(.appendNote(title: "Automation log", text: "- {{date}} {{time}}: {{input}}")) } }
                Button("Show a notification") { edit { $0.steps.append(.notify(title: automation.name, body: "{{input}}")) } }
            } label: {
                Label("Add a step", systemImage: "plus")
            }
            .menuStyle(.button)
            .buttonStyle(.vellumSecondary)
            .fixedSize()

            Text("Each step gets the one before's result as {{input}}. {{trigger}} is what set it off (a file, an email, a meeting), {{item}} is each line in For each, and {{date}} and {{time}} are now. In shell commands they go in quoted, so a file name can't change the command.")
                .font(.system(size: 11))
                .foregroundStyle(theme.inkTertiary(scheme))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .vellum(level: 3, radius: max(theme.radius - 4, 8))
        .onAppear { if scripts.shortcuts.isEmpty { scripts.loadShortcuts() } }
    }
}

private struct TriggerEditor: View {
    @EnvironmentObject private var theme: Theme
    @Environment(\.colorScheme) private var scheme
    @Binding var trigger: AutomationTrigger

    private enum Kind: String, CaseIterable, Identifiable {
        case button, schedule, folder, mail, calendar
        var id: String { rawValue }
    }

    private var kind: Kind {
        switch trigger {
        case .button: return .button
        case .schedule: return .schedule
        case .folder: return .folder
        case .mail: return .mail
        case .calendar: return .calendar
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("", selection: Binding(get: { kind }, set: { value in
                switch value {
                case .button: trigger = .button
                case .schedule: trigger = .schedule(AutomationSchedule())
                case .folder: trigger = .folder(path: NSHomeDirectory() + "/Downloads", pattern: "")
                case .mail: trigger = .mail(from: "", subject: "")
                case .calendar: trigger = .calendar(minutesBefore: 10, titleContains: "")
                }
            })) {
                Text("When I press Run").tag(Kind.button)
                Text("On a schedule").tag(Kind.schedule)
                Text("When a file arrives in a folder").tag(Kind.folder)
                Text("When an email arrives").tag(Kind.mail)
                Text("Before a calendar event").tag(Kind.calendar)
            }
            .labelsHidden()
            .fixedSize()
            switch trigger {
            case .button:
                EmptyView()
            case .schedule(let schedule):
                HStack(spacing: 8) {
                    Picker("", selection: Binding(get: { schedule.kind }, set: { value in var copy = schedule; copy.kind = value; trigger = .schedule(copy) })) {
                        ForEach(AutomationSchedule.Kind.allCases) { kind in Text(kind.title).tag(kind) }
                    }
                    .labelsHidden()
                    .fixedSize()
                    if schedule.kind == .every {
                        Stepper("every \(schedule.minutes) min", value: Binding(get: { schedule.minutes }, set: { value in
                            var copy = schedule; copy.minutes = value; trigger = .schedule(copy)
                        }), in: 5...1_440, step: 5)
                    } else {
                        if schedule.kind == .weekly {
                            Picker("", selection: Binding(get: { schedule.weekday }, set: { value in var copy = schedule; copy.weekday = value; trigger = .schedule(copy) })) {
                                ForEach(1...7, id: \.self) { day in Text(Calendar.current.weekdaySymbols[day - 1]).tag(day) }
                            }
                            .labelsHidden()
                            .fixedSize()
                        }
                        DatePicker("", selection: Binding(get: {
                            Calendar.current.date(bySettingHour: schedule.hour, minute: schedule.minute, second: 0, of: Date()) ?? Date()
                        }, set: { value in
                            var copy = schedule
                            copy.hour = Calendar.current.component(.hour, from: value)
                            copy.minute = Calendar.current.component(.minute, from: value)
                            trigger = .schedule(copy)
                        }), displayedComponents: .hourAndMinute)
                        .labelsHidden()
                        .fixedSize()
                    }
                }
                .font(.system(size: 12))
            case .folder(let path, let pattern):
                HStack(spacing: 8) {
                    Text((path as NSString).abbreviatingWithTildeInPath)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(theme.ink(scheme))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Button("Choose…") {
                        let panel = NSOpenPanel()
                        panel.canChooseDirectories = true
                        panel.canChooseFiles = false
                        if panel.runModal() == .OK, let url = panel.url { trigger = .folder(path: url.path, pattern: pattern) }
                    }
                    .buttonStyle(.vellumSecondary)
                    TextField("Only these, like *.pdf, *.png", text: Binding(get: { pattern }, set: { value in trigger = .folder(path: path, pattern: value) }))
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 200)
                }
            case .mail(let from, let subject):
                HStack(spacing: 8) {
                    TextField("From (name or address)", text: Binding(get: { from }, set: { value in trigger = .mail(from: value, subject: subject) }))
                        .textFieldStyle(.roundedBorder)
                    TextField("Subject contains", text: Binding(get: { subject }, set: { value in trigger = .mail(from: from, subject: value) }))
                        .textFieldStyle(.roundedBorder)
                }
            case .calendar(let minutes, let title):
                HStack(spacing: 8) {
                    Stepper("\(minutes) min before", value: Binding(get: { minutes }, set: { value in trigger = .calendar(minutesBefore: value, titleContains: title) }), in: 1...120)
                        .fixedSize()
                    TextField("Events whose title contains (or leave empty)", text: Binding(get: { title }, set: { value in
                        trigger = .calendar(minutesBefore: minutes, titleContains: value)
                    }))
                    .textFieldStyle(.roundedBorder)
                }
                .font(.system(size: 12))
            }
        }
    }
}

private struct StepRow: View {
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var scripts: ScriptsModel
    @Environment(\.colorScheme) private var scheme
    var index: Int
    var step: AutomationStep
    var count: Int
    var onChange: (AutomationStep) -> Void
    var onMove: (Int) -> Void
    var onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("\(index + 1)")
                    .font(.system(size: 10.5, weight: .bold).monospacedDigit())
                    .foregroundStyle(theme.inkTertiary(scheme))
                    .frame(width: 14)
                Image(systemName: step.symbol)
                    .foregroundStyle(theme.inkSecondary(scheme))
                Text(step.title)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(theme.ink(scheme))
                Spacer()
                Button { onMove(-1) } label: { Image(systemName: "chevron.up") }.buttonStyle(.plain).disabled(index == 0)
                Button { onMove(1) } label: { Image(systemName: "chevron.down") }.buttonStyle(.plain).disabled(index == count - 1)
                Button(action: onDelete) { Image(systemName: "trash") }.buttonStyle(.plain)
            }
            .foregroundStyle(theme.inkSecondary(scheme))
            fields
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(theme.well(scheme)))
    }

    @ViewBuilder
    private var fields: some View {
        switch step {
        case .shell(let command):
            code(command) { onChange(.shell($0)) }
        case .forEach(let command):
            code(command) { onChange(.forEach($0)) }
        case .script(let id):
            Picker("", selection: Binding(get: { id }, set: { onChange(.script($0)) })) {
                ForEach(scripts.scripts) { script in Text("\(script.name) · \(script.language.title)").tag(script.id) }
            }
            .labelsHidden()
        case .agent(let prompt):
            field("What to ask", prompt) { onChange(.agent($0)) }
        case .notify(let title, let body):
            field("Title", title) { onChange(.notify(title: $0, body: body)) }
            field("Message", body) { onChange(.notify(title: title, body: $0)) }
        case .condition(let condition):
            HStack(spacing: 8) {
                Picker("", selection: Binding(get: { condition.test }, set: { value in var copy = condition; copy.test = value; onChange(.condition(copy)) })) {
                    ForEach(AutomationCondition.Test.allCases) { test in Text(test.title).tag(test) }
                }
                .labelsHidden()
                .fixedSize()
                if condition.test == .contains || condition.test == .lacks {
                    TextField("text", text: Binding(get: { condition.text }, set: { value in var copy = condition; copy.text = value; onChange(.condition(copy)) }))
                        .textFieldStyle(.roundedBorder)
                }
            }
        case .approval(let message):
            field("What to ask you", message) { onChange(.approval($0)) }
        case .appendNote(let title, let text):
            field("Note title", title) { onChange(.appendNote(title: $0, text: text)) }
            field("What to add", text) { onChange(.appendNote(title: title, text: $0)) }
        case .shortcut(let name):
            if scripts.shortcuts.isEmpty {
                field("Shortcut name", name) { onChange(.shortcut($0)) }
            } else {
                Picker("", selection: Binding(get: { name }, set: { onChange(.shortcut($0)) })) {
                    ForEach(scripts.shortcuts, id: \.self) { shortcut in Text(shortcut).tag(shortcut) }
                }
                .labelsHidden()
            }
        case .readText(let path):
            field("File (usually {{trigger}})", path) { onChange(.readText($0)) }
        }
    }

    private func code(_ value: String, _ set: @escaping (String) -> Void) -> some View {
        TextField("command", text: Binding(get: { value }, set: set), axis: .vertical)
            .textFieldStyle(.plain)
            .font(.system(size: 12, design: .monospaced))
            .padding(6)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.black.opacity(0.05)))
            .lineLimit(1...6)
    }

    private func field(_ label: String, _ value: String, _ set: @escaping (String) -> Void) -> some View {
        TextField(label, text: Binding(get: { value }, set: set), axis: .vertical)
            .textFieldStyle(.roundedBorder)
            .font(.system(size: 12))
            .lineLimit(1...5)
    }
}

private struct RunHistory: View {
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var automations: AutomationsModel
    @Environment(\.colorScheme) private var scheme
    var automation: Automation
    /// In its own column it scrolls; under the steps it grows with them.
    var scrolls: Bool
    @State private var expanded: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: "Runs")
            let runs = automations.runs(for: automation.id)
            if runs.isEmpty {
                Text("Nothing yet. Press Run, or switch it on and wait for its trigger.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(theme.inkTertiary(scheme))
                    .fixedSize(horizontal: false, vertical: true)
            }
            if scrolls {
                ScrollView { list(runs) }
            } else {
                list(runs)
            }
        }
        .padding(12)
        .frame(maxHeight: scrolls ? CGFloat.infinity : nil, alignment: .top)
        .vellum(level: 3, radius: max(theme.radius - 4, 8))
    }

    private func list(_ runs: [AutomationRun]) -> some View {
                LazyVStack(alignment: .leading, spacing: 6) {
                    ForEach(runs.prefix(scrolls ? 200 : 8)) { run in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 6) {
                                Image(systemName: symbol(run.status))
                                    .foregroundStyle(color(run.status))
                                Text(run.status.title)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(theme.ink(scheme))
                                Spacer()
                                Text(run.started.formatted(date: .abbreviated, time: .shortened))
                                    .font(.system(size: 10.5))
                                    .foregroundStyle(theme.inkTertiary(scheme))
                            }
                            Text(run.trigger)
                                .font(.system(size: 11))
                                .foregroundStyle(theme.inkSecondary(scheme))
                                .lineLimit(2)
                            if let question = automations.approvals[run.id] {
                                Text(question)
                                    .font(.system(size: 11.5))
                                    .foregroundStyle(theme.ink(scheme))
                                    .fixedSize(horizontal: false, vertical: true)
                                HStack {
                                    Button("Yes, carry on") { automations.answer(run.id, yes: true) }.buttonStyle(.vellumPrimary)
                                    Button("No") { automations.answer(run.id, yes: false) }.buttonStyle(.vellumSecondary)
                                }
                            }
                            if expanded == run.id {
                                Text(run.log.joined(separator: "\n"))
                                    .font(.system(size: 10.5, design: .monospaced))
                                    .foregroundStyle(theme.inkSecondary(scheme))
                                    .textSelection(.enabled)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            HStack(spacing: 10) {
                                Button(expanded == run.id ? "Hide log" : "Log") { expanded = expanded == run.id ? nil : run.id }
                                if run.status == .failed || run.status == .stopped { Button("Retry") { automations.retry(run) } }
                                if run.status == .running || run.status == .waiting { Button("Stop") { automations.stop(run) } }
                            }
                            .buttonStyle(.plain)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(theme.inkSecondary(scheme))
                        }
                        .padding(9)
                        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(theme.well(scheme)))
                    }
                }
    }

    private func symbol(_ status: AutomationRun.Status) -> String {
        switch status {
        case .running: return "circle.dotted"
        case .waiting: return "hand.raised.fill"
        case .succeeded: return "checkmark.circle.fill"
        case .failed: return "xmark.octagon.fill"
        case .skipped: return "arrow.uturn.right.circle"
        case .stopped: return "stop.circle"
        }
    }

    private func color(_ status: AutomationRun.Status) -> Color {
        switch status {
        case .succeeded: return .green
        case .failed: return .red
        case .waiting: return .orange
        default: return theme.inkTertiary(scheme)
        }
    }
}
