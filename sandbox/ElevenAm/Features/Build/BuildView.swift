import SwiftUI

enum BuildTab: String, CaseIterable, Identifiable {
    case terminal, scripts, automations, tune

    var id: String { rawValue }

    var title: String {
        switch self {
        case .terminal: return "Terminal"
        case .scripts: return "Scripts"
        case .automations: return "Automations"
        case .tune: return "Tune 11am"
        }
    }
}

/// Johnny's app: a real terminal, scripts, automations, and tuning 11am itself. Nothing runs without you starting it.
struct BuildView: View {
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var build: BuildModel
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "build", subtitle: "Johnny · terminal, scripts and automations") {
                Picker("", selection: $build.tab) {
                    ForEach(BuildTab.allCases) { tab in Text(tab.title).tag(tab) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }
            Group {
                switch build.tab {
                case .terminal: TerminalPane()
                case .scripts: ScriptsPane()
                case .automations: AutomationsPane()
                case .tune:
                    TunePanel()
                        .frame(maxWidth: 720, alignment: .topLeading)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(24)
    }
}

// MARK: Tune

private struct TunePanel: View {
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var build: BuildModel
    @Environment(\.colorScheme) private var scheme

    private let examples = ["Warmer, and a bit more see-through", "Calmer, less motion", "Rounder corners", "Dark mode with crisper text", "Serif titles"]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    AgentLogo(code: "jo", size: 24)
                    SectionLabel(text: "Tune 11am")
                }
                Text("Say how you'd like 11am to look or feel. Johnny shows exactly what would change before anything does.")
                    .font(.system(size: 12))
                    .foregroundStyle(theme.inkTertiary(scheme))
                    .fixedSize(horizontal: false, vertical: true)
                AskField(placeholder: "Make it warmer and a bit more see-through", text: $build.request) {
                    withAnimation(theme.spring) { build.propose() }
                }
                FlowLayout(spacing: 6) {
                    ForEach(examples, id: \.self) { example in
                        Button(example) {
                            build.request = example
                            withAnimation(theme.spring) { build.propose() }
                        }
                        .buttonStyle(.vellumSecondary)
                    }
                }

                if let run = build.tuneRun {
                    TuneRunView(run: run)
                }
                if let notice = build.tuneNotice {
                    Text(notice).font(.system(size: 12)).foregroundStyle(theme.inkSecondary(scheme))
                }

                if build.proposal != nil {
                    VStack(alignment: .leading, spacing: 8) {
                        SectionLabel(text: "Preview · \(build.proposalRequest)")
                        ForEach(build.proposalChanges) { change in
                            HStack {
                                Text(change.name).font(.system(size: 12.5, weight: .medium))
                                Spacer()
                                Text(change.from).font(.system(size: 12).monospacedDigit()).foregroundStyle(theme.inkTertiary(scheme))
                                Image(systemName: "arrow.right").font(.system(size: 9, weight: .bold)).foregroundStyle(theme.inkTertiary(scheme))
                                Text(change.to).font(.system(size: 12, weight: .semibold).monospacedDigit())
                            }
                            .foregroundStyle(theme.ink(scheme))
                        }
                        HStack(spacing: 8) {
                            Button("Apply") { withAnimation(theme.spring) { build.applyProposal() } }
                                .buttonStyle(.vellumPrimary)
                            Button("Discard") { withAnimation(theme.spring) { build.discardProposal() } }
                                .buttonStyle(.vellumSecondary)
                        }
                    }
                    .padding(14)
                    .background(RoundedRectangle(cornerRadius: max(theme.radius - 4, 8)).fill(theme.raised(scheme)))
                    .overlay(RoundedRectangle(cornerRadius: max(theme.radius - 4, 8)).strokeBorder(theme.edge(scheme), lineWidth: 0.5))
                    .transition(.rise(theme.rise))
                }

                if !build.history.isEmpty {
                    SectionLabel(text: "History")
                    ForEach(build.history) { record in
                        HStack(alignment: .firstTextBaseline) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(record.request).font(.system(size: 12.5)).foregroundStyle(theme.ink(scheme))
                                Text(record.date.formatted(date: .omitted, time: .shortened))
                                    .font(.system(size: 10.5)).foregroundStyle(theme.inkTertiary(scheme))
                            }
                            Spacer()
                            Button("Revert") { withAnimation(theme.spring) { build.revert(record) } }
                                .buttonStyle(.vellumSecondary)
                        }
                        .transition(.rise(-theme.rise))
                    }
                }

                LookMaker()
                    .padding(.top, 6)

                Text("This is Tune-lite: the look and feel. The full version changes what each app shows and does, with the same preview, history and undo.")
                    .font(.system(size: 11))
                    .foregroundStyle(theme.inkTertiary(scheme))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
        }
        .scrollContentBackground(.hidden)
        .vellum(level: 3, radius: max(theme.radius - 2, 8))
        .animation(theme.spring, value: build.proposal != nil)
        .animation(theme.spring, value: build.history.count)
    }
}

private struct TuneRunView: View {
    @EnvironmentObject private var build: BuildModel
    @ObservedObject var run: BrainRun

    var body: some View {
        Group {
            if case .failed(_) = run.status {
                RunView(run: run)
            } else {
                ThinkingLine(text: "Johnny is working out the change…")
            }
        }
        .onChange(of: run.status) { _, status in
            if status == .done { build.adoptBrainProposal(from: run.text) }
        }
    }
}

// MARK: Looks

/// Describe a colour look; Johnny saves it as a file Photo and Video both use.
private struct LookMaker: View {
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var build: BuildModel
    @Environment(\.colorScheme) private var scheme

    private let examples = ["Warm film with soft blacks", "Moody and blue", "Punchy black and white", "Bright and airy for skin"]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(text: "Make a colour look")
            Text("Describe a look for Photo and Video. It's saved as a small file you can reuse, share or tweak.")
                .font(.system(size: 12))
                .foregroundStyle(theme.inkTertiary(scheme))
                .fixedSize(horizontal: false, vertical: true)
            AskField(placeholder: "Golden hour, faded, a little grain", text: $build.lookRequest) {
                withAnimation(theme.spring) { build.makeLook() }
            }
            FlowLayout(spacing: 6) {
                ForEach(examples, id: \.self) { example in
                    Button(example) {
                        build.lookRequest = example
                        withAnimation(theme.spring) { build.makeLook() }
                    }
                    .buttonStyle(.vellumSecondary)
                }
            }
            if let run = build.lookRun {
                LookRunView(run: run)
            }
            if let notice = build.lookNotice {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    if build.madeLook != nil {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(theme.ink(scheme))
                    }
                    Text(notice)
                        .font(.system(size: 12))
                        .foregroundStyle(theme.inkSecondary(scheme))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .transition(.rise(theme.rise))
            }
        }
        .animation(theme.spring, value: build.lookNotice)
    }
}

private struct LookRunView: View {
    @EnvironmentObject private var build: BuildModel
    @ObservedObject var run: BrainRun

    var body: some View {
        Group {
            if case .failed(_) = run.status {
                RunView(run: run)
            } else {
                ThinkingLine(text: "Johnny is mixing the look…")
            }
        }
        .onChange(of: run.status) { _, status in
            if status == .done { build.adoptBrainLook(from: run.text) }
        }
    }
}

// MARK: Terminal
