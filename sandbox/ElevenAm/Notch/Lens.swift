import AppKit
import Combine
import ScreenCaptureKit
import SwiftUI
import Vision

/// The lens: a round, see-through ring you move over anything on the screen. When it comes to rest it reads what's
/// under it (Screen Recording permission, then Vision on this Mac) and a note beside it offers to ask about it, copy it,
/// make a task, keep it in Notes or look it up.
@MainActor
final class LensState: ObservableObject {
    @Published var lines: [String] = []
    @Published var reading = false
    @Published var problem: String?
    @Published var noteOpen = false
    /// What happened after a hand-off: "Added to Tasks", "Copied".
    @Published var done: String?
    /// True when the lens sits on the left of the screen, so the note opens to its right.
    @Published var onLeft = false
}

final class LensPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class LensController {
    static let diameter: CGFloat = 220
    static let noteSize = NSSize(width: 380, height: 400)

    private let model: AppModel
    let state = LensState()
    private var panel: LensPanel?
    private var notePanel: LensPanel?
    private var dragStartMouse: NSPoint = .zero
    private var dragStartOrigin: NSPoint = .zero
    private var settle: Task<Void, Never>?
    /// Asks about what it read in the puck's note.
    var onAsk: ((URL) -> Void)?

    init(model: AppModel) {
        self.model = model
    }

    var isShown: Bool { panel?.isVisible == true }

    func toggle() {
        if isShown { hide() } else { show() }
    }

    func show() {
        if panel == nil {
            let size = NSSize(width: Self.diameter + 24, height: Self.diameter + 44)
            let lens = LensPanel(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless, .nonactivatingPanel],
                                 backing: .buffered, defer: false)
            lens.isOpaque = false
            lens.backgroundColor = .clear
            lens.hasShadow = false
            lens.level = .floating
            lens.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
            lens.hidesOnDeactivate = false
            lens.becomesKeyOnlyIfNeeded = true
            let host = NSHostingView(rootView: LensView(controller: self).environmentObject(state).withAppEnvironment(model))
            host.frame = NSRect(origin: .zero, size: size)
            lens.contentView = host
            panel = lens
            if let screen = NSScreen.main?.visibleFrame {
                lens.setFrameOrigin(NSPoint(x: screen.midX - size.width / 2, y: screen.midY - size.height / 2))
            }
        }
        panel?.orderFrontRegardless()
    }

    func hide() {
        closeNote()
        panel?.orderOut(nil)
    }

    // MARK: Moving it

    func pressBegan() {
        dragStartMouse = NSEvent.mouseLocation
        dragStartOrigin = panel?.frame.origin ?? .zero
        settle?.cancel()
        closeNote()
    }

    func dragged() {
        let now = NSEvent.mouseLocation
        panel?.setFrameOrigin(NSPoint(x: dragStartOrigin.x + now.x - dragStartMouse.x, y: dragStartOrigin.y + now.y - dragStartMouse.y))
    }

    /// Let go: a moment's rest, then it reads.
    func dragEnded() {
        settle?.cancel()
        settle = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }
            await read()
        }
    }

    // MARK: Reading

    /// The circle, in screen points (origin bottom left).
    private var circleRect: NSRect? {
        guard let panel else { return nil }
        let frame = panel.frame
        return NSRect(x: frame.minX + 12, y: frame.maxY - 12 - Self.diameter, width: Self.diameter, height: Self.diameter)
    }

    func read() async {
        guard let rect = circleRect, let screen = panel?.screen ?? NSScreen.main else { return }
        state.reading = true
        state.problem = nil
        state.done = nil
        defer { state.reading = false }
        do {
            let image = try await LensReader.capture(rect, on: screen)
            let words = await LensReader.words(in: image, pointSize: rect.size)
            let geometry = LensKit.circle(in: rect.size)
            state.lines = LensKit.lines(words, center: geometry.center, radius: geometry.radius)
            if state.lines.isEmpty { state.problem = "No words under the lens. Move it over some text." }
        } catch {
            state.lines = []
            state.problem = "The lens needs Screen Recording to read the screen. Allow 11am in System Settings › Privacy & Security › Screen Recording, then open 11am again."
        }
        openNote()
    }

    // MARK: The note

    func openNote() {
        guard let panel else { return }
        if notePanel == nil {
            let note = LensPanel(contentRect: NSRect(origin: .zero, size: Self.noteSize), styleMask: [.borderless, .nonactivatingPanel],
                                 backing: .buffered, defer: false)
            note.isOpaque = false
            note.backgroundColor = .clear
            note.hasShadow = false
            note.level = .floating
            note.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
            note.hidesOnDeactivate = false
            let host = NSHostingView(rootView: LensNoteView(controller: self).environmentObject(state).withAppEnvironment(model))
            host.frame = NSRect(origin: .zero, size: Self.noteSize)
            note.contentView = host
            notePanel = note
        }
        let visible = (panel.screen ?? NSScreen.main)?.visibleFrame ?? panel.frame
        let onLeft = panel.frame.midX < visible.midX
        state.onLeft = onLeft
        let x = onLeft ? panel.frame.maxX + 8 : panel.frame.minX - 8 - Self.noteSize.width
        var y = panel.frame.maxY - Self.noteSize.height
        y = min(max(y, visible.minY + 8), visible.maxY - Self.noteSize.height - 8)
        notePanel?.setFrameOrigin(NSPoint(x: x, y: y))
        state.noteOpen = true
        notePanel?.orderFrontRegardless()
    }

    func closeNote() {
        state.noteOpen = false
        notePanel?.orderOut(nil)
    }

    // MARK: Hand-offs

    private var text: String { state.lines.joined(separator: "\n") }

    func ask() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("What the lens read.txt")
        try? text.write(to: url, atomically: true, encoding: .utf8)
        onAsk?(url)
        closeNote()
    }

    func copy() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        state.done = "Copied."
    }

    func makeTask() {
        let title = LensKit.headline(state.lines)
        let origin = TaskOrigin(kind: .agent, monogram: "le", label: "From the lens", quote: String(text.prefix(300)))
        if let task = model.tasks.add("Look at the lens", in: .inbox, origin: origin, select: false) {
            model.tasks.update(task.id) { $0.title = title.isEmpty ? "Look at what the lens read" : title }
            state.done = "Added to Tasks."
            model.log("le", "Made a task from the lens.")
        }
    }

    func keepInNotes() {
        _ = model.notes.newNote(text: "# From the lens\n\n" + text + "\n")
        state.done = "Kept in Notes."
        model.log("bn", "Kept what the lens read in Notes.")
    }

    func lookUp() {
        model.research.lookUp(LensKit.headline(state.lines, limit: 120))
        model.go(to: model.section)
        state.done = "James is looking it up."
    }

    /// For screenshots: the lens over the screen with something it read.
    func preview() {
        show()
        state.lines = ["Before our partner meeting on Thursday, could you", "confirm how much of the round is already", "committed, and whether the angel allocation", "is still open?"]
        openNote()
    }
}

/// Screen capture and Vision, on this Mac.
enum LensReader {
    /// A picture of the square around the circle, leaving out 11am's own windows (the lens itself).
    static func capture(_ rect: NSRect, on screen: NSScreen) async throws -> CGImage {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let screenID = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
        guard let display = content.displays.first(where: { $0.displayID == screenID }) ?? content.displays.first else {
            throw CocoaError(.featureUnsupported)
        }
        let mine = content.applications.filter { $0.bundleIdentifier == Bundle.main.bundleIdentifier }
        let filter = SCContentFilter(display: display, excludingApplications: mine, exceptingWindows: [])
        let configuration = SCStreamConfiguration()
        // Display points, from the top left.
        configuration.sourceRect = CGRect(x: rect.minX - screen.frame.minX, y: screen.frame.maxY - rect.maxY, width: rect.width, height: rect.height)
        let scale = screen.backingScaleFactor
        configuration.width = Int(rect.width * scale)
        configuration.height = Int(rect.height * scale)
        configuration.showsCursor = false
        return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
    }

    /// The words Vision finds, in the picture's points with the origin at the top left.
    static func words(in image: CGImage, pointSize: CGSize) async -> [LensKit.Word] {
        await Task.detached(priority: .userInitiated) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            try? VNImageRequestHandler(cgImage: image).perform([request])
            return (request.results ?? []).compactMap { observation -> LensKit.Word? in
                guard let text = observation.topCandidates(1).first?.string else { return nil }
                let box = observation.boundingBox
                return LensKit.Word(text: text, box: CGRect(x: box.minX * pointSize.width, y: (1 - box.maxY) * pointSize.height,
                                                            width: box.width * pointSize.width, height: box.height * pointSize.height))
            }
        }.value
    }
}

// MARK: - Views

/// The ring: an open ink circle with a white ring inside it so it reads on any background, clear in the middle, and a
/// Courier label to hold it by. Drag it anywhere; it reads when it comes to rest.
struct LensView: View {
    @EnvironmentObject private var state: LensState
    var controller: LensController
    @State private var pressing = false

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle().strokeBorder(Color.white.opacity(0.9), lineWidth: 5)
                Circle().strokeBorder(BrandTokens.inkHex, lineWidth: BrandTokens.ruleOpen).padding(2)
                Circle().strokeBorder(BrandTokens.inkHex, lineWidth: BrandTokens.ruleOpen).padding(-1)
                if state.reading {
                    Circle().trim(from: 0, to: 0.18)
                        .stroke(BrandTokens.inkHex, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .padding(2)
                        .rotationEffect(.degrees(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : (state.reading ? 360 : 0)))
                        .animation(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? nil : .linear(duration: 1).repeatForever(autoreverses: false),
                                   value: state.reading)
                }
            }
            .frame(width: LensController.diameter, height: LensController.diameter)
            .contentShape(Circle())
            .gesture(drag)
            Text(state.reading ? "lens · reading" : "lens · drag me over words")
                .font(BrandFont.label(12))
                .foregroundStyle(Color.white)
                .padding(.horizontal, 12)
                .frame(height: 24)
                .background(Capsule().fill(BrandTokens.inkHex))
                .contentShape(Capsule())
                .gesture(drag)
                .help("Drag the lens over anything on the screen; it reads what's under it")
        }
        .padding(12)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("The lens")
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .global)
            .onChanged { _ in
                if !pressing {
                    pressing = true
                    controller.pressBegan()
                }
                controller.dragged()
            }
            .onEnded { _ in
                pressing = false
                controller.dragEnded()
            }
    }
}

/// What the lens read, on a vellum note, and what to do with it.
struct LensNoteView: View {
    @EnvironmentObject private var state: LensState
    var controller: LensController

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("lens · \(state.lines.count == 1 ? "1 line" : "\(state.lines.count) lines")")
                    .font(BrandFont.label(12))
                Spacer()
                Button {
                    controller.closeNote()
                } label: {
                    Text("×").font(BrandFont.body(18)).frame(width: 24, height: 24).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close")
            }
            if let problem = state.problem {
                HStack(alignment: .top, spacing: 8) {
                    Rectangle().fill(BrandTokens.inkHex).frame(width: BrandTokens.errorBar)
                    Text(problem).font(BrandFont.body(13.5)).fixedSize(horizontal: false, vertical: true)
                }
            }
            if !state.lines.isEmpty {
                ScrollView {
                    Text(state.lines.joined(separator: "\n"))
                        .font(BrandFont.body(15))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 170)
                // Two rows, so the pills fit the note: asking first, then keeping it somewhere.
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Button("Ask") { controller.ask() }.buttonStyle(.vellumPrimary)
                        Button("Look up") { controller.lookUp() }.buttonStyle(.vellumSecondary)
                    }
                    HStack(spacing: 6) {
                        Button("Copy") { controller.copy() }.buttonStyle(.vellumSecondary)
                        Button("Task") { controller.makeTask() }.buttonStyle(.vellumSecondary)
                        Button("Note") { controller.keepInNotes() }.buttonStyle(.vellumSecondary)
                    }
                }
                .fixedSize()
                .help("Ask the team about it, have James look it up, copy it, make it a task, or keep it in Notes")
            }
            if let done = state.done {
                Text(done).font(BrandFont.body(13.5))
            }
        }
        .padding(18)
        .frame(width: LensController.noteSize.width)
        .foregroundStyle(BrandTokens.inkHex)
        .noteSurface()
        .lift(hi: true)
        .environment(\.colorScheme, .light)
        .frame(width: LensController.noteSize.width, height: LensController.noteSize.height, alignment: .top)
    }
}
