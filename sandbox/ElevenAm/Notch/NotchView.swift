import SwiftUI

/// The island that hangs from the notch: idle (matches the hardware), peek (one line), open (pages).
/// One black shape grows and shrinks between sizes; content fades in just behind it and leaves first.
struct NotchView: View {
    @EnvironmentObject private var state: NotchState
    @EnvironmentObject private var brain: Brain
    @EnvironmentObject private var files: FileIndex
    @EnvironmentObject private var today: TodayModel
    @EnvironmentObject private var nightShift: NightShift
    @State private var openHeight: CGFloat = 300

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                NotchShape(topRadius: shape.top, bottomRadius: shape.bottom)
                    .fill(Color.black)
                island
                    .padding(.horizontal, shape.top)
            }
            .frame(width: size.width, height: size.height, alignment: .top)
            .clipShape(NotchShape(topRadius: shape.top, bottomRadius: shape.bottom))
            .contentShape(NotchShape(topRadius: shape.top, bottomRadius: shape.bottom))
            .shadow(color: .black.opacity(state.mode == .open ? 0.4 : 0), radius: 22, y: 10)
            .onHover { inside in
                if inside { state.pointerEntered() } else { state.pointerLeft() }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .environment(\.colorScheme, .dark)
    }

    // MARK: Sizing

    private var notch: CGSize { state.geometry.notchSize }

    private var isLive: Bool { brain.isBusy || files.isIndexing || nightShift.isRunning }

    private var countdown: String? {
        guard let next = today.nextEvent else { return nil }
        let minutes = Int(next.start.timeIntervalSinceNow / 60)
        guard minutes >= 0, minutes <= 60 else { return nil }
        return minutes == 0 ? "now" : "\(minutes)m"
    }

    private var showsEars: Bool { isLive || countdown != nil || !state.geometry.hasNotch }

    /// Top corners flare outward into the menu bar, like the island is pouring out of the notch.
    private var shape: (top: CGFloat, bottom: CGFloat) {
        switch state.mode {
        case .idle: return (6, 10)
        case .peek: return (10, 18)
        case .open: return (14, 28)
        }
    }

    private var size: CGSize {
        switch state.mode {
        case .idle:
            return CGSize(width: notch.width + (showsEars ? 96 : 0) + shape.top * 2, height: notch.height)
        case .peek:
            return CGSize(width: max(notch.width + 240, 460) + shape.top * 2, height: notch.height + 42)
        case .open:
            return CGSize(width: 660 + shape.top * 2, height: min(openHeight, 440))
        }
    }

    // MARK: Content

    @ViewBuilder
    private var island: some View {
        switch state.mode {
        case .idle:
            IdleEars(isLive: isLive, countdown: countdown, hasNotch: state.geometry.hasNotch)
                .frame(height: notch.height)
                .transition(.opacity.animation(.easeOut(duration: 0.18)))
        case .peek:
            Button { state.open() } label: {
                VStack(spacing: 0) {
                    Spacer().frame(height: notch.height)
                    PeekLine()
                        .frame(maxWidth: .infinity)
                        .frame(height: 42)
                }
            }
            .buttonStyle(.plain)
            .transition(.notchContent)
        case .open:
            VStack(spacing: 0) {
                Spacer().frame(height: max(notch.height - 6, 8))
                OpenPanel()
                    .padding(.horizontal, 22)
                    .padding(.bottom, 18)
            }
            .fixedSize(horizontal: false, vertical: true)
            .readHeight { height in
                guard height > 0, abs(height - openHeight) > 0.5 else { return }
                withAnimation(.smooth(duration: 0.3)) { openHeight = height }
            }
            .transition(.notchContent)
        }
    }
}

private struct BlurModifier: ViewModifier {
    var radius: CGFloat

    func body(content: Content) -> some View {
        content.blur(radius: radius)
    }
}

private extension AnyTransition {
    /// Arrives a beat after the shape starts growing, softly out of focus; leaves quickly before it shrinks.
    static var notchContent: AnyTransition {
        .asymmetric(
            insertion: .opacity
                .combined(with: .scale(scale: 0.94, anchor: .top))
                .combined(with: .modifier(active: BlurModifier(radius: 6), identity: BlurModifier(radius: 0)))
                .animation(.spring(response: 0.42, dampingFraction: 0.9).delay(0.07)),
            removal: .opacity.animation(.easeOut(duration: 0.12))
        )
    }
}

/// Hangs flush from the top edge: flared top corners that meet the menu bar, rounded bottom corners like the hardware.
struct NotchShape: Shape {
    var topRadius: CGFloat
    var bottomRadius: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(topRadius, bottomRadius) }
        set {
            topRadius = newValue.first
            bottomRadius = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let top = min(topRadius, rect.width / 4, rect.height / 2)
        let bottom = max(0, min(bottomRadius, (rect.width - top * 2) / 2, rect.height - top))
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.minX + top, y: rect.minY + top), control: CGPoint(x: rect.minX + top, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX + top, y: rect.maxY - bottom))
        path.addQuadCurve(to: CGPoint(x: rect.minX + top + bottom, y: rect.maxY), control: CGPoint(x: rect.minX + top, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX - top - bottom, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX - top, y: rect.maxY - bottom), control: CGPoint(x: rect.maxX - top, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX - top, y: rect.minY + top))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY), control: CGPoint(x: rect.maxX - top, y: rect.minY))
        path.closeSubpath()
        return path
    }
}

private struct IdleEars: View {
    @EnvironmentObject private var theme: Theme
    var isLive: Bool
    var countdown: String?
    var hasNotch: Bool

    var body: some View {
        HStack {
            if isLive {
                PulsingMonogram()
            } else if !hasNotch {
                Wordmark(height: 11, color: Color.white.opacity(0.85))
            }
            Spacer(minLength: 0)
            if let countdown {
                Text(countdown)
                    .font(.system(size: 11, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.9))
            }
        }
        .padding(.horizontal, 14)
    }
}

private struct PulsingMonogram: View {
    @EnvironmentObject private var theme: Theme
    @State private var dim = false

    var body: some View {
        AgentLogo(code: "le", size: 22, color: Color.white)
            .opacity(dim ? 0.35 : 1)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { dim = true }
            }
            .accessibilityLabel("11am is working")
    }
}

private struct PeekLine: View {
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var brain: Brain
    @EnvironmentObject private var today: TodayModel
    @EnvironmentObject private var nightShift: NightShift

    var body: some View {
        HStack(spacing: 10) {
            AgentLogo(code: "le", size: 24, color: Color.white)
            Text(summary)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(0.92))
                .lineLimit(1)
            Spacer(minLength: 0)
            Image(systemName: "chevron.down")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white.opacity(0.5))
        }
        .padding(.horizontal, 20)
    }

    private var summary: String {
        if brain.isBusy { return "Thinking…" }
        if nightShift.isRunning { return "Working overnight jobs…" }
        var parts: [String] = []
        if let next = today.nextEvent {
            parts.append("\(next.title) at \(next.start.formatted(date: .omitted, time: .shortened))")
        }
        if let run = today.briefRun, run.status == .done {
            parts.append(today.briefWasPreparedOvernight ? "brief prepared overnight" : "brief ready")
        }
        return parts.isEmpty ? "Click to open · ⌥Space to ask" : parts.joined(separator: " · ")
    }
}

private struct OpenPanel: View {
    @EnvironmentObject private var state: NotchState

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 6) {
                ForEach(NotchPage.allCases) { page in
                    Button(page.title) { withAnimation(.smooth(duration: 0.3)) { state.page = page } }
                        .buttonStyle(NotchTabStyle(selected: state.page == page))
                }
                Spacer()
                Button {
                    state.close()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white.opacity(0.6))
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(Color.white.opacity(0.08)))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close")
            }

            // Pages cross-fade in place; the island's height follows the new page.
            ZStack(alignment: .topLeading) {
                page(state.page)
                    .id(state.page)
                    .transition(.opacity.animation(.easeInOut(duration: 0.2)))
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    @ViewBuilder
    private func page(_ page: NotchPage) -> some View {
        switch page {
        case .now: NotchNowPage()
        case .ask: NotchAskPage()
        case .overnight: NotchOvernightPage()
        }
    }
}

private struct NotchTabStyle: ButtonStyle {
    var selected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .foregroundStyle(selected ? Color.black : Color.white.opacity(0.85))
            .background(Capsule().fill(selected ? Color.white : Color.white.opacity(0.08)))
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}

private struct NotchRow<Trailing: View>: View {
    @EnvironmentObject private var theme: Theme
    var monogram: String
    var title: String
    var detail: String
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 12) {
            AgentLogo(code: monogram, size: 26, color: Color.white)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                Text(detail).font(.system(size: 11.5)).foregroundStyle(.white.opacity(0.55)).lineLimit(2)
            }
            Spacer(minLength: 8)
            trailing()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(0.06)))
    }
}

private struct NotchNowPage: View {
    @EnvironmentObject private var brain: Brain
    @EnvironmentObject private var files: FileIndex
    @EnvironmentObject private var today: TodayModel
    @EnvironmentObject private var nightShift: NightShift
    @EnvironmentObject private var machine: MachineProfile
    @EnvironmentObject private var mail: MailModel

    private var mailDetail: String {
        let needs = mail.count(.needsYou)
        var parts = [needs == 1 ? "1 needs you" : "\(needs) need you"]
        if mail.draftsReady > 0 { parts.append("\(mail.draftsReady) drafted") }
        parts.append("\(mail.count(.noise)) noise held back")
        return parts.joined(separator: " · ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let next = today.nextEvent ?? (today.isLive ? nil : today.sampleEvents.first) {
                NotchRow(
                    monogram: "le",
                    title: "\(next.start.formatted(date: .omitted, time: .shortened))  \(next.title)",
                    detail: today.isLive ? (next.location ?? next.calendar) : "Sample event. Connect your calendars in Calendar."
                ) { EmptyView() }
            }

            if let run = today.briefRun {
                NotchBriefRow(run: run)
            } else {
                NotchRow(monogram: "le", title: "Brief", detail: "Not written yet. It will be ready after tonight's run.") {
                    Button("Write") { Task { await today.prepareBrief(overnight: false) } }
                        .buttonStyle(NotchTabStyle(selected: true))
                        .disabled(brain.isBusy)
                }
            }

            NotchRow(monogram: "mc", title: "Mail", detail: mailDetail) { EmptyView() }

            NotchRow(monogram: "bn", title: "Files", detail: files.isIndexing ? "Indexing…" : files.status) { EmptyView() }

            NotchRow(
                monogram: "11",
                title: "This Mac",
                detail: "\(machine.summary) · \(brain.mode.title) · Claude this month \(Pricing.format(brain.spentThisMonthUSD))"
            ) { EmptyView() }
        }
    }

}

/// Observes the brief run directly so the row updates while it streams.
private struct NotchBriefRow: View {
    @EnvironmentObject private var brain: Brain
    @EnvironmentObject private var today: TodayModel
    @ObservedObject var run: BrainRun

    var body: some View {
        NotchRow(monogram: "le", title: today.briefWasPreparedOvernight ? "Brief · prepared overnight" : "Brief", detail: detail) {
            Button("Rewrite") { Task { await today.prepareBrief(overnight: false) } }
                .buttonStyle(NotchTabStyle(selected: false))
                .disabled(brain.isBusy)
        }
    }

    private var detail: String {
        switch run.status {
        case .routing, .working: return run.text.isEmpty ? "Writing…" : run.text.replacingOccurrences(of: "\n", with: " ")
        case .failed(let message): return message
        case .done: return run.text.replacingOccurrences(of: "\n", with: " ")
        }
    }
}

private struct NotchAskPage: View {
    @EnvironmentObject private var state: NotchState
    @EnvironmentObject private var brain: Brain
    @EnvironmentObject private var files: FileIndex
    @FocusState private var focused: Bool
    @State private var answerHeight: CGFloat = 24

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "sparkle.magnifyingglass").foregroundStyle(.white.opacity(0.5))
                TextField("Ask the team…", text: $state.askText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .foregroundStyle(.white)
                    .focused($focused)
                    .onSubmit(submit)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(0.08)))

            if let run = state.askRun {
                ScrollView {
                    RunView(run: run)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .readHeight { answerHeight = $0 }
                }
                .frame(height: min(max(answerHeight, 20), 230))
            } else {
                Text("Questions about your files go to Bolton. Everything else goes to Leo. Quick answers run on this Mac.")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
        .onAppear { focused = state.focusAsk }
        .onChange(of: state.focusAsk) { _, newValue in focused = newValue }
        .onChange(of: focused) { _, newValue in state.focusAsk = newValue }
    }

    private func submit() {
        let text = state.askText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        state.askRun = brain.run(AskRouter.request(for: text, files: files))
    }
}

private struct NotchOvernightPage: View {
    @EnvironmentObject private var nightShift: NightShift

    var body: some View {
        let decision = nightShift.conditions()
        VStack(alignment: .leading, spacing: 8) {
            NotchRow(
                monogram: "le",
                title: "Tonight \(nightShift.windowStartHour):00–\(nightShift.windowEndHour):00",
                detail: decision.ok ? "Good moment to run: \(decision.reason.lowercased())." : decision.reason
            ) {
                Button(nightShift.isRunning ? "Running…" : "Run now") {
                    Task { await nightShift.runNow() }
                }
                .buttonStyle(NotchTabStyle(selected: true))
                .disabled(nightShift.isRunning)
            }
            ForEach(nightShift.log.prefix(3)) { entry in
                NotchRow(monogram: "le", title: entry.title, detail: entry.detail) {
                    Text(entry.date.formatted(date: .omitted, time: .shortened))
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.45))
                }
            }
        }
    }
}
