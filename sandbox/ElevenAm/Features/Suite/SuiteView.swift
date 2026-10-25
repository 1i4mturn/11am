import SwiftUI

/// The apps that replace the subscription pile. The agents are how they work, not what you buy.
struct SuiteView: View {
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
        SuiteApp(id: "today", name: "Today", monogram: "le", does: "Calendar, tasks, the brief and the 11am check-in", replaces: "Calendar planners, daily-planning apps", stage: .sandbox),
        SuiteApp(id: "files", name: "Files", monogram: "bn", does: "Search and memory for everything on your Mac", replaces: "Note apps, search tools, clipboard managers", stage: .sandbox),
        SuiteApp(id: "mail", name: "Mail", monogram: "mc", does: "Triage, replies drafted in your voice, people", replaces: "Premium email clients", stage: .sandbox),
        SuiteApp(id: "write", name: "Write", monogram: "wm", does: "Documents, rewrite anywhere, your voice", replaces: "Writing assistants, doc subscriptions", stage: .sandbox),
        SuiteApp(id: "research", name: "Research", monogram: "jm", does: "A WebKit browser with cited research", replaces: "Answer engines, read-later apps", stage: .next),
        SuiteApp(id: "money", name: "Money", monogram: "ge", does: "Sheets, runway, receipts", replaces: "Budgeting apps, receipt scanners", stage: .later),
        SuiteApp(id: "business", name: "Business", monogram: "cr", does: "Pipeline, strategy, decks", replaces: "Solo CRM plans, deck tools", stage: .later),
        SuiteApp(id: "design", name: "Design", monogram: "rt", does: "Brand kit, quick graphics, image tools", replaces: "Design-tool subscriptions for everyday graphics", stage: .later),
        SuiteApp(id: "video", name: "Video", monogram: "co", does: "Record, edit by transcript, captions", replaces: "Screen recorders, transcript editors", stage: .later),
        SuiteApp(id: "learn", name: "Learn", monogram: "hr", does: "Paths, flashcards, languages", replaces: "Flashcard and language-app subscriptions", stage: .later),
        SuiteApp(id: "build", name: "Build", monogram: "jo", does: "Terminal, automations, tune any app", replaces: "Automation subscriptions", stage: .later),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                SectionHeader(title: "the suite", subtitle: "Software you own, on the Mac you have.")

                Text("One set of apps for the work a founder actually does. Most thinking happens on your Mac, heavy work happens overnight, and the cloud is optional, so the bill doesn't keep growing.")
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
                    }
                }
            }
            .padding(24)
        }
        .scrollContentBackground(.hidden)
    }
}
