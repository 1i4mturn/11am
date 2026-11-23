import AppKit
import Combine
import SwiftUI

enum NotchMode {
    case idle, peek, open
}

enum NotchPage: String, CaseIterable, Identifiable {
    case now, ask, overnight

    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

/// Where the hardware notch is, or where a stand-in pill goes on Macs and displays without one.
struct NotchGeometry {
    var screenFrame: NSRect
    var hasNotch: Bool
    var notchSize: CGSize

    init(screen: NSScreen) {
        screenFrame = screen.frame
        let top = screen.safeAreaInsets.top
        if top > 0, let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            hasNotch = true
            notchSize = CGSize(width: screen.frame.width - left.width - right.width, height: top)
        } else {
            hasNotch = false
            notchSize = CGSize(width: 180, height: 24)
        }
    }

    /// The notch area in screen coordinates (origin bottom-left).
    var notchRect: NSRect {
        NSRect(
            x: screenFrame.midX - notchSize.width / 2,
            y: screenFrame.maxY - notchSize.height,
            width: notchSize.width,
            height: notchSize.height
        )
    }

    /// A slightly larger zone that wakes the notch as the pointer approaches.
    var wakeZone: NSRect { notchRect.insetBy(dx: -24, dy: -10) }
}

@MainActor
final class NotchState: ObservableObject {
    @Published var mode: NotchMode = .idle
    @Published var page: NotchPage = .now
    @Published var geometry: NotchGeometry
    @Published var askText = ""
    @Published var askRun: BrainRun?
    @Published var focusAsk = false
    /// The last thing asked, shown while the answer comes.
    @Published var askedText = ""
    /// What a "+ task" did.
    @Published var added: String?
    /// A file is being dragged over the drop: agents' rings open for what they can take, and the shelf waits below.
    @Published var dragging = false
    @Published var dragURLs: [URL] = []
    @Published var dragKinds: [ShelfKind] = []
    /// The agent (by code) or "shelf" under the dragged file.
    @Published var dragTarget: String?
    /// The drop opened because a file came near; it folds away again when the drag ends.
    private var openedForDrag = false

    private var collapseTask: Task<Void, Never>?

    init(geometry: NotchGeometry) {
        self.geometry = geometry
    }

    // Opening has a little life in it; closing settles without a bounce.
    private var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
    private var openAnimation: Animation { reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.5, dampingFraction: 0.78) }
    private var peekAnimation: Animation { reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.42, dampingFraction: 0.82) }
    private var closeAnimation: Animation { reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.38, dampingFraction: 1) }

    private func set(_ newMode: NotchMode) {
        guard newMode != mode else { return }
        let animation: Animation
        switch newMode {
        case .open: animation = openAnimation
        case .peek: animation = peekAnimation
        case .idle: animation = closeAnimation
        }
        withAnimation(animation) { mode = newMode }
    }

    func open(_ page: NotchPage? = nil) {
        cancelCollapse()
        if let page { self.page = page }
        set(.open)
    }

    func peek() {
        cancelCollapse()
        guard mode == .idle else { return }
        set(.peek)
        // If the pointer never actually reaches the notch, fold away again.
        collapseTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard !Task.isCancelled, self.mode == .peek else { return }
            self.set(.idle)
        }
    }

    func pointerLeft() {
        guard !dragging else { return }
        cancelCollapse()
        // Stay open while typing or while an answer is streaming.
        if mode == .open && (focusAsk || !(askRun?.isFinished ?? true)) { return }
        collapseTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 450_000_000)
            guard !Task.isCancelled else { return }
            self.set(.idle)
        }
    }

    func pointerEntered() {
        cancelCollapse()
    }

    func close() {
        cancelCollapse()
        focusAsk = false
        // The drop opens fresh next time, not on the last question.
        if askRun?.isFinished ?? true {
            askRun = nil
            askedText = ""
            added = nil
            askText = ""
        }
        set(.idle)
    }

    /// A file has come near the notch: the drop opens with its rings and the shelf.
    func beginDrag(_ urls: [URL]) {
        dragURLs = urls
        dragKinds = ShelfModel.kinds(urls)
        dragTarget = nil
        guard !dragging else { return }
        if mode != .open { openedForDrag = true }
        focusAsk = false
        withAnimation(.smooth(duration: 0.25)) { dragging = true }
        open()
    }

    /// The drag finished somewhere. After a hand-off the drop stays a moment to say what happened, then folds away
    /// if it only opened for the drag.
    func endDrag(handed: Bool, pointerInside: Bool) {
        guard dragging else { return }
        withAnimation(.smooth(duration: 0.25)) { dragging = false }
        dragTarget = nil
        let wasForDrag = openedForDrag
        openedForDrag = false
        guard wasForDrag, !pointerInside else { return }
        cancelCollapse()
        collapseTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: handed ? 3_200_000_000 : 500_000_000)
            guard !Task.isCancelled, !self.dragging else { return }
            self.set(.idle)
        }
    }

    /// Something was let go on a target in the drop.
    func dropped() {
        lastDrop = Date()
    }

    /// When the last file was let go in the drop, so the end of the drag knows it was handed over.
    private(set) var lastDrop: Date?

    private func cancelCollapse() {
        collapseTask?.cancel()
        collapseTask = nil
    }
}

/// A borderless panel that can take keyboard focus (for Ask) without activating the app.
final class NotchPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect // allow sitting over the menu bar
    }
}

/// Owns the notch window, watches the pointer, and resizes hit-testing to match the state.
@MainActor
final class NotchController {
    private let model: AppModel
    private let state: NotchState
    private var panel: NotchPanel?
    private var monitors: [Any] = []
    private var screenObserver: NSObjectProtocol?
    private var cancellables: Set<AnyCancellable> = []
    private let panelSize = NSSize(width: 760, height: 660)
    /// The tallest the open drop grows.
    static let maxOpenHeight: CGFloat = 640

    init(model: AppModel) {
        self.model = model
        let screen = NotchController.targetScreen()
        self.state = NotchState(geometry: NotchGeometry(screen: screen ?? NSScreen.screens[0]))
    }

    func show() {
        let panel = NotchPanel(
            contentRect: frameForPanel(),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.isMovable = false
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.acceptsMouseMovedEvents = true
        panel.ignoresMouseEvents = true

        let root = NotchView()
            .environmentObject(state)
            .withAppEnvironment(model)
        let host = NSHostingView(rootView: root)
        host.frame = NSRect(origin: .zero, size: panelSize)
        panel.contentView = host
        panel.orderFrontRegardless()
        self.panel = panel

        state.$mode
            .removeDuplicates()
            .sink { [weak self] mode in self?.apply(mode) }
            .store(in: &cancellables)

        installPointerMonitors()

        screenObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.reposition() }
        }
    }

    /// Opens the Now page and keeps it open (used for screenshots).
    func openPreview() {
        state.open(.now)
    }

    /// For screenshots: the drop listening, with a question and its answer.
    func openListeningPreview() {
        state.askedText = "Where's the Acme pilot agreement?"
        let run = BrainRun(prompt: state.askedText)
        run.text = "It's in Documents › Clients › Acme, saved as \u{201C}Acme pilot agreement.pdf\u{201D}. Either side can end the pilot with 7 days' notice."
        run.providerLabel = "On this Mac"
        run.status = .done
        state.askRun = run
        state.open(.ask)
    }

    /// For screenshots: the drop as a file is dragged over an agent's ring.
    func openDragPreview(_ url: URL, over code: String) {
        state.beginDrag([url])
        state.dragTarget = code
    }

    func openAsk() {
        state.open(.ask)
        panel?.makeKeyAndOrderFront(nil)
        state.focusAsk = true
    }

    private func apply(_ mode: NotchMode) {
        guard let panel else { return }
        // When idle, clicks fall straight through to whatever is under the notch.
        panel.ignoresMouseEvents = (mode == .idle)
        if mode == .idle, panel.isKeyWindow {
            panel.resignKey()
        }
    }

    private func installPointerMonitors() {
        let handler: (NSEvent) -> Void = { [weak self] event in
            let type = event.type
            Task { @MainActor in
                switch type {
                case .leftMouseDown: self?.mouseWentDown()
                case .leftMouseUp: self?.mouseWentUp()
                case .leftMouseDragged: self?.mouseDragged()
                default: self?.pointerMoved()
                }
            }
        }
        let events: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .leftMouseDown, .leftMouseUp]
        if let global = NSEvent.addGlobalMonitorForEvents(matching: events, handler: handler) {
            monitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: events, handler: { event in
            handler(event)
            return event
        }) {
            monitors.append(local)
        }
    }

    private func pointerMoved() {
        guard state.mode == .idle else { return }
        if state.geometry.wakeZone.contains(NSEvent.mouseLocation) {
            state.peek()
        }
    }

    // MARK: Dragging files to the drop

    /// The drag pasteboard's count when the button went down: a new count while it's held means a drag has started.
    private var dragCount = NSPasteboard(name: .drag).changeCount
    private var dragFiles: [URL]?

    private func mouseWentDown() {
        dragCount = NSPasteboard(name: .drag).changeCount
        dragFiles = nil
    }

    private func mouseDragged() {
        let board = NSPasteboard(name: .drag)
        guard board.changeCount != dragCount else {
            pointerMoved()
            return
        }
        if dragFiles == nil { dragFiles = FileDrops.dragged() }
        guard let files = dragFiles, !files.isEmpty else { return }
        if state.dragging || dropZone.contains(NSEvent.mouseLocation) {
            state.beginDrag(files)
        }
    }

    private func mouseWentUp() {
        dragFiles = nil
        dragCount = NSPasteboard(name: .drag).changeCount
        guard state.dragging else { return }
        // The drop lands a moment after the button comes up; wait for it before deciding.
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 250_000_000)
            let handed = state.lastDrop.map { Date().timeIntervalSince($0) < 2 } ?? false
            let inside = panel.map { $0.frame.contains(NSEvent.mouseLocation) } ?? false
            state.endDrag(handed: handed, pointerInside: inside && !handed)
        }
    }

    /// Generous room around the notch, so a file only has to come close.
    private var dropZone: NSRect {
        let notch = state.geometry.notchRect
        return NSRect(x: notch.minX - 160, y: notch.minY - 70, width: notch.width + 320, height: notch.height + 140)
    }

    private func reposition() {
        guard let screen = NotchController.targetScreen() else { return }
        state.geometry = NotchGeometry(screen: screen)
        panel?.setFrame(frameForPanel(), display: true)
    }

    private func frameForPanel() -> NSRect {
        let frame = state.geometry.screenFrame
        return NSRect(
            x: frame.midX - panelSize.width / 2,
            y: frame.maxY - panelSize.height,
            width: panelSize.width,
            height: panelSize.height
        )
    }

    /// Prefer the built-in display with a notch; otherwise the main display.
    private static func targetScreen() -> NSScreen? {
        NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main ?? NSScreen.screens.first
    }
}
