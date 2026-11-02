import SwiftUI

/// The places in the sandbox. Apps come first; the agent behind each one is the quiet worker.
enum AppSection: String, CaseIterable, Identifiable {
    case today, calendar, mail, notes, write, files, pdf, research, money, sheets, business, design, photo, video, learn, build, overnight, suite, lab

    var id: String { rawValue }

    var title: String {
        switch self {
        case .today: return "Today"
        case .calendar: return "Calendar"
        case .mail: return "Mail"
        case .notes: return "Notes"
        case .write: return "Write"
        case .files: return "Files"
        case .pdf: return "PDF"
        case .research: return "Research"
        case .money: return "Money"
        case .sheets: return "Sheets"
        case .business: return "Business"
        case .design: return "Design"
        case .photo: return "Photo"
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
        case .calendar: return "le"
        case .mail: return "mc"
        case .notes: return "bn"
        case .write: return "wm"
        case .files: return "bn"
        case .pdf: return "bn"
        case .research: return "jm"
        case .money: return "ge"
        case .sheets: return "ge"
        case .business: return "cr"
        case .design: return "rt"
        case .photo: return "rt"
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
        case .calendar: return "calendar"
        case .mail: return "tray"
        case .notes: return "note.text"
        case .write: return "pencil.line"
        case .files: return "doc.text.magnifyingglass"
        case .pdf: return "doc.richtext"
        case .research: return "safari"
        case .money: return "chart.line.uptrend.xyaxis"
        case .sheets: return "tablecells"
        case .business: return "briefcase"
        case .design: return "paintbrush.pointed"
        case .photo: return "camera.aperture"
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
        case .calendar: return "Every calendar, one week, planned for you"
        case .mail: return "What needs you, with replies drafted"
        case .notes: return "Everything you jot down, linked and findable"
        case .write: return "Writes like you, so you only review"
        case .files: return "Find anything on this Mac"
        case .pdf: return "Read, sign, fill in and fix PDFs"
        case .research: return "Browse, ask, and get a sourced answer"
        case .money: return "Where it is, where it goes, what's next"
        case .sheets: return "Spreadsheets with live formulas and Excel files"
        case .business: return "Pipeline, grounded in real conversations"
        case .design: return "On-brand graphics and image tools"
        case .photo: return "Colour, crop and clean-ups"
        case .video: return "Cut, colour and clean up the sound"
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
    let calendar: CalendarModel
    let notes: NotesModel
    let pdf: PDFModel
    let write: WriteModel
    let research: ResearchModel
    let money: MoneyModel
    let ledger: LedgerModel
    let sheets: SheetsModel
    let business: BusinessModel
    let design: DesignModel
    let studio: DesignStudio
    let looks: LookLibrary
    let photo: PhotoModel
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
        let mail = MailModel(brain: brain, voice: voice)
        self.mail = mail
        let calendar = CalendarModel(brain: brain, mail: mail)
        self.calendar = calendar
        self.notes = NotesModel(brain: brain, today: self.today)
        self.pdf = PDFModel(brain: brain)
        self.write = write
        self.research = ResearchModel(brain: brain, write: write)
        self.money = MoneyModel(brain: brain)
        let ledger = LedgerModel()
        self.ledger = ledger
        self.sheets = SheetsModel(brain: brain)
        self.business = BusinessModel(brain: brain, voice: voice)
        self.design = DesignModel(brain: brain)
        self.studio = DesignStudio(brain: brain)
        let looks = LookLibrary()
        self.looks = looks
        self.photo = PhotoModel(looks: looks)
        self.video = VideoModel(brain: brain, looks: looks)
        self.learn = LearnModel(brain: brain)
        self.build = BuildModel(brain: brain, theme: theme, looks: looks)
        nightShift.attach(to: self)
        money.extraFacts = { [weak ledger] in ledger?.georgeFacts ?? "" }
        // Leo's calendar feeds Today, the brief and the notch countdown, with every connected calendar.
        let today = self.today
        calendar.onToday = { [weak calendar] events in
            today.useCalendar(events.map { list in
                list.map { event in
                    DayEvent(id: event.id, title: event.title, start: event.start, end: event.end, isAllDay: event.isAllDay,
                             location: event.location, calendar: calendar?.calendar(for: event)?.title ?? "")
                }
            })
        }
    }

    func start() {
        machine.startMonitoring()
        files.load()
        write.load()
        notes.load()
        sheets.load()
        studio.load()
        today.refreshAccess()
        calendar.refreshAccess()
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
