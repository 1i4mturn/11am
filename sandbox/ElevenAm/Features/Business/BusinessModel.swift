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
    /// When you expect it to close, for the forecast.
    var closeDate: Date?
    var organisationID: UUID?
    var personID: UUID?
    /// Calls and notes you've logged by hand.
    var logged: [CRMActivity] = []

    /// Open deals with no touch in a week deserve a nudge.
    var isStale: Bool { stage.isOpen && Date().timeIntervalSince(lastTouch) > 7 * 86_400 }
}

extension Deal {
    /// Deals saved before contacts and close dates still load.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? "Deal"
        company = try c.decodeIfPresent(String.self, forKey: .company) ?? ""
        contact = try c.decodeIfPresent(String.self, forKey: .contact) ?? ""
        value = try c.decodeIfPresent(Double.self, forKey: .value) ?? 0
        stage = (try? c.decodeIfPresent(DealStage.self, forKey: .stage)) ?? .lead
        nextStep = try c.decodeIfPresent(String.self, forKey: .nextStep) ?? ""
        lastTouch = try c.decodeIfPresent(Date.self, forKey: .lastTouch) ?? Date()
        notes = try c.decodeIfPresent(String.self, forKey: .notes) ?? ""
        closeDate = try c.decodeIfPresent(Date.self, forKey: .closeDate)
        organisationID = try c.decodeIfPresent(UUID.self, forKey: .organisationID)
        personID = try c.decodeIfPresent(UUID.self, forKey: .personID)
        logged = (try? c.decodeIfPresent([CRMActivity].self, forKey: .logged)) ?? []
    }
}

/// The parts of Business.
enum BusinessTab: String, CaseIterable, Identifiable {
    case pipeline, deals, people, companies, forecast

    var id: String { rawValue }

    var title: String {
        switch self {
        case .pipeline: return "Pipeline"
        case .deals: return "Deals"
        case .people: return "People"
        case .companies: return "Companies"
        case .forecast: return "Forecast"
        }
    }
}

/// Conner in the sandbox: a pipeline you drag between stages, with follow-ups drafted in your voice.
@MainActor
final class BusinessModel: ObservableObject {
    @Published private(set) var deals: [Deal] = []
    @Published var selectedID: UUID?
    @Published private(set) var drafts: [UUID: BrainRun] = [:]
    @Published private(set) var advice: [UUID: BrainRun] = [:]
    @Published var tab: BusinessTab { didSet { UserDefaults.standard.set(tab.rawValue, forKey: "business.tab") } }
    /// One person and one company everywhere: found from your mail, kept here.
    @Published private(set) var people: [CRMPerson] = []
    @Published private(set) var organisations: [CRMOrganisation] = []
    @Published var selectedPersonID: UUID?
    @Published var selectedOrganisationID: UUID?
    @Published var notice: String?

    private let brain: Brain
    private let voice: VoiceProfile
    /// Mail you've sent from 11am, kept so what happened with a deal includes it.
    private var sent: [CRMSentMail] = []

    /// Where activity comes from, and where proposals and tasks go.
    weak var mail: MailModel?
    weak var calendar: CalendarModel?
    weak var write: WriteModel?
    weak var tasks: TasksModel?
    /// Opens another app (Write for a proposal, Mail for an email).
    var onOpen: ((AppSection) -> Void)?

    init(brain: Brain, voice: VoiceProfile) {
        self.brain = brain
        self.voice = voice
        tab = UserDefaults.standard.string(forKey: "business.tab").flatMap(BusinessTab.init(rawValue:)) ?? .pipeline
        deals = JSONStore.load([Deal].self, from: "business-deals") ?? BusinessSamples.deals()
        let savedPeople = JSONStore.load([CRMPerson].self, from: "business-people")
        let savedOrganisations = JSONStore.load([CRMOrganisation].self, from: "business-organisations")
        people = savedPeople ?? BusinessSamples.people()
        organisations = savedOrganisations ?? BusinessSamples.organisations()
        sent = JSONStore.load([CRMSentMail].self, from: "business-sent") ?? []
        linkSampleDeals()
        // Samples are saved straight away, so deals keep pointing at the same people and companies next time.
        if savedPeople == nil || savedOrganisations == nil { saveContacts() }
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

    var staleCount: Int { quietDeals.count }

    // MARK: Editing

    func move(_ id: UUID, to stage: DealStage) {
        guard let index = deals.firstIndex(where: { $0.id == id }), deals[index].stage != stage else { return }
        deals[index].stage = stage
        deals[index].lastTouch = Date()
        save()
    }

    func update(_ deal: Deal) {
        guard let index = deals.firstIndex(where: { $0.id == deal.id }) else { return }
        // The detail edits a copy: keep calls logged and touches made since it was opened.
        var merged = deal
        merged.logged = deals[index].logged
        merged.lastTouch = max(deal.lastTouch, deals[index].lastTouch)
        deals[index] = merged
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

    private func saveContacts() {
        JSONStore.save(people, to: "business-people")
        JSONStore.save(organisations, to: "business-organisations")
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
        func ahead(_ days: Double) -> Date { now.addingTimeInterval(days * 86_400) }
        return [
            Deal(name: "Acme rollout", company: "Acme", contact: "tom@acme.co", value: 38_400, stage: .proposal, nextStep: "Send the deck and one-pager by Friday", lastTouch: ago(1), notes: "Needs SSO before rollout. 40 seats. Tom is the champion, the CFO signs.", closeDate: ahead(24)),
            Deal(name: "Northwind pilot", company: "Northwind", contact: "priya@northwind.vc", value: 12_000, stage: .talking, nextStep: "Confirm how much of the round is committed", lastTouch: ago(2), closeDate: ahead(40)),
            Deal(name: "Studio Wong partnership", company: "Studio Wong", contact: "jess@studiowong.com", value: 6_000, stage: .lead, nextStep: "20 minute intro call next week", lastTouch: ago(3), closeDate: ahead(70)),
            Deal(name: "Fitzroy Legal", company: "Fitzroy Legal", contact: "ops@fitzroylegal.com.au", value: 9_600, stage: .talking, nextStep: "Follow up on security questionnaire", lastTouch: ago(11), notes: "Went quiet after the demo.", closeDate: ahead(30)),
            Deal(name: "Harbour Health", company: "Harbour Health", contact: "it@harbourhealth.org", value: 24_000, stage: .lead, nextStep: "Find the right person in IT", lastTouch: ago(16), closeDate: ahead(95)),
            Deal(name: "Lumen Coffee", company: "Lumen", contact: "sam@lumen.coffee", value: 3_600, stage: .won, nextStep: "Onboarding call", lastTouch: ago(5)),
            Deal(name: "Blue Gum Studio", company: "Blue Gum", contact: "hi@bluegum.studio", value: 4_800, stage: .lost, nextStep: "", lastTouch: ago(30), notes: "Chose to stay on their current tools for now."),
        ]
    }

    static func organisations() -> [CRMOrganisation] {
        [
            CRMOrganisation(name: "Acme", domain: "acme.co", notes: "40 seats. Needs SSO before rollout."),
            CRMOrganisation(name: "Northwind", domain: "northwind.vc", notes: "Seed fund. Priya leads."),
            CRMOrganisation(name: "Studio Wong", domain: "studiowong.com"),
            CRMOrganisation(name: "Fitzroy Legal", domain: "fitzroylegal.com.au"),
            CRMOrganisation(name: "Harbour Health", domain: "harbourhealth.org"),
            CRMOrganisation(name: "Lumen Coffee", domain: "lumen.coffee"),
            CRMOrganisation(name: "Blue Gum Studio", domain: "bluegum.studio"),
        ]
    }

    static func people() -> [CRMPerson] {
        [
            CRMPerson(name: "Tom Becker", email: "tom@acme.co", title: "Head of operations"),
            CRMPerson(name: "Rita Chen", email: "rita@acme.co", title: "CFO"),
            CRMPerson(name: "Priya Shah", email: "priya@northwind.vc", title: "Partner"),
            CRMPerson(name: "Jess Wong", email: "jess@studiowong.com", title: "Founder"),
            CRMPerson(name: "Dana Fitz", email: "ops@fitzroylegal.com.au", title: "Operations"),
            CRMPerson(name: "Sam Lee", email: "sam@lumen.coffee", title: "Owner"),
        ]
    }
}

/// Mail sent from 11am, kept for what's happened with each deal.
struct CRMSentMail: Codable, Equatable {
    var id: String
    var to: [String]
    var subject: String
    var snippet: String
    var date: Date
}

// MARK: Contacts and what's happened

extension BusinessModel {
    private var myAddresses: Set<String> { Set((mail?.accounts ?? []).map { $0.address.lowercased() }) }

    /// The mail 11am knows about, as Conner sees it.
    var crmMail: [CRMMail] {
        let mine = myAddresses
        var result: [CRMMail] = (mail?.messages ?? []).map { message in
            CRMMail(id: message.id, from: message.fromAddress, fromName: message.fromName, to: message.to, subject: message.subject,
                    snippet: message.snippet, date: message.date, outgoing: mine.contains(message.fromAddress.lowercased()))
        }
        result += sent.map { CRMMail(id: $0.id, from: "me", fromName: "", to: $0.to, subject: $0.subject, snippet: $0.snippet, date: $0.date, outgoing: true) }
        return result
    }

    var crmMeetings: [CRMMeeting] {
        (calendar?.events ?? []).map { event in
            CRMMeeting(id: event.id, title: event.title, start: event.start, attendees: event.attendees.map { (name: $0.name, email: $0.email) })
        }
    }

    func findPerson(_ id: UUID?) -> CRMPerson? { id.flatMap { id in people.first { $0.id == id } } }
    func findOrganisation(_ id: UUID?) -> CRMOrganisation? { id.flatMap { id in organisations.first { $0.id == id } } }
    func people(at organisation: UUID) -> [CRMPerson] { people.filter { $0.organisationID == organisation }.sorted { $0.name < $1.name } }
    func deals(for organisation: UUID) -> [Deal] { deals.filter { $0.organisationID == organisation } }
    func deals(with person: UUID) -> [Deal] { deals.filter { $0.personID == person } }

    /// Finds the people you write to in your mail, and their companies.
    func refreshContacts() {
        let result = CRMDirectory.update(people: people, organisations: organisations, mail: crmMail,
                                         wroteTo: mail?.learner.wroteTo ?? [:], me: myAddresses)
        if result.added > 0 {
            people = result.people
            organisations = result.organisations
            notice = "Conner found \(result.added) \(result.added == 1 ? "person" : "people") you write to."
        }
        linkDeals()
        saveContacts()
    }

    /// People get their company from their address, and deals get their person and company from the contact.
    func linkDeals() {
        for index in people.indices where people[index].organisationID == nil {
            if let domain = CRMMatch.domain(of: people[index].email), let organisation = organisations.first(where: { $0.domain == domain }) {
                people[index].organisationID = organisation.id
            }
        }
        var changed = false
        let personIDs = Set(people.map(\.id))
        let organisationIDs = Set(organisations.map(\.id))
        for index in deals.indices {
            // A link to someone or something that's gone is found again.
            if let id = deals[index].personID, !personIDs.contains(id) { deals[index].personID = nil; changed = true }
            if let id = deals[index].organisationID, !organisationIDs.contains(id) { deals[index].organisationID = nil; changed = true }
            let address = CRMMatch.address(deals[index].contact)
            if deals[index].personID == nil, let match = people.first(where: { $0.email == address }) {
                deals[index].personID = match.id
                changed = true
            }
            if deals[index].organisationID == nil {
                let fromPerson = findPerson(deals[index].personID)?.organisationID
                let fromDomain = CRMMatch.domain(of: address).flatMap { domain in organisations.first { $0.domain == domain }?.id }
                let fromName = organisations.first { $0.name.caseInsensitiveCompare(deals[index].company) == .orderedSame }?.id
                if let organisation = fromPerson ?? fromDomain ?? fromName {
                    deals[index].organisationID = organisation
                    changed = true
                }
            }
        }
        if changed { save() }
    }

    fileprivate func linkSampleDeals() {
        linkDeals()
    }

    private func addresses(for deal: Deal) -> (Set<String>, String?) {
        var addresses: Set<String> = []
        let contact = CRMMatch.address(deal.contact)
        if contact.contains("@") { addresses.insert(contact) }
        if let match = findPerson(deal.personID) { addresses.insert(match.email) }
        let organisation = findOrganisation(deal.organisationID)
        if let organisation {
            for member in people where member.organisationID == organisation.id { addresses.insert(member.email) }
        }
        return (addresses, organisation?.domain ?? CRMMatch.domain(of: contact))
    }

    /// Emails, meetings and calls for a deal, newest first.
    func activities(for deal: Deal) -> [CRMActivity] {
        let (addresses, domain) = self.addresses(for: deal)
        return CRMTimeline.activities(addresses: addresses, domain: domain, mail: crmMail, meetings: crmMeetings, logged: deal.logged)
    }

    func activities(forOrganisation organisation: CRMOrganisation) -> [CRMActivity] {
        let addresses = Set(people(at: organisation.id).map(\.email))
        let logged = deals(for: organisation.id).flatMap(\.logged)
        return CRMTimeline.activities(addresses: addresses, domain: organisation.domain, mail: crmMail, meetings: crmMeetings, logged: logged)
    }

    func activities(forPerson person: CRMPerson) -> [CRMActivity] {
        CRMTimeline.activities(addresses: [person.email], domain: nil, mail: crmMail, meetings: crmMeetings)
    }

    /// The latest of what you set by hand and what's happened in mail and meetings.
    func lastTouch(_ deal: Deal) -> Date {
        max(deal.lastTouch, CRMTimeline.lastTouch(activities(for: deal), now: Date()) ?? .distantPast)
    }

    func isQuiet(_ deal: Deal) -> Bool {
        CRMNudge.isQuiet(stage: deal.stage.rawValue, lastTouch: lastTouch(deal), now: Date(), calendar: .current)
    }

    var quietDeals: [Deal] { deals.filter { isQuiet($0) } }

    var forecast: [CRMForecast.Month] {
        CRMForecast.byMonth(deals.filter { $0.stage.isOpen }.map { (value: $0.value, likelihood: $0.stage.likelihood, close: $0.closeDate) },
                            now: Date(), calendar: .current)
    }

    // MARK: Doing things

    func noteSent(to recipients: [String], subject: String, body: String) {
        sent.append(CRMSentMail(id: UUID().uuidString, to: recipients, subject: subject, snippet: String(body.prefix(200)), date: Date()))
        if sent.count > 500 { sent.removeFirst(sent.count - 500) }
        JSONStore.save(sent, to: "business-sent")
        refreshContacts()
        objectWillChange.send()
    }

    /// A call or a note, by hand.
    func log(_ text: String, on dealID: UUID, kind: CRMActivity.Kind = .logged) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let index = deals.firstIndex(where: { $0.id == dealID }) else { return }
        deals[index].logged.append(CRMActivity(id: "log:\(UUID().uuidString)", kind: kind, date: Date(), title: trimmed))
        deals[index].lastTouch = Date()
        save()
    }

    /// William starts a proposal in Write from the deal: the client, the contact and the price filled in.
    func writeProposal(_ deal: Deal) {
        guard let write, let template = DocTemplate.all.first(where: { $0.id == "proposal" }) else { return }
        let contact = findPerson(deal.personID)?.name ?? CRMMatch.displayName(deal.contact)
        let client = findOrganisation(deal.organisationID)?.name ?? deal.company
        let text = CRMProposal.fill(template.markdown, project: deal.name, client: client, contact: contact, organisation: client,
                                    value: deal.value, currency: { Money.format($0) })
        write.addDocument(text: text)
        log("Started a proposal in Write", on: deal.id, kind: .note)
        notice = "The proposal is in Write, with \(client) and the price filled in."
        onOpen?(.write)
    }

    /// The next step goes to Leo's Tasks, dated the way you wrote it ("by Friday").
    func nextStepAsTask(_ deal: Deal) {
        guard let tasks, !deal.nextStep.isEmpty else { return }
        let origin = TaskOrigin(kind: .agent, monogram: "cr", label: "Deal · \(deal.name)", reference: deal.id.uuidString, quote: deal.nextStep)
        if let task = tasks.add(deal.nextStep, in: .inbox, origin: origin, select: false) {
            notice = "Added to Tasks: \(task.title)" + (tasks.dueText(task).map { ", \($0.lowercased())" } ?? "") + "."
        }
    }

    // MARK: People and companies

    func updatePerson(_ person: CRMPerson) {
        guard let index = people.firstIndex(where: { $0.id == person.id }) else { return }
        people[index] = person
        saveContacts()
    }

    func updateOrganisation(_ organisation: CRMOrganisation) {
        guard let index = organisations.firstIndex(where: { $0.id == organisation.id }) else { return }
        organisations[index] = organisation
        saveContacts()
    }

    func addPerson() {
        let person = CRMPerson(name: "New person", email: "", organisationID: selectedOrganisationID)
        people.append(person)
        selectedPersonID = person.id
        saveContacts()
    }

    func addOrganisation() {
        let organisation = CRMOrganisation(name: "New company")
        organisations.append(organisation)
        selectedOrganisationID = organisation.id
        saveContacts()
    }

    func deletePerson(_ id: UUID) {
        people.removeAll { $0.id == id }
        for index in deals.indices where deals[index].personID == id { deals[index].personID = nil }
        if selectedPersonID == id { selectedPersonID = nil }
        saveContacts()
        save()
    }

    func deleteOrganisation(_ id: UUID) {
        organisations.removeAll { $0.id == id }
        for index in people.indices where people[index].organisationID == id { people[index].organisationID = nil }
        for index in deals.indices where deals[index].organisationID == id { deals[index].organisationID = nil }
        if selectedOrganisationID == id { selectedOrganisationID = nil }
        saveContacts()
        save()
    }

    func newDeal(for organisation: UUID) {
        guard let company = findOrganisation(organisation) else { return }
        let contact = people(at: organisation).first
        var deal = Deal(name: "\(company.name) deal", company: company.name, contact: contact?.email ?? "", value: 0, stage: .lead, nextStep: "", lastTouch: Date())
        deal.organisationID = organisation
        deal.personID = contact?.id
        deals.append(deal)
        selectedID = deal.id
        tab = .pipeline
        save()
    }
}
