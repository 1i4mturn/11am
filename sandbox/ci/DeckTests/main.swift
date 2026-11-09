import Foundation

// Checks Conner's decks, finished: charts linked to a range in Sheets (worked out, guessed, refreshed and left alone
// when arranged by hand), rehearsals (per slide, against a target and the last run) and decks saved before either.

var failures = 0
func check(_ condition: Bool, _ name: String) {
    print(condition ? "PASS" : "FAIL", name)
    if !condition { failures += 1 }
}
func same<T: Equatable>(_ actual: T, _ expected: T, _ name: String) {
    if actual == expected {
        print("PASS", name)
    } else {
        print("FAIL", name, "· expected", expected, "· got", actual)
        failures += 1
    }
}

// MARK: A workbook to chart

var workbook = Workbook(name: "Growth", sheets: [GridSheet(name: "Customers"), GridSheet(name: "Notes")])
func set(_ address: String, _ input: String, sheet: Int = 0) {
    guard let cell = CellAddress(address) else { return }
    workbook.sheets[sheet][cell] = GridCell(input: input)
}
set("A1", "Month"); set("B1", "Customers"); set("C1", "Revenue")
for (row, month) in ["Jul", "Aug", "Sep", "Oct"].enumerated() {
    set("A\(row + 2)", month)
    set("B\(row + 2)", ["12", "19", "31", "48"][row])
    set("C\(row + 2)", "=B\(row + 2)*40")
}
set("A6", "Total"); set("B6", "=SUM(B2:B5)"); set("C6", "=SUM(C2:C5)")

let guess = DeckCharts.suggest(workbook, sheet: "Customers")
same(guess?.labels ?? "", "A2:A5", "guess: the month column, under the header, above the total")
same(guess?.values ?? "", "B2:B5", "guess: the first column of numbers")
same(DeckCharts.heading(workbook, sheet: "Customers", values: "B2:B5") ?? "", "Customers", "guess: the header names the chart")
check(DeckCharts.suggest(workbook, sheet: "Notes") == nil, "guess: an empty sheet has nothing to chart")

let link = ChartLink(workbook: "Growth", sheet: "Customers", labels: "A2:A5", values: "C2:C5")
let points = DeckCharts.points(link, in: workbook)
same(points?.map(\.label) ?? [], ["Jul", "Aug", "Sep", "Oct"], "points: labels from the sheet")
same(points?.map(\.value) ?? [], [480, 760, 1240, 1920], "points: values worked out from formulas")
check(DeckCharts.points(ChartLink(workbook: "Growth", sheet: "Gone", labels: "A2:A5", values: "B2:B5"), in: workbook) == nil, "points: a missing sheet is nothing")
check(DeckCharts.points(ChartLink(workbook: "Growth", sheet: "Customers", labels: "A2:A5", values: "B2:B4"), in: workbook) == nil, "points: ranges of different lengths are nothing")
same(DeckCharts.points(ChartLink(workbook: "Growth", sheet: "customers", labels: "a2:a5", values: "b2:b5"), in: workbook)?.count ?? 0, 4, "points: names and ranges in any case")
same(DeckCharts.cells(CellRange("B2:E2")!).map(\.a1), ["B2", "C2", "D2", "E2"], "points: a row works as well as a column")

// MARK: Refreshing a deck

var content = SlideContent()
content.title = "Customers by month"
content.chart = [ChartPoint(label: "Jul", value: 12)]
content.link = ChartLink(workbook: "Growth", sheet: "Customers", labels: "A2:A5", values: "B2:B5")
var deck = SlideDeck(name: "Seed round", theme: .paper, slides: [
    Slide(layout: .title, content: SlideContent(title: "11am"), theme: .paper),
    Slide(layout: .chart, content: content, theme: .paper),
])
let before = deck.slides[1].canvas.layers.count
let now = Date(timeIntervalSince1970: 1_800_000_000)
same(deck.refreshCharts(from: { $0 == "Growth" ? workbook : nil }, now: now), 1, "refresh: the linked chart changes")
same(deck.slides[1].content.chart.map(\.value), [12, 19, 31, 48], "refresh: the sheet's numbers")
check(deck.slides[1].canvas.layers.count > before, "refresh: the slide is laid out again with every bar")
same(deck.slides[1].content.link?.updated, now, "refresh: when it was last brought up to date")
same(deck.refreshCharts(from: { $0 == "Growth" ? workbook : nil }, now: now), 0, "refresh: nothing changes twice")
set("B5", "60")
deck.slides[1].customised = true
let arranged = deck.slides[1].canvas
same(deck.refreshCharts(from: { $0 == "Growth" ? workbook : nil }, now: now), 1, "refresh: a change in the sheet comes through")
same(deck.slides[1].content.chart.last?.value, 60, "refresh: …with the new number")
check(deck.slides[1].canvas == arranged, "refresh: a slide arranged by hand keeps its arrangement")
same(deck.refreshCharts(from: { _ in nil }, now: now), 0, "refresh: a workbook that's gone leaves the chart as it was")

// MARK: Rehearsing

var talk = SlideDeck(name: "Talk", theme: .paper, slides: (1...4).map { number in
    Slide(layout: .bullets, content: SlideContent(title: "Point \(number)"), theme: .paper)
})
talk.slides[3].hidden = true
let ids = talk.slides.map(\.id)
let first = Rehearsal(date: now, times: [ids[0]: 50, ids[1]: 200, ids[2]: 70])
let second = Rehearsal(date: now, times: [ids[0]: 40, ids[1]: 100, ids[2]: 60])
let rows = RehearsalReport.rows(talk, first)
same(rows.count, 3, "rehearsal: hidden slides aren't counted")
same(rows.map(\.title), ["Point 1", "Point 2", "Point 3"], "rehearsal: slides by title")
same(rows.map(\.long), [false, true, false], "rehearsal: the slide that ran long")
same(RehearsalReport.summary(talk, first, targetMinutes: 4), "5:20 for 3 slides, 1:20 over your 4 minutes. Longest: Point 2 (3:20).", "rehearsal: against the target")
same(RehearsalReport.summary(talk, second, previous: first, targetMinutes: 4), "3:20 for 3 slides, 40 seconds under your 4 minutes, 2 minutes faster than last time.", "rehearsal: better than the last run")
same(RehearsalReport.rows(talk, second, previous: first).first?.previous, 50, "rehearsal: each slide's time last run")
same(RehearsalReport.summary(talk, Rehearsal(date: now, times: [ids[0]: 60, ids[1]: 60, ids[2]: 60]), targetMinutes: 3), "3:00 for 3 slides, right on your 3 minutes.", "rehearsal: right on time")
same(RehearsalReport.clock(65), "1:05", "clock: minutes and seconds")
same(RehearsalReport.clock(8), "0:08", "clock: under a minute")
same(RehearsalReport.span(40), "40 seconds", "span: seconds")
same(RehearsalReport.span(120), "2 minutes", "span: whole minutes")

// MARK: Decks saved before

let encoder = JSONEncoder()
encoder.dateEncodingStrategy = .iso8601
let decoder = JSONDecoder()
decoder.dateDecodingStrategy = .iso8601
var plain = SlideDeck(name: "Old", theme: .paper, slides: [Slide(layout: .title, content: SlideContent(title: "Old"), theme: .paper)])
let data = try! encoder.encode(plain)
let text = String(decoding: data, as: UTF8.self)
check(!text.contains("rehearsals") && !text.contains("\"link\""), "old decks: nothing new is written until it's used")
check((try? decoder.decode(SlideDeck.self, from: data)) != nil, "old decks: still open")
plain.rehearsals = [first]
plain.targetMinutes = 7
plain.slides[0].content.link = link
let again = try? decoder.decode(SlideDeck.self, from: encoder.encode(plain))
check(again?.rehearsals?.first?.times.count == 3 && again?.targetMinutes == 7 && again?.slides[0].content.link == link, "new decks: rehearsals, target and links saved")

print(failures == 0 ? "All deck checks passed." : "\(failures) deck checks failed.")
exit(failures == 0 ? 0 : 1)
