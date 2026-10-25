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

    private var collapseTask: Task<Void, Never>?

    init(geometry: NotchGeometry) {
        self.geometry = geometry
    }

    func open(_ page: NotchPage? = nil) {
        cancelCollapse()
        if let page { self.page = page }
        mode = .open
    }

    func peek() {
        cancelCollapse()
        guard mode == .idle else { return }
        mode = .peek
        // If the pointer never actually reaches the notch, fold away again.
        collapseTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard !Task.isCancelled, self.mode == .peek else { return }
            self.mode = .idle
        }
    }

    func pointerLeft() {
        cancelCollapse()
        // Stay open while typing or while an answer is streaming.
        if mode == .open && (focusAsk || !(askRun?.isFinished ?? true)) { return }
        collapseTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 450_000_000)
            guard !Task.isCancelled else { return }
            self.mode = .idle
        }
    }

    func pointerEntered() {
        cancelCollapse()
    }

    func close() {
        cancelCollapse()
        focusAsk = false
        mode = .idle
    }

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
    private let panelSize = NSSize(width: 760, height: 460)

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
        let handler: (NSEvent) -> Void = { [weak self] _ in
            Task { @MainActor in self?.pointerMoved() }
        }
        if let global = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged], handler: handler) {
            monitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged], handler: { event in
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
