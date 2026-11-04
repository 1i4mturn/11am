import SwiftUI

/// The apps that replace the subscription pile. The agents are how they work, not what you buy.
struct SuiteView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var theme: Theme
    @Environment(\.colorScheme) private var scheme

    struct SuiteApp: Identifiable {
        enum Stage: String { case sandbox = "In this sandbox", next = "Next", later = "Later" }
        let id: String
        let name: String
        let monogram: String
        let does: String
        let replaces: String
        let stage: Stage
    }

    private let apps: [SuiteApp] = [
        SuiteApp(id: "today", name: "Today", monogram: "le", does: "The brief, today's timeline and the 11am check-in", replaces: "Daily-planning apps", stage: .sandbox),
        SuiteApp(id: "calendar", name: "Calendar", monogram: "le", does: "Every calendar in one week, plain-words booking, free time and meeting prep", replaces: "Calendar apps and scheduling-link subscriptions", stage: .sandbox),
        SuiteApp(id: "notes", name: "Notes", monogram: "bn", does: "Folders, tags, linked notes, a daily note and answers from all of it", replaces: "Apple Notes, Notion pages, note apps", stage: .sandbox),
        SuiteApp(id: "files", name: "Files", monogram: "bn", does: "Search and memory for everything on your Mac", replaces: "Note apps, search tools, clipboard managers", stage: .sandbox),
        SuiteApp(id: "mail", name: "Mail", monogram: "mc", does: "Triage, replies drafted in your voice, people", replaces: "Premium email clients", stage: .sandbox),
        SuiteApp(id: "write", name: "Write", monogram: "wm", does: "Formatted documents, templates, versions, Word and PDF in and out, your voice", replaces: "Google Docs, Word, writing assistants", stage: .sandbox),
        SuiteApp(id: "pdf", name: "PDF", monogram: "bn", does: "Read, highlight, sign, fill in, reorder pages, compress, protect and truly redact", replaces: "Acrobat, Preview for PDFs", stage: .sandbox),
        SuiteApp(id: "research", name: "Research", monogram: "jm", does: "A WebKit browser with cited research", replaces: "Answer engines, read-later apps", stage: .sandbox),
        SuiteApp(id: "money", name: "Money", monogram: "ge", does: "Sheets, runway, receipts", replaces: "Budgeting apps, receipt scanners", stage: .sandbox),
        SuiteApp(id: "sheets", name: "Sheets", monogram: "ge", does: "Workbooks with live formulas, charts, summaries and George writing the formulas", replaces: "Excel, Google Sheets, Numbers", stage: .sandbox),
        SuiteApp(id: "business", name: "Business", monogram: "cr", does: "Pipeline, strategy, decks", replaces: "Solo CRM plans, deck tools", stage: .sandbox),
        SuiteApp(id: "decks", name: "Decks", monogram: "cr", does: "Slides from an outline or a document, themes, presenter view, PDF and PowerPoint", replaces: "Google Slides, Keynote, Canva presentations", stage: .sandbox),
        SuiteApp(id: "design", name: "Design", monogram: "rt", does: "A canvas for every size, templates, brand kit, magic resize, image tools", replaces: "Canva and design-tool subscriptions", stage: .sandbox),
        SuiteApp(id: "photo", name: "Photo", monogram: "rt", does: "Grade, crop, straighten, clean up, cut out", replaces: "Photo-editor subscriptions for everyday edits", stage: .sandbox),
        SuiteApp(id: "video", name: "Video", monogram: "co", does: "Timeline, trims, colour, voice clean-up, pauses and transcript cuts, music that ducks, titles and captions", replaces: "Video-editor and transcript-editor subscriptions", stage: .sandbox),
        SuiteApp(id: "audio", name: "Audio", monogram: "co", does: "Record the mic or the Mac, multitrack edits, studio sound, silences and ums removed, loudness, chapters", replaces: "Audacity, podcast-editing subscriptions", stage: .sandbox),
        SuiteApp(id: "learn", name: "Learn", monogram: "hr", does: "Paths, flashcards, languages", replaces: "Flashcard and language-app subscriptions", stage: .sandbox),
        SuiteApp(id: "build", name: "Build", monogram: "jo", does: "A real terminal with tabs and splits, scripts in four languages, automations with triggers and steps, tune any app", replaces: "Terminal, Script Editor, Notion automations, automation subscriptions", stage: .sandbox),
        SuiteApp(id: "iphone", name: "iPhone", monogram: "le", does: "Energy from Apple Health, scan and capture to your Mac, your brief and Ask on the go", replaces: "Health and habit apps, scanner apps", stage: .sandbox),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                SectionHeader(title: "the suite", subtitle: "Software you own, on the Mac you have.")

                Text("One set of apps for the work a founder actually does. Most thinking happens on your Mac, heavy work happens overnight, and the cloud is optional, so the bill doesn't keep growing. All eleven have a first baseline in this sandbox.")
                    .font(theme.display(20))
                    .foregroundStyle(theme.inkSecondary(scheme))
                    .fixedSize(horizontal: false, vertical: true)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 14)], spacing: 14) {
                    ForEach(Array(apps.enumerated()), id: \.element.id) { index, app in
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Monogram(text: app.monogram, size: 32, inverted: app.stage == .sandbox)
                                Spacer()
                                Chip(text: app.stage.rawValue, filled: app.stage == .sandbox)
                            }
                            Text(app.name)
                                .font(theme.display(24))
                                .foregroundStyle(theme.ink(scheme))
                            Text(app.does)
                                .font(.system(size: 12.5))
                                .foregroundStyle(theme.inkSecondary(scheme))
                                .fixedSize(horizontal: false, vertical: true)
                            Text("Instead of: \(app.replaces)")
                                .font(.system(size: 11.5))
                                .foregroundStyle(theme.inkTertiary(scheme))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity, minHeight: 170, alignment: .topLeading)
                        .vellum(level: 3, radius: max(theme.radius - 4, 8))
                        .hoverLift()
                        .entrance(index)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if let section = AppSection(rawValue: app.id) {
                                model.go(to: section)
                            } else if app.id == "iphone" {
                                model.go(to: .today)
                                model.phone.showsPairing = true
                            }
                        }
                        .help("Open \(app.name)")
                    }
                }
            }
            .padding(24)
        }
        .scrollContentBackground(.hidden)
    }
}
