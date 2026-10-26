import SwiftUI

/// The places in the sandbox. Apps come first; the agent behind each one is the quiet worker.
enum AppSection: String, CaseIterable, Identifiable {
    case today, mail, write, files, research, money, business, design, video, learn, build, overnight, suite, lab

    var id: String { rawValue }

    var title: String {
        switch self {
        case .today: return "Today"
        case .mail: return "Mail"
        case .write: return "Write"
        case .files: return "Files"
        case .research: return "Research"
        case .money: return "Money"
        case .business: return "Business"
        case .design: return "Design"
        case .video: return "Video"
        case .learn: return "Learn"
        case .build: return "Build"
        case .overnight: return "Overnight"
        case .suite: return "The Suite"
        case .lab: return "Design Lab"
        }
    }

    var monogram: String {
        switch self {
        case .today: return "le"
        case .mail: return "mc"
        case .write: return "wm"
        case .files: return "bn"
        case .research: return "jm"
        case .money: return "ge"
        case .business: return "cr"
        case .design: return "rt"
        case .video: return "co"
        case .learn: return "hr"
        case .build: return "jo"
        case .overnight: return "le"
        case .suite: return "11"
        case .lab: return "rt"
        }
    }

    var symbol: String {
        switch self {
        case .today: return "sun.horizon"
        case .mail: return "tray"
        case .write: return "pencil.line"
        case .files: return "doc.text.magnifyingglass"
        case .research: return "safari"
        case .money: return "chart.line.uptrend.xyaxis"
        case .business: return "briefcase"
        case .design: return "paintbrush.pointed"
        case .video: return "film"
        case .learn: return "graduationcap"
        case .build: return "hammer"
        case .overnight: return "moon.stars"
        case .suite: return "square.grid.2x2"
        case .lab: return "slider.horizontal.3"
        }
    }

    /// ⌘1…⌘9 for the first nine; the rest have no shortcut.
    var shortcutNumber: Int? {
        let number = (AppSection.allCases.firstIndex(of: self) ?? 0) + 1
        return number <= 9 ? number : nil
    }

    var subtitle: String {
        switch self {
        case .today: return "Your day, and the 11am check-in"
        case .mail: return "What needs you, with replies drafted"
        case .write: return "Writes like you, so you only review"
        case .files: return "Find anything on this Mac"
        case .research: return "Browse, ask, and get a sourced answer"
        case .money: return "Where it is, where it goes, what's next"
        case .business: return "Pipeline, grounded in real conversations"
        case .design: return "On-brand graphics and image tools"
        case .video: return "Edit video by editing the words"
        case .learn: return "Ten minutes a day, not homework"
        case .build: return "Make the software fit you"
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
    let voice: VoiceProfile
    let mail: MailModel
    let write: WriteModel
    let research: ResearchModel
    let money: MoneyModel
    let business: BusinessModel
    let design: DesignModel
    let video: VideoModel
    let learn: LearnModel
    let build: BuildModel

    init() {
        let machine = MachineProfile()
        let brain = Brain()
        let files = FileIndex()
        let voice = VoiceProfile()
        let theme = Theme()
        self.theme = theme
        self.machine = machine
        self.brain = brain
        self.files = files
        self.today = TodayModel(brain: brain, files: files)
        self.nightShift = NightShift(machine: machine)
        self.voice = voice
        let write = WriteModel(brain: brain, voice: voice)
        self.mail = MailModel(brain: brain, voice: voice)
        self.write = write
        self.research = ResearchModel(brain: brain, write: write)
        self.money = MoneyModel(brain: brain)
        self.business = BusinessModel(brain: brain, voice: voice)
        self.design = DesignModel(brain: brain)
        self.video = VideoModel(brain: brain)
        self.learn = LearnModel(brain: brain)
        self.build = BuildModel(brain: brain, theme: theme)
        nightShift.attach(to: self)
    }

    func start() {
        machine.startMonitoring()
        files.load()
        write.load()
        today.refreshAccess()
        nightShift.start()
        log("le", "11am started on \(machine.chip) with \(machine.memoryGB) GB. Running in \(machine.tier.title) mode.")
    }

    /// Switches app with the theme's spring, so the content rises in rather than snapping.
    func go(to section: AppSection) {
        guard section != self.section else { return }
        withAnimation(theme.spring) { self.section = section }
    }

    func log(_ monogram: String, _ text: String) {
        activity.insert(ActivityItem(monogram: monogram, text: text), at: 0)
        if activity.count > 60 { activity.removeLast(activity.count - 60) }
    }
}
