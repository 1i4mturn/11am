import AppKit
import SwiftUI

/// The drop: true black, one piece with the notch, hanging from the top of the screen. Idle it's the notch with the
/// active agent and a countdown; peeking it's one line; open it's the drop itself: the eleven agents and the 11 as
/// circles, notices on white cards, what's running, the apps, and the ask bar. Asking stretches it to listen.
struct NotchView: View {
    @EnvironmentObject private var state: NotchState
    @EnvironmentObject private var brain: Brain
    @EnvironmentObject private var files: FileIndex
    @EnvironmentObject private var today: TodayModel
    @EnvironmentObject private var nightShift: NightShift
    @State private var openHeight: CGFloat = 320

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                NotchShape(topRadius: shape.top, bottomRadius: shape.bottom)
                    .fill(BrandTokens.drop)
                island
                    .padding(.horizontal, shape.top)
            }
            .frame(width: size.width, height: size.height, alignment: .top)
            .clipShape(NotchShape(topRadius: shape.top, bottomRadius: shape.bottom))
            .contentShape(NotchShape(topRadius: shape.top, bottomRadius: shape.bottom))
            .shadow(color: .black.opacity(state.mode == .open ? 0.35 : 0), radius: 24, y: 12)
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
        // Time to go, for something across town.
        if let leave = next.leaveBy, Travel.nudge(now: Date(), leaveBy: leave, start: next.start) { return "leave" }
        let minutes = Int(next.start.timeIntervalSinceNow / 60)
        guard minutes >= 0, minutes <= 60 else { return nil }
        return minutes == 0 ? "now" : "\(minutes)m"
    }

    private var showsEars: Bool { isLive || countdown != nil || !state.geometry.hasNotch }

    /// Flared top corners meet the menu bar; the open drop's lower corners are the brand's 36.
    private var shape: (top: CGFloat, bottom: CGFloat) {
        switch state.mode {
        case .idle: return (6, 10)
        case .peek: return (10, 20)
        case .open: return (14, BrandTokens.radiusDrop)
        }
    }

    private var size: CGSize {
        switch state.mode {
        case .idle:
            return CGSize(width: notch.width + (showsEars ? 104 : 0) + shape.top * 2, height: notch.height)
        case .peek:
            return CGSize(width: max(notch.width + 260, 480) + shape.top * 2, height: notch.height + 44)
        case .open:
            return CGSize(width: 640 + shape.top * 2, height: min(openHeight, NotchController.maxOpenHeight))
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
                        .frame(height: 44)
                }
            }
            .buttonStyle(.plain)
            .transition(.notchContent)
        case .open:
            VStack(spacing: 0) {
                Spacer().frame(height: max(notch.height - 4, 10))
                DropPanel()
                    .padding(.horizontal, 24)
                    .padding(.top, 6)
                    .padding(.bottom, 26)
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

/// Hangs flush from the top edge: flared top corners that meet the menu bar, rounded bottom corners.
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

// MARK: - Idle and peek

private struct IdleEars: View {
    @EnvironmentObject private var brain: Brain
    var isLive: Bool
    var countdown: String?
    var hasNotch: Bool

    var body: some View {
        HStack {
            if isLive {
                PulsingCircle(code: brain.isBusy ? "11" : "le")
            } else if !hasNotch {
                Wordmark(height: 11, color: .white)
            }
            Spacer(minLength: 0)
            if let countdown {
                Text(countdown)
                    .font(BrandFont.label(12))
                    .foregroundStyle(.white)
            }
        }
        .padding(.horizontal, 12)
    }
}

/// The active agent resting in the ear: a sheet-ink circle that breathes while it works.
private struct PulsingCircle: View {
    var code: String
    @State private var dim = false

    var body: some View {
        DropCircle(code: code, size: 20, lit: !dim)
            .onAppear {
                guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
                withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { dim = true }
            }
            .accessibilityLabel("11am is working")
    }
}

private struct PeekLine: View {
    @EnvironmentObject private var brain: Brain
    @EnvironmentObject private var today: TodayModel
    @EnvironmentObject private var nightShift: NightShift

    var body: some View {
        HStack(spacing: 10) {
            DropCircle(code: "le", size: 26, lit: true)
            Text(summary)
                .font(BrandFont.body(13.5, weight: .medium))
                .foregroundStyle(.white)
                .lineLimit(1)
            Spacer(minLength: 0)
            Icon("chevron.down")
                .font(.brand(size: 11))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 20)
    }

    private var summary: String {
        if brain.isBusy { return "Thinking" }
        if nightShift.isRunning { return "Working through tonight's jobs" }
        var parts: [String] = []
        if let next = today.nextEvent {
            if let leave = next.leaveBy, Travel.nudge(now: Date(), leaveBy: leave, start: next.start) {
                parts.append("Leave \(leave <= Date() ? "now" : "at \(leave.formatted(date: .omitted, time: .shortened))") for \(next.title)")
            } else {
                parts.append("\(next.title) at \(next.start.formatted(date: .omitted, time: .shortened))")
            }
        }
        if let run = today.briefRun, run.status == .done {
            parts.append(today.briefWasPreparedOvernight ? "brief prepared overnight" : "brief ready")
        }
        return parts.isEmpty ? "Click to open · ⌥Space to talk" : parts.joined(separator: " · ")
    }
}

// MARK: - Circles

/// An agent in the drop: sheet-ink at rest, white when it has something new (or is the one working).
struct DropCircle: View {
    var code: String
    var size: CGFloat = 48
    var lit = false

    var body: some View {
        AgentLogo(code: code, size: size, color: lit ? BrandTokens.inkHex : .white, scale: 1)
            .background { Circle().fill(lit ? Color.white : BrandTokens.sheetInk) }
            .clipShape(Circle())
    }
}

/// The twelfth spot: the 11 in a white circle with two soft rings. Tap it to talk.
struct ListeningCircle: View {
    var size: CGFloat = 48
    var halo = false

    var body: some View {
        AgentLogo(code: "11", size: size, color: BrandTokens.inkHex, scale: 1)
            .background { Circle().fill(Color.white) }
            .clipShape(Circle())
            .background {
                Circle().stroke(Color.white.opacity(0.28), lineWidth: 6).padding(-3)
                Circle().stroke(Color.white.opacity(0.12), lineWidth: 7).padding(-9.5)
            }
            .background {
                if halo {
                    Circle()
                        .fill(RadialGradient(colors: [BrandTokens.halo, Color.white.opacity(0.5), .clear], center: .center,
                                             startRadius: 0, endRadius: size * 1.2))
                        .frame(width: size * 2.6, height: size * 2.6)
                        .blur(radius: BrandTokens.blurHalo)
                }
            }
    }
}

// MARK: - The drop, open

/// Which agent works in which app, for a tap on its circle.
enum DropAgents {
    static let order = ["le", "mr", "wi", "jm", "ge", "cr", "rb", "jo", "hr", "ce", "bn"]

    static func section(for code: String) -> AppSection {
        switch code {
        case "le": return .today
        case "mr": return .mail
        case "wi": return .write
        case "jm": return .research
        case "ge": return .money
        case "cr": return .business
        case "rb": return .design
        case "jo": return .build
        case "hr": return .learn
        case "ce": return .video
        default: return .notes
        }
    }

    static func role(_ code: String) -> String {
        switch code {
        case "le": return "chief of staff"
        case "mr": return "mail"
        case "wi": return "writing"
        case "jm": return "research"
        case "ge": return "money"
        case "cr": return "business"
        case "rb": return "design"
        case "jo": return "build"
        case "hr": return "learning"
        case "ce": return "video and audio"
        default: return "notes and files"
        }
    }
}

private struct DropPanel: View {
    @EnvironmentObject private var state: NotchState
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var brain: Brain
    @EnvironmentObject private var files: FileIndex
    @EnvironmentObject private var today: TodayModel
    @EnvironmentObject private var nightShift: NightShift
    @EnvironmentObject private var mail: MailModel

    private var listening: Bool { state.focusAsk || state.askRun != nil || !state.askText.isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            if listening {
                DropListening()
            } else {
                agents
                notices
                if let live { live }
                openRow
            }
            DropAskBar()
        }
        .foregroundStyle(.white)
    }

    private var header: some View {
        HStack {
            Text("the drop · \(Date().formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute()))")
                .font(BrandFont.label(12))
            Spacer()
            Wordmark(height: 16, color: .white)
            Button {
                state.close()
            } label: {
                Text("×")
                    .font(BrandFont.body(18))
                    .frame(width: 26, height: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")
            .padding(.leading, 8)
        }
    }

    // MARK: Agents

    /// Agents with something waiting: Leo with a brief or a meeting soon, Marc with mail that needs you, Bolton indexing.
    private var newAgents: Set<String> {
        var lit: Set<String> = []
        if today.briefRun?.status == .done { lit.insert("le") }
        if let next = today.nextEvent, next.start.timeIntervalSinceNow < 3_600 { lit.insert("le") }
        if mail.count(.needsYou) > 0 { lit.insert("mr") }
        if files.isIndexing { lit.insert("bn") }
        return lit
    }

    private var agents: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: 6), spacing: 14) {
            ForEach(DropAgents.order, id: \.self) { code in
                Button {
                    open(DropAgents.section(for: code))
                } label: {
                    DropCircle(code: code, size: 48, lit: newAgents.contains(code))
                }
                .buttonStyle(.plain)
                .help("\(AgentCode.name(code)) · \(DropAgents.role(code))")
                .accessibilityLabel(AgentCode.name(code))
            }
            Button {
                state.focusAsk = true
            } label: {
                ListeningCircle(size: 48)
            }
            .buttonStyle(.plain)
            .help("Talk to the team · ⌥Space")
            .accessibilityLabel("Talk to the team")
        }
        .padding(.vertical, 6)
    }

    // MARK: Notices

    private struct Notice: Identifiable {
        var id: String
        var agent: String
        var text: String
        var action: String
        var run: () -> Void
    }

    private var noticeList: [Notice] {
        var list: [Notice] = []
        if let next = today.nextEvent ?? (today.isLive ? nil : today.sampleEvents.first) {
            var text = "\(next.title) at \(next.start.formatted(date: .omitted, time: .shortened))"
            if let leave = next.leaveBy { text += ", leave by \(leave.formatted(date: .omitted, time: .shortened))" }
            if !today.isLive { text += " (sample)" }
            list.append(Notice(id: "event", agent: "le", text: text, action: "Open") { open(.calendar) })
        }
        if let run = today.briefRun {
            switch run.status {
            case .done:
                list.append(Notice(id: "brief", agent: "le", text: today.briefWasPreparedOvernight ? "morning brief is ready, written overnight" : "morning brief is ready",
                                   action: "Open") { open(.today) })
            case .failed:
                list.append(Notice(id: "brief", agent: "le", text: "the brief didn't finish", action: "Try again") {
                    Task { await today.prepareBrief(overnight: false) }
                })
            default:
                break
            }
        } else {
            list.append(Notice(id: "brief", agent: "le", text: "no brief yet; it's written overnight", action: "Write now") {
                Task { await today.prepareBrief(overnight: false) }
            })
        }
        let needs = mail.count(.needsYou)
        if needs > 0 {
            var text = needs == 1 ? "1 email needs you" : "\(needs) emails need you"
            if mail.draftsReady > 0 { text += ", \(mail.draftsReady) drafted" }
            list.append(Notice(id: "mail", agent: "mr", text: text, action: "Open") { open(.mail) })
        }
        return Array(list.prefix(3))
    }

    private var notices: some View {
        VStack(spacing: 8) {
            ForEach(noticeList) { notice in
                HStack(spacing: 12) {
                    (Text(AgentCode.name(notice.agent)).font(BrandFont.body(14, weight: .semibold))
                        + Text(" · \(notice.text)").font(BrandFont.body(14)))
                        .lineLimit(2)
                    Spacer(minLength: 8)
                    Button(notice.action, action: notice.run)
                        .buttonStyle(DropPillStyle(kind: .ink))
                        .disabled(brain.isBusy && notice.id == "brief")
                }
                .foregroundStyle(BrandTokens.inkHex)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: BrandTokens.radiusNotice, style: .continuous).fill(Color.white))
            }
        }
    }

    // MARK: Live

    private var live: AnyView? {
        let code: String, text: String
        if nightShift.isRunning {
            code = "le"; text = "leo · working through tonight's jobs"
        } else if files.isIndexing {
            code = "bn"; text = "bolton · indexing your files"
        } else if brain.isBusy {
            code = "11"; text = "thinking"
        } else {
            return nil
        }
        return AnyView(
            HStack(spacing: 12) {
                DropCircle(code: code, size: 30, lit: true)
                Text(text).font(BrandFont.label(12))
                Spacer(minLength: 8)
                ProgressDots()
            }
        )
    }

    // MARK: Apps

    private var openRow: some View {
        let apps: [AppSection] = [.today, .calendar, .tasks, .mail, .notes, .write]
        return HStack(spacing: 8) {
            ForEach(apps) { section in
                Button(section.title) { open(section) }
                    .buttonStyle(DropPillStyle(kind: model.section == section && mainWindowVisible ? .paper : .sheet))
            }
            Spacer(minLength: 0)
        }
    }

    private var mainWindowVisible: Bool {
        NSApp.windows.contains { $0.canBecomeMain && $0.isVisible }
    }

    private func open(_ section: AppSection) {
        NSApp.activate()
        NSApp.windows.first { $0.canBecomeMain }?.makeKeyAndOrderFront(nil)
        model.go(to: section)
        state.close()
    }
}

/// Five dots that fill in turn while something runs: progress is counted in dots, never a smooth bar.
struct ProgressDots: View {
    var count = 5
    @State private var filled = 0

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<count, id: \.self) { index in
                Circle()
                    .fill(index < filled ? Color.white : Color.clear)
                    .overlay { Circle().strokeBorder(Color.white, lineWidth: BrandTokens.ruleOpen) }
                    .frame(width: 10, height: 10)
            }
        }
        .task {
            guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
                filled = 2
                return
            }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 380_000_000)
                filled = (filled + 1) % (count + 1)
            }
        }
        .accessibilityLabel("Working")
    }
}

/// Pills inside the drop: ink on the white notices, paper for the app whose window is showing, sheet-ink for the rest.
struct DropPillStyle: ButtonStyle {
    enum Kind { case ink, paper, sheet, open }
    var kind: Kind

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(BrandFont.body(13.5, weight: .semibold))
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 16)
            .frame(minHeight: 34)
            .foregroundStyle(kind == .paper ? BrandTokens.inkHex : (kind == .open ? BrandTokens.inkHex : .white))
            .background {
                switch kind {
                case .ink: Capsule().fill(BrandTokens.inkHex)
                case .paper: Capsule().fill(Color.white)
                case .sheet: Capsule().fill(BrandTokens.sheetInk)
                case .open: Capsule().strokeBorder(BrandTokens.inkHex, lineWidth: BrandTokens.ruleOpen)
                }
            }
            .opacity(configuration.isPressed ? 0.8 : 1)
            .contentShape(Capsule())
    }
}

// MARK: - Asking

/// The ask bar: a sheet-ink pill along the bottom of the drop.
private struct DropAskBar: View {
    @EnvironmentObject private var state: NotchState
    @EnvironmentObject private var brain: Brain
    @EnvironmentObject private var files: FileIndex
    @EnvironmentObject private var tasks: TasksModel
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 10) {
            TextField("", text: $state.askText, prompt: Text("Ask the team, or + to add a task").foregroundStyle(.white.opacity(0.7)))
                .textFieldStyle(.plain)
                .font(BrandFont.body(14))
                .foregroundStyle(.white)
                .focused($focused)
                .onSubmit(submit)
            Text("⌥space to talk")
                .font(BrandFont.label(12))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 18)
        .frame(minHeight: 40)
        .background(Capsule().fill(BrandTokens.sheetInk))
        .onAppear { focused = state.focusAsk }
        .onChange(of: state.focusAsk) { _, newValue in focused = newValue }
        .onChange(of: focused) { _, newValue in if newValue { state.focusAsk = true } }
    }

    private func submit() {
        let text = state.askText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        // "+ Call Tom tomorrow" is a task, not a question.
        if text.hasPrefix("+") {
            if let task = tasks.add(String(text.dropFirst()), in: .inbox, select: false) {
                let when = tasks.dueText(task).map { " · \($0)" } ?? ""
                state.added = "Added to Tasks: \(task.title)\(when)"
                state.askText = ""
                state.askRun = nil
            }
            return
        }
        state.added = nil
        state.askedText = text
        state.askRun = brain.run(AskRouter.request(for: text, files: files))
    }
}

/// Listening: the 11 with its halo, the sentence in Schibsted, where it's going, and the answer on a white card.
private struct DropListening: View {
    @EnvironmentObject private var state: NotchState

    private var sentence: String {
        let typed = state.askText.trimmingCharacters(in: .whitespacesAndNewlines)
        return typed.isEmpty ? (state.askedText.isEmpty ? "Ask the team anything." : state.askedText) : typed
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 20) {
                ListeningCircle(size: 56, halo: state.askRun.map { !$0.isFinished } ?? true)
                    .padding(10)
                Text(sentence)
                    .font(BrandFont.heading(24, weight: .heavy))
                    .tracking(-0.6)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 6) {
                ForEach(routes, id: \.self) { route in
                    Text(route)
                        .font(BrandFont.label(12))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 3)
                        .overlay { Capsule().strokeBorder(Color.white, lineWidth: BrandTokens.ruleOpen) }
                }
            }
            if let run = state.askRun {
                DropAnswer(run: run)
            } else if let added = state.added {
                Text(added).font(BrandFont.body(14))
            }
        }
    }

    private var routes: [String] {
        let text = state.askText.isEmpty ? state.askedText : state.askText
        if text.trimmingCharacters(in: .whitespaces).hasPrefix("+") { return ["leo", "a task"] }
        let agent = AskRouter.agent(for: text)
        return [agent.name.lowercased(), agent.monogram == "bn" ? "your files" : "chief of staff"]
    }
}

private struct DropAnswer: View {
    @ObservedObject var run: BrainRun
    @State private var height: CGFloat = 24

    var body: some View {
        ScrollView {
            RunView(run: run)
                .frame(maxWidth: .infinity, alignment: .leading)
                .readHeight { height = $0 }
        }
        .frame(height: min(max(height, 22), 200))
        .padding(16)
        .background(RoundedRectangle(cornerRadius: BrandTokens.radiusNotice, style: .continuous).fill(Color.white))
        .environment(\.colorScheme, .light)
    }
}
