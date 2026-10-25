import SwiftUI

/// The places in the sandbox. Apps come first; the agent behind each one is the quiet worker.
enum AppSection: String, CaseIterable, Identifiable {
    case today, files, overnight, suite, lab

    var id: String { rawValue }

    var title: String {
        switch self {
        case .today: return "Today"
        case .files: return "Files"
        case .overnight: return "Overnight"
        case .suite: return "The Suite"
        case .lab: return "Design Lab"
        }
    }

    var monogram: String {
        switch self {
        case .today: return "le"
        case .files: return "bn"
        case .overnight: return "le"
        case .suite: return "11"
        case .lab: return "rt"
        }
    }

    var symbol: String {
        switch self {
        case .today: return "sun.horizon"
        case .files: return "doc.text.magnifyingglass"
        case .overnight: return "moon.stars"
        case .suite: return "square.grid.2x2"
        case .lab: return "slider.horizontal.3"
        }
    }

    /// ⌘1…⌘5
    var shortcutNumber: Int {
        (AppSection.allCases.firstIndex(of: self) ?? 0) + 1
    }

    var subtitle: String {
        switch self {
        case .today: return "Your day, and the 11am check-in"
        case .files: return "Find anything on this Mac"
        case .overnight: return "Heavy work, done while you sleep"
        case .suite: return "The apps that replace the subscriptions"
        case .lab: return "Tune the vellum, lock the look"
        }
    }
}

struct ActivityItem: Identifiable, Codable {
    var id = UUID()
    var date = Date()
    var monogram: String
    var text: String
}

@MainActor
final class AppModel: ObservableObject {
    @Published var section: AppSection = .today
    @Published var showsPane = true
    @Published private(set) var activity: [ActivityItem] = []

    let theme: Theme
    let machine: MachineProfile
    let brain: Brain
    let files: FileIndex
    let today: TodayModel
    let nightShift: NightShift

    init() {
        let machine = MachineProfile()
        let brain = Brain()
        let files = FileIndex()
        self.theme = Theme()
        self.machine = machine
        self.brain = brain
        self.files = files
        self.today = TodayModel(brain: brain, files: files)
        self.nightShift = NightShift(machine: machine)
        nightShift.attach(to: self)
    }

    func start() {
        machine.startMonitoring()
        files.load()
        today.refreshAccess()
        nightShift.start()
        log("le", "11am started on \(machine.chip) with \(machine.memoryGB) GB. Running in \(machine.tier.title) mode.")
    }

    func log(_ monogram: String, _ text: String) {
        activity.insert(ActivityItem(monogram: monogram, text: text), at: 0)
        if activity.count > 60 { activity.removeLast(activity.count - 60) }
    }
}
