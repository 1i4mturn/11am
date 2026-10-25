import Foundation

/// Heavy work waits for the Mac to be free: on power, cool, idle or inside the overnight window.
/// Uses NSBackgroundActivityScheduler, so macOS decides the gentlest moment to run.
@MainActor
final class NightShift: ObservableObject {
    struct Entry: Identifiable, Codable {
        var id = UUID()
        var date = Date()
        var title: String
        var detail: String
    }

    struct Job: Identifiable {
        let id: String
        let title: String
        let detail: String
        let monogram: String
    }

    @Published var windowStartHour: Int { didSet { save() } }
    @Published var windowEndHour: Int { didSet { save() } }
    @Published var requiresPower: Bool { didSet { save() } }
    @Published var idleMinutes: Int { didSet { save() } }

    @Published private(set) var log: [Entry] = []
    @Published private(set) var isRunning = false
    @Published private(set) var lastCheck: Date?
    @Published private(set) var lastDecision = "Not checked yet"

    let jobs: [Job] = [
        Job(id: "index", title: "Refresh the file index", detail: "Re-reads changed files in your chosen folders so search is instant tomorrow.", monogram: "bn"),
        Job(id: "brief", title: "Prepare tomorrow's brief", detail: "Writes the morning brief ahead of time, so it's ready when you open the lid.", monogram: "le"),
        Job(id: "tidy", title: "Tidy 11am's own caches", detail: "Keeps 11am's footprint small on disk.", monogram: "jo"),
    ]

    private let machine: MachineProfile
    private weak var model: AppModel?
    private var scheduler: NSBackgroundActivityScheduler?
    private let defaults = UserDefaults.standard

    init(machine: MachineProfile) {
        self.machine = machine
        let stored = UserDefaults.standard
        windowStartHour = stored.object(forKey: "night.start") as? Int ?? 1
        windowEndHour = stored.object(forKey: "night.end") as? Int ?? 6
        requiresPower = stored.object(forKey: "night.power") as? Bool ?? true
        idleMinutes = stored.object(forKey: "night.idle") as? Int ?? 20
        if let data = stored.data(forKey: "night.log"),
           let saved = try? JSONDecoder().decode([Entry].self, from: data) {
            log = saved
        }
    }

    func attach(to model: AppModel) {
        self.model = model
    }

    func start() {
        let scheduler = NSBackgroundActivityScheduler(identifier: "au.elevenam.sandbox.nightshift")
        scheduler.repeats = true
        scheduler.interval = 30 * 60
        scheduler.tolerance = 10 * 60
        scheduler.qualityOfService = .utility
        scheduler.schedule { [weak self] completion in
            Task { @MainActor in
                await self?.check()
                completion(.finished)
            }
        }
        self.scheduler = scheduler
    }

    /// Whether now is a good moment, and why.
    func conditions(at date: Date = Date()) -> (ok: Bool, reason: String) {
        if isRunning { return (false, "Already running") }
        if requiresPower && !machine.onACPower { return (false, "Waiting for the charger") }
        if machine.lowPowerMode { return (false, "Low Power Mode is on") }
        if !machine.isCoolEnough { return (false, "Mac is warm, waiting to cool down") }
        let hour = Calendar.current.component(.hour, from: date)
        let inWindow = windowStartHour <= windowEndHour
            ? (hour >= windowStartHour && hour < windowEndHour)
            : (hour >= windowStartHour || hour < windowEndHour)
        let idle = machine.secondsIdle >= Double(idleMinutes * 60)
        if inWindow || idle {
            return (true, inWindow ? "Inside the overnight window" : "Mac has been idle for \(idleMinutes)+ minutes")
        }
        return (false, "Mac is in use. Next window starts at \(windowStartHour):00")
    }

    func check() async {
        machine.refresh()
        lastCheck = Date()
        let decision = conditions()
        lastDecision = decision.reason
        guard decision.ok else { return }
        // Only once per night: skip if the last full run was within 8 hours.
        if let last = log.first(where: { $0.title == "Night shift finished" }), Date().timeIntervalSince(last.date) < 8 * 3600 {
            lastDecision = "Already ran tonight"
            return
        }
        await runJobs(reason: decision.reason)
    }

    /// Runs tonight's jobs immediately, ignoring the window (for testing).
    func runNow() async {
        guard !isRunning else { return }
        await runJobs(reason: "Run manually")
    }

    private func runJobs(reason: String) async {
        guard let model else { return }
        isRunning = true
        defer { isRunning = false }
        record("Night shift started", reason)
        model.log("le", "Night shift started: \(reason.lowercased()).")

        // 1. Files
        let before = model.files.files.count
        await model.files.reindex()
        record("File index refreshed", "\(model.files.files.count) files indexed (\(model.files.files.count - before >= 0 ? "+" : "")\(model.files.files.count - before)).")

        // 2. Brief (cloud only if allowed overnight)
        let briefText = await model.today.prepareBrief(overnight: true, allowCloud: model.brain.allowCloudOvernight)
        record("Brief prepared", briefText)

        // 3. Tidy
        let freed = NightShift.tidyCaches()
        record("Caches tidied", freed)

        record("Night shift finished", "All jobs done.")
        model.log("le", "Night shift finished. Brief is ready.")
    }

    private func record(_ title: String, _ detail: String) {
        log.insert(Entry(title: title, detail: detail), at: 0)
        if log.count > 80 { log.removeLast(log.count - 80) }
        if let data = try? JSONEncoder().encode(log) {
            defaults.set(data, forKey: "night.log")
        }
    }

    private func save() {
        defaults.set(windowStartHour, forKey: "night.start")
        defaults.set(windowEndHour, forKey: "night.end")
        defaults.set(requiresPower, forKey: "night.power")
        defaults.set(idleMinutes, forKey: "night.idle")
    }

    private static func tidyCaches() -> String {
        let fm = FileManager.default
        guard let caches = fm.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("au.elevenam.sandbox", isDirectory: true),
              let items = try? fm.contentsOfDirectory(at: caches, includingPropertiesForKeys: [.contentModificationDateKey]) else {
            return "Nothing to tidy."
        }
        var removed = 0
        let cutoff = Date().addingTimeInterval(-7 * 24 * 3600)
        for item in items {
            let modified = (try? item.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date()
            if modified < cutoff, (try? fm.removeItem(at: item)) != nil {
                removed += 1
            }
        }
        return removed == 0 ? "Nothing older than a week." : "Removed \(removed) old cache files."
    }
}
