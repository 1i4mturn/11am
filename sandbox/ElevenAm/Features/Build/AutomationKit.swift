import Foundation

// Johnny's automations: a trigger and steps that call scripts, the shell, agents, notes and notifications.
// The types and the runner have no UI, so they're tested on their own.

/// When something should run on a clock.
struct AutomationSchedule: Codable, Hashable, Sendable {
    enum Kind: String, Codable, CaseIterable, Identifiable, Sendable {
        case every, daily, weekdays, weekly

        var id: String { rawValue }

        var title: String {
            switch self {
            case .every: return "Every few minutes"
            case .daily: return "Every day"
            case .weekdays: return "Weekdays"
            case .weekly: return "Once a week"
            }
        }
    }

    var kind: Kind = .daily
    /// For `every`.
    var minutes = 60
    var hour = 9
    var minute = 0
    /// 1 is Sunday, as in Calendar.
    var weekday = 2

    /// The first time after `date` it should run.
    func next(after date: Date, calendar: Calendar = .current) -> Date {
        switch kind {
        case .every:
            return date.addingTimeInterval(TimeInterval(max(minutes, 1) * 60))
        case .daily, .weekdays, .weekly:
            var day = calendar.startOfDay(for: date)
            for _ in 0..<15 {
                if let candidate = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day), candidate > date {
                    let weekdayOfDay = calendar.component(.weekday, from: candidate)
                    switch kind {
                    case .daily: return candidate
                    case .weekdays: if (2...6).contains(weekdayOfDay) { return candidate }
                    case .weekly: if weekdayOfDay == weekday { return candidate }
                    case .every: break
                    }
                }
                day = calendar.date(byAdding: .day, value: 1, to: day) ?? day.addingTimeInterval(86_400)
            }
            return date.addingTimeInterval(86_400)
        }
    }

    var summary: String {
        let time = String(format: "%d:%02d %@", hour % 12 == 0 ? 12 : hour % 12, minute, hour < 12 ? "am" : "pm")
        switch kind {
        case .every: return minutes % 60 == 0 && minutes >= 60 ? "Every \(minutes / 60 == 1 ? "hour" : "\(minutes / 60) hours")" : "Every \(minutes) minutes"
        case .daily: return "Every day at \(time)"
        case .weekdays: return "Weekdays at \(time)"
        case .weekly:
            let name = Calendar.current.weekdaySymbols[max(0, min(weekday - 1, 6))]
            return "\(name)s at \(time)"
        }
    }
}

enum AutomationTrigger: Codable, Hashable, Sendable {
    case button
    case schedule(AutomationSchedule)
    /// A new file in a folder; only names matching the pattern (like "*.pdf"), if one is set.
    case folder(path: String, pattern: String)
    /// New email whose sender or subject contains these (either can be empty).
    case mail(from: String, subject: String)
    /// Some minutes before a calendar event whose title contains this (empty for any).
    case calendar(minutesBefore: Int, titleContains: String)

    var kindTitle: String {
        switch self {
        case .button: return "When I press Run"
        case .schedule: return "On a schedule"
        case .folder: return "When a file arrives in a folder"
        case .mail: return "When an email arrives"
        case .calendar: return "Before a calendar event"
        }
    }

    var summary: String {
        switch self {
        case .button: return "When you press Run"
        case .schedule(let schedule): return schedule.summary
        case .folder(let path, let pattern):
            let folder = (path as NSString).abbreviatingWithTildeInPath
            return pattern.isEmpty ? "New files in \(folder)" : "New \(pattern) in \(folder)"
        case .mail(let from, let subject):
            if from.isEmpty && subject.isEmpty { return "Any new email" }
            return ["New email", from.isEmpty ? nil : "from \(from)", subject.isEmpty ? nil : "about \u{201C}\(subject)\u{201D}"].compactMap { $0 }.joined(separator: " ")
        case .calendar(let minutes, let title):
            return "\(minutes) min before \(title.isEmpty ? "each event" : "events with \u{201C}\(title)\u{201D}")"
        }
    }
}

enum AutomationStep: Codable, Hashable, Sendable {
    /// A shell command; it gets the previous step's result as {{input}} and on its standard input.
    case shell(String)
    /// A script from the Scripts library.
    case script(UUID)
    /// Ask an agent; the answer becomes the result.
    case agent(String)
    /// A notification.
    case notify(title: String, body: String)
    /// Stop here (as skipped) unless the result passes.
    case condition(AutomationCondition)
    /// A shell command for each line of the result, with {{item}}.
    case forEach(String)
    /// Wait for you to say yes.
    case approval(String)
    /// Add the result to a note in Notes (made if it doesn't exist).
    case appendNote(title: String, text: String)
    /// One of your Shortcuts, given the result.
    case shortcut(String)
    /// The text of a document (PDF, Word, RTF, web page or plain text) at a path, usually {{trigger}}.
    case readText(String)

    var title: String {
        switch self {
        case .shell: return "Run a shell command"
        case .script: return "Run a script"
        case .agent: return "Ask an agent"
        case .notify: return "Show a notification"
        case .condition: return "Only continue if…"
        case .forEach: return "For each line…"
        case .approval: return "Ask me first"
        case .appendNote: return "Add to a note"
        case .shortcut: return "Run a shortcut"
        case .readText: return "Read a document's text"
        }
    }

    var symbol: String {
        switch self {
        case .shell: return "terminal"
        case .script: return "applescript"
        case .agent: return "sparkles"
        case .notify: return "bell"
        case .condition: return "arrow.triangle.branch"
        case .forEach: return "repeat"
        case .approval: return "hand.raised"
        case .appendNote: return "note.text"
        case .shortcut: return "square.2.layers.3d"
        case .readText: return "doc.text"
        }
    }
}

struct AutomationCondition: Codable, Hashable, Sendable {
    enum Test: String, Codable, CaseIterable, Identifiable, Sendable {
        case contains, lacks, isEmpty, isNotEmpty, succeeded

        var id: String { rawValue }

        var title: String {
            switch self {
            case .contains: return "the result contains"
            case .lacks: return "the result doesn't contain"
            case .isEmpty: return "the result is empty"
            case .isNotEmpty: return "the result isn't empty"
            case .succeeded: return "the last step worked"
            }
        }
    }

    var test: Test = .isNotEmpty
    var text = ""

    func passes(result: String, succeeded: Bool) -> Bool {
        let trimmed = result.trimmingCharacters(in: .whitespacesAndNewlines)
        switch test {
        case .contains: return trimmed.localizedCaseInsensitiveContains(text)
        case .lacks: return !trimmed.localizedCaseInsensitiveContains(text)
        case .isEmpty: return trimmed.isEmpty
        case .isNotEmpty: return !trimmed.isEmpty
        case .succeeded: return succeeded
        }
    }
}

struct Automation: Codable, Identifiable, Hashable, Sendable {
    var id = UUID()
    var name: String
    var enabled = true
    var trigger: AutomationTrigger
    var steps: [AutomationStep]
    var created = Date()
}

struct AutomationRun: Codable, Identifiable, Hashable, Sendable {
    enum Status: String, Codable, Sendable {
        case running, waiting, succeeded, failed, skipped, stopped

        var title: String {
            switch self {
            case .running: return "Running"
            case .waiting: return "Waiting for you"
            case .succeeded: return "Done"
            case .failed: return "Failed"
            case .skipped: return "Skipped"
            case .stopped: return "Stopped"
            }
        }
    }

    var id = UUID()
    var automationID: UUID
    var name: String
    var started = Date()
    var finished: Date?
    var status = Status.running
    /// What set it off: a file, an email subject, an event.
    var trigger: String
    var log: [String] = []
    var output = ""
}

/// Fills in {{input}}, {{trigger}}, {{item}}, {{date}} and {{time}}.
enum AutomationTemplate {
    static func fill(_ text: String, input: String, trigger: String, item: String = "", now: Date = Date()) -> String {
        let day = DateFormatter()
        day.locale = Locale(identifier: "en_AU")
        day.dateFormat = "yyyy-MM-dd"
        let clock = DateFormatter()
        clock.locale = Locale(identifier: "en_AU")
        clock.dateFormat = "HH:mm"
        return text
            .replacingOccurrences(of: "{{input}}", with: input.trimmingCharacters(in: .whitespacesAndNewlines))
            .replacingOccurrences(of: "{{trigger}}", with: trigger)
            .replacingOccurrences(of: "{{item}}", with: item)
            .replacingOccurrences(of: "{{date}}", with: day.string(from: now))
            .replacingOccurrences(of: "{{time}}", with: clock.string(from: now))
    }

    /// Wraps a value in single quotes for the shell.
    static func quoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// For shell commands, values go in quoted, so a file name or an email subject can't change the command.
    static func fillShell(_ text: String, input: String, trigger: String, item: String = "") -> String {
        let marker = "\u{1}"
        var prepared = text
        for (name, code) in [("item", "I"), ("trigger", "T"), ("input", "N")] {
            prepared = prepared
                .replacingOccurrences(of: "'{{\(name)}}'", with: "{{\(name)}}")
                .replacingOccurrences(of: "\"{{\(name)}}\"", with: "{{\(name)}}")
                .replacingOccurrences(of: "{{\(name)}}", with: marker + code)
        }
        return fill(prepared, input: input, trigger: trigger)
            .replacingOccurrences(of: marker + "I", with: quoted(item))
            .replacingOccurrences(of: marker + "T", with: quoted(trigger))
            .replacingOccurrences(of: marker + "N", with: quoted(input.trimmingCharacters(in: .whitespacesAndNewlines)))
    }
}

/// What the runner needs from the rest of 11am.
struct AutomationServices {
    var shell: (_ command: String, _ input: String) async -> (output: String, ok: Bool)
    var script: (_ id: UUID, _ input: String) async -> (output: String, ok: Bool)
    var agent: (_ prompt: String) async -> String?
    var notify: (_ title: String, _ body: String) -> Void
    var appendNote: (_ title: String, _ text: String) -> Void
    var approve: (_ message: String) async -> Bool
    var shortcut: (_ name: String, _ input: String) async -> (output: String, ok: Bool)
    var readText: (_ path: String) -> String?

    /// Shell commands through zsh, for tests and the app alike.
    static func runShell(_ command: String, input: String) async -> (output: String, ok: Bool) {
        guard let result = try? await ScriptRun.run(command, language: .shell, input: input, timeout: 600) else { return ("", false) }
        let text = result.output + (result.status == 0 || result.log.isEmpty ? "" : result.log)
        return (text, result.status == 0)
    }
}

/// Runs on the main actor so the log, notes and notifications are touched from one place; the slow steps await elsewhere.
@MainActor
enum AutomationRunner {
    /// Runs the steps in order. Each step's result is the next step's {{input}}.
    static func run(_ automation: Automation, trigger: String, services: AutomationServices,
                    log: @escaping (String) -> Void, waiting: @escaping (Bool) -> Void = { _ in },
                    stopped: () -> Bool = { false }) async -> (status: AutomationRun.Status, output: String) {
        var result = trigger
        var ok = true
        for (index, step) in automation.steps.enumerated() {
            if stopped() { return (.stopped, result) }
            let number = "Step \(index + 1)"
            switch step {
            case .shell(let command):
                let filled = AutomationTemplate.fillShell(command, input: result, trigger: trigger)
                log("\(number): $ \(filled)")
                let outcome = await services.shell(filled, result)
                result = outcome.output
                ok = outcome.ok
                if !result.isEmpty { log(String(result.prefix(2_000))) }
                if !ok {
                    log("\(number) failed.")
                    return (.failed, result)
                }
            case .script(let id):
                log("\(number): running a script")
                let outcome = await services.script(id, result)
                result = outcome.output
                ok = outcome.ok
                if !result.isEmpty { log(String(result.prefix(2_000))) }
                if !ok {
                    log("\(number): the script failed.")
                    return (.failed, result)
                }
            case .agent(let prompt):
                let filled = AutomationTemplate.fill(prompt, input: result, trigger: trigger)
                log("\(number): asking an agent")
                guard let answer = await services.agent(filled) else {
                    log("\(number): no answer.")
                    return (.failed, result)
                }
                result = answer
                ok = true
                log(String(answer.prefix(2_000)))
            case .notify(let title, let body):
                let filledTitle = AutomationTemplate.fill(title, input: result, trigger: trigger)
                let filledBody = AutomationTemplate.fill(body, input: result, trigger: trigger)
                services.notify(filledTitle, filledBody)
                log("\(number): notified \u{201C}\(filledTitle)\u{201D}")
            case .condition(let condition):
                guard condition.passes(result: result, succeeded: ok) else {
                    log("\(number): \(condition.test.title)\(condition.text.isEmpty ? "" : " \u{201C}\(condition.text)\u{201D}") — no, so it stops here.")
                    return (.skipped, result)
                }
                log("\(number): \(condition.test.title)\(condition.text.isEmpty ? "" : " \u{201C}\(condition.text)\u{201D}") — yes.")
            case .forEach(let command):
                let items = result.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                log("\(number): \(items.count) \(items.count == 1 ? "item" : "items")")
                var outputs: [String] = []
                for item in items {
                    if stopped() { return (.stopped, result) }
                    let filled = AutomationTemplate.fillShell(command, input: result, trigger: trigger, item: item)
                    let outcome = await services.shell(filled, item)
                    outputs.append(outcome.output.trimmingCharacters(in: .newlines))
                    if !outcome.ok {
                        log("\(number): failed on \(item)")
                        return (.failed, outputs.joined(separator: "\n"))
                    }
                }
                result = outputs.filter { !$0.isEmpty }.joined(separator: "\n")
                ok = true
            case .approval(let message):
                let filled = AutomationTemplate.fill(message, input: result, trigger: trigger)
                log("\(number): waiting for your OK — \(filled)")
                waiting(true)
                let approved = await services.approve(filled)
                waiting(false)
                guard approved else {
                    log("\(number): you said no.")
                    return (.stopped, result)
                }
                log("\(number): approved.")
            case .appendNote(let title, let text):
                let filledTitle = AutomationTemplate.fill(title, input: result, trigger: trigger)
                let filledText = AutomationTemplate.fill(text.isEmpty ? "{{input}}" : text, input: result, trigger: trigger)
                services.appendNote(filledTitle, filledText)
                log("\(number): added to the note \u{201C}\(filledTitle)\u{201D}")
            case .readText(let path):
                let filled = AutomationTemplate.fill(path.isEmpty ? "{{trigger}}" : path, input: result, trigger: trigger)
                let expanded = (filled as NSString).expandingTildeInPath
                guard let text = services.readText(expanded) else {
                    log("\(number): couldn't read \(filled)")
                    return (.failed, result)
                }
                result = String(text.prefix(40_000))
                ok = true
                log("\(number): read \(result.count) characters from \((expanded as NSString).lastPathComponent)")
            case .shortcut(let name):
                log("\(number): running the shortcut \u{201C}\(name)\u{201D}")
                let outcome = await services.shortcut(name, result)
                result = outcome.output
                ok = outcome.ok
                if !ok {
                    log("\(number): the shortcut failed.")
                    return (.failed, result)
                }
            }
        }
        return (.succeeded, result)
    }
}

/// Spots files that are new in a folder since last time it looked.
struct FolderSnapshot: Sendable {
    private(set) var names: Set<String>

    init(path: String) {
        names = Set((try? FileManager.default.contentsOfDirectory(atPath: path)) ?? [])
    }

    /// New files since the last look that match a pattern like "*.pdf" (empty matches all). Hidden and partial downloads are left out.
    mutating func newFiles(in path: String, matching pattern: String) -> [String] {
        let now = Set((try? FileManager.default.contentsOfDirectory(atPath: path)) ?? [])
        let added = now.subtracting(names)
        names = now
        return added.filter { name in
            guard !name.hasPrefix("."), !name.hasSuffix(".download"), !name.hasSuffix(".crdownload"), !name.hasSuffix(".part") else { return false }
            return Self.matches(name, pattern)
        }.sorted().map { (path as NSString).appendingPathComponent($0) }
    }

    static func matches(_ name: String, _ pattern: String) -> Bool {
        let patterns = pattern.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard !patterns.isEmpty else { return true }
        return patterns.contains { glob in
            let escaped = NSRegularExpression.escapedPattern(for: glob).replacingOccurrences(of: "\\*", with: ".*").replacingOccurrences(of: "\\?", with: ".")
            return name.range(of: "^\(escaped)$", options: [.regularExpression, .caseInsensitive]) != nil
        }
    }
}

/// Ready-made automations to start from.
enum AutomationTemplates {
    static func all(home: String = NSHomeDirectory()) -> [Automation] {
        let downloads = (home as NSString).appendingPathComponent("Downloads")
        return [
            Automation(name: "Tidy screenshots off the Desktop", enabled: false,
                       trigger: .schedule(AutomationSchedule(kind: .daily, hour: 18, minute: 0)),
                       steps: [
                           .shell("mkdir -p ~/Pictures/Screenshots && find ~/Desktop -maxdepth 1 -name 'Screenshot*' -print"),
                           .condition(AutomationCondition(test: .isNotEmpty)),
                           .forEach("mv {{item}} ~/Pictures/Screenshots/ && basename {{item}}"),
                           .notify(title: "Screenshots tidied", body: "{{input}}"),
                       ]),
            Automation(name: "Summarise new PDFs in Downloads", enabled: false,
                       trigger: .folder(path: downloads, pattern: "*.pdf"),
                       steps: [
                           .readText("{{trigger}}"),
                           .agent("Summarise this document in five bullet points for a busy founder:\n\n{{input}}"),
                           .appendNote(title: "PDF summaries", text: "## {{date}} · {{trigger}}\n\n{{input}}"),
                           .notify(title: "Summarised a PDF", body: "It's in Notes › PDF summaries."),
                       ]),
            Automation(name: "Flag invoices that arrive by email", enabled: false,
                       trigger: .mail(from: "", subject: "invoice"),
                       steps: [
                           .notify(title: "An invoice arrived", body: "{{trigger}}"),
                           .appendNote(title: "Invoices to pay", text: "- [ ] {{date}}: {{trigger}}"),
                       ]),
            Automation(name: "Prep me before meetings", enabled: false,
                       trigger: .calendar(minutesBefore: 10, titleContains: ""),
                       steps: [
                           .agent("In three short bullet points, what should I have ready for this meeting? {{trigger}}"),
                           .notify(title: "Meeting in 10 minutes", body: "{{input}}"),
                       ]),
            Automation(name: "Clear out old downloads (asks first)", enabled: false,
                       trigger: .schedule(AutomationSchedule(kind: .weekly, hour: 17, minute: 30, weekday: 6)),
                       steps: [
                           .shell("find ~/Downloads -maxdepth 1 -type f -mtime +30 -print"),
                           .condition(AutomationCondition(test: .isNotEmpty)),
                           .approval("Move {{input}} to the Bin?"),
                           .forEach("mv {{item}} ~/.Trash/"),
                           .notify(title: "Old downloads moved to the Bin", body: "Done."),
                       ]),
        ]
    }
}
