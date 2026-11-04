import Foundation

// Checks Harris's language course: the written units, lessons built from them, forgiving answer checking,
// pronunciation compared word by word, the review boxes, the placement test, progress, and units Harris writes.

var failures = 0
func check(_ condition: Bool, _ name: String) {
    print(condition ? "PASS" : "FAIL", name)
    if !condition { failures += 1 }
}

let spanish = LanguageInfo.find("es-ES")!
let french = LanguageInfo.find("fr-FR")!
let japanese = LanguageInfo.find("ja-JP")!

// MARK: The written courses

for course in [LanguageCourses.spanish, LanguageCourses.french] {
    let name = course.language
    check(course.units.count >= 5 && course.units.allSatisfy { $0.words.count >= 8 && $0.sentences.count >= 6 && !$0.tip.isEmpty },
          "\(name): five units, each with words, sentences and a tip")
    let terms = course.units.flatMap { $0.words.map { Tokens.fold($0.term) } }
    check(Set(terms).count == terms.count, "\(name): no word taught twice")
    let ids = course.units.map(\.id)
    check(Set(ids).count == ids.count, "\(name): unit ids are unique")
    check(course.units.compactMap(\.story).allSatisfy { story in story.questions.allSatisfy { $0.options.indices.contains($0.answer) } && story.lines.count >= 4 },
          "\(name): stories have lines and answerable questions")
    check(CEFR.allCases.allSatisfy { level in course.placement.filter { $0.level == level }.count >= 4 }
          && course.placement.allSatisfy { $0.options.indices.contains($0.answer) && $0.prompt.contains("___") },
          "\(name): placement questions at every level, each with a gap and a right answer")
    // Every sentence's words should mostly be taught by then (names and small words aside).
    var taught = Set<String>()
    var untaught: [String] = []
    for unit in course.units {
        for word in unit.words { for token in Tokens.words(word.term) { taught.insert(Tokens.fold(token)) } }
        for sentence in unit.sentences {
            for token in Tokens.words(sentence.target) where token.first?.isUppercase == false && token.count > 2 && !taught.contains(Tokens.fold(token)) {
                untaught.append(token)
            }
        }
    }
    check(untaught.count <= 8, "\(name): sentences use words already taught (\(untaught.count) not yet: \(Set(untaught).sorted().prefix(8).joined(separator: ", ")))")
}

// MARK: Lessons

let unit = LanguageCourses.spanish.units[1]
let first = LessonBuilder.lesson(unit, number: 0, language: spanish)
check(first.prefix(8).allSatisfy { if case .pictureChoice = $0 { return true } else { return false } }, "Lesson 1 starts with new words and pictures")
check(first.contains { if case .matchPairs = $0 { return true } else { return false } }, "…and matches pairs")
if case .pictureChoice(let item, let options) = first[0] {
    check(options.count == 4 && options.contains(item) && Set(options).count == 4, "Four different choices, one of them right")
}
let second = LessonBuilder.lesson(unit, number: 1, language: spanish)
let third = LessonBuilder.lesson(unit, number: 2, language: spanish)
check(second.contains { if case .build = $0 { return true } else { return false } } && second.contains { if case .toEnglish = $0 { return true } else { return false } },
      "Lesson 2 translates and builds sentences")
check(third.contains { if case .speak = $0 { return true } else { return false } } && third.contains { if case .dictation = $0 { return true } else { return false } }
      && third.contains { if case .toTarget = $0 { return true } else { return false } }, "Lesson 3 speaks, listens and writes in Spanish")
check(LessonBuilder.lesson(unit, number: 1, language: spanish) == second, "The same lesson comes out the same each time")
for exercise in first + second + third {
    if case .build(let sentence, let tiles) = exercise {
        let need = Tokens.words(sentence.target, language: spanish)
        var pool = tiles
        let allThere = need.allSatisfy { word in
            guard let index = pool.firstIndex(of: word) else { return false }
            pool.remove(at: index)
            return true
        }
        check(allThere && tiles.count > need.count, "Building a sentence has every word, plus a couple that don't belong (\(sentence.target))")
        break
    }
}
for exercise in second + third {
    if case .fillGap(let sentence, let gap, let options) = exercise {
        let answer = Tokens.words(sentence.target, language: spanish)[gap]
        check(options.contains(answer) && options.count >= 3, "Fill the gap offers the missing word among others (\(answer))")
        break
    }
}
let withReviews = LessonBuilder.lesson(unit, number: 1, reviews: [Sentence(target: "Buenas noches, Ana.", english: "Good night, Ana.")], language: spanish)
check(withReviews.count == second.count + 1 && withReviews.contains { $0.items == ["Buenas noches, Ana."] }, "Earlier mistakes are woven into a lesson")

// MARK: Checking answers

check(AnswerCheck.check("hola, me llamo ana", against: ["Hola, me llamo Ana."], language: spanish) == .right, "Capitals and punctuation don't matter")
if case .nearly(let note) = AnswerCheck.check("Donde esta el hotel", against: ["¿Dónde está el hotel?"], language: spanish) {
    check(note.contains("Dónde"), "Missing accents count, with a note (\(note))")
} else { check(false, "Missing accents count, with a note") }
if case .nearly = AnswerCheck.check("Quiero un cafe con lehce", against: ["Quiero un café con leche."], language: spanish) {
    check(true, "A small typo is nearly right")
} else { check(false, "A small typo is nearly right") }
check(AnswerCheck.check("Quiero un té", against: ["Quiero un café."], language: spanish) == .wrong, "A different word is wrong")
check(AnswerCheck.check("I'd like a coffee", against: AnswerCheck.englishAnswers(LanguageCourses.spanish.units[1].sentences[0]), language: nil) == .right,
      "Other good English is accepted")
check(AnswerCheck.check("I want coffee", against: ["I want a coffee."], language: nil) == .right, "English articles don't decide it")
check(AnswerCheck.check("", against: ["Hola."], language: spanish) == .wrong, "An empty answer is wrong")
check(AnswerCheck.check("C’est mon ami", against: ["C'est mon ami."], language: french) == .right, "Curly and straight apostrophes match")
check(Tokens.words("¿Dónde está el hotel?") == ["Dónde", "está", "el", "hotel"] && Tokens.words("こんにちは。", language: japanese).count == 5,
      "Words split, and Japanese by character")
check(AnswerCheck.distance("kitten", "sitting") == 3, "Edit distance")

// MARK: Pronunciation

let perfect = Pronunciation.compare(heard: "Hola me llamo Ana", expected: "Hola, me llamo Ana.", language: spanish)
check(perfect.score == 1 && perfect.missed.isEmpty, "Saying it all is a perfect score")
let partial = Pronunciation.compare(heard: "hola me Ana", expected: "Hola, me llamo Ana.", language: spanish)
check(partial.score == 0.75 && partial.missed == ["llamo"], "A missed word is named (\(partial.missed))")
let jumbled = Pronunciation.compare(heard: "Ana llamo me hola", expected: "Hola, me llamo Ana.", language: spanish)
check(jumbled.score < 0.5, "Words out of order don't all count (\(jumbled.score))")
let close = Pronunciation.compare(heard: "donde esta la estacion", expected: "¿Dónde está la estación?", language: spanish)
check(close.score == 1, "Accents in the transcript don't matter")
check(Pronunciation.compare(heard: "", expected: "Hola.", language: spanish).score == 0, "Silence scores nothing")

// MARK: Reviews

var item = ReviewItem(id: "el café", english: "the coffee", isWord: true)
let now = Date(timeIntervalSince1970: 1_800_000_000)
item.record(correct: true, at: now)
check(item.box == 1 && item.due == now.addingTimeInterval(86_400), "Right moves it up a box: back tomorrow")
item.record(correct: true, at: now)
item.record(correct: true, at: now)
check(item.box == 3 && item.isKnown && item.due == now.addingTimeInterval(7 * 86_400), "Three right: known, back in a week")
item.record(correct: false, at: now)
check(item.box == 0 && item.mistakes == 1 && item.due == now.addingTimeInterval(600), "Wrong: back in ten minutes")
let review = LessonBuilder.review([Sentence(target: "Hola.", english: "Hello."), Sentence(target: "Gracias.", english: "Thank you.")],
                                  words: unit.words.prefix(4).map { $0 }, language: spanish)
check(review.count == 3, "A review mixes the sentences you missed with words")

// MARK: Placement

let questions = Placement.questions(LanguageCourses.spanish)
check(questions.count == 16 && questions.first?.level == .a1 && questions.last?.level == .b2, "Placement: four questions a level, easiest first")
var answers: [PlacementQuestion: Int] = [:]
for question in questions where question.level == .a1 { answers[question] = question.answer }
check(Placement.level(answers: answers) == .a2, "All of A1 right: start at A2")
for question in questions where question.level == .a2 { answers[question] = question.answer }
for (index, question) in questions.filter({ $0.level == .b1 }).enumerated() { answers[question] = index < 2 ? question.answer : (question.answer + 1) % 4 }
check(Placement.level(answers: answers) == .b1, "Half of B1 wrong: start at B1")
var beginner: [PlacementQuestion: Int] = [:]
for question in questions.prefix(2) { beginner[question] = (question.answer + 1) % 4 }
check(Placement.level(answers: beginner) == .a1, "Getting A1 wrong: start at the beginning")
var expert: [PlacementQuestion: Int] = [:]
for question in questions { expert[question] = question.answer }
check(Placement.level(answers: expert) == .b2, "Everything right: B2, the top of the course")

// MARK: Progress

var sydney = Calendar(identifier: .gregorian)
sydney.timeZone = TimeZone(identifier: "Australia/Sydney")!
sydney.firstWeekday = 2
let wednesday = sydney.date(from: DateComponents(year: 2026, month: 11, day: 4, hour: 9))!
let days = [StudyDay(day: "2026-11-04", minutes: 10), StudyDay(day: "2026-11-03", minutes: 12), StudyDay(day: "2026-11-02", minutes: 8),
            StudyDay(day: "2026-10-31", minutes: 20)]
check(StudyProgress.minutes(thisWeek: days, now: wednesday, calendar: sydney) == 30, "Minutes this week (Monday on)")
check(StudyProgress.streak(days, now: wednesday, calendar: sydney) == 3, "A streak counts days in a row")
let thursday = sydney.date(byAdding: .day, value: 1, to: wednesday)!
check(StudyProgress.streak(days, now: thursday, calendar: sydney) == 3, "…and doesn't break before the day's over")
check(StudyProgress.streak(days, now: sydney.date(byAdding: .day, value: 2, to: wednesday)!, calendar: sydney) == 0, "A missed day ends it, quietly")

// MARK: Units Harris writes

let written = """
Here's the unit:
{"title": "Al mercado", "tip": "Use cuánto cuesta to ask a price.",
 "words": [{"term": "la fruta", "meaning": "the fruit", "symbol": "apple.logo"}, {"term": "la manzana", "meaning": "the apple", "symbol": null},
           {"term": "el queso", "meaning": "the cheese"}, {"term": "cuánto", "meaning": "how much"}, {"term": "cuesta", "meaning": "costs"},
           {"term": "el euro", "meaning": "the euro", "symbol": "eurosign"}],
 "sentences": [{"target": "¿Cuánto cuesta la fruta?", "english": "How much is the fruit?", "alternatives": ["How much does the fruit cost?"]},
               {"target": "Quiero una manzana.", "english": "I want an apple."}, {"target": "El queso cuesta dos euros.", "english": "The cheese costs two euros."},
               {"target": "¿Cuánto cuesta el queso?", "english": "How much is the cheese?"}, {"target": "Una manzana, por favor.", "english": "An apple, please."}],
 "story": {"title": "En el mercado", "lines": [{"target": "Voy al mercado.", "english": "I go to the market."}],
           "questions": [{"question": "Where does she go?", "options": ["The market", "The bank"], "answer": 0}]}}
"""
do {
    let generated = try UnitWriter.unit(from: written, language: spanish, level: .a1, number: 1)
    check(generated.generated && generated.words.count == 6 && generated.sentences.count == 5 && generated.words[1].symbol == nil
          && generated.story?.questions.count == 1 && generated.id == "es-a1-g1", "A unit Harris writes is read and checked")
} catch {
    check(false, "A unit Harris writes is read and checked (\(error.localizedDescription))")
}
check((try? UnitWriter.unit(from: "Sorry, I can't.", language: spanish, level: .a1, number: 2)) == nil, "Something that isn't a unit is refused")
let thin = #"{"title": "x", "tip": "", "words": [{"term": "a", "meaning": "b"}], "sentences": []}"#
do { _ = try UnitWriter.unit(from: thin, language: spanish, level: .a1, number: 2); check(false, "A unit too short to learn from is refused") } catch {
    check((error as? UnitWriter.Problem) == .tooSmall, "A unit too short to learn from is refused")
}
let repeated = written.replacingOccurrences(of: "\"term\": \"el queso\"", with: "\"term\": \"la fruta\"")
do { _ = try UnitWriter.unit(from: repeated, language: spanish, level: .a1, number: 2); check(false, "A unit that repeats itself is refused") } catch {
    check((error as? UnitWriter.Problem) == .duplicate("la fruta"), "A unit that repeats itself is refused")
}
let badStory = written.replacingOccurrences(of: "\"answer\": 0}", with: "\"answer\": 5}")
check((try? UnitWriter.unit(from: badStory, language: spanish, level: .a1, number: 2)) == nil, "A story question without a right answer is refused")
let prompt = UnitWriter.prompt(language: japanese, level: .a2, number: 3, after: ["Hello", "Food"])
check(prompt.system.contains("Japanese") && prompt.system.contains("A2") && prompt.prompt.contains("Hello, Food"), "Harris is asked for the right language and level")

print(failures == 0 ? "ALL PASSED" : "\(failures) FAILED")
exit(failures == 0 ? 0 : 1)
