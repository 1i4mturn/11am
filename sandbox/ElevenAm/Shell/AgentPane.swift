import SwiftUI

/// The quiet assistant beside every app: who's working, a scoped ask, and what the team just did.
struct AgentPane: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var brain: Brain
    @EnvironmentObject private var files: FileIndex
    @Environment(\.colorScheme) private var scheme

    @State private var askText = ""
    @State private var run: BrainRun?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Monogram(text: agent.monogram, size: 32, inverted: true)
                    .id(agent.monogram)
                    .transition(.scale(scale: 0.8).combined(with: .opacity))
                VStack(alignment: .leading, spacing: 1) {
                    Text(agent.name)
                        .font(theme.display(18))
                        .foregroundStyle(theme.ink(scheme))
                    Text(agent.role)
                        .font(.system(size: 11.5))
                        .foregroundStyle(theme.inkTertiary(scheme))
                }
            }

            AskField(placeholder: "Ask \(agent.name.lowercased())…", text: $askText) {
                let text = askText.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { return }
                run = brain.run(AskRouter.request(for: text, files: files))
            }

            if let run {
                ScrollView {
                    RunView(run: run)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 260)
            }

            Divider().opacity(0.5)

            SectionLabel(text: "Activity")
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(model.activity) { item in
                        HStack(alignment: .top, spacing: 8) {
                            AgentLogo(code: item.monogram, size: 20, color: theme.inkSecondary(scheme))
                                .offset(y: -3)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.text)
                                    .font(.system(size: 12))
                                    .foregroundStyle(theme.ink(scheme))
                                    .fixedSize(horizontal: false, vertical: true)
                                Text(item.date.formatted(date: .omitted, time: .shortened))
                                    .font(.system(size: 10.5))
                                    .foregroundStyle(theme.inkTertiary(scheme))
                            }
                        }
                        .transition(.rise(-theme.rise))
                    }
                    if model.activity.isEmpty {
                        Text("Nothing yet. The team's work shows up here, with where it ran.")
                            .font(.system(size: 12))
                            .foregroundStyle(theme.inkTertiary(scheme))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .animation(theme.spring, value: model.activity.first?.id)
            }
        }
        .padding(18)
        .animation(theme.spring, value: model.section)
    }

    private var agent: (monogram: String, name: String, role: String) {
        switch model.section {
        case .today, .overnight: return ("le", "Leo", "Chief of staff · plans your day")
        case .calendar: return ("le", "Leo", "Calendar · guards your time")
        case .mail: return ("mc", "Marc", "Mail and people · drafts in your voice")
        case .notes: return ("bn", "Bolton", "Notes and memory · finds what you noted")
        case .write: return ("wm", "William", "Writing and voice · you only review")
        case .files: return ("bn", "Bolton", "Memory and files · finds anything")
        case .pdf: return ("bn", "Bolton", "Documents · reads, signs and fixes PDFs")
        case .research: return ("jm", "James", "Research · sourced, honest answers")
        case .money: return ("ge", "George", "Finance · never invents a number")
        case .sheets: return ("ge", "George", "Numbers · writes formulas, reads your sheets")
        case .business: return ("cr", "Conner", "Business · what's worth building and selling")
        case .decks: return ("cr", "Conner", "Decks · outlines, slides and what to say")
        case .design: return ("rt", "Robert", "Design · a considered look for everything")
        case .photo: return ("rt", "Robert", "Photo · colour, crop and clean-ups")
        case .video: return ("co", "Cole", "Video · cut, colour and clean sound")
        case .learn: return ("hr", "Harris", "Learning · sharper, without homework")
        case .build: return ("jo", "Johnny", "Build · makes the software fit you")
        case .suite: return ("le", "Leo", "Routes your asks to the right app")
        case .lab: return ("rt", "Robert", "Design · keeps the look considered")
        }
    }
}
