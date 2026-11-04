import AVFoundation
import Foundation
import Speech
import UserNotifications

/// Where you are in one language.
struct LanguageProgress: Codable, Hashable {
    var language: String
    /// Lessons finished in each unit (0 to 3).
    var lessonsDone: [String: Int] = [:]
    var storiesRead: Set<String> = []
    var reviews: [ReviewItem] = []
    var placedAt: CEFR?
    /// Units Harris wrote for this language.
    var written: [CourseUnit] = []
    /// Grammar tips already shown, so each comes once, when it's first needed.
    var tipsSeen: Set<String> = []
}

struct LanguageSettings: Codable, Hashable {
    var language: String?
    var dailyMinutes = 10
    var remind = false
    var remindHour = 19
    var remindMinute = 30
    var streaks = false
    var days: [StudyDay] = []
}

/// A lesson being done.
struct LessonSession: Identifiable {
    enum Kind: Equatable { case lesson(unit: String, number: Int), review, practice }

    let id = UUID()
    var kind: Kind
    var title: String
    var exercises: [Exercise]
    var index = 0
    var mistakes: [Exercise] = []
    var right = 0
    var started = Date()
    var tip: String?

    var current: Exercise? { exercises.indices.contains(index) ? exercises[index] : nil }
    var progress: Double { exercises.isEmpty ? 1 : Double(index) / Double(exercises.count) }
    var finished: Bool { index >= exercises.count }
}

struct PlacementSession {
    var questions: [PlacementQuestion]
    var index = 0
    var answers: [PlacementQuestion: Int] = [:]

    var current: PlacementQuestion? { questions.indices.contains(index) ? questions[index] : nil }
}

/// Harris's language course: lessons, reviews of what you got wrong, stories, a placement test, and a gentle daily goal.
@MainActor
final class LanguageModel: ObservableObject {
    @Published private(set) var settings: LanguageSettings
    @Published private(set) var progress: LanguageProgress?
    @Published var session: LessonSession?
    @Published var placement: PlacementSession?
    @Published var placedResult: CEFR?
    @Published var storyUnit: CourseUnit?
    @Published private(set) var writing: BrainRun?
    @Published var notice: String?
    @Published var choosing = false

    let speaker = Speaker()
    let listener = Listener()
    private let brain: Brain
    private var minuteTimer: Timer?

    init(brain: Brain) {
        self.brain = brain
        settings = JSONStore.load(LanguageSettings.self, from: "language-settings") ?? LanguageSettings()
        if let id = settings.language { progress = JSONStore.load(LanguageProgress.self, from: "language-\(id)") ?? LanguageProgress(language: id) }
    }

    var language: LanguageInfo? { settings.language.flatMap(LanguageInfo.find) }

    /// Written units first, then any Harris has written, in order.
    var course: Course {
        guard let language else { return Course(language: "", units: [], placement: []) }
        var course = LanguageCourses.course(language)
        course.units += progress?.written ?? []
        return course
    }

    // MARK: Choosing a language

    func choose(_ language: LanguageInfo) {
        saveProgress()
        settings.language = language.id
        progress = JSONStore.load(LanguageProgress.self, from: "language-\(language.id)") ?? LanguageProgress(language: language.id)
        choosing = false
        saveSettings()
        if course.units.isEmpty { writeNextUnit() }
    }

    // MARK: Where you are

    func lessonsDone(_ unit: CourseUnit) -> Int { progress?.lessonsDone[unit.id] ?? 0 }

    /// The next lesson to do: the first unfinished lesson at or after where the placement test put you.
    var next: (unit: CourseUnit, lesson: Int)? {
        let start = progress?.placedAt.flatMap { level in course.units.firstIndex { $0.level >= level } } ?? 0
        for unit in course.units.dropFirst(start) where lessonsDone(unit) < unit.lessonCount {
            return (unit, lessonsDone(unit))
        }
        return nil
    }

    var level: CEFR { next?.unit.level ?? course.units.last?.level ?? progress?.placedAt ?? .a1 }

    var dueReviews: [ReviewItem] { (progress?.reviews ?? []).filter { $0.due <= Date() } }

    var wordsKnown: Int { (progress?.reviews ?? []).filter { $0.isWord && $0.isKnown }.count }

    var wordsSeen: Int { (progress?.reviews ?? []).filter(\.isWord).count }

    var minutesThisWeek: Double { StudyProgress.minutes(thisWeek: settings.days) }

    var minutesToday: Double { settings.days.first { $0.day == Self.dayKey(Date()) }?.minutes ?? 0 }

    var streak: Int { StudyProgress.streak(settings.days) }

    // MARK: Lessons

    func start(_ unit: CourseUnit, lesson number: Int) {
        guard let language else { return }
        let reviews = dueReviews.filter { !$0.isWord }.prefix(3).map { item in Sentence(target: item.id, english: item.english) }
        let exercises = LessonBuilder.lesson(unit, number: number, reviews: Array(reviews), language: language)
        var tip: String?
        if !(progress?.tipsSeen.contains(unit.id) ?? true), !unit.tip.isEmpty, number >= 1 {
            tip = unit.tip
            progress?.tipsSeen.insert(unit.id)
        }
        session = LessonSession(kind: .lesson(unit: unit.id, number: number), title: "\(unit.title) · lesson \(number + 1)", exercises: exercises, tip: tip)
        startTiming()
    }

    func continueCourse() {
        guard let next else {
            writeNextUnit()
            return
        }
        start(next.unit, lesson: next.lesson)
    }

    func startReview() {
        guard let language else { return }
        let due = dueReviews
        let sentences = due.filter { !$0.isWord }.prefix(8).map { Sentence(target: $0.id, english: $0.english) }
        let words = due.filter(\.isWord).prefix(5).map { VocabItem(term: $0.id, meaning: $0.english) }
        guard !sentences.isEmpty || words.count >= 3 else {
            notice = "Nothing to review right now. Mistakes come back here on their own."
            return
        }
        session = LessonSession(kind: .review, title: "Review", exercises: LessonBuilder.review(Array(sentences), words: Array(words), language: language))
        startTiming()
    }

    /// Records an answer and moves the reviews along. Returns nothing; the view shows the verdict it worked out.
    func answered(_ exercise: Exercise, correct: Bool) {
        guard var current = session else { return }
        if correct { current.right += 1 } else { current.mistakes.append(exercise) }
        session = current
        record(exercise, correct: correct)
    }

    func advance() {
        guard var current = session else { return }
        current.index += 1
        // Mistakes come back once at the end of the lesson.
        if current.finished, !current.mistakes.isEmpty, current.exercises.count < 40 {
            current.exercises.append(contentsOf: current.mistakes.prefix(4))
            current.mistakes = []
        }
        session = current
        if current.finished { finish() }
    }

    private func finish() {
        guard let current = session else { return }
        if case .lesson(let unitID, let number) = current.kind {
            let done = max(lessonsDone(course.unit(unitID) ?? CourseUnit(id: unitID, level: .a1, title: "", tip: "", words: [], sentences: [])), number + 1)
            progress?.lessonsDone[unitID] = done
        }
        stopTiming()
        saveProgress()
    }

    func closeSession() {
        stopTiming()
        session = nil
        saveProgress()
    }

    /// Words and sentences you meet go into the review boxes; mistakes come back soon, right answers later.
    private func record(_ exercise: Exercise, correct: Bool) {
        guard progress != nil else { return }
        switch exercise {
        case .pictureChoice(let item, _):
            upsert(id: item.term, english: item.meaning, word: true, correct: correct)
        case .matchPairs(let items):
            for item in items { upsert(id: item.term, english: item.meaning, word: true, correct: correct) }
        case .listen(let sentence, _), .speak(let sentence), .toEnglish(let sentence), .toTarget(let sentence),
             .fillGap(let sentence, _, _), .dictation(let sentence), .build(let sentence, _):
            upsert(id: sentence.target, english: sentence.english, word: false, correct: correct)
        }
    }

    private func upsert(id: String, english: String, word: Bool, correct: Bool) {
        if let index = progress?.reviews.firstIndex(where: { $0.id == id }) {
            progress?.reviews[index].record(correct: correct)
        } else {
            var item = ReviewItem(id: id, english: english, isWord: word)
            item.record(correct: correct)
            progress?.reviews.append(item)
        }
    }

    // MARK: Stories

    func read(_ unit: CourseUnit) {
        storyUnit = unit
    }

    func finishedStory(_ unit: CourseUnit) {
        progress?.storiesRead.insert(unit.id)
        storyUnit = nil
        saveProgress()
    }

    // MARK: Placement

    func startPlacement() {
        let questions = Placement.questions(course)
        guard !questions.isEmpty else {
            notice = "There's no placement test for this language yet, so it starts at the beginning."
            return
        }
        placedResult = nil
        placement = PlacementSession(questions: questions)
    }

    func answerPlacement(_ choice: Int) {
        guard var current = placement, let question = current.current else { return }
        current.answers[question] = choice
        // Stop early once a level is clearly too hard: two wrong at the same level.
        let wrongHere = current.answers.filter { $0.key.level == question.level && $0.key.answer != $0.value }.count
        current.index += 1
        if wrongHere >= 2 { current.index = current.questions.count }
        placement = current
        if current.current == nil {
            let level = Placement.level(answers: current.answers)
            placedResult = level
            progress?.placedAt = level
            saveProgress()
        }
    }

    func closePlacement() {
        placement = nil
        placedResult = nil
    }

    // MARK: Units Harris writes

    func writeNextUnit() {
        guard let language, writing == nil else { return }
        let level = course.units.last?.level ?? (progress?.placedAt ?? .a1)
        let atLevel = course.units.filter { $0.level == level }.count
        // Six units a level, then the next level.
        let target = atLevel >= 6 ? (CEFR.allCases.first { $0 > level } ?? level) : level
        let number = (progress?.written.count ?? 0) + 1
        let prompt = UnitWriter.prompt(language: language, level: target, number: number, after: course.units.suffix(6).map(\.title))
        let run = brain.run(BrainRequest(system: prompt.system, prompt: prompt.prompt, weight: .deep))
        writing = run
        notice = "Harris is writing your next \(language.name) unit…"
        Task {
            await run.finished()
            defer { writing = nil }
            guard case .done = run.status else {
                notice = "Harris couldn't write the unit: \(run.status.failureText). Writing units needs Apple Intelligence or Claude (Settings › Brain)."
                return
            }
            do {
                let unit = try UnitWriter.unit(from: run.text, language: language, level: target, number: number)
                progress?.written.append(unit)
                saveProgress()
                notice = "New unit: \(unit.title)."
            } catch {
                notice = error.localizedDescription + " Try again."
            }
        }
    }

    // MARK: Time and reminders

    private func startTiming() {
        minuteTimer?.invalidate()
        minuteTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.addMinutes(0.25) }
        }
    }

    private func stopTiming() {
        minuteTimer?.invalidate()
        minuteTimer = nil
        saveSettings()
    }

    private func addMinutes(_ minutes: Double) {
        let key = Self.dayKey(Date())
        if let index = settings.days.firstIndex(where: { $0.day == key }) {
            settings.days[index].minutes += minutes
        } else {
            settings.days.append(StudyDay(day: key, minutes: minutes))
            settings.days = Array(settings.days.suffix(120))
        }
    }

    static func dayKey(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    func update(_ change: (inout LanguageSettings) -> Void) {
        let before = settings
        change(&settings)
        saveSettings()
        if settings.remind != before.remind || settings.remindHour != before.remindHour || settings.remindMinute != before.remindMinute {
            Task { await scheduleReminder() }
        }
    }

    private func scheduleReminder() async {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ["language-practice"])
        guard settings.remind, let language else { return }
        guard (try? await center.requestAuthorization(options: [.alert, .sound])) == true else { return }
        let content = UNMutableNotificationContent()
        content.title = "\(language.hello)! \(settings.dailyMinutes) minutes of \(language.name)?"
        content.body = "Harris has your next lesson ready."
        let trigger = UNCalendarNotificationTrigger(dateMatching: DateComponents(hour: settings.remindHour, minute: settings.remindMinute), repeats: true)
        try? await center.add(UNNotificationRequest(identifier: "language-practice", content: content, trigger: trigger))
    }

    // MARK: Saving

    private func saveProgress() {
        guard let progress else { return }
        JSONStore.save(progress, to: "language-\(progress.language)")
    }

    private func saveSettings() {
        JSONStore.save(settings, to: "language-settings")
    }

    func flushSave() {
        saveProgress()
        saveSettings()
    }

    // MARK: Sample

    /// For screenshots: Spanish, part-way through, with a lesson open if asked.
    func loadSample(lesson: Bool) {
        guard let spanish = LanguageInfo.find("es-ES") else { return }
        settings.language = spanish.id
        var sample = LanguageProgress(language: spanish.id)
        sample.lessonsDone = ["es-a1-1": 3, "es-a1-2": 3, "es-a1-3": 1]
        sample.storiesRead = []
        let course = LanguageCourses.spanish
        for unit in course.units.prefix(2) {
            for word in unit.words { sample.reviews.append(ReviewItem(id: word.term, english: word.meaning, isWord: true, box: 3, due: Date().addingTimeInterval(86_400 * 3))) }
        }
        sample.reviews.append(ReviewItem(id: "La cuenta, por favor.", english: "The bill, please.", isWord: false, box: 0, due: Date().addingTimeInterval(-60), mistakes: 1))
        sample.reviews.append(ReviewItem(id: "Buenas noches, Ana.", english: "Good night, Ana.", isWord: false, box: 0, due: Date().addingTimeInterval(-60), mistakes: 1))
        sample.tipsSeen = ["es-a1-1", "es-a1-2"]
        progress = sample
        let calendar = Calendar.current
        settings.days = (0..<5).compactMap { offset in
            calendar.date(byAdding: .day, value: -offset, to: Date()).map { StudyDay(day: Self.dayKey($0), minutes: [12, 9, 15, 6, 10][offset]) }
        }
        if lesson, let unit = course.unit("es-a1-3") {
            start(unit, lesson: 1)
            stopTiming()
        }
    }
}

extension BrainRun.Status {
    var failureText: String {
        if case .failed(let message) = self { return message }
        return "it stopped"
    }
}

/// Reads the language aloud with the Mac's voices (the premium ones if you've downloaded them in System Settings › Accessibility › Spoken Content).
@MainActor
final class Speaker: NSObject, ObservableObject {
    private let synthesizer = AVSpeechSynthesizer()

    func say(_ text: String, language: String, slow: Bool = false) {
        synthesizer.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: text)
        let voices = AVSpeechSynthesisVoice.speechVoices().filter { $0.language == language }
        // The best installed voice: premium, then enhanced, then the default.
        utterance.voice = voices.max { $0.quality.rawValue < $1.quality.rawValue } ?? AVSpeechSynthesisVoice(language: language)
        utterance.rate = slow ? 0.36 : 0.47
        synthesizer.speak(utterance)
    }

    static func hasVoice(for language: String) -> Bool {
        AVSpeechSynthesisVoice.speechVoices().contains { $0.language.hasPrefix(String(language.prefix(2))) }
    }
}

/// Listens for one sentence in the language and writes down what it heard, on this Mac where it can.
@MainActor
final class Listener: ObservableObject {
    @Published private(set) var isListening = false
    @Published private(set) var heard = ""
    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    func start(language: String) async -> String? {
        let speechOK: Bool = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0 == .authorized) }
        }
        guard speechOK else { return "Speaking exercises need Speech Recognition (System Settings › Privacy & Security)." }
        let micOK = await AVCaptureDevice.requestAccess(for: .audio)
        guard micOK else { return "Speaking exercises need the microphone (System Settings › Privacy & Security)." }
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: language)), recognizer.isAvailable else {
            return "This Mac can't recognise \(Locale.current.localizedString(forIdentifier: language) ?? language) speech yet."
        }
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        if recognizer.supportsOnDeviceRecognition { request.requiresOnDeviceRecognition = true }
        self.request = request
        heard = ""
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 2_048, format: format) { [weak request] buffer, _ in
            request?.append(buffer)
        }
        do {
            engine.prepare()
            try engine.start()
        } catch {
            return "The microphone couldn't start: \(error.localizedDescription)"
        }
        isListening = true
        task = recognizer.recognitionTask(with: request) { [weak self] result, _ in
            guard let text = result?.bestTranscription.formattedString else { return }
            Task { @MainActor in self?.heard = text }
        }
        return nil
    }

    /// Stops and returns what was heard.
    func stop() -> String {
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.finish()
        request = nil
        task = nil
        isListening = false
        return heard
    }
}
