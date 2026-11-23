import AppKit
import Combine
import SwiftUI

/// How 11am shows its apps: each in its own window (brand v2), or the earlier single window with a sidebar.
enum WindowStyle: String, CaseIterable, Identifiable {
    case perApp, single

    var id: String { rawValue }

    var title: String {
        switch self {
        case .perApp: return "Each app in its own window"
        case .single: return "One window with a sidebar"
        }
    }
}

/// The app windows. Each app opens as its own window with an ink title bar (`marc · mail`), remembers where you put
/// it, and comes back next time; the drop and the puck stay put with no window open at all.
@MainActor
final class AppWindows: NSObject, ObservableObject, NSWindowDelegate {
    weak var model: AppModel?
    /// The apps with a window open, oldest first.
    @Published private(set) var openSections: [AppSection] = []
    @Published var style: WindowStyle {
        didSet { if style != oldValue { restyle() } }
    }

    private var windows: [AppSection: NSWindow] = [:]
    private var main: NSWindow?
    private var terminating = false
    private var appearanceWatcher: AnyCancellable?

    static let defaultSize = NSSize(width: 1180, height: 780)
    static let minSize = NSSize(width: 760, height: 520)

    override init() {
        style = WindowStyle(rawValue: UserDefaults.standard.string(forKey: "windows.style") ?? "") ?? .perApp
        super.init()
    }

    func isOpen(_ section: AppSection) -> Bool { openSections.contains(section) }

    /// The app last in front, for the Dock icon and the next launch.
    var lastSection: AppSection {
        UserDefaults.standard.string(forKey: "windows.last").flatMap(AppSection.init(rawValue:)) ?? .today
    }

    // MARK: Showing

    /// Brings an app forward: its own window, made if it isn't open yet, or the one window switched to it.
    func show(_ section: AppSection, activate: Bool = true) {
        guard let model else { return }
        if activate { NSApp.activate() }
        switch style {
        case .single:
            let window = main ?? makeMain(model)
            if model.section != section { withAnimation(model.theme.spring) { model.section = section } }
            openSections = [section]
            bringForward(window)
        case .perApp:
            let window = windows[section] ?? make(section, model)
            model.section = section
            bringForward(window)
        }
        UserDefaults.standard.set(section.rawValue, forKey: "windows.last")
    }

    /// At launch: the app asked for, or the windows that were open last time (Today the first time).
    func restore(start: AppSection?) {
        watchAppearance()
        if let start {
            show(start, activate: false)
            return
        }
        guard style == .perApp else {
            show(lastSection, activate: false)
            return
        }
        let saved = (UserDefaults.standard.stringArray(forKey: "windows.open") ?? []).compactMap(AppSection.init(rawValue:))
        let list = saved.isEmpty ? [lastSection] : saved
        let front = list.contains(lastSection) ? lastSection : list[list.count - 1]
        for section in list where section != front { show(section, activate: false) }
        show(front, activate: false)
    }

    /// The Dock icon clicked with nothing showing: the app last in front comes back.
    func reopen() {
        let showing = style == .single ? (main?.isVisible ?? false) : windows.values.contains { $0.isVisible || $0.isMiniaturized }
        if !showing { show(lastSection) }
    }

    func prepareToQuit() {
        terminating = true
    }

    private func bringForward(_ window: NSWindow) {
        if window.isMiniaturized { window.deminiaturize(nil) }
        window.makeKeyAndOrderFront(nil)
    }

    // MARK: Making windows

    private func make(_ section: AppSection, _ model: AppModel) -> NSWindow {
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: Self.defaultSize),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        // Shown in the Window menu, Mission Control and the Dock's window list.
        window.title = section.title
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        window.minSize = Self.minSize
        window.collectionBehavior.insert(.fullScreenPrimary)
        let host = NSHostingView(rootView: AppWindowView(section: section).withAppEnvironment(model))
        host.sizingOptions = [.minSize]
        window.contentView = host
        window.delegate = self
        // Each app remembers where you left it; a new one steps down from the window in front.
        let name = Self.frameName(section)
        if !window.setFrameUsingName(name) { place(window) }
        window.setFrameAutosaveName(name)
        windows[section] = window
        openSections.append(section)
        saveOpen()
        return window
    }

    private func makeMain(_ model: AppModel) -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1240, height: 800),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.title = "11am"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        window.minSize = NSSize(width: 980, height: 640)
        let host = NSHostingView(rootView: RootView().frame(minWidth: 980, minHeight: 640).withAppEnvironment(model))
        host.sizingOptions = [.minSize]
        window.contentView = host
        window.delegate = self
        if !window.setFrameUsingName("11am.main") { window.center() }
        window.setFrameAutosaveName("11am.main")
        main = window
        return window
    }

    private static func frameName(_ section: AppSection) -> String { "11am.app.\(section.rawValue)" }

    private func place(_ window: NSWindow) {
        let screen = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let size = NSSize(width: min(Self.defaultSize.width, screen.width - 40), height: min(Self.defaultSize.height, screen.height - 40))
        var frame = NSRect(x: screen.midX - size.width / 2, y: screen.midY - size.height / 2, width: size.width, height: size.height)
        if let front = windows.values.first(where: { $0.isKeyWindow }) ?? windows.values.first(where: { $0.isVisible }) {
            let stepped = NSRect(x: front.frame.minX + 28, y: front.frame.maxY - 28 - size.height, width: size.width, height: size.height)
            if screen.contains(stepped) { frame = stepped }
        }
        window.setFrame(frame, display: false)
    }

    private func saveOpen() {
        guard !terminating, style == .perApp else { return }
        UserDefaults.standard.set(openSections.map(\.rawValue), forKey: "windows.open")
    }

    /// Switching style closes what's open and shows the same app the new way.
    private func restyle() {
        UserDefaults.standard.set(style.rawValue, forKey: "windows.style")
        let current = model?.section ?? lastSection
        let open = Array(windows.values) + [main].compactMap { $0 }
        for window in open { window.close() }
        show(current)
    }

    /// The theme's Light or Dark applies to every window, the way the single window's did.
    private func watchAppearance() {
        guard appearanceWatcher == nil, let theme = model?.theme else { return }
        appearanceWatcher = theme.$values
            .map(\.appearance)
            .removeDuplicates()
            .sink { appearance in
                switch appearance {
                case .system: NSApp.appearance = nil
                case .light: NSApp.appearance = NSAppearance(named: .aqua)
                case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
                }
            }
    }

    // MARK: NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        if window === main {
            main = nil
            if style == .single { openSections = [] }
            return
        }
        guard let section = windows.first(where: { $0.value === window })?.key else { return }
        window.saveFrame(usingName: Self.frameName(section))
        window.setFrameAutosaveName("")
        windows[section] = nil
        openSections.removeAll { $0 == section }
        if model?.agentFor == section { model?.agentFor = nil }
        saveOpen()
    }

    func windowDidBecomeKey(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              let section = windows.first(where: { $0.value === window })?.key else { return }
        model?.section = section
        UserDefaults.standard.set(section.rawValue, forKey: "windows.last")
    }
}

// MARK: - The window

/// One app in its own window: an ink title bar that says whose app it is, then the app on paper.
struct AppWindowView: View {
    let section: AppSection
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var research: ResearchModel
    @EnvironmentObject private var theme: Theme
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        GeometryReader { proxy in
            VStack(spacing: 0) {
                AppTitleBar(section: section)
                    .frame(height: proxy.safeAreaInsets.top > 0 ? proxy.safeAreaInsets.top : 28)
                SectionContent(section: section)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
                    .overlay(alignment: .topTrailing) { lookUp }
            }
        }
        .ignoresSafeArea(.container, edges: .top)
        .background {
            ZStack {
                theme.paper(scheme)
                Tooth()
            }
            .ignoresSafeArea()
        }
        .frame(minWidth: AppWindows.minSize.width, minHeight: AppWindows.minSize.height)
        .tint(theme.ink(scheme))
        .animation(theme.spring, value: research.lookup?.id)
    }

    /// A look-up asked for from another app shows over the app in front.
    @ViewBuilder
    private var lookUp: some View {
        if let lookup = research.lookup, model.section == section, section != .research {
            ScrollView {
                LookUpCard(lookup: lookup)
            }
            .scrollContentBackground(.hidden)
            .frame(width: 340)
            .frame(maxHeight: 520)
            .fixedSize(horizontal: false, vertical: true)
            .padding(8)
            .vellum(level: 1, radius: theme.radius)
            .shadow(color: .black.opacity(0.18), radius: 18, y: 8)
            .padding(18)
            .transition(.move(edge: .trailing).combined(with: .opacity))
        }
    }
}

/// The ink title bar: the window buttons on the left, `marc · mail` in Courier in the middle, and the agent's circle on
/// the right, which opens a note to ask them and see what the team has done.
struct AppTitleBar: View {
    let section: AppSection
    @EnvironmentObject private var model: AppModel
    @Environment(\.colorScheme) private var scheme

    private var agent: String { AgentCode.brand(section.monogram) }

    private var label: String {
        let who = agent == "11" ? "11am" : AgentCode.name(agent).lowercased()
        return "\(who) · \(section.title.lowercased())"
    }

    var body: some View {
        ZStack {
            // On paper the bar is ink; in the ink theme it's a sheet-ink band so it still reads as a bar.
            Rectangle().fill(scheme == .dark ? BrandTokens.sheetInk : BrandTokens.inkHex)
            WindowDragArea()
            Text(label)
                .font(BrandFont.label(12.5))
                .foregroundStyle(Color.white)
                .lineLimit(1)
                .allowsHitTesting(false)
            HStack {
                Spacer()
                Button {
                    model.agentFor = model.agentFor == section ? nil : section
                } label: {
                    AgentCircle(code: agent, size: 20, style: .paper)
                }
                .buttonStyle(.plain)
                .help("Ask \(AgentCode.name(agent)) · ⌘\\")
                .accessibilityLabel("Ask \(AgentCode.name(agent))")
                .popover(isPresented: Binding(get: { model.agentFor == section }, set: { model.agentFor = $0 ? section : nil }),
                         arrowEdge: .bottom) {
                    AgentPane(section: section)
                        .frame(width: 320, height: 440)
                }
            }
            .padding(.horizontal, 10)
        }
    }
}

/// The empty part of the title bar moves the window, and a double-click does what the Mac is set to (zoom, by default).
struct WindowDragArea: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { DragView() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    final class DragView: NSView {
        override var mouseDownCanMoveWindow: Bool { true }

        override func mouseDown(with event: NSEvent) {
            guard event.clickCount == 2 else {
                window?.performDrag(with: event)
                return
            }
            switch UserDefaults.standard.string(forKey: "AppleActionOnDoubleClick") ?? "Maximize" {
            case "Minimize": window?.performMiniaturize(nil)
            case "None": break
            default: window?.performZoom(nil)
            }
        }
    }
}

/// Each app's view, for its window (or the one window's main sheet).
struct SectionContent: View {
    var section: AppSection

    var body: some View {
        switch section {
        case .today: TodayView()
        case .calendar: CalendarView()
        case .tasks: TasksView()
        case .mail: MailView()
        case .notes: NotesView()
        case .write: WriteView()
        case .files: FilesView()
        case .pdf: PDFAppView()
        case .research: ResearchView()
        case .money: MoneyView()
        case .sheets: SheetsView()
        case .business: BusinessView()
        case .decks: DecksView()
        case .design: DesignView()
        case .photo: PhotoView()
        case .video: VideoView()
        case .audio: AudioView()
        case .learn: LearnView()
        case .build: BuildView()
        case .overnight: OvernightView()
        case .suite: SuiteView()
        case .lab: DesignLabView()
        }
    }
}
