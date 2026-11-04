import SwiftUI

/// Harris's app: a language course, and flashcards and paths for everything else.
struct LearnView: View {
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var learn: LearnModel
    @EnvironmentObject private var languages: LanguageModel
    @Environment(\.colorScheme) private var scheme
    @AppStorage("learn.tab") private var tab = "languages"

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeader(title: "learn", subtitle: subtitle) {
                HStack(spacing: 10) {
                    Picker("", selection: $tab) {
                        Text("Languages").tag("languages")
                        Text("Cards and paths").tag("cards")
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                    if tab == "cards" { deckMenu }
                }
            }
            if tab == "languages" {
                LanguagePane()
                    .frame(maxHeight: .infinity, alignment: .top)
            } else {
                cards
            }
        }
        .padding(24)
    }

    private var subtitle: String {
        if tab == "languages" {
            guard let language = languages.language else { return "Harris · pick a language to start" }
            return "Harris · \(language.name) · \(languages.dueReviews.count) to review · \(languages.wordsKnown) words known"
        }
        return "Harris · \(learn.dueCount) due · \(learn.learnedCount) learned · \(learn.deck?.cards.count ?? 0) cards"
    }

    private var deckMenu: some View {
                Menu {
                    ForEach(learn.decks) { deck in
                        Button(deck.name) { withAnimation(theme.spring) { learn.select(deck.id) } }
                    }
                    Divider()
                    Button("New deck") { withAnimation(theme.spring) { learn.newDeck(named: "") } }
                } label: {
                    Label(learn.deck?.name ?? "Decks", systemImage: "rectangle.stack")
                }
                .menuStyle(.button)
                .buttonStyle(.borderless)
                .fixedSize()
                .foregroundStyle(theme.inkSecondary(scheme))
    }

    private var cards: some View {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 16) {
                    ReviewArea().frame(minWidth: 380)
                    SidePanel().frame(width: 300)
                }
                ScrollView {
                    VStack(spacing: 16) {
                        ReviewArea().frame(height: 380)
                        SidePanel()
                    }
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
    }
}

/// The card flips over in 3D when you tap it or show the answer.
private struct ReviewArea: View {
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var learn: LearnModel
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(spacing: 16) {
            if let card = learn.current {
                FlipCard(front: card.front, back: card.back, showingBack: learn.showingBack)
                    .id(card.id)
                    .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .move(edge: .leading).combined(with: .opacity)))
                    .onTapGesture { withAnimation(theme.spring) { learn.flip() } }
                if learn.showingBack {
                    HStack(spacing: 8) {
                        ForEach(Grade.allCases) { grade in
                            Button(grade.title) {
                                withAnimation(theme.spring) { learn.grade(grade) }
                            }
                            .buttonStyle(VellumButtonStyle(kind: grade == .good ? .primary : .secondary))
                        }
                    }
                    .transition(.rise(theme.rise))
                } else {
                    Button("Show answer") { withAnimation(theme.spring) { learn.flip() } }
                        .buttonStyle(.vellumPrimary)
                }
                Text("\(learn.queue.count) left in this session")
                    .font(.system(size: 11.5).monospacedDigit())
                    .foregroundStyle(theme.inkTertiary(scheme))
                    .contentTransition(.numericText())
            } else {
                VStack(spacing: 12) {
                    AgentLogo(code: "hr", size: 56, color: theme.inkSecondary(scheme))
                    Text(learn.reviewedToday > 0 ? "Done for now. \(learn.reviewedToday) reviewed." : "Nothing due right now.")
                        .font(theme.display(22))
                        .foregroundStyle(theme.ink(scheme))
                    Text("Cards come back just before you'd forget them.")
                        .font(.system(size: 12.5))
                        .foregroundStyle(theme.inkTertiary(scheme))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(theme.spring, value: learn.queue.first)
        .animation(theme.spring, value: learn.showingBack)
    }
}

private struct FlipCard: View {
    @EnvironmentObject private var theme: Theme
    @Environment(\.colorScheme) private var scheme
    var front: String
    var back: String
    var showingBack: Bool

    var body: some View {
        ZStack {
            face(text: front, label: "Question")
                .opacity(showingBack ? 0 : 1)
            face(text: back, label: "Answer")
                .rotation3DEffect(.degrees(180), axis: (x: 0, y: 1, z: 0))
                .opacity(showingBack ? 1 : 0)
        }
        .rotation3DEffect(.degrees(showingBack ? 180 : 0), axis: (x: 0, y: 1, z: 0), perspective: 0.5)
        .frame(maxWidth: 520, minHeight: 220, maxHeight: 280)
    }

    private func face(text: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(text: label)
            Spacer(minLength: 0)
            Text(text)
                .font(theme.display(label == "Question" ? 28 : 20))
                .foregroundStyle(theme.ink(scheme))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(26)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .vellum(level: 3, radius: theme.radius + 4)
        .background {
            RoundedRectangle(cornerRadius: theme.radius + 4, style: .continuous).fill(theme.raised(scheme))
        }
    }
}

private struct SidePanel: View {
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var learn: LearnModel
    @EnvironmentObject private var brain: Brain
    @Environment(\.colorScheme) private var scheme
    @State private var notes = ""
    @State private var goal = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        AgentLogo(code: "hr", size: 22)
                        SectionLabel(text: "Make cards from your notes")
                    }
                    TextEditor(text: $notes)
                        .font(.system(size: 12.5))
                        .scrollContentBackground(.hidden)
                        .padding(6)
                        .frame(height: 90)
                        .background(RoundedRectangle(cornerRadius: 8).fill(theme.well(scheme)))
                        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(theme.edge(scheme), lineWidth: 0.5))
                        .overlay(alignment: .topLeading) {
                            if notes.isEmpty {
                                Text("Paste notes, an article, a chapter…")
                                    .font(.system(size: 12.5))
                                    .foregroundStyle(theme.inkTertiary(scheme))
                                    .padding(11)
                                    .allowsHitTesting(false)
                            }
                        }
                    Button("Make cards") { learn.makeCards(from: notes) }
                        .buttonStyle(.vellumSecondary)
                        .disabled(brain.isBusy)
                    if let notice = learn.notice {
                        Text(notice).font(.system(size: 11.5)).foregroundStyle(theme.inkSecondary(scheme))
                    }
                    if let run = learn.cardsRun {
                        CardsPreview(run: run)
                    }
                }
                .padding(14)
                .vellum(level: 3, radius: max(theme.radius - 2, 8))

                VStack(alignment: .leading, spacing: 8) {
                    SectionLabel(text: "Learning path")
                    if let path = learn.path {
                        Text(path.goal)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(theme.ink(scheme))
                        ForEach(path.steps) { step in
                            Button {
                                withAnimation(theme.spring) { learn.toggle(step) }
                            } label: {
                                HStack(alignment: .firstTextBaseline, spacing: 8) {
                                    Image(systemName: step.done ? "checkmark.circle.fill" : "circle")
                                        .font(.system(size: 12))
                                    Text(step.title)
                                        .font(.system(size: 12.5))
                                        .strikethrough(step.done)
                                        .multilineTextAlignment(.leading)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                .foregroundStyle(theme.ink(scheme).opacity(step.done ? 0.45 : 1))
                            }
                            .buttonStyle(.plain)
                        }
                        if let run = learn.pathRun {
                            PathPreview(run: run)
                        }
                        Button("Start over") { withAnimation(theme.spring) { learn.clearPath() } }
                            .buttonStyle(.plain)
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(theme.inkTertiary(scheme))
                    } else {
                        AskField(placeholder: "What do you want to get better at?", text: $goal) {
                            learn.makePath(for: goal)
                        }
                        Text("Harris turns a goal into five ten-minute sessions.")
                            .font(.system(size: 11.5))
                            .foregroundStyle(theme.inkTertiary(scheme))
                    }
                }
                .padding(14)
                .vellum(level: 3, radius: max(theme.radius - 2, 8))
            }
        }
        .scrollContentBackground(.hidden)
    }
}

private struct CardsPreview: View {
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var learn: LearnModel
    @Environment(\.colorScheme) private var scheme
    @ObservedObject var run: BrainRun

    var body: some View {
        let cards = LearnModel.parseCards(run.text)
        VStack(alignment: .leading, spacing: 6) {
            if run.status == .done && !cards.isEmpty {
                ForEach(cards) { card in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(card.front).font(.system(size: 12, weight: .semibold))
                        Text(card.back).font(.system(size: 11.5)).foregroundStyle(theme.inkSecondary(scheme))
                    }
                    .foregroundStyle(theme.ink(scheme))
                }
                Button("Add \(cards.count) cards") { withAnimation(theme.spring) { learn.addCards(cards) } }
                    .buttonStyle(.vellumPrimary)
            } else {
                RunView(run: run)
            }
        }
    }
}

private struct PathPreview: View {
    @EnvironmentObject private var learn: LearnModel
    @ObservedObject var run: BrainRun

    var body: some View {
        RunView(run: run)
            .onChange(of: run.status) { _, status in
                if status == .done { learn.adoptPath(from: run.text) }
            }
    }
}
