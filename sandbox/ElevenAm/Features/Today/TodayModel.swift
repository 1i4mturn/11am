import EventKit
import Foundation
import UserNotifications

struct DayEvent: Identifiable {
    let id: String
    let title: String
    let start: Date
    let end: Date
    let isAllDay: Bool
    let location: String?
    let calendar: String
}

/// Leo-lite: today's calendar, the brief, and the 11am check-in.
@MainActor
final class TodayModel: ObservableObject {
    enum CalendarAccess { case unknown, granted, denied }

    @Published private(set) var events: [DayEvent] = []
    /// Today from Leo's calendar, with Outlook and Microsoft 365 as well as the calendars on this Mac.
    @Published private(set) var calendarEvents: [DayEvent]?
    @Published private(set) var access: CalendarAccess = .unknown
    @Published private(set) var briefRun: BrainRun?
    @Published private(set) var briefDate: Date?
    @Published private(set) var briefWasPreparedOvernight = false
    @Published var checkInEnabled: Bool {
        didSet {
            UserDefaults.standard.set(checkInEnabled, forKey: "today.checkin")
            Task { await scheduleCheckIn() }
        }
    }

    private let store = EKEventStore()
    private let brain: Brain
    private let files: FileIndex

    init(brain: Brain, files: FileIndex) {
        self.brain = brain
        self.files = files
        checkInEnabled = UserDefaults.standard.bool(forKey: "today.checkin")
    }

    var nextEvent: DayEvent? {
        (calendarEvents ?? events).first { !$0.isAllDay && $0.end > Date() }
    }

    /// Real events are showing, not the sample day.
    var isLive: Bool { calendarEvents != nil || access == .granted }

    func useCalendar(_ events: [DayEvent]?) {
        calendarEvents = events?.filter { $0.end > Calendar.current.startOfDay(for: Date()) }
    }

    func refreshAccess() {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess:
            access = .granted
            loadEvents()
        case .denied, .restricted, .writeOnly:
            access = .denied
        default:
            access = .unknown
        }
    }

    func requestAccess() async {
        do {
            let granted = try await store.requestFullAccessToEvents()
            access = granted ? .granted : .denied
            if granted { loadEvents() }
        } catch {
            access = .denied
        }
    }

    func loadEvents() {
        guard access == .granted else { return }
        let start = Calendar.current.startOfDay(for: Date())
        guard let end = Calendar.current.date(byAdding: .day, value: 1, to: start) else { return }
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        events = store.events(matching: predicate)
            .sorted { $0.startDate < $1.startDate }
            .map { event in
                DayEvent(
                    id: event.eventIdentifier ?? UUID().uuidString,
                    title: event.title ?? "Untitled",
                    start: event.startDate,
                    end: event.endDate,
                    isAllDay: event.isAllDay,
                    location: event.location,
                    calendar: event.calendar?.title ?? ""
                )
            }
    }

    /// Sample day shown until calendar access is granted, so the layout can be judged.
    var sampleEvents: [DayEvent] {
        let start = Calendar.current.startOfDay(for: Date())
        func at(_ hour: Int, _ minute: Int = 0) -> Date {
            Calendar.current.date(byAdding: .minute, value: hour * 60 + minute, to: start) ?? start
        }
        return [
            DayEvent(id: "s1", title: "Investor call", start: at(9), end: at(9, 45), isAllDay: false, location: "Zoom", calendar: "Sample"),
            DayEvent(id: "s2", title: "The 11am check-in", start: at(11), end: at(11, 10), isAllDay: false, location: nil, calendar: "Sample"),
            DayEvent(id: "s3", title: "Deep work", start: at(13), end: at(15), isAllDay: false, location: nil, calendar: "Sample"),
            DayEvent(id: "s4", title: "Design review", start: at(15, 30), end: at(16, 15), isAllDay: false, location: "Studio", calendar: "Sample"),
        ]
    }

    var shownEvents: [DayEvent] { calendarEvents ?? (access == .granted ? events : sampleEvents) }

    /// Writes the brief. Returns a one-line summary for the overnight log.
    @discardableResult
    func prepareBrief(overnight: Bool, allowCloud: Bool = true) async -> String {
        loadEvents()
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        let day = DateFormatter.localizedString(from: Date(), dateStyle: .full, timeStyle: .none)

        let eventLines = shownEvents.map { event in
            event.isAllDay ? "- All day: \(event.title)" : "- \(formatter.string(from: event.start)) \(event.title)\(event.location.map { " (\($0))" } ?? "")"
        }
        let fileLines = files.recentlyChanged(within: 24).prefix(8).map { "- \($0.name)" }

        let prompt = """
        Today is \(day).
        Calendar\(isLive ? "" : " (sample data)"):
        \(eventLines.isEmpty ? "- Nothing scheduled" : eventLines.joined(separator: "\n"))

        Files changed in the last day:
        \(fileLines.isEmpty ? "- None" : fileLines.joined(separator: "\n"))

        Write the brief.
        """

        let request = BrainRequest(
            system: """
            You are Leo, the chief of staff inside 11am, a Mac app for founders. Write a short daily brief: \
            three to five lines, plain sentences, no headings, no bullet symbols, no emoji. Lead with what matters most. \
            Mention protected focus time if there is a long gap. Never invent meetings, people or numbers.
            """,
            prompt: prompt,
            weight: .deep,
            allowsCloud: allowCloud
        )

        let run = brain.run(request)
        briefRun = run
        briefDate = Date()
        briefWasPreparedOvernight = overnight
        await run.finished()

        switch run.status {
        case .done: return "Ready (\(run.providerLabel))."
        case .failed(let message): return "Couldn't write the brief: \(message)"
        default: return "Stopped."
        }
    }

    // MARK: 11am check-in

    private func scheduleCheckIn() async {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ["checkin"])
        guard checkInEnabled else { return }
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        guard granted else { return }

        let content = UNMutableNotificationContent()
        content.title = "Your 11am check-in"
        content.body = "Here's what's done, what's waiting on you, and the shape of the afternoon."
        var components = DateComponents()
        components.hour = 11
        components.minute = 0
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        try? await center.add(UNNotificationRequest(identifier: "checkin", content: content, trigger: trigger))
    }
}
