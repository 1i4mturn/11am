import Foundation

struct Flashcard: Identifiable, Codable, Hashable {
    var id = UUID()
    var front: String
    var back: String
    /// Leitner box: 0 is new or forgotten; each step up waits longer.
    var box = 0
    var due = Date()
}

struct Deck: Identifiable, Codable {
    var id = UUID()
    var name: String
    var cards: [Flashcard]
}

struct PathStep: Identifiable, Codable, Hashable {
    var id = UUID()
    var title: String
    var done = false
}

struct LearningPath: Codable {
    var goal: String
    var steps: [PathStep]
}

enum Grade: Int, CaseIterable, Identifiable {
    case again = 1, hard, good, easy

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .again: return "Again"
        case .hard: return "Hard"
        case .good: return "Good"
        case .easy: return "Easy"
        }
    }
}

private struct LearnState: Codable {
    var decks: [Deck]
    var path: LearningPath?
}

/// Harris in the sandbox: flashcards with spaced repetition, cards made from your own text, and learning paths.
@MainActor
final class LearnModel: ObservableObject {
    @Published private(set) var decks: [Deck] = []
    @Published var deckID: UUID?
    @Published private(set) var queue: [UUID] = []
    @Published var showingBack = false
    @Published private(set) var reviewedToday = 0
    @Published private(set) var path: LearningPath?
    @Published private(set) var cardsRun: BrainRun?
    @Published private(set) var pathRun: BrainRun?
    @Published var notice: String?

    /// Days to wait after each box.
    private static let intervals: [Double] = [0, 1, 3, 7, 16, 35]

    private let brain: Brain

    init(brain: Brain) {
        self.brain = brain
        if let state = JSONStore.load(LearnState.self, from: "learn") {
            decks = state.decks
            path = state.path
        } else {
            decks = [LearnSamples.deck()]
        }
        deckID = decks.first?.id
        startReview()
    }

    var deck: Deck? { decks.first { $0.id == deckID } }

    var dueCount: Int { deck?.cards.filter { $0.due <= Date() }.count ?? 0 }

    var learnedCount: Int { deck?.cards.filter { $0.box >= 3 }.count ?? 0 }

    var current: Flashcard? {
        guard let id = queue.first else { return nil }
        return deck?.cards.first { $0.id == id }
    }

    // MARK: Review

    func select(_ id: UUID) {
        deckID = id
        startReview()
    }

    func startReview() {
        queue = deck?.cards.filter { $0.due <= Date() }.map(\.id) ?? []
        showingBack = false
    }

    func flip() {
        guard current != nil else { return }
        showingBack.toggle()
    }

    func grade(_ grade: Grade) {
        guard let card = current, let deckIndex = decks.firstIndex(where: { $0.id == deckID }),
              let cardIndex = decks[deckIndex].cards.firstIndex(where: { $0.id == card.id }) else { return }
        var updated = card
        switch grade {
        case .again:
            updated.box = 0
            updated.due = Date().addingTimeInterval(10 * 60)
        case .hard:
            updated.box = max(1, card.box)
            updated.due = Date().addingTimeInterval(LearnModel.intervals[updated.box] * 86_400 / 2)
        case .good:
            updated.box = min(card.box + 1, LearnModel.intervals.count - 1)
            updated.due = Date().addingTimeInterval(LearnModel.intervals[updated.box] * 86_400)
        case .easy:
            updated.box = min(card.box + 2, LearnModel.intervals.count - 1)
            updated.due = Date().addingTimeInterval(LearnModel.intervals[updated.box] * 86_400)
        }
        decks[deckIndex].cards[cardIndex] = updated
        queue.removeFirst()
        // Forgotten cards come back at the end of this session.
        if grade == .again { queue.append(card.id) }
        showingBack = false
        reviewedToday += 1
        save()
    }

    // MARK: Making cards

    func makeCards(from text: String) {
        let source = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !source.isEmpty else { notice = "Paste some notes or an article first."; return }
        notice = nil
        let system = """
        You are Harris, the learning agent inside 11am. Write six to ten flashcards that test the important ideas in the text. \
        Use exactly this format, one card after another:
        Q: question
        A: short answer
        """
        cardsRun = brain.run(BrainRequest(system: system, prompt: String(source.prefix(8_000)), weight: .quick))
    }

    static func parseCards(_ text: String) -> [Flashcard] {
        var cards: [Flashcard] = []
        var question: String?
        for raw in text.split(separator: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.lowercased().hasPrefix("q:") {
                question = line.dropFirst(2).trimmingCharacters(in: .whitespaces)
            } else if line.lowercased().hasPrefix("a:"), let front = question {
                cards.append(Flashcard(front: front, back: line.dropFirst(2).trimmingCharacters(in: .whitespaces)))
                question = nil
            }
        }
        return cards
    }

    func addCards(_ cards: [Flashcard]) {
        guard !cards.isEmpty, let index = decks.firstIndex(where: { $0.id == deckID }) else { return }
        decks[index].cards.append(contentsOf: cards)
        cardsRun = nil
        save()
        startReview()
    }

    func newDeck(named name: String) {
        let deck = Deck(name: name.isEmpty ? "New deck" : name, cards: [])
        decks.append(deck)
        select(deck.id)
        save()
    }

    // MARK: Paths

    func makePath(for goal: String) {
        let goal = goal.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !goal.isEmpty else { return }
        let system = """
        You are Harris, the learning agent inside 11am. Turn the goal into a path of five steps, each one a ten-minute session. \
        Write exactly five lines, each starting with the step number and a full stop, like "1. Read about…". Nothing else.
        """
        pathRun = brain.run(BrainRequest(system: system, prompt: "Goal: \(goal)", weight: .quick))
        path = LearningPath(goal: goal, steps: [])
    }

    func adoptPath(from text: String) {
        let steps = text.split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.first?.isNumber == true }
            .map { line -> PathStep in
                let title = line.drop { $0.isNumber || $0 == "." || $0 == ")" || $0 == " " }
                return PathStep(title: String(title))
            }
        guard !steps.isEmpty, var current = path else { return }
        current.steps = Array(steps.prefix(7))
        path = current
        pathRun = nil
        save()
    }

    func toggle(_ step: PathStep) {
        guard var current = path, let index = current.steps.firstIndex(where: { $0.id == step.id }) else { return }
        current.steps[index].done.toggle()
        path = current
        save()
    }

    func clearPath() {
        path = nil
        pathRun = nil
        save()
    }

    private func save() {
        JSONStore.save(LearnState(decks: decks, path: path), to: "learn")
    }
}

enum LearnSamples {
    static func deck() -> Deck {
        let cards: [(String, String)] = [
            ("What is runway?", "How many months the business can keep going at its current net burn: cash ÷ net burn."),
            ("Gross burn vs net burn?", "Gross burn is everything going out each month. Net burn is gross burn minus revenue."),
            ("What is MRR?", "Monthly recurring revenue: the predictable revenue from subscriptions in a month."),
            ("How do you get ARR from MRR?", "ARR is MRR × 12."),
            ("What is CAC?", "Customer acquisition cost: sales and marketing spend ÷ new customers in the same period."),
            ("What is LTV?", "Lifetime value: the gross margin a customer brings in over the whole time they stay."),
            ("A healthy LTV to CAC ratio?", "Around 3:1 or better."),
            ("What is CAC payback?", "Months of a customer's gross margin it takes to earn back what it cost to win them."),
            ("What is gross margin?", "Revenue minus the direct cost of delivering it, as a share of revenue."),
            ("What is dilution?", "The drop in your ownership percentage when new shares are issued, for example in a raise."),
        ]
        return Deck(name: "Startup money basics", cards: cards.map { Flashcard(front: $0.0, back: $0.1) })
    }
}
