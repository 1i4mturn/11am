import Combine
import SwiftUI

/// The places in the sandbox. Apps come first; the agent behind each one is the quiet worker.
enum AppSection: String, CaseIterable, Identifiable {
    case today, calendar, tasks, mail, notes, write, files, pdf, research, money, sheets, business, decks, design, photo, video, audio, learn, build, overnight, suite, lab

    var id: String { rawValue }

    var title: String {
        switch self {
        case .today: return "Today"
        case .calendar: return "Calendar"
        case .tasks: return "Tasks"
        case .mail: return "Mail"
        case .notes: return "Notes"
        case .write: return "Write"
        case .files: return "Files"
        case .pdf: return "PDF"
        case .research: return "Research"
        case .money: return "Money"
        case .sheets: return "Sheets"
        case .business: return "Business"
        case .decks: return "Decks"
        case .design: return "Design"
        case .photo: return "Photo"
        case .video: return "Video"
        case .audio: return "Audio"
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
        case .tasks: return "le"
        case .mail: return "mc"
        case .notes: return "bn"
        case .write: return "wm"
        case .files: return "bn"
        case .pdf: return "bn"
        case .research: return "jm"
        case .money: return "ge"
        case .sheets: return "ge"
        case .business: return "cr"
        case .decks: return "cr"
        case .design: return "rt"
        case .photo: return "rt"
        case .video: return "co"
        case .audio: return "co"
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
        case .tasks: return "checklist"
        case .mail: return "tray"
        case .notes: return "note.text"
        case .write: return "pencil.line"
        case .files: return "doc.text.magnifyingglass"
        case .pdf: return "doc.richtext"
        case .research: return "safari"
        case .money: return "chart.line.uptrend.xyaxis"
        case .sheets: return "tablecells"
        case .business: return "briefcase"
        case .decks: return "play.rectangle"
        case .design: return "paintbrush.pointed"
        case .photo: return "camera.aperture"
        case .video: return "film"
        case .audio: return "waveform"
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
        case .tasks: return "What to do and when, promises kept"
        case .mail: return "What needs you, with replies drafted"
        case .notes: return "Everything you jot down, linked and findable"
        case .write: return "Writes like you, so you only review"
        case .files: return "Find anything on this Mac"
        case .pdf: return "Read, sign, fill in and fix PDFs"
        case .research: return "Browse, ask, and get a sourced answer"
        case .money: return "Where it is, where it goes, what's next"
        case .sheets: return "Spreadsheets with live formulas and Excel files"
        case .business: return "Pipeline, grounded in real conversations"
        case .decks: return "Slides from an outline, presented or sent as PowerPoint"
        case .design: return "On-brand graphics and image tools"
        case .photo: return "Colour, crop and clean-ups"
        case .video: return "Cut, colour and clean up the sound"
        case .audio: return "Record, cut and clean up sound, podcasts and voice notes"
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
    let browser = FileBrowser()
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
    let decks: DecksModel
    let looks: LookLibrary
    let photo: PhotoModel
    let video: VideoModel
    let audio: AudioModel
    let learn: LearnModel
    let build: BuildModel
    let terminal: TerminalWorkspace
    let scripts: ScriptsModel
    let automations: AutomationsModel
    let phone: PhoneLinkModel
    let languages: LanguageModel
    let tasks: TasksModel
    private var watchers: Set<AnyCancellable> = []

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
        self.decks = DecksModel(brain: brain)
        let looks = LookLibrary()
        self.looks = looks
        self.photo = PhotoModel(looks: looks)
        self.video = VideoModel(brain: brain, looks: looks)
        self.audio = AudioModel(brain: brain)
        self.learn = LearnModel(brain: brain)
        self.build = BuildModel(brain: brain, theme: theme, looks: looks)
        self.terminal = TerminalWorkspace(brain: brain)
        let scripts = ScriptsModel(brain: brain)
        self.scripts = scripts
        self.automations = AutomationsModel(brain: brain, scripts: scripts, notes: self.notes, mail: mail, calendar: calendar)
        let phone = PhoneLinkModel(brain: brain, notes: self.notes, today: self.today)
        self.phone = phone
        self.languages = LanguageModel(brain: brain)
        let tasks = TasksModel(brain: brain)
        self.tasks = tasks
        // Checkboxes on a page become tasks; Notion databases become workbooks.
        self.notes.tasks = tasks
        self.notes.sheets = self.sheets
        self.today.energyFacts = { [weak phone] in phone?.energyFacts }
        self.today.onBriefWritten = { [weak phone] in phone?.briefChanged() }
        // Leo's tasks feed Today and the brief; Marc turns promises in the mail you send into tasks.
        self.today.taskFacts = { [weak tasks] in tasks?.briefFacts ?? "" }
        tasks.onChange = { [weak today = self.today] in today?.tasksChanged() }
        // Conner keeps what you send with the deal it belongs to.
        let business = self.business
        business.mail = mail
        business.calendar = calendar
        business.write = write
        business.tasks = tasks
        // Marc's "Times that work" comes from Leo's calendar.
        mail.freeTimes = { [weak calendar] in
            guard let calendar else { return "" }
            let slots = Array(calendar.freeSlots(minutes: 30, days: 5).prefix(6))
            guard !slots.isEmpty else { return "" }
            return FreeTime.text(slots).components(separatedBy: "\n").dropFirst().joined(separator: "\n")
        }
        // Leo's meeting prep knows the open deals; a task dropped on the calendar gets a block of time.
        calendar.dealFacts = { [weak business] attendees in business?.dealFacts(attendees: attendees) ?? "" }
        calendar.taskLookup = { [weak tasks] id in
            tasks?.book.task(id).map { task in (title: task.title, minutes: task.checklist.count > 3 ? 90 : 60) }
        }
        calendar.onBlocked = { [weak tasks] id, start in
            tasks?.update(id) { task in
                if task.due == nil || !task.dueHasTime {
                    task.due = start
                    task.dueHasTime = true
                }
            }
        }
        mail.onSent = { [weak tasks, weak business, weak ledger] to, subject, body in
            tasks?.noteSent(to: to, subject: subject, body: body)
            business?.noteSent(to: to, subject: subject, body: body)
            ledger?.noteSent(subject: subject)
        }
        // James clips into Bolton's notes, cites in William's documents and Conner's decks.
        research.notes = self.notes
        research.decks = self.decks
        self.decks.sheets = self.sheets
        self.studio.sheets = self.sheets
        // William finds your own material in Bolton's notes and files, and hands documents to Harris for cards.
        write.notes = self.notes
        write.files = files
        write.learn = self.learn
        write.formatCitations = { [weak research = self.research] text in
            guard let research, !Citations.markers(in: text).isEmpty else { return text }
            return Citations.format(text, sources: research.library, style: research.style).text
        }
        // George's bills to pay go on Leo's list; Marc sends the reminders for late invoices.
        ledger.mail = mail
        ledger.brain = brain
        ledger.tasks = tasks
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
        decks.load()
        audio.load()
        tasks.load()
        automations.start()
        tasks.onLog = { [weak self] monogram, text in self?.log(monogram, text) }
        tasks.onOpenOrigin = { [weak self] origin in self?.open(origin) }
        business.onOpen = { [weak self] section in self?.go(to: section) }
        ledger.onOpen = { [weak self] section in self?.go(to: section) }
        research.onOpen = { [weak self] section in self?.go(to: section) }
        write.onOpen = { [weak self] section in self?.go(to: section) }
        research.onShowPane = { [weak self] in self?.showsPane = true }
        research.onLog = { [weak self] text in self?.log("jm", text) }
        // When someone you were waiting on replies, their follow-up comes off the list.
        mail.$messages
            .sink { [weak tasks] messages in tasks?.checkReplies(messages.map { (from: $0.fromAddress, date: $0.date) }) }
            .store(in: &watchers)
        phone.start()
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

    /// Goes to where a task came from.
    func open(_ origin: TaskOrigin) {
        switch origin.kind {
        case .mail:
            go(to: .mail)
            if let id = origin.reference, mail.messages.contains(where: { $0.id == id }) { mail.selectedID = id }
        case .meeting:
            go(to: .calendar)
            if let id = origin.reference { calendar.selectedID = id }
        case .agent where origin.reference?.hasPrefix("bill:") == true:
            go(to: .money)
            if let id = origin.reference.flatMap({ UUID(uuidString: String($0.dropFirst(5))) }) {
                ledger.tab = .bills
                ledger.selectedInvoice = id
            }
        default:
            break
        }
    }

    func log(_ monogram: String, _ text: String) {
        activity.insert(ActivityItem(monogram: monogram, text: text), at: 0)
        if activity.count > 60 { activity.removeLast(activity.count - 60) }
    }
}
