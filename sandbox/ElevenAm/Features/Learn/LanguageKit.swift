import Foundation

// Harris's language course: units of words and sentences, lessons built from them, forgiving answer checking,
// pronunciation compared word by word, mistakes brought back on a schedule, and a placement test.
// No UI and no Apple frameworks beyond Foundation, so it's tested on its own.

/// The Common European Framework levels the course runs through.
enum CEFR: String, Codable, CaseIterable, Comparable, Sendable {
    case a1 = "A1", a2 = "A2", b1 = "B1", b2 = "B2"

    var title: String {
        switch self {
        case .a1: return "A1 · Beginner"
        case .a2: return "A2 · Elementary"
        case .b1: return "B1 · Intermediate"
        case .b2: return "B2 · Upper intermediate"
        }
    }

    static func < (a: CEFR, b: CEFR) -> Bool {
        allCases.firstIndex(of: a)! < allCases.firstIndex(of: b)!
    }
}

struct LanguageInfo: Codable, Hashable, Identifiable, Sendable {
    /// BCP 47, like "es-ES".
    var id: String
    var name: String
    /// "Hola" in the language, for the picker.
    var hello: String
    /// Ships with written units; the others are written by Harris as you go.
    var builtIn: Bool

    var code: String { String(id.prefix(2)) }

    static let all: [LanguageInfo] = [
        LanguageInfo(id: "es-ES", name: "Spanish", hello: "Hola", builtIn: true),
        LanguageInfo(id: "fr-FR", name: "French", hello: "Bonjour", builtIn: true),
        LanguageInfo(id: "it-IT", name: "Italian", hello: "Ciao", builtIn: false),
        LanguageInfo(id: "de-DE", name: "German", hello: "Hallo", builtIn: false),
        LanguageInfo(id: "pt-BR", name: "Portuguese", hello: "Olá", builtIn: false),
        LanguageInfo(id: "ja-JP", name: "Japanese", hello: "こんにちは", builtIn: false),
        LanguageInfo(id: "zh-CN", name: "Mandarin", hello: "你好", builtIn: false),
        LanguageInfo(id: "ko-KR", name: "Korean", hello: "안녕하세요", builtIn: false),
    ]

    static func find(_ id: String) -> LanguageInfo? { all.first { $0.id == id } }

    /// Languages written without spaces between words, where answers are compared character by character.
    var noSpaces: Bool { ["ja", "zh"].contains(code) }
}

struct VocabItem: Codable, Hashable, Identifiable, Sendable {
    var term: String
    var meaning: String
    /// An SF Symbol that pictures it, for "words with pictures".
    var symbol: String?

    var id: String { term }
}

struct Sentence: Codable, Hashable, Identifiable, Sendable {
    var target: String
    var english: String
    /// Other English that means the same.
    var alternatives: [String] = []

    var id: String { target }

    init(target: String, english: String, alternatives: [String] = []) {
        self.target = target
        self.english = english
        self.alternatives = alternatives
    }

    private enum CodingKeys: String, CodingKey { case target, english, alternatives }

    /// Alternatives are optional in what Harris writes.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        target = try container.decode(String.self, forKey: .target)
        english = try container.decode(String.self, forKey: .english)
        alternatives = try container.decodeIfPresent([String].self, forKey: .alternatives) ?? []
    }
}

struct StoryQuestion: Codable, Hashable, Sendable {
    var question: String
    var options: [String]
    var answer: Int
}

struct Story: Codable, Hashable, Sendable {
    var title: String
    /// Each line in the language, with its English.
    var lines: [Sentence]
    var questions: [StoryQuestion]
}

struct CourseUnit: Codable, Hashable, Identifiable, Sendable {
    var id: String
    var level: CEFR
    var title: String
    /// A grammar tip, shown when it's needed (the first time a lesson leans on it).
    var tip: String
    var words: [VocabItem]
    var sentences: [Sentence]
    var story: Story?
    /// Written by Harris rather than shipped.
    var generated = false

    var lessonCount: Int { 3 }
}

struct PlacementQuestion: Codable, Hashable, Sendable {
    var level: CEFR
    var prompt: String
    var english: String
    var options: [String]
    var answer: Int
}

struct Course: Codable, Hashable, Sendable {
    var language: String
    var units: [CourseUnit]
    var placement: [PlacementQuestion]

    func unit(_ id: String) -> CourseUnit? { units.first { $0.id == id } }

    /// The first unit at a level, for starting where the placement test puts you.
    func firstUnit(at level: CEFR) -> CourseUnit? { units.first { $0.level >= level } }
}

// MARK: Exercises

enum Exercise: Codable, Hashable, Sendable {
    /// A new word: pick its picture-and-meaning from four.
    case pictureChoice(VocabItem, options: [VocabItem])
    /// Hear a sentence, choose what it means.
    case listen(Sentence, options: [String])
    /// Say a sentence out loud.
    case speak(Sentence)
    /// Type the English for a sentence in the language.
    case toEnglish(Sentence)
    /// Type a sentence in the language from its English.
    case toTarget(Sentence)
    /// Pick the missing word.
    case fillGap(Sentence, gap: Int, options: [String])
    /// Match words with their meanings.
    case matchPairs([VocabItem])
    /// Hear it, type it.
    case dictation(Sentence)
    /// Put the word tiles in order.
    case build(Sentence, tiles: [String])

    var title: String {
        switch self {
        case .pictureChoice: return "New word"
        case .listen: return "Listen"
        case .speak: return "Say it"
        case .toEnglish: return "Translate"
        case .toTarget: return "Translate"
        case .fillGap: return "Fill the gap"
        case .matchPairs: return "Match the pairs"
        case .dictation: return "Write what you hear"
        case .build: return "Build the sentence"
        }
    }

    /// The words this exercise practises, for bringing mistakes back.
    var items: [String] {
        switch self {
        case .pictureChoice(let item, _): return [item.term]
        case .matchPairs(let items): return items.map(\.term)
        case .listen(let sentence, _), .speak(let sentence), .toEnglish(let sentence), .toTarget(let sentence),
             .fillGap(let sentence, _, _), .dictation(let sentence), .build(let sentence, _):
            return [sentence.target]
        }
    }
}

/// A small, repeatable shuffle, so a lesson is the same if you leave and come back.
struct SeededRandom: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) { state = seed == 0 ? 0x9E37_79B9_7F4A_7C15 : seed }

    mutating func next() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }

    static func seed(_ text: String) -> UInt64 {
        text.unicodeScalars.reduce(1_469_598_103_934_665_603) { ($0 ^ UInt64($1.value)) &* 1_099_511_628_211 }
    }
}

enum LessonBuilder {
    /// One lesson of a unit. Lesson 0 introduces the words, 1 practises them in sentences, 2 mixes everything and adds speaking.
    /// `reviews` are earlier sentences or words you got wrong, woven in.
    static func lesson(_ unit: CourseUnit, number: Int, reviews: [Sentence] = [], language: LanguageInfo) -> [Exercise] {
        var random = SeededRandom(seed: SeededRandom.seed("\(unit.id)-\(number)"))
        var exercises: [Exercise] = []
        let words = unit.words
        let sentences = unit.sentences
        func wordOptions(for item: VocabItem) -> [VocabItem] {
            var others = words.filter { $0 != item }.shuffled(using: &random)
            others = Array(others.prefix(3))
            return ([item] + others).shuffled(using: &random)
        }
        func meaningOptions(for sentence: Sentence) -> [String] {
            let others = sentences.filter { $0 != sentence }.map(\.english).shuffled(using: &random).prefix(3)
            return ([sentence.english] + others).shuffled(using: &random)
        }
        func gap(in sentence: Sentence) -> Exercise? {
            let tokens = Tokens.words(sentence.target, language: language)
            guard tokens.count >= 2 else { return nil }
            // Prefer a word from the unit's vocabulary.
            let vocab = Set(words.flatMap { Tokens.words($0.term, language: language).map { Tokens.fold($0) } })
            let candidates = tokens.indices.filter { vocab.contains(Tokens.fold(tokens[$0])) }
            let index = candidates.isEmpty ? Int.random(in: 0..<tokens.count, using: &random) : candidates.randomElement(using: &random)!
            let answer = tokens[index]
            let distractors = words.flatMap { Tokens.words($0.term, language: language) }
                .filter { Tokens.fold($0) != Tokens.fold(answer) }.shuffled(using: &random).prefix(3)
            guard distractors.count >= 2 else { return nil }
            return .fillGap(sentence, gap: index, options: ([answer] + distractors).shuffled(using: &random))
        }
        func build(_ sentence: Sentence) -> Exercise {
            let tokens = Tokens.words(sentence.target, language: language)
            let extras = words.flatMap { Tokens.words($0.term, language: language) }
                .filter { word in !tokens.contains { Tokens.fold($0) == Tokens.fold(word) } }
                .shuffled(using: &random).prefix(2)
            return .build(sentence, tiles: (tokens + extras).shuffled(using: &random))
        }

        switch number {
        case 0:
            for item in words.prefix(8) { exercises.append(.pictureChoice(item, options: wordOptions(for: item))) }
            exercises.append(.matchPairs(Array(words.shuffled(using: &random).prefix(5))))
            for sentence in sentences.prefix(3) { exercises.append(.listen(sentence, options: meaningOptions(for: sentence))) }
        case 1:
            for (index, sentence) in sentences.enumerated() {
                switch index % 4 {
                case 0: exercises.append(.toEnglish(sentence))
                case 1: exercises.append(build(sentence))
                case 2: if let gap = gap(in: sentence) { exercises.append(gap) } else { exercises.append(.toEnglish(sentence)) }
                default: exercises.append(.listen(sentence, options: meaningOptions(for: sentence)))
                }
            }
            exercises.append(.matchPairs(Array(words.shuffled(using: &random).prefix(5))))
        default:
            for (index, sentence) in sentences.shuffled(using: &random).enumerated() {
                switch index % 5 {
                case 0: exercises.append(.speak(sentence))
                case 1: exercises.append(.toTarget(sentence))
                case 2: exercises.append(.dictation(sentence))
                case 3: exercises.append(build(sentence))
                default: if let gap = gap(in: sentence) { exercises.append(gap) } else { exercises.append(.speak(sentence)) }
                }
            }
        }
        for sentence in reviews.prefix(4) {
            exercises.insert(.toEnglish(sentence), at: min(exercises.count, 2 + Int.random(in: 0...max(0, exercises.count - 2), using: &random)))
        }
        return exercises
    }

    /// A review lesson from what's due: things you got wrong, and things you haven't seen for a while.
    static func review(_ sentences: [Sentence], words: [VocabItem], language: LanguageInfo) -> [Exercise] {
        var random = SeededRandom(seed: SeededRandom.seed(sentences.map(\.target).joined() + words.map(\.term).joined()))
        var exercises: [Exercise] = []
        for (index, sentence) in sentences.enumerated() {
            exercises.append(index % 3 == 0 ? .toTarget(sentence) : (index % 3 == 1 ? .toEnglish(sentence) : .dictation(sentence)))
        }
        if words.count >= 3 { exercises.append(.matchPairs(Array(words.prefix(5)))) }
        return exercises.shuffled(using: &random)
    }
}

// MARK: Checking answers

enum Tokens {
    /// Words in a sentence, without punctuation. Japanese and Chinese are split into characters.
    static func words(_ text: String, language: LanguageInfo? = nil) -> [String] {
        if language?.noSpaces == true {
            return text.filter { !$0.isPunctuation && !$0.isWhitespace && !"「」、。？！".contains($0) }.map(String.init)
        }
        let separators = CharacterSet.whitespacesAndNewlines
        return text.components(separatedBy: separators).compactMap { raw in
            let trimmed = raw.trimmingCharacters(in: CharacterSet.punctuationCharacters.union(CharacterSet(charactersIn: "¿¡«»“”\"")))
            return trimmed.isEmpty ? nil : trimmed
        }
    }

    /// Lowercase without accents: "Está" and "esta" match here.
    static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil).lowercased()
    }

    /// Lowercase, accents kept, apostrophes made straight.
    static func plain(_ text: String) -> String {
        text.lowercased().replacingOccurrences(of: "’", with: "'")
    }
}

enum AnswerCheck {
    enum Verdict: Equatable, Sendable {
        case right
        /// Right, with a small slip worth knowing about (an accent, a typo).
        case nearly(String)
        case wrong
    }

    /// Edit distance between two strings.
    static func distance(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var previous = Array(0...b.count)
        for i in 1...a.count {
            var current = [i] + Array(repeating: 0, count: b.count)
            for j in 1...b.count {
                current[j] = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1))
            }
            previous = current
        }
        return previous[b.count]
    }

    private static let englishFiller: Set<String> = ["the", "a", "an"]

    /// Checks a typed answer against what was expected, forgiving capitals, punctuation, small typos and (with a note) missing accents.
    static func check(_ given: String, against expected: [String], language: LanguageInfo?) -> Verdict {
        let givenWords = Tokens.words(given, language: language)
        guard !givenWords.isEmpty else { return .wrong }
        var best = Verdict.wrong
        for answer in expected {
            let answerWords = Tokens.words(answer, language: language)
            let joinedGiven = givenWords.map(Tokens.plain).joined(separator: " ")
            let joinedAnswer = answerWords.map(Tokens.plain).joined(separator: " ")
            if joinedGiven == joinedAnswer { return .right }
            if givenWords.map(Tokens.fold) == answerWords.map(Tokens.fold) {
                // Only the accents differ.
                let missed = zip(givenWords, answerWords).first { Tokens.plain($0) != Tokens.plain($1) }?.1 ?? answer
                best = .nearly("Watch the accent: \(missed)")
                continue
            }
            if language == nil {
                // English: "a" and "the" don't decide it.
                let a = givenWords.map(Tokens.fold).filter { !englishFiller.contains($0) }
                let b = answerWords.map(Tokens.fold).filter { !englishFiller.contains($0) }
                if a == b { return .right }
            }
            let foldedGiven = givenWords.map(Tokens.fold).joined(separator: " ")
            let foldedAnswer = answerWords.map(Tokens.fold).joined(separator: " ")
            let allowed = max(1, foldedAnswer.count / 12)
            if distance(foldedGiven, foldedAnswer) <= allowed, best == .wrong {
                best = .nearly("Nearly: \(answer)")
            }
        }
        return best
    }

    /// The expected English for a sentence, with its alternatives.
    static func englishAnswers(_ sentence: Sentence) -> [String] { [sentence.english] + sentence.alternatives }
}

/// What you said, compared word by word with what you meant to say.
enum Pronunciation {
    struct Result: Equatable, Sendable {
        /// Each expected word and whether it was heard.
        var words: [(word: String, heard: Bool)]
        var score: Double

        static func == (a: Result, b: Result) -> Bool {
            a.score == b.score && a.words.map(\.word) == b.words.map(\.word) && a.words.map(\.heard) == b.words.map(\.heard)
        }

        var missed: [String] { words.filter { !$0.heard }.map(\.word) }

        var verdict: String {
            if score >= 0.95 { return "Clear as anything." }
            if score >= 0.75 { return "Good. Listen again to \(missed.prefix(2).joined(separator: " and "))." }
            if score >= 0.4 { return "Getting there. Try \(missed.prefix(3).joined(separator: ", ")) slowly." }
            return "That didn't come through. Listen once more, then try again."
        }
    }

    static func compare(heard: String, expected: String, language: LanguageInfo) -> Result {
        let want = Tokens.words(expected, language: language)
        let got = Tokens.words(heard, language: language).map(Tokens.fold)
        // Longest common subsequence, so a word said out of place doesn't count twice.
        let a = want.map(Tokens.fold)
        var table = Array(repeating: Array(repeating: 0, count: got.count + 1), count: a.count + 1)
        if !a.isEmpty && !got.isEmpty {
            for i in 1...a.count {
                for j in 1...got.count {
                    let near = a[i - 1] == got[j - 1] || (a[i - 1].count > 3 && AnswerCheck.distance(a[i - 1], got[j - 1]) <= 1)
                    table[i][j] = near ? table[i - 1][j - 1] + 1 : max(table[i - 1][j], table[i][j - 1])
                }
            }
        }
        var heardFlags = Array(repeating: false, count: a.count)
        var i = a.count, j = got.count
        while i > 0 && j > 0 {
            let near = a[i - 1] == got[j - 1] || (a[i - 1].count > 3 && AnswerCheck.distance(a[i - 1], got[j - 1]) <= 1)
            if near && table[i][j] == table[i - 1][j - 1] + 1 {
                heardFlags[i - 1] = true
                i -= 1
                j -= 1
            } else if table[i - 1][j] >= table[i][j - 1] {
                i -= 1
            } else {
                j -= 1
            }
        }
        let words = zip(want, heardFlags).map { (word: $0, heard: $1) }
        let score = want.isEmpty ? 0 : Double(heardFlags.filter { $0 }.count) / Double(want.count)
        return Result(words: words, score: score)
    }
}

// MARK: Reviews, placement and progress

/// Something to practise again: a sentence or word, in the same boxes as the flashcards.
struct ReviewItem: Codable, Hashable, Identifiable, Sendable {
    /// The sentence or word in the language.
    var id: String
    var english: String
    var isWord: Bool
    var box = 0
    var due = Date()
    var mistakes = 0

    static let intervals: [Double] = [0, 1, 3, 7, 16, 35]

    /// Right answers move it up a box and further away; a wrong one brings it back today.
    mutating func record(correct: Bool, at now: Date = Date()) {
        if correct {
            box = min(box + 1, Self.intervals.count - 1)
            due = now.addingTimeInterval(Self.intervals[box] * 86_400)
        } else {
            box = 0
            mistakes += 1
            due = now.addingTimeInterval(10 * 60)
        }
    }

    var isKnown: Bool { box >= 3 }
}

enum Placement {
    /// The questions, a few from each level, easiest first.
    static func questions(_ course: Course, perLevel: Int = 4) -> [PlacementQuestion] {
        CEFR.allCases.flatMap { level in course.placement.filter { $0.level == level }.prefix(perLevel) }
    }

    /// The level to start at: the highest where you got at least three in four, never skipping a level you didn't pass.
    static func level(answers: [PlacementQuestion: Int]) -> CEFR {
        var placed = CEFR.a1
        for level in CEFR.allCases {
            let asked = answers.filter { $0.key.level == level }
            guard !asked.isEmpty else { break }
            let right = asked.filter { $0.key.answer == $0.value }.count
            if Double(right) / Double(asked.count) >= 0.75 {
                if let next = CEFR.allCases.first(where: { $0 > level }) { placed = next } else { placed = level }
            } else {
                break
            }
        }
        return placed
    }
}

struct StudyDay: Codable, Hashable, Sendable {
    /// yyyy-MM-dd.
    var day: String
    var minutes: Double
}

enum StudyProgress {
    static func minutes(thisWeek days: [StudyDay], now: Date = Date(), calendar: Calendar = .current) -> Double {
        guard let start = calendar.dateInterval(of: .weekOfYear, for: now)?.start else { return 0 }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        let first = formatter.string(from: start)
        return days.filter { $0.day >= first }.reduce(0) { $0 + $1.minutes }
    }

    /// Days in a row with any practice, ending today or yesterday. Only shown if you turn streaks on.
    static func streak(_ days: [StudyDay], now: Date = Date(), calendar: Calendar = .current) -> Int {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        let practised = Set(days.filter { $0.minutes > 0 }.map(\.day))
        var day = now
        if !practised.contains(formatter.string(from: day)) {
            day = calendar.date(byAdding: .day, value: -1, to: day) ?? day
        }
        var count = 0
        while practised.contains(formatter.string(from: day)) {
            count += 1
            day = calendar.date(byAdding: .day, value: -1, to: day) ?? day
        }
        return count
    }
}

// MARK: Units Harris writes

enum UnitWriter {
    /// What Harris is asked for when a language or level has no written units yet.
    static func prompt(language: LanguageInfo, level: CEFR, number: Int, after titles: [String]) -> (system: String, prompt: String) {
        let system = """
        You are Harris, the teacher inside 11am, writing one unit of a \(language.name) course for an English speaker at CEFR \(level.rawValue). \
        Reply with JSON only, no commentary, in exactly this shape:
        {"title": "...", "tip": "one grammar tip in plain English, two sentences at most",
         "words": [{"term": "word in \(language.name)", "meaning": "English", "symbol": "an SF Symbol name or null"}],
         "sentences": [{"target": "sentence in \(language.name)", "english": "natural English", "alternatives": ["other natural English"]}],
         "story": {"title": "...", "lines": [{"target": "...", "english": "..."}], "questions": [{"question": "English", "options": ["...", "...", "..."], "answer": 0}]}}
        Give 10 words and 8 short sentences that use them, natural and correct, at \(level.rawValue). Include the article or gender with nouns where the language has them. \
        The story has 5 to 7 lines using mostly these words, and 3 questions.
        """
        let prompt = "Unit \(number) of \(level.rawValue). Earlier units: \(titles.isEmpty ? "none" : titles.joined(separator: ", ")). Choose a useful everyday topic that follows on."
        return (system, prompt)
    }

    struct Draft: Decodable {
        var title: String
        var tip: String
        var words: [VocabItem]
        var sentences: [Sentence]
        var story: Story?

        private enum CodingKeys: String, CodingKey { case title, tip, words, sentences, story }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            title = try container.decode(String.self, forKey: .title)
            tip = try container.decodeIfPresent(String.self, forKey: .tip) ?? ""
            words = try container.decode([VocabItem].self, forKey: .words)
            sentences = try container.decode([Sentence].self, forKey: .sentences)
            story = try? container.decodeIfPresent(Story.self, forKey: .story)
        }
    }

    enum Problem: LocalizedError, Equatable {
        case notJSON, tooSmall, empty(String), duplicate(String), storyAnswer

        var errorDescription: String? {
            switch self {
            case .notJSON: return "Harris's unit didn't come back as a unit."
            case .tooSmall: return "Harris's unit was too short to learn from."
            case .empty(let what): return "Harris's unit had an empty \(what)."
            case .duplicate(let what): return "Harris's unit repeated \u{201C}\(what)\u{201D}."
            case .storyAnswer: return "One of the story's questions had no right answer."
            }
        }
    }

    /// Reads and checks a written unit: enough words and sentences, nothing empty or repeated, answers that exist.
    static func unit(from text: String, language: LanguageInfo, level: CEFR, number: Int) throws -> CourseUnit {
        guard let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}"),
              let data = String(text[start...end]).data(using: .utf8),
              let draft = try? JSONDecoder().decode(Draft.self, from: data) else { throw Problem.notJSON }
        guard draft.words.count >= 6, draft.sentences.count >= 5 else { throw Problem.tooSmall }
        for word in draft.words where word.term.trimmingCharacters(in: .whitespaces).isEmpty || word.meaning.trimmingCharacters(in: .whitespaces).isEmpty {
            throw Problem.empty("word")
        }
        for sentence in draft.sentences where sentence.target.trimmingCharacters(in: .whitespaces).isEmpty || sentence.english.trimmingCharacters(in: .whitespaces).isEmpty {
            throw Problem.empty("sentence")
        }
        var seen = Set<String>()
        for term in draft.words.map(\.term) + draft.sentences.map(\.target) {
            guard seen.insert(Tokens.fold(term)).inserted else { throw Problem.duplicate(term) }
        }
        var story = draft.story
        if let current = story {
            if current.questions.contains(where: { !$0.options.indices.contains($0.answer) }) { throw Problem.storyAnswer }
            if current.lines.isEmpty { story = nil }
        }
        let words = draft.words.map { word -> VocabItem in
            var copy = word
            if let symbol = copy.symbol, symbol.isEmpty || symbol == "null" { copy.symbol = nil }
            return copy
        }
        return CourseUnit(id: "\(language.code)-\(level.rawValue.lowercased())-g\(number)", level: level, title: draft.title, tip: draft.tip,
                          words: words, sentences: draft.sentences, story: story, generated: true)
    }
}
