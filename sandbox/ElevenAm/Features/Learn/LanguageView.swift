import SwiftUI

/// Harris's language course: choose a language, then lessons, reviews, stories and a placement test.
struct LanguagePane: View {
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var languages: LanguageModel
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Group {
            if let session = languages.session {
                LessonPlayer(session: session)
            } else if languages.placement != nil {
                PlacementView()
            } else if let unit = languages.storyUnit, let story = unit.story {
                StoryReader(unit: unit, story: story)
            } else if languages.language == nil || languages.choosing {
                LanguagePicker()
            } else {
                CourseHome()
            }
        }
        .animation(theme.spring, value: languages.session?.id)
        .overlay(alignment: .bottom) {
            if let notice = languages.notice {
                Text(notice)
                    .font(.system(size: 12.5))
                    .foregroundStyle(theme.ink(scheme))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(.regularMaterial, in: Capsule())
                    .padding(.bottom, 8)
                    .onTapGesture { languages.notice = nil }
                    .task(id: notice) {
                        try? await Task.sleep(nanoseconds: 5_000_000_000)
                        if languages.notice == notice { languages.notice = nil }
                    }
            }
        }
    }
}

// MARK: Choosing

private struct LanguagePicker: View {
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var languages: LanguageModel
    @Environment(\.colorScheme) private var scheme
    private let columns = [GridItem(.adaptive(minimum: 180), spacing: 12)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Which language?")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(theme.ink(scheme))
                Text("Short lessons from beginner (A1) to upper intermediate (B2): words with pictures, listening, speaking, translating both ways, stories. Mistakes come back until they stick. No hearts, no ads, and streaks only if you want them.")
                    .font(.system(size: 13))
                    .foregroundStyle(theme.inkSecondary(scheme))
                    .fixedSize(horizontal: false, vertical: true)
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(LanguageInfo.all) { language in
                        Button { languages.choose(language) } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(language.hello)
                                    .font(.system(size: 24, weight: .bold))
                                    .foregroundStyle(theme.ink(scheme))
                                Text(language.name)
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(theme.ink(scheme))
                                Text(language.builtIn ? "Written course to start" : "Harris writes each unit as you go")
                                    .font(.system(size: 11.5))
                                    .foregroundStyle(theme.inkTertiary(scheme))
                            }
                            .frame(maxWidth: .infinity, minHeight: 110, alignment: .topLeading)
                            .padding(14)
                            .vellum(level: 3, radius: max(theme.radius - 4, 8))
                            .overlay {
                                if language.id == languages.language?.id {
                                    RoundedRectangle(cornerRadius: max(theme.radius - 4, 8), style: .continuous).strokeBorder(theme.ink(scheme), lineWidth: 1.5)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                Text("Honest limit: the written units are checked by hand; units Harris writes are generated and checked for shape and repeats, so expect strong vocabulary and practice and a little less polish. Writing units needs Apple Intelligence or Claude (Settings › Brain).")
                    .font(.system(size: 11.5))
                    .foregroundStyle(theme.inkTertiary(scheme))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.trailing, 4)
        }
    }
}

// MARK: Home

private struct CourseHome: View {
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var languages: LanguageModel
    @EnvironmentObject private var brain: Brain
    @Environment(\.colorScheme) private var scheme
    @State private var showsSettings = false

    var body: some View {
        let course = languages.course
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(languages.language?.name ?? "") · \(languages.level.title)")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(theme.ink(scheme))
                        Text("\(languages.wordsKnown) words known of \(languages.wordsSeen) met · \(Int(languages.minutesThisWeek)) minutes this week"
                             + (languages.settings.streaks && languages.streak > 0 ? " · \(languages.streak)-day streak" : ""))
                            .font(.system(size: 12))
                            .foregroundStyle(theme.inkTertiary(scheme))
                    }
                    Spacer()
                    Button { languages.choosing = true } label: { Label("Language", systemImage: "globe") }
                        .buttonStyle(.vellumSecondary)
                    Button { showsSettings.toggle() } label: { Image(systemName: "slider.horizontal.3") }
                        .buttonStyle(.vellumSecondary)
                        .popover(isPresented: $showsSettings, arrowEdge: .bottom) { LanguageSettingsView().padding(16).frame(width: 300) }
                }
                GoalCard()
                HStack(spacing: 10) {
                    Button {
                        languages.continueCourse()
                    } label: {
                        Label(languages.next.map { "Continue: \($0.unit.title), lesson \($0.lesson + 1)" } ?? "Write the next unit", systemImage: "play.fill")
                    }
                    .buttonStyle(.vellumPrimary)
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(languages.next == nil && (languages.writing != nil || brain.isBusy))
                    Button("Review \(languages.dueReviews.count)") { languages.startReview() }
                        .buttonStyle(.vellumSecondary)
                        .disabled(languages.dueReviews.isEmpty)
                        .help("Things you got wrong, and things you haven't seen for a while")
                    if languages.progress?.placedAt == nil && !course.placement.isEmpty {
                        Button("Placement test") { languages.startPlacement() }
                            .buttonStyle(.vellumSecondary)
                            .help("Already know some? A few questions to start at the right level")
                    }
                    if languages.writing != nil {
                        ProgressView().controlSize(.small)
                        Text("Harris is writing a unit…")
                            .font(.system(size: 12))
                            .foregroundStyle(theme.inkTertiary(scheme))
                    }
                }
                ForEach(CEFR.allCases, id: \.self) { level in
                    let units = course.units.filter { $0.level == level }
                    if !units.isEmpty {
                        SectionLabel(text: level.title)
                            .padding(.top, 6)
                        ForEach(units) { unit in UnitRow(unit: unit) }
                    }
                }
                if course.units.isEmpty {
                    Text(languages.writing == nil ? "No units yet. Harris writes them as you go." : "Harris is writing the first unit…")
                        .font(.system(size: 13))
                        .foregroundStyle(theme.inkTertiary(scheme))
                }
            }
            .padding(.trailing, 4)
        }
    }
}

private struct GoalCard: View {
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var languages: LanguageModel
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let goal = Double(languages.settings.dailyMinutes)
        let today = languages.minutesToday
        HStack(spacing: 14) {
            ZStack {
                Circle().stroke(theme.ink(scheme).opacity(0.1), lineWidth: 6)
                Circle()
                    .trim(from: 0, to: min(1, today / max(goal, 1)))
                    .stroke(theme.ink(scheme), style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("\(Int(today))")
                    .font(.system(size: 14, weight: .bold).monospacedDigit())
                    .foregroundStyle(theme.ink(scheme))
            }
            .frame(width: 46, height: 46)
            VStack(alignment: .leading, spacing: 2) {
                Text(today >= goal ? "Today's \(Int(goal)) minutes done." : "\(Int(max(0, goal - today).rounded(.up))) minutes to today's goal")
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(theme.ink(scheme))
                Text(languages.settings.remind
                     ? String(format: "Reminder at %d:%02d. Change it in the settings.", languages.settings.remindHour, languages.settings.remindMinute)
                     : "Set a daily reminder in the settings, if you'd like one.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(theme.inkTertiary(scheme))
            }
            Spacer()
        }
        .padding(12)
        .vellum(level: 3, radius: max(theme.radius - 4, 8))
    }
}

private struct UnitRow: View {
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var languages: LanguageModel
    @Environment(\.colorScheme) private var scheme
    var unit: CourseUnit

    var body: some View {
        let done = languages.lessonsDone(unit)
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(done >= unit.lessonCount ? theme.ink(scheme) : theme.well(scheme))
                Image(systemName: unit.words.first?.symbol ?? "text.bubble")
                    .font(.system(size: 14))
                    .foregroundStyle(done >= unit.lessonCount ? theme.paper(scheme) : theme.inkSecondary(scheme))
            }
            .frame(width: 36, height: 36)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(unit.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(theme.ink(scheme))
                    if unit.generated {
                        Text("by Harris")
                            .font(.system(size: 10))
                            .foregroundStyle(theme.inkTertiary(scheme))
                    }
                }
                Text(unit.words.prefix(5).map(\.term).joined(separator: " · "))
                    .font(.system(size: 11.5))
                    .foregroundStyle(theme.inkTertiary(scheme))
                    .lineLimit(1)
            }
            Spacer()
            HStack(spacing: 6) {
                ForEach(0..<unit.lessonCount, id: \.self) { number in
                    Button { languages.start(unit, lesson: number) } label: {
                        Text("\(number + 1)")
                            .font(.system(size: 11.5, weight: .semibold).monospacedDigit())
                            .foregroundStyle(number < done ? theme.paper(scheme) : theme.ink(scheme))
                            .frame(width: 26, height: 26)
                            .background(Circle().fill(number < done ? theme.ink(scheme) : theme.well(scheme)))
                    }
                    .buttonStyle(.plain)
                    .help("Lesson \(number + 1): \(["new words", "sentences", "speaking and writing"][number])")
                }
                if unit.story != nil {
                    Button { languages.read(unit) } label: {
                        Image(systemName: (languages.progress?.storiesRead.contains(unit.id) ?? false) ? "book.closed.fill" : "book.closed")
                            .frame(width: 26, height: 26)
                            .background(Circle().fill(theme.well(scheme)))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(theme.ink(scheme))
                    .help("Story: \(unit.story?.title ?? "")")
                }
            }
        }
        .padding(10)
        .vellum(level: 3, radius: max(theme.radius - 4, 8))
    }
}

private struct LanguageSettingsView: View {
    @EnvironmentObject private var languages: LanguageModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Stepper("Daily goal: \(languages.settings.dailyMinutes) minutes", value: Binding(get: { languages.settings.dailyMinutes },
                                                                                           set: { value in languages.update { $0.dailyMinutes = value } }), in: 5...60, step: 5)
            Toggle("Remind me each day", isOn: Binding(get: { languages.settings.remind }, set: { value in languages.update { $0.remind = value } }))
            if languages.settings.remind {
                DatePicker("At", selection: Binding(get: {
                    Calendar.current.date(bySettingHour: languages.settings.remindHour, minute: languages.settings.remindMinute, second: 0, of: Date()) ?? Date()
                }, set: { value in
                    languages.update {
                        $0.remindHour = Calendar.current.component(.hour, from: value)
                        $0.remindMinute = Calendar.current.component(.minute, from: value)
                    }
                }), displayedComponents: .hourAndMinute)
            }
            Toggle("Show a streak", isOn: Binding(get: { languages.settings.streaks }, set: { value in languages.update { $0.streaks = value } }))
            Text("Streaks are off unless you want them. Missing a day costs nothing.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Divider()
            Button("Take the placement test again") { languages.startPlacement() }
        }
        .font(.system(size: 12.5))
    }
}

// MARK: The lesson

private struct LessonPlayer: View {
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var languages: LanguageModel
    @Environment(\.colorScheme) private var scheme
    var session: LessonSession
    @State private var tipShown = true

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Button { languages.closeSession() } label: { Image(systemName: "xmark") }
                    .buttonStyle(.plain)
                    .foregroundStyle(theme.inkSecondary(scheme))
                    .keyboardShortcut(.cancelAction)
                    .help("Stop here (your progress is kept)")
                ProgressView(value: session.progress)
                    .tint(theme.ink(scheme))
                Text(session.title)
                    .font(.system(size: 12))
                    .foregroundStyle(theme.inkTertiary(scheme))
                    .lineLimit(1)
                    .fixedSize()
            }
            if let tip = session.tip, tipShown, session.index < 2 {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "lightbulb")
                    Text(tip).fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    Button { tipShown = false } label: { Image(systemName: "xmark").font(.system(size: 10)) }
                        .buttonStyle(.plain)
                }
                .font(.system(size: 12.5))
                .foregroundStyle(theme.ink(scheme))
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.yellow.opacity(0.14)))
            }
            if let exercise = session.current {
                ExerciseCard(exercise: exercise)
                    .id("\(session.id)-\(session.index)")
                    .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .opacity))
            } else {
                LessonDone(session: session)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: 680)
        .frame(maxWidth: .infinity)
        .animation(theme.spring, value: session.index)
    }
}

private struct LessonDone: View {
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var languages: LanguageModel
    @Environment(\.colorScheme) private var scheme
    var session: LessonSession

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "checkmark.seal")
                .font(.system(size: 44))
                .foregroundStyle(theme.ink(scheme))
            Text("Lesson done")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(theme.ink(scheme))
            Text("\(session.right) right of \(session.exercises.count). Anything you missed comes back in your reviews.")
                .font(.system(size: 13))
                .foregroundStyle(theme.inkSecondary(scheme))
            HStack {
                Button("Back to the course") { languages.closeSession() }
                    .buttonStyle(.vellumSecondary)
                if languages.next != nil {
                    Button("Next lesson") {
                        languages.closeSession()
                        languages.continueCourse()
                    }
                    .buttonStyle(.vellumPrimary)
                    .keyboardShortcut(.return, modifiers: [])
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
    }
}

/// One exercise: the question, your answer, and what Harris thinks of it.
private struct ExerciseCard: View {
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var languages: LanguageModel
    @Environment(\.colorScheme) private var scheme
    var exercise: Exercise
    @State private var typed = ""
    @State private var chosen: String?
    @State private var tiles: [String] = []
    @State private var verdict: AnswerCheck.Verdict?
    @State private var pronunciation: Pronunciation.Result?
    @State private var matched: Set<String> = []
    @State private var pickedTerm: String?
    @State private var wrongPair = false

    private var language: LanguageInfo? { languages.language }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(exercise.title.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .tracking(1)
                .foregroundStyle(theme.inkTertiary(scheme))
            content
            if let verdict { feedback(verdict) }
            HStack {
                Spacer()
                if verdict == nil {
                    if canSkip {
                        Button("Can't listen or speak now") { decide(.right, record: false) }
                            .buttonStyle(.vellumSecondary)
                    }
                    Button("Check") { check() }
                        .buttonStyle(.vellumPrimary)
                        .keyboardShortcut(.return, modifiers: [])
                        .disabled(!ready)
                } else {
                    Button("Continue") { languages.advance() }
                        .buttonStyle(.vellumPrimary)
                        .keyboardShortcut(.return, modifiers: [])
                }
            }
        }
        .padding(22)
        .vellum(level: 3, radius: max(theme.radius - 2, 8))
        .onAppear(perform: prepare)
    }

    private var canSkip: Bool {
        switch exercise {
        case .speak, .dictation, .listen: return true
        default: return false
        }
    }

    private func prepare() {
        switch exercise {
        case .listen(let sentence, _), .dictation(let sentence):
            if let language { languages.speaker.say(sentence.target, language: language.id) }
        case .pictureChoice(let item, _):
            if let language { languages.speaker.say(item.term, language: language.id) }
        default:
            break
        }
    }

    @ViewBuilder
    private var content: some View {
        switch exercise {
        case .pictureChoice(let item, let options):
            Text("Which one is \u{201C}\(item.term)\u{201D}?")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(theme.ink(scheme))
            HStack(spacing: 10) {
                ForEach(options) { option in
                    choiceTile(option.meaning, symbol: option.symbol, selected: chosen == option.meaning) { chosen = option.meaning }
                }
            }
        case .listen(let sentence, let options):
            listenButton(sentence.target)
            VStack(spacing: 8) {
                ForEach(options, id: \.self) { option in
                    choiceRow(option, selected: chosen == option) { chosen = option }
                }
            }
        case .speak(let sentence):
            HStack(spacing: 10) {
                listenButton(sentence.target)
                VStack(alignment: .leading, spacing: 2) {
                    Text(sentence.target).font(.system(size: 20, weight: .semibold)).foregroundStyle(theme.ink(scheme))
                    Text(sentence.english).font(.system(size: 13)).foregroundStyle(theme.inkTertiary(scheme))
                }
            }
            SpeakButton(listener: languages.listener, expected: sentence.target) { heard in
                guard let language else { return }
                let result = Pronunciation.compare(heard: heard, expected: sentence.target, language: language)
                pronunciation = result
                decide(result.score >= 0.75 ? (result.score >= 0.95 ? .right : .nearly(result.verdict)) : .wrong)
            }
            if let pronunciation {
                HStack(spacing: 6) {
                    ForEach(Array(pronunciation.words.enumerated()), id: \.offset) { _, word in
                        Text(word.word)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(word.heard ? Color.green : Color.orange)
                    }
                }
            }
        case .toEnglish(let sentence):
            HStack(spacing: 10) {
                listenButton(sentence.target, small: true)
                Text(sentence.target).font(.system(size: 22, weight: .semibold)).foregroundStyle(theme.ink(scheme))
            }
            answerField("Type it in English")
        case .toTarget(let sentence):
            Text(sentence.english).font(.system(size: 22, weight: .semibold)).foregroundStyle(theme.ink(scheme))
            answerField("Type it in \(language?.name ?? "the language")")
        case .fillGap(let sentence, let gap, let options):
            let words = Tokens.words(sentence.target, language: language)
            Text(words.enumerated().map { $0.offset == gap ? "____" : $0.element }.joined(separator: " "))
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(theme.ink(scheme))
            Text(sentence.english).font(.system(size: 13)).foregroundStyle(theme.inkTertiary(scheme))
            HStack(spacing: 8) {
                ForEach(options, id: \.self) { option in
                    choiceRow(option, selected: chosen == option) { chosen = option }
                }
            }
        case .matchPairs(let items):
            MatchGrid(items: items, matched: $matched, picked: $pickedTerm, wrong: $wrongPair)
                .onChange(of: matched) { _, now in
                    if now.count == items.count && verdict == nil { decide(wrongPair ? .nearly("Matched, after a slip or two.") : .right) }
                }
        case .dictation:
            listenButton(exerciseSentence?.target ?? "")
            answerField("Type what you hear")
        case .build(let sentence, let pool):
            Text(sentence.english).font(.system(size: 20, weight: .semibold)).foregroundStyle(theme.ink(scheme))
            FlowRow(words: tiles, filled: true) { index in tiles.remove(at: index) }
                .frame(minHeight: 44)
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(theme.edge(scheme), style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
            FlowRow(words: remaining(pool), filled: false) { index in tiles.append(remaining(pool)[index]) }
        }
    }

    private var exerciseSentence: Sentence? {
        switch exercise {
        case .listen(let sentence, _), .speak(let sentence), .toEnglish(let sentence), .toTarget(let sentence),
             .fillGap(let sentence, _, _), .dictation(let sentence), .build(let sentence, _):
            return sentence
        default:
            return nil
        }
    }

    private func remaining(_ pool: [String]) -> [String] {
        var left = pool
        for tile in tiles { if let index = left.firstIndex(of: tile) { left.remove(at: index) } }
        return left
    }

    private var ready: Bool {
        switch exercise {
        case .pictureChoice, .listen, .fillGap: return chosen != nil
        case .toEnglish, .toTarget, .dictation: return !typed.trimmingCharacters(in: .whitespaces).isEmpty
        case .build: return !tiles.isEmpty
        case .speak, .matchPairs: return false
        }
    }

    private func check() {
        switch exercise {
        case .pictureChoice(let item, _):
            decide(chosen == item.meaning ? .right : .wrong)
        case .listen(let sentence, _):
            decide(chosen == sentence.english ? .right : .wrong)
        case .fillGap(let sentence, let gap, _):
            let answer = Tokens.words(sentence.target, language: language)[gap]
            decide(Tokens.fold(chosen ?? "") == Tokens.fold(answer) ? .right : .wrong)
        case .toEnglish(let sentence):
            decide(AnswerCheck.check(typed, against: AnswerCheck.englishAnswers(sentence), language: nil))
        case .toTarget(let sentence), .dictation(let sentence):
            decide(AnswerCheck.check(typed, against: [sentence.target], language: language))
        case .build(let sentence, _):
            decide(AnswerCheck.check(tiles.joined(separator: " "), against: [sentence.target], language: language))
        case .speak, .matchPairs:
            break
        }
    }

    private func decide(_ result: AnswerCheck.Verdict, record: Bool = true) {
        verdict = result
        if record {
            switch result {
            case .right, .nearly: languages.answered(exercise, correct: true)
            case .wrong: languages.answered(exercise, correct: false)
            }
        }
        if let sentence = exerciseSentence, let language, result != .wrong {
            languages.speaker.say(sentence.target, language: language.id)
        }
    }

    @ViewBuilder
    private func feedback(_ verdict: AnswerCheck.Verdict) -> some View {
        let (title, detail, colour): (String, String?, Color) = {
            switch verdict {
            case .right: return ("Right", nil, .green)
            case .nearly(let note): return ("Right", note, .green)
            case .wrong: return ("Not quite", correctAnswer, .orange)
            }
        }()
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: verdict == .wrong ? "arrow.uturn.backward.circle.fill" : "checkmark.circle.fill")
                .font(.system(size: 20))
                .foregroundStyle(colour)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 14, weight: .semibold)).foregroundStyle(theme.ink(scheme))
                if let detail {
                    Text(detail).font(.system(size: 13)).foregroundStyle(theme.inkSecondary(scheme)).textSelection(.enabled)
                }
            }
            Spacer()
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(colour.opacity(0.12)))
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private var correctAnswer: String? {
        switch exercise {
        case .pictureChoice(let item, _): return "\(item.term) means \u{201C}\(item.meaning)\u{201D}."
        case .toEnglish(let sentence), .listen(let sentence, _): return sentence.english
        case .speak(let sentence): return pronunciation.map(\.verdict) ?? sentence.target
        case .toTarget(let sentence), .dictation(let sentence), .build(let sentence, _), .fillGap(let sentence, _, _): return sentence.target
        case .matchPairs: return nil
        }
    }

    private func answerField(_ prompt: String) -> some View {
        TextField(prompt, text: $typed)
            .textFieldStyle(.plain)
            .font(.system(size: 17))
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(theme.well(scheme)))
            .disabled(verdict != nil)
            .onSubmit { if verdict == nil && ready { check() } }
    }

    private func listenButton(_ text: String, small: Bool = false) -> some View {
        HStack(spacing: 6) {
            Button {
                if let language { languages.speaker.say(text, language: language.id) }
            } label: {
                Image(systemName: "speaker.wave.2.fill")
                    .font(.system(size: small ? 13 : 18))
                    .frame(width: small ? 30 : 46, height: small ? 30 : 46)
                    .background(Circle().fill(theme.ink(scheme)))
                    .foregroundStyle(theme.paper(scheme))
            }
            .buttonStyle(.plain)
            .help("Listen")
            if !small {
                Button {
                    if let language { languages.speaker.say(text, language: language.id, slow: true) }
                } label: {
                    Image(systemName: "tortoise.fill")
                        .font(.system(size: 13))
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(theme.well(scheme)))
                }
                .buttonStyle(.plain)
                .foregroundStyle(theme.ink(scheme))
                .help("Slowly")
            }
        }
    }

    private func choiceTile(_ text: String, symbol: String?, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: symbol ?? "textformat")
                    .font(.system(size: 28))
                    .frame(height: 36)
                Text(text)
                    .font(.system(size: 13, weight: .medium))
                    .multilineTextAlignment(.center)
            }
            .foregroundStyle(theme.ink(scheme))
            .frame(maxWidth: .infinity, minHeight: 100)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(selected ? theme.ink(scheme).opacity(0.1) : theme.well(scheme)))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(selected ? theme.ink(scheme) : Color.clear, lineWidth: 1.5))
        }
        .buttonStyle(.plain)
        .disabled(verdict != nil)
    }

    private func choiceRow(_ text: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(text)
                .font(.system(size: 14.5, weight: .medium))
                .foregroundStyle(theme.ink(scheme))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(selected ? theme.ink(scheme).opacity(0.1) : theme.well(scheme)))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(selected ? theme.ink(scheme) : Color.clear, lineWidth: 1.5))
        }
        .buttonStyle(.plain)
        .disabled(verdict != nil)
    }
}

/// Hold to talk is awkward with a trackpad, so: press to start, press to stop.
private struct SpeakButton: View {
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var languages: LanguageModel
    @Environment(\.colorScheme) private var scheme
    @ObservedObject var listener: Listener
    var expected: String
    var onDone: (String) -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button {
                if listener.isListening {
                    onDone(listener.stop())
                } else if let language = languages.language {
                    Task {
                        if let problem = await listener.start(language: language.id) { languages.notice = problem }
                    }
                }
            } label: {
                Label(listener.isListening ? "Done" : "Press and speak", systemImage: listener.isListening ? "stop.fill" : "mic.fill")
            }
            .buttonStyle(.vellumPrimary)
            Text(listener.isListening ? (listener.heard.isEmpty ? "Listening…" : listener.heard) : "Heard on this Mac, compared word by word.")
                .font(.system(size: 13))
                .foregroundStyle(theme.inkSecondary(scheme))
                .lineLimit(2)
        }
    }
}

private struct MatchGrid: View {
    @EnvironmentObject private var theme: Theme
    @Environment(\.colorScheme) private var scheme
    var items: [VocabItem]
    @Binding var matched: Set<String>
    @Binding var picked: String?
    @Binding var wrong: Bool
    @State private var flash: String?

    var body: some View {
        let meanings = items.map(\.meaning).sorted()
        HStack(alignment: .top, spacing: 16) {
            VStack(spacing: 8) {
                ForEach(items) { item in
                    tile(item.term, done: matched.contains(item.term), selected: picked == item.term) { picked = item.term }
                }
            }
            VStack(spacing: 8) {
                ForEach(meanings, id: \.self) { meaning in
                    let owner = items.first { $0.meaning == meaning }
                    tile(meaning, done: owner.map { matched.contains($0.term) } ?? false, selected: false, shaking: flash == meaning) {
                        guard let term = picked else { return }
                        if items.first(where: { $0.term == term })?.meaning == meaning {
                            matched.insert(term)
                            picked = nil
                        } else {
                            wrong = true
                            flash = meaning
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { flash = nil }
                        }
                    }
                }
            }
        }
    }

    private func tile(_ text: String, done: Bool, selected: Bool, shaking: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(text)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(done ? theme.inkTertiary(scheme) : theme.ink(scheme))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(shaking ? Color.orange.opacity(0.2) : (selected ? theme.ink(scheme).opacity(0.12) : theme.well(scheme))))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(selected ? theme.ink(scheme) : Color.clear, lineWidth: 1.5))
        }
        .buttonStyle(.plain)
        .disabled(done)
    }
}

/// Word tiles that wrap.
private struct FlowRow: View {
    @EnvironmentObject private var theme: Theme
    @Environment(\.colorScheme) private var scheme
    var words: [String]
    var filled: Bool
    var onTap: (Int) -> Void

    var body: some View {
        FlowLayout(spacing: 6) {
            ForEach(Array(words.enumerated()), id: \.offset) { index, word in
                Button { onTap(index) } label: {
                    Text(word)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(theme.ink(scheme))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(filled ? theme.ink(scheme).opacity(0.08) : theme.well(scheme)))
                        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(theme.edge(scheme), lineWidth: 0.5))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: Stories

private struct StoryReader: View {
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var languages: LanguageModel
    @Environment(\.colorScheme) private var scheme
    var unit: CourseUnit
    var story: Story
    @State private var revealed: Set<Int> = []
    @State private var answers: [Int: Int] = [:]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Button { languages.storyUnit = nil } label: { Image(systemName: "chevron.left") }
                        .buttonStyle(.plain)
                        .keyboardShortcut(.cancelAction)
                    Text(story.title)
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(theme.ink(scheme))
                    Spacer()
                    Button {
                        if let language = languages.language { languages.speaker.say(story.lines.map(\.target).joined(separator: " "), language: language.id) }
                    } label: { Label("Read it to me", systemImage: "speaker.wave.2.fill") }
                        .buttonStyle(.vellumSecondary)
                }
                ForEach(Array(story.lines.enumerated()), id: \.offset) { index, line in
                    HStack(alignment: .top, spacing: 10) {
                        Button {
                            if let language = languages.language { languages.speaker.say(line.target, language: language.id) }
                        } label: { Image(systemName: "speaker.wave.1") }
                            .buttonStyle(.plain)
                            .foregroundStyle(theme.inkSecondary(scheme))
                        VStack(alignment: .leading, spacing: 3) {
                            Text(line.target)
                                .font(.system(size: 17))
                                .foregroundStyle(theme.ink(scheme))
                            if revealed.contains(index) {
                                Text(line.english)
                                    .font(.system(size: 13))
                                    .foregroundStyle(theme.inkTertiary(scheme))
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if revealed.contains(index) { revealed.remove(index) } else { revealed.insert(index) }
                        }
                    }
                }
                Text("Click a line to see it in English.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(theme.inkTertiary(scheme))
                SectionLabel(text: "Questions")
                ForEach(Array(story.questions.enumerated()), id: \.offset) { number, question in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(question.question)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(theme.ink(scheme))
                        HStack(spacing: 8) {
                            ForEach(Array(question.options.enumerated()), id: \.offset) { index, option in
                                let picked = answers[number] == index
                                let showRight = answers[number] != nil && index == question.answer
                                Button(option) { answers[number] = index }
                                    .buttonStyle(.vellumSecondary)
                                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(showRight ? Color.green : (picked ? Color.orange : Color.clear), lineWidth: 1.5))
                                    .disabled(answers[number] != nil)
                            }
                        }
                    }
                }
                if answers.count == story.questions.count {
                    Button("Done") { languages.finishedStory(unit) }
                        .buttonStyle(.vellumPrimary)
                }
            }
            .frame(maxWidth: 680, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
    }
}

// MARK: Placement

private struct PlacementView: View {
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var languages: LanguageModel
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Button { languages.closePlacement() } label: { Image(systemName: "xmark") }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.cancelAction)
                if let session = languages.placement {
                    ProgressView(value: Double(session.index), total: Double(max(session.questions.count, 1)))
                        .tint(theme.ink(scheme))
                }
            }
            if let result = languages.placedResult {
                VStack(spacing: 12) {
                    Text("Start at \(result.title)")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(theme.ink(scheme))
                    Text("Earlier units stay open if you want to brush up.")
                        .font(.system(size: 13))
                        .foregroundStyle(theme.inkSecondary(scheme))
                    Button("Start") { languages.closePlacement() }
                        .buttonStyle(.vellumPrimary)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 40)
            } else if let question = languages.placement?.current {
                Text(question.level.rawValue)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(theme.inkTertiary(scheme))
                Text(question.prompt)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(theme.ink(scheme))
                Text(question.english)
                    .font(.system(size: 13))
                    .foregroundStyle(theme.inkTertiary(scheme))
                VStack(spacing: 8) {
                    ForEach(Array(question.options.enumerated()), id: \.offset) { index, option in
                        Button { languages.answerPlacement(index) } label: {
                            Text(option)
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(theme.ink(scheme))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(12)
                                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(theme.well(scheme)))
                        }
                        .buttonStyle(.plain)
                    }
                }
                Text("No penalty for guessing wrong; it stops early once the level's right.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(theme.inkTertiary(scheme))
            }
            Spacer()
        }
        .frame(maxWidth: 620)
        .frame(maxWidth: .infinity)
    }
}
