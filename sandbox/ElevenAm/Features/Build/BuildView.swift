import SwiftUI

/// Johnny's app: describe a change to 11am and see it before it applies; a terminal that never runs anything on its own.
struct BuildView: View {
    @EnvironmentObject private var theme: Theme
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeader(title: "build", subtitle: "Johnny · makes the software fit you")
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 14) {
                    TunePanel().frame(minWidth: 320)
                    TerminalPanel().frame(minWidth: 360)
                }
                ScrollView {
                    VStack(spacing: 14) {
                        TunePanel()
                        TerminalPanel().frame(height: 420)
                    }
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
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

private struct TerminalPanel: View {
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var build: BuildModel
    @EnvironmentObject private var brain: Brain
    @Environment(\.colorScheme) private var scheme
    @State private var ask = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionLabel(text: "Terminal")
                Spacer()
                if build.isRunning {
                    ProgressView().controlSize(.small)
                    Button("Stop") { build.stop() }.buttonStyle(.vellumSecondary)
                }
                Button("Clear") { build.clearOutput() }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(theme.inkTertiary(scheme))
            }

            AskField(placeholder: "Ask Johnny for a command: \"largest files in Downloads\"", text: $ask) {
                build.suggestCommand(for: ask)
            }
            .disabled(brain.isBusy)
            if let run = build.commandRun {
                SuggestionView(run: run)
            }

            // Output: the one place in 11am that's always dark, like a real terminal.
            ScrollViewReader { proxy in
                ScrollView {
                    Text(build.output.isEmpty ? "Commands run in zsh in your home folder. Nothing runs until you press Run." : build.output)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(Color.white.opacity(build.output.isEmpty ? 0.45 : 0.9))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .padding(12)
                    Color.clear.frame(height: 1).id("end")
                }
                .onChange(of: build.output) { _, _ in proxy.scrollTo("end", anchor: .bottom) }
            }
            .frame(maxHeight: .infinity)
            .background(RoundedRectangle(cornerRadius: max(theme.radius - 4, 8), style: .continuous).fill(Color(white: 0.08)))
            .clipShape(RoundedRectangle(cornerRadius: max(theme.radius - 4, 8), style: .continuous))

            if build.needsConfirmation {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                    Text("This command can change or delete things. Run it anyway?")
                        .font(.system(size: 12))
                    Spacer()
                    Button("Run anyway") { build.run(confirmed: true) }.buttonStyle(.vellumPrimary)
                    Button("Cancel") { build.cancelConfirmation() }.buttonStyle(.vellumSecondary)
                }
                .foregroundStyle(theme.ink(scheme))
                .transition(.rise(theme.rise))
            }

            HStack(spacing: 8) {
                Text("$")
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundStyle(theme.inkTertiary(scheme))
                TextField("ls -la ~/Downloads", text: $build.command)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, design: .monospaced))
                    .onSubmit { build.run() }
                Button("Run") { build.run() }
                    .buttonStyle(.vellumPrimary)
                    .disabled(build.command.trimmingCharacters(in: .whitespaces).isEmpty || build.isRunning)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(theme.well(scheme)))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(theme.edge(scheme), lineWidth: 0.5))
        }
        .padding(16)
        .frame(maxHeight: .infinity)
        .vellum(level: 3, radius: max(theme.radius - 2, 8))
        .animation(theme.spring, value: build.needsConfirmation)
    }
}

private struct SuggestionView: View {
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var build: BuildModel
    @Environment(\.colorScheme) private var scheme
    @ObservedObject var run: BrainRun

    var body: some View {
        let suggestion = BuildModel.parseSuggestion(run.text)
        VStack(alignment: .leading, spacing: 6) {
            if run.status == .done && !suggestion.command.isEmpty {
                Text(suggestion.command)
                    .font(.system(size: 12.5, design: .monospaced))
                    .foregroundStyle(theme.ink(scheme))
                    .textSelection(.enabled)
                if !suggestion.why.isEmpty {
                    Text(suggestion.why).font(.system(size: 11.5)).foregroundStyle(theme.inkSecondary(scheme))
                }
                Button("Use this command") { build.useSuggestion(suggestion.command) }
                    .buttonStyle(.vellumSecondary)
            } else {
                RunView(run: run)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(theme.well(scheme)))
    }
}
