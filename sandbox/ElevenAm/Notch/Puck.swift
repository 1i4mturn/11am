import AppKit
import Combine
import SwiftUI

/// The puck: an ink disc with the 11 that floats over everything, snaps to the side of the screen and stays where you
/// leave it. Hold it (or ⌥Space) to talk: a halo spreads while it listens and a note opens with what it heard, where
/// it's going and the answer. Click it to type instead. Esc closes the note.
@MainActor
final class PuckState: ObservableObject {
    @Published var listening = false
    @Published var noteOpen = false
    @Published var transcript = ""
    /// What was last sent, so the note can show it above the answer.
    @Published var sent = ""
    @Published var run: BrainRun?
    @Published var added: String?
    @Published var addedTaskID: UUID?
    @Published var problem: String?
    @Published var focusField = false
    /// True when the puck sits on the left of the screen, so the note opens to its right.
    @Published var onLeft = false
    let listener = Listener()
}

/// A round, borderless panel. Clear everywhere but the disc, so clicks beside it fall through.
final class PuckPanel: NSPanel {
    // Key only when clicked, so presses reach the disc; it never brings 11am forward.
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// The note can take typing without bringing 11am's window forward.
final class PuckNotePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class PuckController {
    static let disc: CGFloat = 96
    /// Room around the disc for the halo.
    static let margin: CGFloat = 48
    static let edgeGap: CGFloat = 16
    static let noteSize = NSSize(width: 380, height: 420)

    private let model: AppModel
    let state = PuckState()
    private var panel: PuckPanel?
    private var notePanel: PuckNotePanel?
    private var dragStartMouse: NSPoint = .zero
    private var dragStartOrigin: NSPoint = .zero
    private var heardWatcher: AnyCancellable?
    private var talkStarted: Date?
    private var keyMonitor: Any?

    init(model: AppModel) {
        self.model = model
    }

    private var side: CGFloat { Self.disc + Self.margin * 2 }

    var isShown: Bool { panel?.isVisible == true }

    // MARK: Showing

    func show() {
        if panel == nil {
            let panel = PuckPanel(contentRect: NSRect(origin: savedOrigin(), size: NSSize(width: side, height: side)),
                                  styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            panel.level = .floating
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
            panel.hidesOnDeactivate = false
            panel.becomesKeyOnlyIfNeeded = true
            // It's moved by hand, so a press can also mean "talk".
            panel.isMovable = false
            let root = PuckView(controller: self)
                .environmentObject(state)
                .withAppEnvironment(model)
            let host = NSHostingView(rootView: root)
            host.frame = NSRect(origin: .zero, size: NSSize(width: side, height: side))
            panel.contentView = host
            self.panel = panel
            state.onLeft = panel.frame.midX < (screen?.visibleFrame.midX ?? 0)
        }
        panel?.orderFrontRegardless()
        UserDefaults.standard.set(false, forKey: "puck.hidden")
    }

    func hide() {
        closeNote()
        panel?.orderOut(nil)
        UserDefaults.standard.set(true, forKey: "puck.hidden")
    }

    func toggle() {
        if isShown { hide() } else { show() }
    }

    private var screen: NSScreen? { panel?.screen ?? NSScreen.main ?? NSScreen.screens.first }

    // MARK: Moving

    func pressBegan() {
        dragStartMouse = NSEvent.mouseLocation
        dragStartOrigin = panel?.frame.origin ?? .zero
    }

    func drag() {
        guard let panel else { return }
        let mouse = NSEvent.mouseLocation
        panel.setFrameOrigin(NSPoint(x: dragStartOrigin.x + mouse.x - dragStartMouse.x, y: dragStartOrigin.y + mouse.y - dragStartMouse.y))
        placeNote()
    }

    /// Snaps to the nearer side of the screen and remembers the spot.
    func dragEnded() {
        guard let panel, let visible = (panel.screen ?? screen)?.visibleFrame else { return }
        let frame = panel.frame
        let onLeft = frame.midX < visible.midX
        let x = onLeft ? visible.minX + Self.edgeGap - Self.margin : visible.maxX - Self.edgeGap - Self.disc - Self.margin
        let y = min(max(frame.minY, visible.minY + Self.edgeGap - Self.margin), visible.maxY - Self.edgeGap - Self.disc - Self.margin)
        let target = NSRect(x: x, y: y, width: side, height: side)
        state.onLeft = onLeft
        NSAnimationContext.runAnimationGroup { context in
            context.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 0.22
            panel.animator().setFrame(target, display: true)
        } completionHandler: { [weak self] in
            Task { @MainActor in self?.placeNote() }
        }
        UserDefaults.standard.set([Double(x), Double(y)], forKey: "puck.origin")
    }

    private func savedOrigin() -> NSPoint {
        let visible = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        if let saved = UserDefaults.standard.array(forKey: "puck.origin") as? [Double], saved.count == 2 {
            let point = NSPoint(x: saved[0], y: saved[1])
            // Only if it's still on a screen (displays come and go).
            if NSScreen.screens.contains(where: { $0.visibleFrame.insetBy(dx: -Self.margin, dy: -Self.margin).contains(NSPoint(x: point.x + Self.margin + 1, y: point.y + Self.margin + 1)) }) {
                return point
            }
        }
        // Bottom right, clear of the Dock.
        return NSPoint(x: visible.maxX - Self.edgeGap - Self.disc - Self.margin, y: visible.minY + 96 - Self.margin)
    }

    // MARK: The note

    func tapped() {
        if state.noteOpen {
            closeNote()
        } else {
            openNote(typing: true)
        }
    }

    func openNote(typing: Bool) {
        if notePanel == nil {
            let note = PuckNotePanel(contentRect: NSRect(origin: .zero, size: Self.noteSize),
                                     styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            note.isOpaque = false
            note.backgroundColor = .clear
            note.hasShadow = false
            note.level = .floating
            note.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
            note.hidesOnDeactivate = false
            note.becomesKeyOnlyIfNeeded = true
            let root = PuckNoteView(controller: self)
                .environmentObject(state)
                .withAppEnvironment(model)
            let host = NSHostingView(rootView: root)
            host.frame = NSRect(origin: .zero, size: Self.noteSize)
            note.contentView = host
            notePanel = note
        }
        state.noteOpen = true
        placeNote()
        notePanel?.orderFrontRegardless()
        if typing {
            notePanel?.makeKey()
            state.focusField = true
        }
        installEscape()
    }

    func closeNote() {
        if state.listening { _ = state.listener.stop() }
        heardWatcher = nil
        state.listening = false
        state.noteOpen = false
        state.focusField = false
        notePanel?.orderOut(nil)
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }

    /// Beside the disc, on the side with room, lined up with it.
    private func placeNote() {
        guard let panel, let note = notePanel, let visible = (panel.screen ?? screen)?.visibleFrame else { return }
        let disc = panel.frame.insetBy(dx: Self.margin, dy: Self.margin)
        let onLeft = disc.midX < visible.midX
        state.onLeft = onLeft
        let x = onLeft ? disc.maxX + 12 : disc.minX - 12 - Self.noteSize.width
        var y = disc.maxY - Self.noteSize.height
        y = min(max(y, visible.minY + 8), visible.maxY - Self.noteSize.height - 8)
        note.setFrameOrigin(NSPoint(x: x, y: y))
    }

    private func installEscape() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53 else { return event }
            let handled = MainActor.assumeIsolated { () -> Bool in
                guard let self, self.state.noteOpen, self.notePanel?.isKeyWindow == true || self.state.listening else { return false }
                self.closeNote()
                return true
            }
            return handled ? nil : event
        }
    }

    // MARK: Talking

    /// Hold to talk: the halo spreads, the note opens, and what's heard is written out as it comes.
    func startTalking() {
        guard !state.listening else { return }
        state.problem = nil
        state.run = nil
        state.added = nil
        state.transcript = ""
        state.listening = true
        talkStarted = Date()
        openNote(typing: false)
        heardWatcher = state.listener.$heard
            .receive(on: RunLoop.main)
            .sink { [weak self] heard in
                guard let self, self.state.listening else { return }
                self.state.transcript = heard
            }
        Task { @MainActor in
            if let problem = await state.listener.start(language: Locale.current.identifier) {
                state.problem = problem
                state.listening = false
                state.focusField = true
                notePanel?.makeKey()
            }
        }
    }

    /// Let go: send what was heard. A quick tap of ⌥Space opens the note for typing instead.
    func stopTalking(send: Bool) {
        guard state.listening else { return }
        let text = state.listener.stop()
        heardWatcher = nil
        state.listening = false
        let held = talkStarted.map { Date().timeIntervalSince($0) } ?? 0
        if !text.trimmingCharacters(in: .whitespaces).isEmpty { state.transcript = text }
        if send && held > 0.4 && !state.transcript.trimmingCharacters(in: .whitespaces).isEmpty {
            submit()
        } else {
            state.focusField = true
            notePanel?.makeKey()
        }
    }

    /// ⌥Space pressed and released: held to talk, or tapped to type.
    func hotKeyDown() {
        if !isShown { show() }
        startTalking()
    }

    func hotKeyUp() {
        stopTalking(send: true)
    }

    /// Sends the words on: "+ …" or "remind me to …" becomes a task, the rest goes to the agent it's about.
    func submit() {
        let text = state.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        state.sent = text
        state.added = nil
        state.addedTaskID = nil
        let lower = text.lowercased()
        if text.hasPrefix("+") || lower.hasPrefix("remind me to ") || lower.hasPrefix("add a task ") {
            var body = text
            if body.hasPrefix("+") { body = String(body.dropFirst()) }
            for prefix in ["remind me to ", "add a task "] where body.lowercased().hasPrefix(prefix) { body = String(body.dropFirst(prefix.count)) }
            if let task = model.tasks.add(body, in: .inbox, select: false) {
                let when = model.tasks.dueText(task).map { ", \($0)" } ?? ""
                state.added = "Added to Tasks: \(task.title)\(when)"
                state.addedTaskID = task.id
                state.run = nil
                state.transcript = ""
            }
            return
        }
        state.run = model.brain.run(AskRouter.request(for: text, files: model.files))
        state.transcript = ""
    }

    /// Takes back a task the puck just added.
    func undoTask() {
        guard let id = state.addedTaskID else { return }
        model.tasks.delete(id)
        state.added = "Taken back off the list."
        state.addedTaskID = nil
    }

    // MARK: Samples

    /// For screenshots: the puck listening, its note open with what it heard.
    func previewListening() {
        show()
        state.transcript = "What's on this afternoon, and is the board deck ready?"
        state.listening = true
        openNote(typing: false)
    }

    /// For screenshots: the note with a sent question and its answer.
    func previewAnswer() {
        show()
        state.sent = "Where's the Acme pilot agreement, and when can either side end it?"
        let run = BrainRun(prompt: state.sent)
        run.text = "It's in Documents › Clients › Acme, saved as \u{201C}Acme pilot agreement.pdf\u{201D}. Either side can end the pilot with 7 days' notice in writing."
        run.providerLabel = "On this Mac"
        run.status = .done
        state.run = run
        openNote(typing: false)
    }
}

// MARK: - Views

/// The disc: ink, the 11, a count of what needs you, and the halo while it listens.
struct PuckView: View {
    @EnvironmentObject private var state: PuckState
    @EnvironmentObject private var mail: MailModel
    @EnvironmentObject private var tasks: TasksModel
    var controller: PuckController
    @State private var pressed: Date?
    @State private var dragging = false
    @State private var talking = false
    @State private var holdTask: Task<Void, Never>?

    private var count: Int { mail.count(.needsYou) + tasks.overdueCount }

    var body: some View {
        ZStack {
            if state.listening {
                Circle()
                    .fill(RadialGradient(colors: [BrandTokens.halo, Color.white.opacity(0.7), .clear], center: .center,
                                         startRadius: 0, endRadius: PuckController.disc))
                    .blur(radius: BrandTokens.blurHalo)
                    .transition(.opacity.combined(with: .scale(scale: 0.6)))
            }
            disc
        }
        .frame(width: PuckController.disc + PuckController.margin * 2, height: PuckController.disc + PuckController.margin * 2)
        .animation(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? nil : .easeOut(duration: 0.35), value: state.listening)
    }

    private var disc: some View {
        AgentLogo(code: "11", size: PuckController.disc, color: .white, scale: 1)
            .background { Circle().fill(BrandTokens.inkHex) }
            .overlay { Tooth().clipShape(Circle()) }
            .clipShape(Circle())
            .shadow(color: .black.opacity(0.08), radius: 2, y: 2)
            .shadow(color: .black.opacity(0.18), radius: 20, y: 16)
            .overlay(alignment: .topTrailing) {
                if count > 0 {
                    Text("\(count)")
                        .font(BrandFont.label(12))
                        .foregroundStyle(BrandTokens.inkHex)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color.white))
                        .overlay { Capsule().strokeBorder(BrandTokens.inkHex, lineWidth: BrandTokens.ruleOpen) }
                        .offset(x: 4, y: -2)
                        .accessibilityLabel("\(count) need you")
                }
            }
            .contentShape(Circle())
            .gesture(press)
            .help("Hold to talk, click to type, drag to move")
            .accessibilityLabel("11am")
            .accessibilityAddTraits(.isButton)
    }

    /// One gesture for three things: a click opens the note, a hold talks, a drag moves it.
    private var press: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .global)
            .onChanged { value in
                if pressed == nil {
                    pressed = Date()
                    controller.pressBegan()
                    holdTask = Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 350_000_000)
                        guard !Task.isCancelled, !dragging, pressed != nil else { return }
                        talking = true
                        controller.startTalking()
                    }
                }
                if !talking, hypot(value.translation.width, value.translation.height) > 4 {
                    dragging = true
                    holdTask?.cancel()
                    controller.drag()
                }
            }
            .onEnded { _ in
                holdTask?.cancel()
                if dragging {
                    controller.dragEnded()
                } else if talking {
                    controller.stopTalking(send: true)
                } else {
                    controller.tapped()
                }
                pressed = nil
                dragging = false
                talking = false
            }
    }
}

/// The note the puck opens: vellum, square, with the time and who it's from in Courier, the words in Schibsted,
/// where they're going, and the answer.
struct PuckNoteView: View {
    @EnvironmentObject private var state: PuckState
    var controller: PuckController
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("\(Date().formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute())) · \(state.listening ? "listening" : "you")")
                        .font(BrandFont.label(12))
                    Spacer()
                    if state.listening { ProgressDotsInk() }
                    Button {
                        controller.closeNote()
                    } label: {
                        Text("×").font(BrandFont.body(18)).frame(width: 24, height: 24).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Close")
                }

                if !state.sent.isEmpty && !state.listening && state.transcript.isEmpty {
                    Text(state.sent)
                        .font(BrandFont.heading(20, weight: .heavy))
                        .tracking(-0.4)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if state.listening {
                    Text(state.transcript.isEmpty ? "Listening…" : state.transcript)
                        .font(BrandFont.heading(22, weight: .heavy))
                        .tracking(-0.5)
                        .fixedSize(horizontal: false, vertical: true)
                } else if state.run == nil && state.added == nil || !state.transcript.isEmpty {
                    TextField("", text: $state.transcript, prompt: Text("Say or type what you need").foregroundStyle(BrandTokens.inkHex.opacity(0.55)), axis: .vertical)
                        .textFieldStyle(.plain)
                        .font(BrandFont.heading(20, weight: .heavy))
                        .lineLimit(1...4)
                        .focused($focused)
                        .onSubmit { controller.submit() }
                }

                routes

                if let problem = state.problem {
                    HStack(alignment: .top, spacing: 8) {
                        Rectangle().fill(BrandTokens.inkHex).frame(width: BrandTokens.errorBar)
                        Text(problem).font(BrandFont.body(13.5)).fixedSize(horizontal: false, vertical: true)
                    }
                }

                if let run = state.run {
                    PuckAnswer(run: run)
                } else if let added = state.added {
                    Text(added).font(BrandFont.body(14)).fixedSize(horizontal: false, vertical: true)
                }

                actions
            }
            .padding(20)
            .frame(width: PuckController.noteSize.width)
            .foregroundStyle(BrandTokens.inkHex)
            .noteSurface()
            .lift(hi: true)
            .environment(\.colorScheme, .light)
            Spacer(minLength: 0)
        }
        .frame(width: PuckController.noteSize.width, height: PuckController.noteSize.height, alignment: .top)
        .onAppear { focused = state.focusField }
        .onChange(of: state.focusField) { _, value in focused = value }
    }

    @ViewBuilder
    private var routes: some View {
        let text = state.listening || !state.transcript.isEmpty ? state.transcript : state.sent
        if !text.trimmingCharacters(in: .whitespaces).isEmpty {
            HStack(spacing: 6) {
                ForEach(PuckNoteView.routes(for: text), id: \.self) { route in
                    Chip(text: route)
                }
            }
        }
    }

    static func routes(for text: String) -> [String] {
        let lower = text.lowercased().trimmingCharacters(in: .whitespaces)
        if lower.hasPrefix("+") || lower.hasPrefix("remind me to") || lower.hasPrefix("add a task") { return ["leo", "a task"] }
        let agent = AskRouter.agent(for: text)
        return [agent.name.lowercased(), agent.monogram == "bn" ? "your files" : "chief of staff"]
    }

    @ViewBuilder
    private var actions: some View {
        HStack(spacing: 8) {
            Spacer()
            if state.addedTaskID != nil {
                Button("Undo") { controller.undoTask() }.buttonStyle(.vellumSecondary)
            }
            if let run = state.run, run.isFinished {
                Button("Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(run.text, forType: .string)
                }
                .buttonStyle(.vellumSecondary)
                Button("Edit") {
                    state.transcript = state.sent
                    state.run = nil
                    state.focusField = true
                }
                .buttonStyle(.vellumSecondary)
            }
            if state.listening {
                Button("Send") { controller.stopTalking(send: true) }.buttonStyle(.vellumPrimary)
            } else if !state.transcript.trimmingCharacters(in: .whitespaces).isEmpty {
                Button("Send") { controller.submit() }.buttonStyle(.vellumPrimary)
            }
        }
    }
}

private struct PuckAnswer: View {
    @ObservedObject var run: BrainRun
    @State private var height: CGFloat = 24

    var body: some View {
        ScrollView {
            RunView(run: run)
                .frame(maxWidth: .infinity, alignment: .leading)
                .readHeight { height = $0 }
        }
        .frame(height: min(max(height, 22), 180))
    }
}

/// Dots on paper, for the note while it listens.
private struct ProgressDotsInk: View {
    @State private var filled = 0

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(index < filled ? BrandTokens.inkHex : Color.clear)
                    .overlay { Circle().strokeBorder(BrandTokens.inkHex, lineWidth: BrandTokens.ruleOpen) }
                    .frame(width: 8, height: 8)
            }
        }
        .task {
            guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 400_000_000)
                filled = (filled + 1) % 4
            }
        }
    }
}
