import Foundation

// Checks Conner's contacts: addresses and companies from mail, the people you actually write to,
// what's happened with a deal, the forecast, quiet deals and proposals.

var failures = 0
func check(_ condition: Bool, _ name: String) {
    print(condition ? "PASS" : "FAIL", name)
    if !condition { failures += 1 }
}

var cal = Calendar(identifier: .gregorian)
cal.timeZone = TimeZone(identifier: "Australia/Sydney")!
func day(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 9) -> Date { cal.date(from: DateComponents(year: y, month: m, day: d, hour: h))! }
let now = day(2026, 11, 5, 10)

// MARK: Addresses and companies

check(CRMMatch.address("Tom Baker <TOM@Acme.co>") == "tom@acme.co", "An address from a display name, in lower case")
check(CRMMatch.displayName("Tom Baker <tom@acme.co>") == "Tom Baker" && CRMMatch.displayName("jess.wong@studiowong.com") == "Jess Wong", "Names from display names and addresses")
check(CRMMatch.domain(of: "tom@acme.co") == "acme.co" && CRMMatch.domain(of: "someone@gmail.com") == nil && CRMMatch.domain(of: "x@bigpond.com") == nil, "Company domains, not free mail")
check(CRMMatch.organisationName(fromDomain: "acme.co") == "Acme", "acme.co → Acme")
check(CRMMatch.organisationName(fromDomain: "fitzroylegal.com.au") == "Fitzroylegal", "fitzroylegal.com.au → Fitzroylegal")
check(CRMMatch.organisationName(fromDomain: "mail.harbourhealth.org") == "Harbourhealth", "Mail subdomains are skipped")
check(CRMMatch.organisationName(fromDomain: "lumen.coffee") == "Lumen", "lumen.coffee → Lumen")
let acme = CRMOrganisation(name: "Acme", domain: "acme.co")
check(CRMMatch.belongs("ops@ACME.co", to: acme, people: []) && CRMMatch.belongs("a@eu.acme.co", to: acme, people: []) && !CRMMatch.belongs("a@notacme.co", to: acme, people: []), "Addresses that belong to a company")

// MARK: The people you actually write to

let mail: [CRMMail] = [
    CRMMail(id: "1", from: "tom@acme.co", fromName: "Tom Baker", to: ["me@mine.com"], subject: "Deck for Friday", snippet: "Can you send the deck?", date: day(2026, 11, 3), outgoing: false),
    CRMMail(id: "2", from: "me@mine.com", fromName: "Me", to: ["Tom Baker <tom@acme.co>", "Rita Chen <rita@acme.co>"], subject: "Re: Deck for Friday", snippet: "I'll send it by Friday.", date: day(2026, 11, 4), outgoing: true),
    CRMMail(id: "3", from: "news@saas-weekly.com", fromName: "SaaS Weekly", to: ["me@mine.com"], subject: "This week", snippet: "", date: day(2026, 11, 4), outgoing: false),
    CRMMail(id: "4", from: "priya@northwind.vc", fromName: "Priya Shah", to: ["me@mine.com"], subject: "Venue options", snippet: "", date: day(2026, 11, 2), outgoing: false),
    CRMMail(id: "5", from: "me@mine.com", fromName: "Me", to: ["mum@gmail.com"], subject: "Sunday", snippet: "", date: day(2026, 11, 1), outgoing: true),
]
let existingTom = CRMPerson(name: "Thomas Baker", email: "TOM@acme.co", title: "Head of ops")
let built = CRMDirectory.update(people: [existingTom], organisations: [], mail: mail, wroteTo: ["priya@northwind.vc": 2, "noreply@x.com": 1], me: ["me@mine.com"])
let emails = Set(built.people.map(\.email))
check(emails == ["tom@acme.co", "rita@acme.co", "priya@northwind.vc", "mum@gmail.com"], "People you wrote to, not newsletters or no-reply: \(emails.sorted())")
check(built.added == 3, "Three new people")
check(built.people.first { $0.email == "tom@acme.co" }?.name == "Thomas Baker" && built.people.first { $0.email == "tom@acme.co" }?.title == "Head of ops", "Someone you already have is left as they are")
check(built.people.first { $0.email == "rita@acme.co" }?.name == "Rita Chen", "Names from the To line")
check(Set(built.organisations.map(\.name)) == ["Acme", "Northwind"], "Companies from their domains, not gmail.com")
let acmeID = built.organisations.first { $0.domain == "acme.co" }?.id
check(built.people.first { $0.email == "rita@acme.co" }?.organisationID == acmeID && built.people.first { $0.email == "mum@gmail.com" }?.organisationID == nil, "People are filed under their company")
let again = CRMDirectory.update(people: built.people, organisations: built.organisations, mail: mail, wroteTo: [:], me: ["me@mine.com"])
check(again.added == 0 && again.organisations.count == 2, "Running it again adds nothing")

// MARK: What's happened

let meetings = [
    CRMMeeting(id: "kickoff", title: "Acme kickoff", start: day(2026, 11, 6), attendees: [("Tom", "tom@acme.co"), ("Me", "me@mine.com")]),
    CRMMeeting(id: "dentist", title: "Dentist", start: day(2026, 11, 2), attendees: []),
]
let logged = [CRMActivity(id: "log:1", kind: .logged, date: day(2026, 10, 30), title: "Called Rita about SSO")]
let timeline = CRMTimeline.activities(addresses: ["rita@acme.co"], domain: "acme.co", mail: mail, meetings: meetings, logged: logged)
check(timeline.map(\.id) == ["event:kickoff", "mail:2", "mail:1", "log:1"], "Emails, meetings and calls with the company, newest first: \(timeline.map(\.id))")
check(timeline.first { $0.id == "mail:2" }?.kind == .sent && timeline.first { $0.id == "mail:1" }?.kind == .received, "Sent and received")
check(CRMTimeline.lastTouch(timeline, now: now) == day(2026, 11, 4), "The last touch is the latest that's already happened")
check(CRMTimeline.activities(addresses: ["priya@northwind.vc"], domain: nil, mail: mail, meetings: meetings).map(\.id) == ["mail:4"], "Just one person")

// MARK: Forecast

let forecast = CRMForecast.byMonth([
    (value: 10_000, likelihood: 0.6, close: day(2026, 11, 20)),
    (value: 20_000, likelihood: 0.3, close: day(2026, 12, 15)),
    (value: 5_000, likelihood: 0.1, close: day(2026, 10, 1)),
    (value: 99_000, likelihood: 0.3, close: nil),
], now: now, calendar: cal)
check(forecast.count == 2, "Two months")
check(forecast.first?.total == 15_000 && abs((forecast.first?.weighted ?? 0) - 6_500) < 0.01 && forecast.first?.count == 2, "Overdue deals count in this month")
check(forecast.last?.weighted == 6_000, "Weighted by stage")

// MARK: Quiet deals

check(CRMNudge.isQuiet(stage: "proposal", lastTouch: day(2026, 10, 29), now: now, calendar: cal), "A proposal quiet for a week needs a nudge")
check(!CRMNudge.isQuiet(stage: "lead", lastTouch: day(2026, 10, 29), now: now, calendar: cal), "A lead can wait two weeks")
check(!CRMNudge.isQuiet(stage: "won", lastTouch: day(2026, 1, 1), now: now, calendar: cal), "Won deals never nag")
check(CRMNudge.text(lastTouch: day(2026, 11, 4), now: now, calendar: cal) == "Last touch yesterday" && CRMNudge.text(lastTouch: day(2026, 10, 25), now: now, calendar: cal) == "Quiet for 11 days", "How quiet, in words")

// MARK: Proposals

let template = "# Proposal: [project] for [client]\n\nPrepared for [name], [organisation]\n\n| [Item] | $[0] |\n| **Total (ex GST)** | **$[0]** |"
let filled = CRMProposal.fill(template, project: "Acme rollout", client: "Acme", contact: "Tom Baker", organisation: "Acme", value: 38_400, currency: { "$\(Int($0))" })
check(filled.contains("# Proposal: Acme rollout for Acme") && filled.contains("Prepared for Tom Baker, Acme") && filled.contains("| Acme rollout | $38400 |") && filled.contains("**$38400**"), "A proposal filled from the deal")

// MARK: Saved by older versions

let old = try? JSONDecoder().decode(CRMPerson.self, from: Data(#"{"name": "Old", "email": "OLD@X.CO"}"#.utf8))
check(old?.email == "old@x.co" && old?.title == "", "People saved by older versions still load")

print(failures == 0 ? "ALL PASSED" : "\(failures) FAILED")
exit(failures == 0 ? 0 : 1)
