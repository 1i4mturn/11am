import AppKit
import Foundation

enum DealStage: String, Codable, CaseIterable, Identifiable {
    case lead, talking, proposal, won, lost

    var id: String { rawValue }

    var title: String {
        switch self {
        case .lead: return "Lead"
        case .talking: return "Talking"
        case .proposal: return "Proposal"
        case .won: return "Won"
        case .lost: return "Lost"
        }
    }

    /// Used for the weighted pipeline.
    var likelihood: Double {
        switch self {
        case .lead: return 0.1
        case .talking: return 0.3
        case .proposal: return 0.6
        case .won: return 1
        case .lost: return 0
        }
    }

    var isOpen: Bool { self != .won && self != .lost }
}

struct Deal: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var company: String
    var contact: String
    var value: Double
    var stage: DealStage
    var nextStep: String
    var lastTouch: Date
    var notes = ""

    /// Open deals with no touch in a week deserve a nudge.
    var isStale: Bool { stage.isOpen && Date().timeIntervalSince(lastTouch) > 7 * 86_400 }
}

/// Conner in the sandbox: a pipeline you drag between stages, with follow-ups drafted in your voice.
@MainActor
final class BusinessModel: ObservableObject {
    @Published private(set) var deals: [Deal] = []
    @Published var selectedID: UUID?
    @Published private(set) var drafts: [UUID: BrainRun] = [:]
    @Published private(set) var advice: [UUID: BrainRun] = [:]

    private let brain: Brain
    private let voice: VoiceProfile

    init(brain: Brain, voice: VoiceProfile) {
        self.brain = brain
        self.voice = voice
        deals = JSONStore.load([Deal].self, from: "business-deals") ?? BusinessSamples.deals()
    }

    var selected: Deal? { deals.first { $0.id == selectedID } }

    func deals(in stage: DealStage) -> [Deal] {
        deals.filter { $0.stage == stage }.sorted { $0.value > $1.value }
    }

    func total(_ stage: DealStage) -> Double {
        deals(in: stage).reduce(0) { $0 + $1.value }
    }

    var weightedPipeline: Double {
        deals.filter { $0.stage.isOpen }.reduce(0) { $0 + $1.value * $1.stage.likelihood }
    }

    var staleCount: Int { deals.filter(\.isStale).count }

    // MARK: Editing

    func move(_ id: UUID, to stage: DealStage) {
        guard let index = deals.firstIndex(where: { $0.id == id }), deals[index].stage != stage else { return }
        deals[index].stage = stage
        deals[index].lastTouch = Date()
        save()
    }

    func update(_ deal: Deal) {
        guard let index = deals.firstIndex(where: { $0.id == deal.id }) else { return }
        deals[index] = deal
        save()
    }

    func addDeal() {
        let deal = Deal(name: "New deal", company: "", contact: "", value: 0, stage: .lead, nextStep: "", lastTouch: Date())
        deals.append(deal)
        selectedID = deal.id
        save()
    }

    func delete(_ id: UUID) {
        deals.removeAll { $0.id == id }
        if selectedID == id { selectedID = nil }
        save()
    }

    func touch(_ id: UUID) {
        guard let index = deals.firstIndex(where: { $0.id == id }) else { return }
        deals[index].lastTouch = Date()
        save()
    }

    private func save() {
        JSONStore.save(deals, to: "business-deals")
    }

    // MARK: Asking

    func draftFollowUp(_ deal: Deal) {
        let system = """
        You are Conner, the business agent inside 11am, writing a short follow-up email as the user, in their voice. \
        Move the deal one step forward without being pushy. Write only the email body.

        \(voice.instructions)
        """
        let prompt = """
        Deal: \(deal.name) with \(deal.company)
        Stage: \(deal.stage.title)
        Value: \(Money.format(deal.value))
        Last contact: \(deal.lastTouch.formatted(.relative(presentation: .named)))
        Next step we planned: \(deal.nextStep.isEmpty ? "none set" : deal.nextStep)
        Notes: \(deal.notes.isEmpty ? "none" : deal.notes)
        """
        drafts[deal.id] = brain.run(BrainRequest(system: system, prompt: prompt, weight: .quick))
    }

    func adviseNextStep(_ deal: Deal) {
        let system = """
        You are Conner, the business agent inside 11am. Suggest the single best next step to move this deal forward, \
        in one or two sentences, then one risk to watch. Be concrete. No preamble.
        """
        let prompt = "Deal: \(deal.name) with \(deal.company). Stage: \(deal.stage.title). Value: \(Money.format(deal.value)). Last touch: \(deal.lastTouch.formatted(.relative(presentation: .named))). Planned next step: \(deal.nextStep). Notes: \(deal.notes)"
        advice[deal.id] = brain.run(BrainRequest(system: system, prompt: prompt, weight: .quick))
    }

    /// Sending stays with your own Mail app.
    func openInMail(_ deal: Deal, body: String) {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = deal.contact
        components.queryItems = [URLQueryItem(name: "subject", value: deal.name), URLQueryItem(name: "body", value: body)]
        if let url = components.url { NSWorkspace.shared.open(url) }
        touch(deal.id)
    }
}

/// The same small world as the sample inbox and books: Acme, Northwind, a studio intro.
enum BusinessSamples {
    static func deals() -> [Deal] {
        let now = Date()
        func ago(_ days: Double) -> Date { now.addingTimeInterval(-days * 86_400) }
        return [
            Deal(name: "Acme rollout", company: "Acme", contact: "tom@acme.co", value: 38_400, stage: .proposal, nextStep: "Send the deck and one-pager by Friday", lastTouch: ago(1), notes: "Needs SSO before rollout. 40 seats. Tom is the champion, the CFO signs."),
            Deal(name: "Northwind pilot", company: "Northwind", contact: "priya@northwind.vc", value: 12_000, stage: .talking, nextStep: "Confirm how much of the round is committed", lastTouch: ago(2)),
            Deal(name: "Studio Wong partnership", company: "Studio Wong", contact: "jess@studiowong.com", value: 6_000, stage: .lead, nextStep: "20 minute intro call next week", lastTouch: ago(3)),
            Deal(name: "Fitzroy Legal", company: "Fitzroy Legal", contact: "ops@fitzroylegal.com.au", value: 9_600, stage: .talking, nextStep: "Follow up on security questionnaire", lastTouch: ago(11), notes: "Went quiet after the demo."),
            Deal(name: "Harbour Health", company: "Harbour Health", contact: "it@harbourhealth.org", value: 24_000, stage: .lead, nextStep: "Find the right person in IT", lastTouch: ago(16)),
            Deal(name: "Lumen Coffee", company: "Lumen", contact: "sam@lumen.coffee", value: 3_600, stage: .won, nextStep: "Onboarding call", lastTouch: ago(5)),
            Deal(name: "Blue Gum Studio", company: "Blue Gum", contact: "hi@bluegum.studio", value: 4_800, stage: .lost, nextStep: "", lastTouch: ago(30), notes: "Chose to stay on their current tools for now."),
        ]
    }
}
